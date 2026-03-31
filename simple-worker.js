/**
 * VLESS over WebSocket — Cloudflare Worker (Service Worker format)
 *
 * Paste into the Cloudflare Workers editor, replace UUID, deploy.
 *
 * Security model:
 *   - /vless        → VLESS WebSocket; rejects connections with wrong UUID
 *   - /<YOUR-UUID>  → shows the v2rayNG connection link (secret URL, only you know it)
 *   - everything else → 404
 */

// ✏️ Replace with your own UUID (generate at https://www.uuidgenerator.net/)
const UUID = 'CHANGE_ME';

// ─── Router ──────────────────────────────────────────────────────────────────

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request).catch(e =>
    new Response(`Worker error: ${e.message}\n${e.stack}`, {
      status: 500,
      headers: { 'content-type': 'text/plain' },
    })
  ));
});

async function handleRequest(req) {
  const url = new URL(req.url);

  // Secret config page — only reachable if you know the UUID
  if (url.pathname === `/${UUID}`) {
    return new Response(getLink(req.headers.get('Host')), {
      headers: { 'content-type': 'text/plain;charset=utf-8' },
    });
  }

  // VLESS proxy endpoint
  if (url.pathname === '/vless') {
    return handleWs(req);
  }

  return new Response('Not found', { status: 404 });
}

// ─── WebSocket upgrade ────────────────────────────────────────────────────────

function handleWs(req) {
  if (req.headers.get('Upgrade') !== 'websocket')
    return new Response('WebSocket required', { status: 426 });

  const pair = new WebSocketPair();
  const [client, server] = [pair[0], pair[1]];
  server.accept();

  // Promise chain serialises all writes — prevents concurrent-write errors
  let writeQueue = Promise.resolve();
  let remoteWriter = null;

  server.addEventListener('message', ({ data }) => {
    writeQueue = writeQueue.then(async () => {
      const buf =
        data instanceof ArrayBuffer ? data
        : data instanceof Blob      ? await data.arrayBuffer()
        :                             new TextEncoder().encode(data).buffer;

      if (!remoteWriter) {
        // First chunk — parse VLESS header
        let host, port, payload;
        try {
          ({ host, port, payload } = parseVless(buf));
        } catch (e) {
          server.close(1008, String(e));
          return;
        }

        server.send(new Uint8Array([0, 0])); // VLESS response header

        const sock = connect({ hostname: host, port });
        remoteWriter = sock.writable.getWriter();

        // Pipe remote → client
        sock.readable.pipeTo(new WritableStream({
          write(chunk) {
            try { server.send(chunk); } catch {}
          },
        })).catch(() => { try { server.close(); } catch {} });

        if (payload.byteLength > 0)
          await remoteWriter.write(new Uint8Array(payload));

      } else {
        await remoteWriter.write(new Uint8Array(buf));
      }
    }).catch(e => {
      console.error('write error:', e);
      try { server.close(1011, 'internal error'); } catch {}
    });
  });

  server.addEventListener('close', () => remoteWriter?.close().catch(() => {}));
  server.addEventListener('error', () => remoteWriter?.close().catch(() => {}));

  return new Response(null, { status: 101, webSocket: client });
}

// ─── VLESS header parser ──────────────────────────────────────────────────────

function parseVless(buf) {
  if (buf.byteLength < 24) throw new Error('Header too short');

  const view = new DataView(buf);

  // Validate UUID (bytes 1–16)
  const uuid = [...new Uint8Array(buf, 1, 16)]
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
  if (uuid !== UUID.replace(/-/g, '').toLowerCase())
    throw new Error('Auth failed');

  const addonLen = view.getUint8(17);
  let i = 18 + addonLen;

  const cmd = view.getUint8(i++);
  if (cmd !== 1) throw new Error('Only TCP supported');

  const port = view.getUint16(i); i += 2;
  const addrType = view.getUint8(i++);

  let host;
  if (addrType === 1) {       // IPv4
    host = [...new Uint8Array(buf, i, 4)].join('.'); i += 4;
  } else if (addrType === 2) { // Domain
    const len = view.getUint8(i++);
    host = new TextDecoder().decode(new Uint8Array(buf, i, len)); i += len;
  } else if (addrType === 3) { // IPv6
    const b = new Uint8Array(buf, i, 16);
    host = Array.from({ length: 8 }, (_, j) =>
      ((b[j * 2] << 8) | b[j * 2 + 1]).toString(16)
    ).join(':');
    i += 16;
  } else {
    throw new Error(`Unknown address type: ${addrType}`);
  }

  return { host, port, payload: buf.slice(i) };
}

// ─── Config link ──────────────────────────────────────────────────────────────

function getLink(host) {
  const params = new URLSearchParams({
    encryption: 'none',
    security:   'tls',
    sni:        host,
    fp:         'chrome',
    type:       'ws',
    host:       host,
    path:       '/vless',
  });
  const link = `vless://${UUID}@${host}:443?${params}#CF-Worker`;

  return [
    '=== v2rayNG Connection Info ===',
    '',
    'Import this link (tap + → Import from clipboard):',
    '',
    link,
    '',
    '--- Manual settings ---',
    `  Address    : ${host}`,
    '  Port       : 443',
    `  UUID       : ${UUID}`,
    '  Encryption : none',
    '  Transport  : WebSocket',
    '  Path       : /vless',
    '  TLS        : TLS',
    `  SNI        : ${host}`,
    '  Fingerprint: chrome',
  ].join('\n');
}
