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
let lastSpeech = null;
let speechCalls = 0;
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    if (req.url.endsWith('/audio/speech')) {
      lastSpeech = { auth: req.headers.authorization, body: JSON.parse(body) };
      if (req.headers.authorization !== 'Bearer tts-key-9876') {
        res.writeHead(401);
        return res.end('{"error":"bad key"}');
      }
      speechCalls += 1;
      res.writeHead(200, { 'Content-Type': 'audio/mpeg' });
      return res.end(Buffer.from('ID3-fake-mp3'));
    }
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
  const sys = lastUpstream.body.messages[0].content;
  assert.ok(sys.startsWith('Be kind.\n\n'));
  assert.match(sys, /laid-back friend/); // the default style prompt
  assert.ok(!/live voice call/.test(sys)); // no call style in text chat
  assert.ok(sys.endsWith('\n\nবাংলায় উত্তর দাও।'));
  assert.equal(lastUpstream.body.max_tokens, undefined);
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

test('voice is off by default; public config has no provider details', async () => {
  const pub = await j('/v1/config');
  assert.equal(pub.body.voiceEnabled, false);
  assert.equal(pub.body.voiceMode, 'off');
  assert.equal(pub.body.callPauseMs, 900);
  const r = await j('/v1/tts', { method: 'POST', body: { text: 'হ্যালো' } });
  assert.equal(r.status, 403);
  assert.equal(r.body.error.code, 'voice_off');
});

test('voice call turn: fast model, short replies, less history, call style', async () => {
  const history = [];
  for (let i = 0; i < 30; i++) history.push({ role: i % 2 ? 'assistant' : 'user', content: `m${i}` });
  history.push({ role: 'user', content: 'শেষ' });
  const r = await fetch(`${base}/v1/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      call: true,
      model: 'gpt-x',
      messages: [{ role: 'system', content: 'বাংলায় উত্তর দাও।' }, ...history],
    }),
  });
  assert.equal(r.status, 200);
  await r.text();
  // Models are auto and gpt-x after the admin save: no auto/fast, so the default.
  assert.equal(lastUpstream.body.model, 'gpt-x');
  assert.equal(lastUpstream.body.max_tokens, 160);
  const sys = lastUpstream.body.messages[0].content;
  assert.match(sys, /live voice call/);
  assert.match(sys, /laid-back friend/);
  assert.equal(lastUpstream.body.messages.length, 1 + 10);
  assert.equal(lastUpstream.body.messages.at(-1).content, 'শেষ');

  const auth = { Authorization: `Bearer ${token}` };
  await j('/admin/config', {
    method: 'PUT',
    headers: auth,
    body: { models: ['auto', 'auto/fast', 'gpt-x'], callMaxTokens: 120, callHistory: 4 },
  });
  const call = async () =>
    (await fetch(`${base}/v1/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ call: true, messages: history }),
    })).text();
  await call();
  assert.equal(lastUpstream.body.model, 'auto/fast');
  assert.equal(lastUpstream.body.max_tokens, 120);
  assert.equal(lastUpstream.body.messages.length, 1 + 4);
  await j('/admin/config', { method: 'PUT', headers: auth, body: { callModel: 'gpt-x' } });
  await call();
  assert.equal(lastUpstream.body.model, 'gpt-x');
  await j('/admin/config', { method: 'PUT', headers: auth, body: { callModel: '' } });
  const bad = await j('/admin/config', { method: 'PUT', headers: auth, body: { callPauseMs: 50 } });
  assert.equal(bad.status, 400);
});

test('voice providers: saved with masked keys, key kept on edit, cloud voice speaks', async () => {
  const auth = { Authorization: `Bearer ${token}` };
  const types = await j('/admin/voice-types', { headers: auth });
  const names = types.body.types.map((t) => t.type);
  for (const t of ['azure', 'google', 'openai', 'elevenlabs']) assert.ok(names.includes(t), t);
  const azure = types.body.types.find((t) => t.type === 'azure');
  assert.ok(azure.fields.find((f) => f.key === 'voice').suggestions.includes('bn-BD-NabanitaNeural'));
  assert.equal((await j('/admin/voice-types')).status, 401);

  const fakeUrl = `http://127.0.0.1:${fake.address().port}/v1`;
  const saved = await j('/admin/config', {
    method: 'PUT',
    headers: auth,
    body: {
      voiceEnabled: true,
      voiceProvider: 'test-voice',
      voiceProviders: [
        { id: 'test-voice', type: 'openai', name: 'Test voice', baseUrl: fakeUrl, model: 'tts-1', voice: 'alloy', apiKey: 'tts-key-9876' },
        { id: 'ms', type: 'azure', name: 'Microsoft', region: 'eastus', voice: 'bn-BD-PradeepNeural' },
      ],
    },
  });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  const list = saved.body.config.voiceProviders;
  assert.equal(list[0].apiKeySet, true);
  assert.equal(list[0].apiKeyHint, '••••9876');
  assert.equal(list[0].apiKey, undefined);
  assert.equal(list[1].apiKeySet, false);
  assert.ok(!JSON.stringify(saved.body).includes('tts-key-9876'));

  const pub = await j('/v1/config');
  assert.equal(pub.body.voiceMode, 'server');
  assert.equal(pub.body.voiceProviders, undefined);
  assert.ok(!JSON.stringify(pub.body).includes('tts-key'));
  assert.ok(!JSON.stringify(pub.body).includes(fakeUrl));

  // Edit without retyping the key: it stays.
  await j('/admin/config', {
    method: 'PUT',
    headers: auth,
    body: { voiceProviders: [{ id: 'test-voice', type: 'openai', name: 'Renamed', baseUrl: fakeUrl, model: 'tts-1', voice: 'nova', apiKey: '' }, list[1]] },
  });
  const file = JSON.parse(fs.readFileSync(process.env.CONFIG_FILE, 'utf8'));
  assert.equal(file.voiceProviders[0].apiKey, 'tts-key-9876');
  assert.equal(file.voiceProviders[0].voice, 'nova');

  const speak = (text) =>
    fetch(`${base}/v1/tts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    });
  const r = await speak('আমি বাংলা এআই।');
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'audio/mpeg');
  assert.equal(Buffer.from(await r.arrayBuffer()).toString(), 'ID3-fake-mp3');
  assert.equal(lastSpeech.body.voice, 'nova');
  assert.equal(lastSpeech.body.input, 'আমি বাংলা এআই।');
  // The same line again comes from the cache.
  const calls = speechCalls;
  await (await speak('আমি বাংলা এআই।')).arrayBuffer();
  assert.equal(speechCalls, calls);
  const long = await j('/v1/tts', { method: 'POST', body: { text: 'ক'.repeat(700) } });
  assert.equal(long.status, 413);

  // Admin sample with the saved key, and with a wrong one.
  const ok = await j('/admin/tts-test', { method: 'POST', headers: auth, body: { provider: { id: 'test-voice', type: 'openai', baseUrl: fakeUrl, model: 'tts-1', voice: 'alloy' } } });
  assert.equal(ok.body.ok, true, JSON.stringify(ok.body));
  assert.equal(Buffer.from(ok.body.audio, 'base64').toString(), 'ID3-fake-mp3');
  const no = await j('/admin/tts-test', { method: 'POST', headers: auth, body: { provider: { id: 'new-one', type: 'openai', baseUrl: fakeUrl, model: 'tts-1', voice: 'alloy', apiKey: 'nope' } } });
  assert.equal(no.body.ok, false);
  assert.match(no.body.error, /rejected the key/);
  const gap = await j('/admin/tts-test', { method: 'POST', headers: auth, body: { provider: { id: 'ms', type: 'azure', region: 'eastus', voice: 'bn-BD-PradeepNeural' } } });
  assert.equal(gap.body.ok, false);
  assert.match(gap.body.error, /missing: Speech key/);

  // A provider without its key cannot be the active voice: the app uses the phone voice.
  await j('/admin/config', { method: 'PUT', headers: auth, body: { voiceProvider: 'ms' } });
  assert.equal((await j('/v1/config')).body.voiceMode, 'device');
  // Removing the active provider falls back to the phone voice.
  const removed = await j('/admin/config', { method: 'PUT', headers: auth, body: { voiceProviders: [] } });
  assert.equal(removed.body.config.voiceProvider, 'device');
  const bad = await j('/admin/config', { method: 'PUT', headers: auth, body: { voiceProviders: [{ type: 'nope' }] } });
  assert.equal(bad.status, 400);
  await j('/admin/config', { method: 'PUT', headers: auth, body: { voiceEnabled: false } });
});

test('admin overview stats, prompt defaults and prompt try-out', async () => {
  const auth = { Authorization: `Bearer ${token}` };
  const st = await j('/admin/stats', { headers: auth });
  assert.equal(st.status, 200);
  assert.ok(st.body.stats.chats >= 2);
  assert.ok(st.body.stats.callTurns >= 3);
  assert.ok(st.body.stats.ttsRequests >= 2);
  assert.equal(st.body.ready, true);
  assert.equal((await j('/admin/stats')).status, 401);
  const d = await j('/admin/defaults', { headers: auth });
  assert.match(d.body.stylePrompt, /laid-back/);
  const t = await j('/admin/try-chat', {
    method: 'POST',
    headers: auth,
    body: { text: 'কেমন আছো?', call: true, draft: { callPrompt: 'Speak briefly.' } },
  });
  assert.equal(t.body.ok, true);
  assert.equal(t.body.reply, 'হ্যালো');
  assert.match(lastUpstream.body.messages[0].content, /Speak briefly\./);
  assert.match(lastUpstream.body.messages[0].content, /natural spoken Bangla/);
});
