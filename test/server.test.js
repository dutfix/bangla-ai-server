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
process.env.ADMIN_EMAIL = ' Admin@Example.com ';
process.env.RESEND_API_KEY = 're_test_key';
process.env.TOKEN_SECRET = 'test-secret';
process.env.CODE_SEND_GAP_MS = '50';
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

// Fake Resend: remembers the last email.
let lastMail = null;
let mailFails = false;
const mailer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    if (mailFails) {
      res.writeHead(403);
      return res.end('{"message":"nope"}');
    }
    lastMail = { auth: req.headers.authorization, body: JSON.parse(body) };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end('{"id":"x"}');
  });
});
const mailedCode = () => lastMail.body.text.match(/(\d{6})/)[1];

let base;
let server;
test.before(async () => {
  await new Promise((r) => fake.listen(0, r));
  await new Promise((r) => mailer.listen(0, r));
  process.env.RESEND_API_URL = `http://127.0.0.1:${mailer.address().port}/emails`;
  const { start } = require('../server.js');
  server = await start({ port: 0 });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => {
  server.close();
  fake.close();
  mailer.close();
});

let ipN = 0;
const j = async (p, opts = {}) => {
  ipN += 1;
  const r = await fetch(base + p, {
    ...opts,
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': `10.0.0.${ipN % 250}`,
      ...(opts.headers || {}),
    },
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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ask = (email) => j('/admin/request-code', { method: 'POST', body: { email } });
const verify = (email, code) => j('/admin/verify-code', { method: 'POST', body: { email, code } });

test('email code sign-in: generic answer, code mailed only to the admin', async () => {
  lastMail = null;
  const other = await ask('someone@else.com');
  assert.equal(other.status, 200);
  assert.equal(lastMail, null);
  await sleep(60);
  const r = await ask('ADMIN@example.com ');
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.body).sort(), Object.keys(other.body).sort());
  assert.equal(r.body.message, other.body.message);
  assert.equal(lastMail.auth, 'Bearer re_test_key');
  assert.deepEqual(lastMail.body.to, ['admin@example.com']);
  assert.match(lastMail.body.subject, /\d{6}/);
  assert.equal((await ask('not-an-email')).status, 400);
  // The password route is gone.
  assert.equal((await j('/admin/login', { method: 'POST', body: { password: 'x' } })).status, 410);
});

test('email code sign-in: wrong code, then right code once', async () => {
  await sleep(60);
  await ask('admin@example.com');
  const code = mailedCode();
  const wrongCode = code === '000000' ? '111111' : '000000';
  const w = await verify('admin@example.com', wrongCode);
  assert.equal(w.status, 401);
  assert.equal(w.body.error.code, 'wrong_code');
  assert.equal(w.body.error.triesLeft, 4);
  const r = await verify(' Admin@Example.com', code.split('').join(' '));
  assert.equal(r.status, 200);
  assert.equal(r.body.expiresInDays, 30);
  token = r.body.token;
  assert.ok(token);
  // Single use.
  assert.equal((await verify('admin@example.com', code)).status, 401);
});

test('email code sign-in: five wrong tries end the code; wrong email never works', async () => {
  await sleep(60);
  await ask('admin@example.com');
  const code = mailedCode();
  assert.equal((await verify('other@example.com', code)).body.error.code, 'wrong_code');
  const wrongCode = code === '000000' ? '111111' : '000000';
  let last;
  for (let i = 0; i < 4; i++) last = await verify('admin@example.com', wrongCode);
  assert.equal(last.status, 429);
  assert.equal(last.body.error.code, 'too_many_tries');
  assert.equal((await verify('admin@example.com', code)).status, 401);
});

test('email code sign-in: expired code and send limits', async () => {
  await sleep(60);
  await ask('admin@example.com');
  const { _expireForTest } = require('../server.js');
  _expireForTest();
  const e = await verify('admin@example.com', mailedCode());
  assert.equal(e.body.error.code, 'expired_code');
  // One address asking twice within the gap is told to wait.
  const h = { 'X-Forwarded-For': '10.9.9.9' };
  await j('/admin/request-code', { method: 'POST', headers: h, body: { email: 'a@b.co' } });
  const again = await j('/admin/request-code', { method: 'POST', headers: h, body: { email: 'a@b.co' } });
  assert.equal(again.status, 429);
  assert.equal(again.body.error.code, 'too_soon');
  // A mailer failure still gives the generic answer.
  await sleep(60);
  mailFails = true;
  const f = await ask('admin@example.com');
  mailFails = false;
  assert.equal(f.status, 200);
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
