'use strict';

// The web app is served at "/" next to the API. `npm test`
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'baiweb-'));
process.env.CONFIG_FILE = path.join(dir, 'config.json');
process.env.ADMIN_EMAIL = 'admin@example.com';
process.env.TOKEN_SECRET = 'test-secret';
delete process.env.DATABASE_URL;

const web = require('../web');
const { start } = require('../server');

const hasBuild = web.available();
let server;
let base;

test.before(async () => {
  server = await start({ port: 0 });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => server.close());

test('a browser at / gets the app page', { skip: !hasBuild && 'no public/ build' }, async () => {
  const r = await fetch(`${base}/`, { headers: { Accept: 'text/html,*/*' } });
  assert.strictEqual(r.status, 200);
  assert.match(r.headers.get('content-type'), /text\/html/);
  const html = await r.text();
  assert.match(html, /<title>Bangla AI<\/title>/);
  assert.match(html, /flutter_bootstrap\.js/);
});

test('the site is installable: manifest, service worker, install script', { skip: !hasBuild && 'no public/ build' }, async () => {
  const m = await (await fetch(`${base}/manifest.json`)).json();
  assert.strictEqual(m.display, 'standalone');
  assert.strictEqual(m.start_url, '/');
  assert.strictEqual(m.scope, '/');
  assert.ok(m.icons.some((i) => i.sizes === '192x192' && i.purpose === 'any'));
  assert.ok(m.icons.some((i) => i.sizes === '512x512' && i.purpose === 'any'));
  assert.ok(m.icons.some((i) => i.purpose === 'maskable'));
  for (const f of [...m.icons, ...(m.screenshots || [])]) {
    const r = await fetch(`${base}${f.src}`);
    assert.strictEqual(r.status, 200, f.src);
    assert.strictEqual(r.headers.get('content-type'), 'image/png', f.src);
  }
  const sw = await fetch(`${base}/sw.js`);
  assert.strictEqual(sw.status, 200);
  assert.match(sw.headers.get('content-type'), /javascript/);
  assert.strictEqual(sw.headers.get('cache-control'), 'no-cache');
  const swText = await sw.text();
  // The worker must leave the API alone.
  for (const p of ["'/v1/'", "'/admin/'", "'/health'", "'authorization'"]) assert.ok(swText.includes(p), p);
  const html = await (await fetch(`${base}/`, { headers: { Accept: 'text/html' } })).text();
  assert.match(html, /<link rel="manifest" href="manifest.json">/);
  assert.match(html, /<script src="pwa.js" defer><\/script>/);
  assert.strictEqual((await fetch(`${base}/pwa.js`)).status, 200);
  const boot = await (await fetch(`${base}/flutter_bootstrap.js`)).text();
  assert.ok(!boot.includes('serviceWorkerVersion: "'), 'Flutter service worker must not be registered');
});

test('an API client asking for JSON at / still gets the status', async () => {
  const r = await fetch(`${base}/`, { headers: { Accept: 'application/json' } });
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(await r.json(), { name: 'Bangla AI server', ok: true });
});

test('app files are served, gzipped, with the wasm type', { skip: !hasBuild && 'no public/ build' }, async () => {
  const http = require('node:http');
  const get = (p) =>
    new Promise((resolve, reject) => {
      http
        .get(`${base}${p}`, { headers: { 'Accept-Encoding': 'gzip' } }, (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => resolve({ res, body: Buffer.concat(chunks) }));
        })
        .on('error', reject);
    });
  const js = await get('/main.dart.js');
  assert.strictEqual(js.res.statusCode, 200);
  assert.strictEqual(js.res.headers['content-encoding'], 'gzip');
  assert.ok(zlib.gunzipSync(js.body).length > js.body.length);
  const wasm = await get('/canvaskit/canvaskit.wasm');
  assert.strictEqual(wasm.res.statusCode, 200);
  assert.strictEqual(wasm.res.headers['content-type'], 'application/wasm');
  // Revalidation answers 304.
  const again = await fetch(`${base}/main.dart.js`, { headers: { 'If-None-Match': js.res.headers.etag } });
  assert.strictEqual(again.status, 304);
});

test('the API is unchanged and nothing escapes public/', async () => {
  const h = await fetch(`${base}/health`);
  assert.strictEqual(h.status, 200);
  assert.strictEqual((await h.json()).ok, true);
  const c = await fetch(`${base}/v1/config`);
  assert.strictEqual(c.status, 200);
  const missing = await fetch(`${base}/v1/nope`);
  assert.strictEqual(missing.status, 404);
  const admin = await fetch(`${base}/admin/config`);
  assert.strictEqual(admin.status, 401);
  const escape = await fetch(`${base}/..%2fserver.js`);
  assert.strictEqual(escape.status, 404);
  const pkg = await fetch(`${base}/%2e%2e/package.json`);
  assert.strictEqual(pkg.status, 404);
});
