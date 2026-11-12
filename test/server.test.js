'use strict';

// Runs the server against a fake OmniRoute. `npm test`
const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bai-'));
process.env.CONFIG_FILE = path.join(dir, 'config.json');
// Trailing space and a decomposed Bangla vowel sign, as a web form might store it.
process.env.ADMIN_PASSWORD = 'test-pass\u09CB ';
process.env.MODELS = 'auto,auto/fast';
delete process.env.DATABASE_URL;

let lastUpstream = null;
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    lastUpstream = { auth: req.headers.authorization, body: JSON.parse(body) };
    if (req.headers.authorization !== 'Bearer sk-secret-1234') {
      res.writeHead(401);
      return res.end('{"error":{"message":"bad key"}}');
    }
    if (lastUpstream.body.stream) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.write('data: {"choices":[{"delta":{"content":"হ্যা"}}]}\n\n');
      res.write('data: {"choices":[{"delta":{"content":"লো"}}]}\n\n');
      return res.end('data: [DONE]\n\n');
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { content: 'হ্যালো' } }] }));
  });
});

let base;
let server;
test.before(async () => {
  await new Promise((r) => fake.listen(0, r));
  const { start } = require('../server.js');
  server = await start({ port: 0 });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => {
  server.close();
  fake.close();
});

const j = async (p, opts = {}) => {
  const r = await fetch(base + p, {
    ...opts,
    headers: { 'Content-Type': 'application/json', ...(opts.headers || {}) },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  return { status: r.status, body: await r.json().catch(() => null) };
};

let token;

test('health', async () => {
  const r = await j('/health');
  assert.equal(r.status, 200);
  assert.equal(r.body.ok, true);
  assert.equal(r.body.store, 'file');
});

test('public config has no key and is not ready yet', async () => {
  const r = await j('/v1/config');
  assert.equal(r.body.ready, false);
  assert.deepEqual(r.body.models, ['auto', 'auto/fast']);
  assert.equal('apiKey' in r.body, false);
});

test('admin login: wrong then right', async () => {
  assert.equal((await j('/admin/login', { method: 'POST', body: { password: 'nope' } })).status, 401);
  const r = await j('/admin/login', { method: 'POST', body: { password: ' test-pass\u09C7\u09BE\n' } });
  assert.equal(r.status, 200);
  token = r.body.token;
  assert.ok(token);
});

test('admin endpoints need a token', async () => {
  assert.equal((await j('/admin/config')).status, 401);
  assert.equal((await j('/admin/config', { headers: { Authorization: 'Bearer x.y' } })).status, 401);
});

test('admin saves config; key masked; public view updated', async () => {
  const auth = { Authorization: `Bearer ${token}` };
  const bad = await j('/admin/config', { method: 'PUT', headers: auth, body: { speed: 9 } });
  assert.equal(bad.status, 400);
  const r = await j('/admin/config', {
    method: 'PUT',
    headers: auth,
    body: {
      baseUrl: `http://127.0.0.1:${fake.address().port}/v1/`,
      apiKey: 'sk-secret-1234',
      models: ['auto', 'gpt-x', 'auto'],
      defaultModel: 'gpt-x',
      systemPrompt: 'Be kind.',
      voiceName: 'bn-bd-x-ban-local',
      speed: 1.2,
      pitch: 0.9,
    },
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.config.apiKeySet, true);
  assert.equal(r.body.config.apiKeyHint, '••••1234');
  assert.equal(r.body.config.apiKey, undefined);
  assert.deepEqual(r.body.config.models, ['auto', 'gpt-x']);
  assert.ok(!r.body.config.baseUrl.endsWith('/'));
  // An empty key keeps the stored one.
  await j('/admin/config', { method: 'PUT', headers: auth, body: { apiKey: '' } });
  const pub = await j('/v1/config');
  assert.equal(pub.body.ready, true);
  assert.equal(pub.body.defaultModel, 'gpt-x');
  assert.equal(pub.body.voiceName, 'bn-bd-x-ban-local');
  assert.equal(pub.body.speed, 1.2);
  assert.ok(!JSON.stringify(pub.body).includes('sk-secret'));
  // Persisted to the store.
  const saved = JSON.parse(fs.readFileSync(process.env.CONFIG_FILE, 'utf8'));
  assert.equal(saved.apiKey, 'sk-secret-1234');
});

test('admin test connection', async () => {
  const auth = { Authorization: `Bearer ${token}` };
  const ok = await j('/admin/test', { method: 'POST', headers: auth, body: {} });
  assert.equal(ok.body.ok, true);
  assert.equal(ok.body.reply, 'হ্যালো');
  const no = await j('/admin/test', { method: 'POST', headers: auth, body: { apiKey: 'wrong' } });
  assert.equal(no.body.ok, false);
  assert.match(no.body.error, /rejected the API key/);
});

test('chat proxy streams, adds the key and the admin prompt, forces allowed model', async () => {
  const r = await fetch(`${base}/v1/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'not-allowed',
      messages: [
        { role: 'system', content: 'বাংলায় উত্তর দাও।' },
        { role: 'user', content: 'হ্যালো' },
      ],
    }),
  });
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type'), /event-stream/);
  const text = await r.text();
  assert.match(text, /হ্যা/);
  assert.match(text, /\[DONE\]/);
  assert.equal(lastUpstream.auth, 'Bearer sk-secret-1234');
  assert.equal(lastUpstream.body.model, 'gpt-x');
  assert.equal(lastUpstream.body.messages[0].role, 'system');
  assert.equal(lastUpstream.body.messages[0].content, 'Be kind.\n\nবাংলায় উত্তর দাও।');
  assert.equal(lastUpstream.body.messages.length, 2);
});

test('chat proxy non-stream and validation', async () => {
  const r = await j('/v1/chat', {
    method: 'POST',
    body: { stream: false, model: 'auto', messages: [{ role: 'user', content: 'hi' }] },
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.choices[0].message.content, 'হ্যালো');
  assert.equal(lastUpstream.body.model, 'auto');
  const bad = await j('/v1/chat', { method: 'POST', body: { messages: [{ role: 'tool', content: 1 }] } });
  assert.equal(bad.status, 400);
});

test('disabled switch blocks chat with the message', async () => {
  const auth = { Authorization: `Bearer ${token}` };
  await j('/admin/config', { method: 'PUT', headers: auth, body: { enabled: false, disabledMessage: 'বন্ধ' } });
  const r = await j('/v1/chat', { method: 'POST', body: { messages: [{ role: 'user', content: 'hi' }] } });
  assert.equal(r.status, 503);
  assert.equal(r.body.error.code, 'disabled');
  assert.equal(r.body.error.message, 'বন্ধ');
  assert.equal((await j('/v1/config')).body.enabled, false);
  await j('/admin/config', { method: 'PUT', headers: auth, body: { enabled: true } });
});

test('admin login: wrong password says so, too many fails are limited', async () => {
  const bad1 = await j('/admin/login', { method: 'POST', body: { password: 'TEST-PASS' } });
  assert.equal(bad1.status, 401);
  assert.equal(bad1.body.error.code, 'wrong_password');
  let last;
  for (let i = 0; i < 10; i++) last = await j('/admin/login', { method: 'POST', body: { password: 'x' } });
  assert.equal(last.status, 429);
  assert.equal(last.body.error.code, 'rate_limited');
});
