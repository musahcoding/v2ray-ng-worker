/**
 * VLESS over WebSocket - Cloudflare Worker (ES Module format)
 *
 * UUID is read from a Worker Secret (never hardcoded):
 *   Worker -> Settings -> Variables and Secrets -> Add Secret -> name: UUID
 *
 * Routes:
 *   /vless    - VLESS WebSocket proxy endpoint
 *   /<UUID>   - shows the v2rayNG connection link
 *   other     - 404
 */

import { connect } from 'cloudflare:sockets';

export default {
  async fetch(req, env) {
    try {
      const uuid = env.UUID;
      if (!uuid) return new Response('UUID secret not set', { status: 500 });

      const url = new URL(req.url);

      if (url.pathname === '/' + uuid) {
        return new Response(getLink(req.headers.get('Host'), uuid), {
          headers: { 'content-type': 'text/plain;charset=utf-8' },
        });
      }

      if (url.pathname === '/vless') {
        return handleWs(req, uuid);
      }

      return new Response('Not found', { status: 404 });
    } catch (e) {
      return new Response('Worker error: ' + e.message + '\n' + e.stack, {
        status: 500,
        headers: { 'content-type': 'text/plain' },
      });
    }
  },
};

function handleWs(req, uuid) {
  if (req.headers.get('Upgrade') !== 'websocket')
    return new Response('WebSocket required', { status: 426 });

  const pair = new WebSocketPair();
  const [client, server] = [pair[0], pair[1]];
  server.accept();

  let writeQueue = Promise.resolve();
  let remoteWriter = null;

  server.addEventListener('message', ({ data }) => {
    writeQueue = writeQueue.then(async () => {
      const buf =
        data instanceof ArrayBuffer ? data
        : data instanceof Blob      ? await data.arrayBuffer()
        :                             new TextEncoder().encode(data).buffer;

      if (!remoteWriter) {
        let host, port, payload, cmd;
        try {
          ({ host, port, payload, cmd } = parseVless(buf, uuid));
        } catch (e) {
          server.close(1008, String(e));
          return;
        }

        server.send(new Uint8Array([0, 0]));

        if (cmd === 2) {
          remoteWriter = 'udp';
          if (payload.byteLength > 0) await forwardDns(server, payload);
          return;
        }

        const sock = connect({ hostname: host, port });
        remoteWriter = sock.writable.getWriter();

        sock.readable.pipeTo(new WritableStream({
          write(chunk) {
            try { server.send(chunk); } catch (_) {}
          },
        })).catch(() => { try { server.close(); } catch (_) {} });

        if (payload.byteLength > 0)
          await remoteWriter.write(new Uint8Array(payload));

      } else if (remoteWriter === 'udp') {
        await forwardDns(server, buf);
      } else {
        await remoteWriter.write(new Uint8Array(buf));
      }
    }).catch(e => {
      console.error('write error:', e);
      try { server.close(1011, 'internal error'); } catch (_) {}
    });
  });

  server.addEventListener('close', () => {
    if (remoteWriter && remoteWriter !== 'udp') remoteWriter.close().catch(() => {});
  });
  server.addEventListener('error', () => {
    if (remoteWriter && remoteWriter !== 'udp') remoteWriter.close().catch(() => {});
  });

  return new Response(null, { status: 101, webSocket: client });
}

function parseVless(buf, uuid) {
  if (buf.byteLength < 24) throw new Error('Header too short');

  const view = new DataView(buf);

  const got = Array.from(new Uint8Array(buf, 1, 16))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
  if (got !== uuid.replace(/-/g, '').toLowerCase())
    throw new Error('Auth failed');

  const addonLen = view.getUint8(17);
  let i = 18 + addonLen;

  const cmd = view.getUint8(i++);
  if (cmd !== 1 && cmd !== 2) throw new Error('Unsupported command');

  const port = view.getUint16(i); i += 2;
  const addrType = view.getUint8(i++);

  let host;
  if (addrType === 1) {
    host = Array.from(new Uint8Array(buf, i, 4)).join('.'); i += 4;
  } else if (addrType === 2) {
    const len = view.getUint8(i++);
    host = new TextDecoder().decode(new Uint8Array(buf, i, len)); i += len;
  } else if (addrType === 3) {
    const b = new Uint8Array(buf, i, 16);
    host = Array.from({ length: 8 }, (_, j) =>
      ((b[j * 2] << 8) | b[j * 2 + 1]).toString(16)
    ).join(':');
    i += 16;
  } else {
    throw new Error('Unknown address type: ' + addrType);
  }

  return { cmd, host, port, payload: buf.slice(i) };
}

async function forwardDns(ws, buf) {
  try {
    const ab = buf instanceof ArrayBuffer ? buf : buf.buffer;
    const view = new DataView(ab);
    const dnsLen = view.getUint16(0);
    console.log('DNS query received, length:', dnsLen, 'buf size:', ab.byteLength);

    const dnsQuery = ab.slice(2, 2 + dnsLen);

    const resp = await fetch('https://1.1.1.1/dns-query', {
      method: 'POST',
      headers: { 'content-type': 'application/dns-message' },
      body: dnsQuery,
    });

    console.log('DoH response status:', resp.status);

    if (!resp.ok) {
      console.error('DoH error:', resp.status, await resp.text());
      return;
    }

    const answer = new Uint8Array(await resp.arrayBuffer());
    console.log('DNS answer length:', answer.byteLength);
    const out = new Uint8Array(2 + answer.byteLength);
    new DataView(out.buffer).setUint16(0, answer.byteLength);
    out.set(answer, 2);
    try { ws.send(out.buffer); } catch (_) {}
  } catch (e) {
    console.error('forwardDns error:', e.message, e.stack);
  }
}

function getLink(host, uuid) {
  const params = new URLSearchParams({
    encryption: 'none',
    security:   'tls',
    sni:        host,
    fp:         'chrome',
    type:       'ws',
    host:       host,
    path:       '/vless',
  });
  const link = 'vless://' + uuid + '@' + host + ':443?' + params + '#CF-Worker';

  return [
    '=== v2rayNG Connection Info ===',
    '',
    'Import this link (tap + -> Import from clipboard):',
    '',
    link,
    '',
    '--- Manual settings ---',
    '  Address    : ' + host,
    '  Port       : 443',
    '  UUID       : ' + uuid,
    '  Encryption : none',
    '  Transport  : WebSocket',
    '  Path       : /vless',
    '  TLS        : TLS',
    '  SNI        : ' + host,
    '  Fingerprint: chrome',
  ].join('\n');
}
