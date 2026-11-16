// Local test server: runs the real Worker code over HTTP with an in-memory database.
// Used by tests/Run-Tests.ps1 (WARPATH_TEST_SERVER). Not for production.
//   ADMIN_TOKEN=... node test/dev-server.mjs [port]
import http from 'node:http';
import { createHash } from 'node:crypto';
import { handle } from '../src/index.js';
import { FakeD1 } from './fake-d1.js';

const port = Number(process.argv[2] || 8787);
const token = process.env.ADMIN_TOKEN || 'dev-admin-token-0123456789abcdefghijkl';
const env = { DB: new FakeD1(), ADMIN_TOKEN_SHA256: createHash('sha256').update(token).digest('hex'), RATE_SALT: 'dev' };

http
  .createServer(async (req, res) => {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const request = new Request('http://127.0.0.1:' + port + req.url, {
      method: req.method,
      headers: Object.fromEntries(Object.entries(req.headers).map(([k, v]) => [k, String(v)])),
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
    });
    const response = await handle(request, env, new Date());
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  })
  .listen(port, '127.0.0.1', () => console.log('analytics dev server on http://127.0.0.1:' + port));
