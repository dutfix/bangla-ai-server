// Bangla AI backend for Render.com (Node 20+, one dependency: pg).
//
// - Keeps the OmniRoute key on the server: the apps never see it.
// - GET  /health               liveness check (no database, answers fast)
// - GET  /v1/config            public app config (no key)
// - POST /v1/chat              chat proxy to OmniRoute, streams SSE back
// - POST /admin/login          admin password -> signed token (12 h)
// - GET  /admin/config         full config, key masked (admin)
// - PUT  /admin/config         update any config field (admin)
// - POST /admin/test           test OmniRoute with stored or draft values
//
// Config is stored in Postgres (DATABASE_URL) so it survives restarts and
// redeploys. Without DATABASE_URL it uses a JSON file (local development).
// Initial values come from environment variables (see README.md).

'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const env = process.env;
const PORT = Number(env.PORT || 10000);
const ADMIN_PASSWORD = env.ADMIN_PASSWORD || '';
// Signs admin tokens. Derived from the password when not set, so changing
// the password signs everyone out.
const TOKEN_SECRET =
  env.TOKEN_SECRET ||
  crypto.createHash('sha256').update(`bangla-ai:${ADMIN_PASSWORD}`).digest('hex');
const TOKEN_HOURS = 12;
// Optional shared key the main app sends in X-App-Key, to keep casual
// strangers off the chat proxy. Not a real secret: it ships in the APK.
const APP_KEY = env.APP_KEY || '';
// Table name, so the server can share a database with other apps safely.
const CONFIG_TABLE = /^[a-z_][a-z0-9_]{0,62}$/.test(env.CONFIG_TABLE || '')
  ? env.CONFIG_TABLE
  : 'bangla_ai_config';

const LIMITS = {
  bodyBytes: 256 * 1024,
  messages: 60,
  messageChars: 16000,
  upstreamTimeoutMs: 120000,
};

// ---------------------------------------------------------------- config

function listEnv(name, fallback) {
  const v = env[name];
  if (!v) return fallback;
  return v.split(',').map((s) => s.trim()).filter(Boolean);
}

function numEnv(name, fallback) {
  const n = Number(env[name]);
  return Number.isFinite(n) && env[name] !== undefined && env[name] !== '' ? n : fallback;
}

/** The starting config, from environment variables. */
function seedConfig() {
  const models = listEnv('MODELS', ['auto', 'auto/fast']);
  return {
    enabled: env.APP_ENABLED !== 'false',
    disabledMessage:
      env.DISABLED_MESSAGE ||
      'অ্যাপটি এখন সাময়িকভাবে বন্ধ আছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।',
    baseUrl: env.OMNIROUTE_BASE_URL || '',
    apiKey: env.OMNIROUTE_API_KEY || '',
    models,
    defaultModel: env.DEFAULT_MODEL || models[0] || 'auto',
    systemPrompt: env.SYSTEM_PROMPT || '',
    voiceName: env.VOICE_NAME || '',
    voiceLocale: env.VOICE_LOCALE || 'bn-BD',
    speed: numEnv('VOICE_SPEED', 1.0),
    pitch: numEnv('VOICE_PITCH', 1.0),
    updatedAt: new Date(0).toISOString(),
  };
}

/** Checks and cleans a partial config from the admin. Throws on bad input. */
function cleanPatch(p) {
  if (!p || typeof p !== 'object' || Array.isArray(p)) throw bad('Body must be a JSON object.');
  const out = {};
  const str = (k, max) => {
    if (p[k] === undefined) return;
    if (typeof p[k] !== 'string') throw bad(`${k} must be text.`);
    if (p[k].length > max) throw bad(`${k} is too long.`);
    out[k] = p[k].trim();
  };
  if (p.enabled !== undefined) {
    if (typeof p.enabled !== 'boolean') throw bad('enabled must be true or false.');
    out.enabled = p.enabled;
  }
  str('disabledMessage', 500);
  str('baseUrl', 500);
  str('systemPrompt', 8000);
  str('voiceName', 200);
  str('voiceLocale', 20);
  str('defaultModel', 200);
  // An empty or missing key keeps the stored one; send clearApiKey to remove it.
  if (typeof p.apiKey === 'string' && p.apiKey.trim()) {
    if (p.apiKey.length > 1000) throw bad('apiKey is too long.');
    out.apiKey = p.apiKey.trim();
  }
  if (p.clearApiKey === true) out.apiKey = '';
  if (out.baseUrl) {
    let u;
    try {
      u = new URL(out.baseUrl);
    } catch {
      throw bad('baseUrl is not a valid address.');
    }
    if (!/^https?:$/.test(u.protocol)) throw bad('baseUrl must start with http:// or https://');
    out.baseUrl = out.baseUrl.replace(/\/+$/, '');
  }
  if (p.models !== undefined) {
    if (!Array.isArray(p.models) || p.models.some((m) => typeof m !== 'string')) {
      throw bad('models must be a list of text.');
    }
    const models = [...new Set(p.models.map((m) => m.trim()).filter(Boolean))];
    if (!models.length) throw bad('Add at least one model.');
    if (models.length > 50) throw bad('Too many models.');
    out.models = models;
  }
  for (const [k, lo, hi] of [['speed', 0.25, 2.5], ['pitch', 0.5, 2.0]]) {
    if (p[k] === undefined) continue;
    const n = Number(p[k]);
    if (!Number.isFinite(n) || n < lo || n > hi) throw bad(`${k} must be between ${lo} and ${hi}.`);
    out[k] = Math.round(n * 100) / 100;
  }
  return out;
}

function merge(cfg, patch) {
  const next = { ...cfg, ...patch, updatedAt: new Date().toISOString() };
  if (!next.models.includes(next.defaultModel)) next.defaultModel = next.models[0];
  return next;
}

/** What the main app may see: everything except the key. */
function publicConfig(cfg) {
  return {
    enabled: cfg.enabled,
    disabledMessage: cfg.disabledMessage,
    models: cfg.models,
    defaultModel: cfg.defaultModel,
    voiceName: cfg.voiceName,
    voiceLocale: cfg.voiceLocale,
    speed: cfg.speed,
    pitch: cfg.pitch,
    ready: Boolean(cfg.baseUrl && cfg.apiKey),
    updatedAt: cfg.updatedAt,
  };
}

/** What the admin sees: the key masked to its last 4 characters. */
function adminConfig(cfg) {
  const k = cfg.apiKey || '';
  return {
    ...cfg,
    apiKey: undefined,
    apiKeySet: Boolean(k),
    apiKeyHint: k ? `••••${k.slice(-4)}` : '',
  };
}

// ---------------------------------------------------------------- storage

class PgStore {
  constructor(url) {
    const { Pool } = require('pg');
    const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url) || /\.internal[:/]|@dpg-[^.]+[:/]/.test(url);
    this.pool = new Pool({
      connectionString: url,
      max: 3,
      // Render's internal URLs need no TLS; external and Neon URLs do.
      ssl: local || /sslmode=disable/.test(url) ? false : { rejectUnauthorized: false },
    });
    this.kind = 'postgres';
  }
  async init() {
    await this.pool.query(
      `CREATE TABLE IF NOT EXISTS ${CONFIG_TABLE} (id INT PRIMARY KEY, data JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
    );
  }
  async load() {
    const r = await this.pool.query(`SELECT data FROM ${CONFIG_TABLE} WHERE id = 1`);
    return r.rows[0] ? r.rows[0].data : null;
  }
  async save(cfg) {
    await this.pool.query(
      `INSERT INTO ${CONFIG_TABLE} (id, data, updated_at) VALUES (1, $1, now()) ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [cfg],
    );
  }
}

class FileStore {
  constructor(file) {
    this.file = file;
    this.kind = 'file';
  }
  async init() {}
  async load() {
    try {
      return JSON.parse(fs.readFileSync(this.file, 'utf8'));
    } catch {
      return null;
    }
  }
  async save(cfg) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(this.file, JSON.stringify(cfg, null, 2));
  }
}

function makeStore() {
  if (env.DATABASE_URL) return new PgStore(env.DATABASE_URL);
  return new FileStore(env.CONFIG_FILE || path.join(__dirname, 'data', 'config.json'));
}

// ---------------------------------------------------------------- state

let store = null;
let config = seedConfig();
let storeOk = false;
let storeError = '';

async function loadConfig() {
  try {
    await store.init();
    const saved = await store.load();
    // Saved values win; fields added in later versions come from the seed.
    config = saved ? { ...seedConfig(), ...saved } : seedConfig();
    if (!saved) await store.save(config);
    storeOk = true;
    storeError = '';
  } catch (e) {
    storeOk = false;
    storeError = String(e && e.message ? e.message : e);
    console.error('Config store unavailable, using environment values:', storeError);
  }
}

async function saveConfig(next) {
  config = next;
  try {
    await store.save(next);
    storeOk = true;
    storeError = '';
  } catch (e) {
    storeOk = false;
    storeError = String(e && e.message ? e.message : e);
    throw Object.assign(new Error(`Saved in memory only: the database failed (${storeError}).`), {
      status: 503,
    });
  }
}

// ---------------------------------------------------------------- helpers

function bad(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-App-Key',
  'Access-Control-Max-Age': '86400',
};

function send(res, status, body, headers = {}) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    ...CORS,
    ...headers,
  });
  res.end(data);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > LIMITS.bodyBytes) {
        reject(bad('Request is too large.', 413));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(bad('Body is not valid JSON.'));
      }
    });
    req.on('error', reject);
  });
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function signToken() {
  const payload = b64url(JSON.stringify({ exp: Date.now() + TOKEN_HOURS * 3600e3 }));
  const sig = b64url(crypto.createHmac('sha256', TOKEN_SECRET).update(payload).digest());
  return `${payload}.${sig}`;
}

function verifyToken(token) {
  if (!token || !token.includes('.')) return false;
  const [payload, sig] = token.split('.');
  const want = b64url(crypto.createHmac('sha256', TOKEN_SECRET).update(payload).digest());
  const a = Buffer.from(sig);
  const b = Buffer.from(want);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return false;
  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString()).exp > Date.now();
  } catch {
    return false;
  }
}

function requireAdmin(req) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  if (!verifyToken(token)) throw bad('Please sign in again.', 401);
}

function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

// Login attempts per IP: at most 8 per 10 minutes.
const attempts = new Map();
function loginAllowed(ip) {
  const now = Date.now();
  const list = (attempts.get(ip) || []).filter((t) => now - t < 10 * 60e3);
  attempts.set(ip, list);
  if (list.length >= 8) return false;
  list.push(now);
  return true;
}

function clientIp(req) {
  const f = req.headers['x-forwarded-for'];
  return (typeof f === 'string' && f.split(',')[0].trim()) || req.socket.remoteAddress || '';
}

/** Validates chat messages from the app. */
function cleanMessages(list) {
  if (!Array.isArray(list) || !list.length) throw bad('messages must be a non-empty list.');
  if (list.length > LIMITS.messages) list = list.slice(-LIMITS.messages);
  return list.map((m) => {
    if (!m || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string') {
      throw bad('Each message needs a role (system, user, assistant) and text content.');
    }
    return { role: m.role, content: m.content.slice(0, LIMITS.messageChars) };
  });
}

function upstreamError(status, text) {
  let detail = text;
  try {
    const j = JSON.parse(text);
    detail = (j.error && (j.error.message || j.error)) || j.message || text;
  } catch {}
  detail = String(detail).slice(0, 300);
  if (status === 401 || status === 403) return `OmniRoute rejected the API key (${status}).`;
  if (status === 404) return 'OmniRoute returned 404: check that the base URL ends with /v1 and the model name.';
  return `OmniRoute error ${status}: ${detail}`;
}

async function callOmniRoute(cfg, body, signal) {
  if (!cfg.baseUrl || !cfg.apiKey) {
    throw bad('The server has no OmniRoute address or key yet. Set them in the admin app.', 503);
  }
  let res;
  try {
    res = await fetch(`${cfg.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg.apiKey}`,
        Accept: body.stream ? 'text/event-stream' : 'application/json',
      },
      body: JSON.stringify(body),
      signal,
    });
  } catch (e) {
    if (e && e.name === 'AbortError') throw bad('OmniRoute took too long to answer.', 504);
    throw bad(`Could not reach OmniRoute at ${cfg.baseUrl}: ${e && e.cause ? e.cause.code || e.cause.message : e}`, 502);
  }
  return res;
}

// ---------------------------------------------------------------- routes

async function chat(req, res) {
  if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) throw bad('Unknown app.', 401);
  const cfg = config;
  if (!cfg.enabled) throw Object.assign(bad(cfg.disabledMessage, 503), { code: 'disabled' });
  const body = await readJson(req);
  const app = cleanMessages(body.messages);
  const model = cfg.models.includes(body.model) ? body.model : cfg.defaultModel;
  const stream = body.stream !== false;
  // The admin's system prompt goes first, then the app's own system lines
  // (reply language, call style), then the conversation.
  const sys = [cfg.systemPrompt, ...app.filter((m) => m.role === 'system').map((m) => m.content)]
    .filter((s) => s && s.trim())
    .join('\n\n');
  const messages = [
    ...(sys ? [{ role: 'system', content: sys }] : []),
    ...app.filter((m) => m.role !== 'system'),
  ];
  const upstreamBody = { model, messages, stream };
  if (Number.isFinite(body.max_tokens)) upstreamBody.max_tokens = Math.min(Math.max(1, body.max_tokens), 4096);
  if (Number.isFinite(body.temperature)) upstreamBody.temperature = Math.min(Math.max(0, body.temperature), 2);

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), LIMITS.upstreamTimeoutMs);
  res.on('close', () => ctl.abort());
  try {
    const up = await callOmniRoute(cfg, upstreamBody, ctl.signal);
    if (!up.ok) {
      const text = await up.text();
      throw bad(upstreamError(up.status, text), up.status === 401 || up.status === 403 ? 502 : up.status);
    }
    res.writeHead(200, {
      'Content-Type': stream ? 'text/event-stream; charset=utf-8' : 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Accel-Buffering': 'no',
      'X-Model': model,
      ...CORS,
    });
    if (!up.body) return res.end();
    for await (const chunk of up.body) {
      if (!res.write(chunk)) await new Promise((r) => res.once('drain', r));
    }
    res.end();
  } catch (e) {
    if (res.headersSent) {
      // Mid-stream failure: tell the app in the stream itself.
      if (e.name !== 'AbortError') {
        res.write(`data: ${JSON.stringify({ error: { message: String(e.message || e) } })}\n\n`);
      }
      return res.end();
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

async function testConnection(req, res) {
  requireAdmin(req);
  const draft = await readJson(req);
  const patch = cleanPatch({ ...draft, models: draft.models || undefined });
  const cfg = { ...config, ...patch };
  const model = draft.model || patch.defaultModel || cfg.defaultModel;
  const started = Date.now();
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 45000);
  try {
    const up = await callOmniRoute(
      cfg,
      {
        model,
        stream: false,
        max_tokens: 30,
        messages: [{ role: 'user', content: 'একটি শব্দে উত্তর দাও: হ্যালো' }],
      },
      ctl.signal,
    );
    const text = await up.text();
    if (!up.ok) return send(res, 200, { ok: false, status: up.status, error: upstreamError(up.status, text) });
    let reply = '';
    try {
      reply = JSON.parse(text).choices[0].message.content || '';
    } catch {
      return send(res, 200, { ok: false, error: 'OmniRoute answered, but not in the OpenAI format.' });
    }
    send(res, 200, { ok: true, model, reply: reply.trim().slice(0, 200), ms: Date.now() - started });
  } catch (e) {
    send(res, 200, { ok: false, error: String(e.message || e) });
  } finally {
    clearTimeout(timer);
  }
}

async function route(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const m = req.method;

  if (m === 'OPTIONS') {
    res.writeHead(204, CORS);
    return res.end();
  }
  if (p === '/health' && (m === 'GET' || m === 'HEAD')) {
    return send(res, 200, { ok: true, store: store.kind, storeOk, time: new Date().toISOString() });
  }
  if (p === '/' && m === 'GET') {
    return send(res, 200, { name: 'Bangla AI server', ok: true });
  }
  if (p === '/v1/config' && m === 'GET') {
    return send(res, 200, publicConfig(config));
  }
  if (p === '/v1/chat' && m === 'POST') return chat(req, res);

  if (p === '/admin/login' && m === 'POST') {
    if (!ADMIN_PASSWORD) throw bad('ADMIN_PASSWORD is not set on the server.', 503);
    if (!loginAllowed(clientIp(req))) throw bad('Too many attempts. Wait 10 minutes.', 429);
    const { password } = await readJson(req);
    if (typeof password !== 'string' || !safeEqual(password, ADMIN_PASSWORD)) {
      throw bad('Wrong password.', 401);
    }
    return send(res, 200, { token: signToken(), expiresInHours: TOKEN_HOURS });
  }
  if (p === '/admin/config' && m === 'GET') {
    requireAdmin(req);
    return send(res, 200, { config: adminConfig(config), store: store.kind, storeOk, storeError });
  }
  if (p === '/admin/config' && (m === 'PUT' || m === 'POST')) {
    requireAdmin(req);
    const patch = cleanPatch(await readJson(req));
    await saveConfig(merge(config, patch));
    return send(res, 200, { config: adminConfig(config), store: store.kind, storeOk });
  }
  if (p === '/admin/test' && m === 'POST') return testConnection(req, res);

  throw bad('Not found.', 404);
}

function handler(req, res) {
  route(req, res).catch((e) => {
    const status = e.status || 500;
    if (status >= 500 && status !== 503) console.error(e);
    if (res.headersSent) return res.end();
    send(res, status, { error: { message: String(e.message || e), code: e.code || undefined } });
  });
}

async function start({ port = PORT } = {}) {
  store = makeStore();
  // Listen first so Render's health check passes while the database wakes.
  const server = http.createServer(handler);
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  await new Promise((r) => server.listen(port, '0.0.0.0', r));
  await loadConfig();
  // Retry the database in the background if it was asleep or unreachable.
  if (!storeOk) {
    const retry = setInterval(async () => {
      if (storeOk) return clearInterval(retry);
      await loadConfig();
    }, 15000);
    retry.unref();
  }
  console.log(`Bangla AI server on :${server.address().port} (store: ${store.kind}, ok: ${storeOk})`);
  return server;
}

if (require.main === module) {
  if (!ADMIN_PASSWORD) console.warn('Warning: ADMIN_PASSWORD is not set; admin login is off.');
  start();
}

module.exports = { start, cleanPatch, publicConfig, adminConfig, seedConfig, verifyToken, signToken };
