// Bangla AI backend for Render.com (Node 20+, one dependency: pg).
//
// - Keeps the OmniRoute key on the server: the apps never see it.
// - GET  /health               liveness check (no database, answers fast)
// - GET  /v1/config            public app config (no key)
// - POST /v1/chat              chat proxy to OmniRoute, streams SSE back
// - POST /admin/request-code   emails a 6-digit code to ADMIN_EMAIL
// - POST /admin/verify-code    email + code -> signed token (30 days)
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
const voice = require('./voice');
const web = require('./web');
const agents = require('./agents');
const { makeTasks } = require('./tasks');
const { createAuth } = require('./auth');

const env = process.env;
const PORT = Number(env.PORT || 10000);
const VERSION = '1.3.0';

// Admin sign-in is passwordless: the admin enters their email, the server
// emails a 6-digit code (through Resend's HTTP API: Render's free plan blocks
// SMTP ports), and the code is exchanged for a signed token.
const ADMIN_EMAIL = normalizeEmail(env.ADMIN_EMAIL);
const ENV_RESEND_KEY = (env.RESEND_API_KEY || '').trim();
// The mailer key comes from RESEND_API_KEY when it looks like a Resend key
// (re_...), else from the database (set once through /admin/setup-mailer).
let RESEND_API_KEY = ENV_RESEND_KEY.startsWith('re_') ? ENV_RESEND_KEY : '';
// One-time setup: sha256 of a random token held by whoever deployed this.
const SETUP_TOKEN_SHA256 = (env.SETUP_TOKEN_SHA256 || 'fa7f5895e018cfca4215719f907c9147fc5f67f5a0a0f59bd60ec860c459b669').trim();
const RESEND_API_URL = env.RESEND_API_URL || 'https://api.resend.com/emails';
const MAIL_FROM = env.MAIL_FROM || 'Bangla AI <onboarding@resend.dev>';
// Signs admin tokens. Without TOKEN_SECRET a random one is used, so a
// restart signs everyone out.
const TOKEN_SECRET = env.TOKEN_SECRET || crypto.randomBytes(32).toString('hex');
const TOKEN_DAYS = 30;
const CODE = {
  ttlMs: 10 * 60e3, // a code works for 10 minutes
  maxTries: 5, // wrong tries per code
  sendGapMs: numEnvEarly('CODE_SEND_GAP_MS', 60e3), // at most one email a minute
  sendsPerHour: 10, // and ten an hour
};

function numEnvEarly(name, fallback) {
  const n = Number(env[name]);
  return env[name] && Number.isFinite(n) ? n : fallback;
}

function normalizeEmail(s) {
  return String(s == null ? '' : s)
    .normalize('NFC')
    .replace(/[\u200B\u200C\u200D\u2060\uFEFF]/g, '')
    .trim()
    .toLowerCase();
}

// Optional shared key the main app sends in X-App-Key, to keep casual
// strangers off the chat proxy. Not a real secret: it ships in the APK.
const APP_KEY = env.APP_KEY || '';
// Table name, so the server can share a database with other apps safely.
const CONFIG_TABLE = /^[a-z_][a-z0-9_]{0,62}$/.test(env.CONFIG_TABLE || '')
  ? env.CONFIG_TABLE
  : 'bangla_ai_config';

const LIMITS = {
  bodyBytes: 512 * 1024,
  messages: 60,
  messageChars: 16000,
  upstreamTimeoutMs: 120000,
  ttsChars: 600, // one sentence or two per /v1/tts request
  ttsCharsPerMinute: 4000, // per phone (IP), protects a paid voice quota
};

// How the AI talks. Admin-editable; these are the starting values.
const DEFAULT_STYLE_PROMPT = [
  'Talk like a sharp, laid-back friend who happens to know a lot: warm, direct, and lightly funny when the moment fits (never forced).',
  'Get to the point. No flattery or canned assistant lines: no "Great question!", "Certainly!", "As an AI...", "I hope this helps", and do not repeat the question back or open every reply with an acknowledgment.',
  'Do not end with a follow-up question unless you truly need an answer to help.',
  'Match the user: a short message gets a short reply; go deeper only when they ask or the topic needs it.',
  'In Bangla, sound like natural everyday spoken Bangla (cholito), not stiff textbook language; in English, plain conversational English.',
  'Be honest: if you are not sure, say so plainly and never make things up. You are an AI assistant; do not claim to be a human.',
  'Use lists, headings or code only when they really help in a text chat.',
].join(' ');

const DEFAULT_CALL_PROMPT = [
  'This is a live voice call, so talk the way people actually speak.',
  'Reply in one to three short spoken sentences. No markdown, lists, emojis, links or code.',
  'Skip filler openers like "Sure!" or "Okay, so". If something needs more detail, give the gist; they will ask for more.',
].join(' ');

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
    // Voice features stay off until the admin sets them up.
    voiceEnabled: env.VOICE_ENABLED === 'true',
    voiceProvider: 'device', // 'device' or the id of an entry in voiceProviders
    voiceProviders: [],
    stylePrompt: env.STYLE_PROMPT || DEFAULT_STYLE_PROMPT,
    callPrompt: env.CALL_PROMPT || DEFAULT_CALL_PROMPT,
    callModel: env.CALL_MODEL || '', // '' = auto/fast when listed, else the default model
    callMaxTokens: numEnv('CALL_MAX_TOKENS', 160),
    callPauseMs: numEnv('CALL_PAUSE_MS', 900),
    callHistory: numEnv('CALL_HISTORY', 10),
    callOfflineVoice: true, // use a phone voice's offline twin in calls (starts faster)
    // Accounts: when true, chat and voice need a signed-in user.
    requireSignIn: env.REQUIRE_SIGN_IN === 'true',
    ttsDailyChars: numEnv('TTS_DAILY_CHARS', 200000),
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
  str('stylePrompt', 8000);
  str('callPrompt', 4000);
  str('callModel', 200);
  str('voiceProvider', 40);
  for (const k of ['voiceEnabled', 'callOfflineVoice', 'requireSignIn']) {
    if (p[k] === undefined) continue;
    if (typeof p[k] !== 'boolean') throw bad(`${k} must be true or false.`);
    out[k] = p[k];
  }
  if (p.voiceProviders !== undefined) out.voiceProviders = voice.cleanProviders(p.voiceProviders, bad);
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
  for (const [k, lo, hi] of [
    ['callMaxTokens', 40, 1000],
    ['callPauseMs', 400, 3000],
    ['callHistory', 2, 40],
    ['ttsDailyChars', 0, 10000000],
  ]) {
    if (p[k] === undefined) continue;
    const n = Number(p[k]);
    if (!Number.isInteger(n) || n < lo || n > hi) throw bad(`${k} must be a whole number from ${lo} to ${hi}.`);
    out[k] = n;
  }
  return out;
}

function merge(cfg, patch) {
  const next = { ...cfg, ...patch, updatedAt: new Date().toISOString() };
  if (patch.voiceProviders) next.voiceProviders = voice.mergeProviders(cfg.voiceProviders, patch.voiceProviders);
  if (!next.models.includes(next.defaultModel)) next.defaultModel = next.models[0];
  if (next.voiceProvider !== 'device' && !next.voiceProviders.some((v) => v.id === next.voiceProvider)) {
    next.voiceProvider = 'device';
  }
  return next;
}

/** The cloud voice provider in use, or null for the phone's own voice. */
function activeProvider(cfg) {
  if (cfg.voiceProvider === 'device') return null;
  const p = (cfg.voiceProviders || []).find((v) => v.id === cfg.voiceProvider);
  return p && !voice.missing(p) ? p : null;
}

/** The model for voice calls: the admin's pick, else a fast one. */
function callModelOf(cfg) {
  if (cfg.callModel) return cfg.callModel;
  return cfg.models.includes('auto/fast') ? 'auto/fast' : cfg.defaultModel;
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
    // 'off' (no call button, no read-aloud), 'device' (phone voice) or
    // 'server' (the app plays audio from POST /v1/tts). No provider details.
    voiceEnabled: Boolean(cfg.voiceEnabled),
    voiceMode: !cfg.voiceEnabled ? 'off' : activeProvider(cfg) ? 'server' : 'device',
    callPauseMs: cfg.callPauseMs,
    callHistory: cfg.callHistory,
    callOfflineVoice: cfg.callOfflineVoice,
    requireSignIn: Boolean(cfg.requireSignIn),
    accounts: auth.options(),
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
    voiceProviders: voice.maskProviders(cfg.voiceProviders),
    callModelInUse: callModelOf(cfg),
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
  // Row 2 holds server-only secrets (never sent to any app).
  async loadSecrets() {
    const r = await this.pool.query(`SELECT data FROM ${CONFIG_TABLE} WHERE id = 2`);
    return r.rows[0] ? r.rows[0].data : {};
  }
  async saveSecrets(data) {
    await this.saveRow(2, data);
  }
  // Row 3 holds the usage counters for the admin's overview.
  async loadRow(id) {
    const r = await this.pool.query(`SELECT data FROM ${CONFIG_TABLE} WHERE id = $1`, [id]);
    return r.rows[0] ? r.rows[0].data : null;
  }
  async saveRow(id, data) {
    await this.pool.query(
      `INSERT INTO ${CONFIG_TABLE} (id, data, updated_at) VALUES ($1, $2, now()) ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [id, data],
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
  async loadSecrets() {
    try {
      return JSON.parse(fs.readFileSync(`${this.file}.secrets`, 'utf8'));
    } catch {
      return {};
    }
  }
  async saveSecrets(data) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(`${this.file}.secrets`, JSON.stringify(data));
  }
  async loadRow(id) {
    try {
      return JSON.parse(fs.readFileSync(`${this.file}.row${id}`, 'utf8'));
    } catch {
      return null;
    }
  }
  async saveRow(id, data) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(`${this.file}.row${id}`, JSON.stringify(data));
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

async function loadSecrets() {
  try {
    const sec = (await store.loadSecrets()) || {};
    if (!RESEND_API_KEY && typeof sec.resendApiKey === 'string' && sec.resendApiKey.startsWith('re_')) {
      RESEND_API_KEY = sec.resendApiKey;
      console.log('Mailer key loaded from the database.');
    }
  } catch (e) {
    console.error(`Could not load server secrets: ${e.message}`);
  }
}

async function setupMailer(req, res) {
  const token = String(req.headers['x-setup-token'] || '');
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  if (!SETUP_TOKEN_SHA256 || !token || !safeEqual(hash, SETUP_TOKEN_SHA256)) {
    throw Object.assign(bad('Not allowed.', 403), { code: 'forbidden' });
  }
  const { resendApiKey } = await readJson(req);
  const key = String(resendApiKey || '').trim();
  if (!/^re_[A-Za-z0-9_]{20,}$/.test(key)) throw bad('That is not a Resend API key.', 400);
  const sec = (await store.loadSecrets()) || {};
  await store.saveSecrets({ ...sec, resendApiKey: key });
  RESEND_API_KEY = key;
  console.log('Mailer key saved to the database.');
  return send(res, 200, { ok: true });
}

async function loadConfig() {
  await loadConfigOnly();
  await loadSecrets();
}

async function loadConfigOnly() {
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
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-App-Key, X-Device',
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
  const payload = b64url(
    JSON.stringify({ sub: ADMIN_EMAIL, exp: Date.now() + TOKEN_DAYS * 86400e3 }),
  );
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

// ---------------------------------------------------------------- sign-in codes
//
// One active code at a time, kept in memory as a hash (a free Render server
// stays awake for 15 minutes after a request, longer than a code lives).

let activeCode = null; // { hash, expires, tries }
let sendTimes = []; // when codes were emailed, for the send limits
const ipRequests = new Map(); // code requests per address, for abuse limits

function hashCode(code) {
  return crypto.createHmac('sha256', TOKEN_SECRET).update(`code:${code}`).digest('hex');
}

function newCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

/** Code requests from one address: one a minute, twenty an hour. */
function ipRequestWait(ip) {
  const now = Date.now();
  const list = (ipRequests.get(ip) || []).filter((t) => now - t < 3600e3);
  ipRequests.set(ip, list);
  if (list.length && now - list[list.length - 1] < CODE.sendGapMs) {
    return Math.ceil((CODE.sendGapMs - (now - list[list.length - 1])) / 1000);
  }
  if (list.length >= 20) return Math.ceil((3600e3 - (now - list[0])) / 1000);
  list.push(now);
  return 0;
}

/** Seconds until another code may be emailed (0 = now). */
function sendWait() {
  const now = Date.now();
  sendTimes = sendTimes.filter((t) => now - t < 3600e3);
  const last = sendTimes[sendTimes.length - 1];
  if (last && now - last < CODE.sendGapMs) return Math.ceil((CODE.sendGapMs - (now - last)) / 1000);
  if (sendTimes.length >= CODE.sendsPerHour) return Math.ceil((3600e3 - (now - sendTimes[0])) / 1000);
  return 0;
}

function codeEmail(code) {
  const subject = `বাংলা এআই অ্যাডমিন কোড: ${code}`;
  const text =
    `আপনার বাংলা এআই অ্যাডমিন সাইন-ইন কোড: ${code}\n` +
    `কোডটি ১০ মিনিট কাজ করবে, একবারই ব্যবহার করা যাবে।\n\n` +
    `Your Bangla AI Admin sign-in code: ${code}\n` +
    `It works for 10 minutes, once. If you didn't ask for it, ignore this email.`;
  const html = `<div style="font-family:Arial,'Noto Sans Bengali',sans-serif;max-width:420px;margin:auto;padding:24px;color:#0f172a">
<div style="background:#006a4e;color:#fff;border-radius:12px;padding:14px 18px;font-size:18px;font-weight:bold">বাংলা এআই অ্যাডমিন</div>
<p style="font-size:15px;margin:20px 0 8px">আপনার সাইন-ইন কোড / Your sign-in code:</p>
<p style="font-size:34px;letter-spacing:8px;font-weight:bold;margin:0 0 16px;color:#006a4e">${code}</p>
<p style="font-size:13px;color:#475569;line-height:1.6">কোডটি ১০ মিনিট কাজ করবে, একবারই ব্যবহার করা যাবে।<br>It works for 10 minutes, once. If you didn't ask for it, ignore this email.</p>
</div>`;
  return { subject, text, html };
}

/** Emails the code through Resend. Throws with a short reason on failure. */
async function mailCode(to, code) {
  if (!RESEND_API_KEY) throw new Error('RESEND_API_KEY is not set');
  const { subject, text, html } = codeEmail(code);
  const r = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: MAIL_FROM, to: [to], subject, text, html }),
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) {
    const body = (await r.text().catch(() => '')).slice(0, 300);
    throw new Error(`Resend answered ${r.status}: ${body}`);
  }
}

const GENERIC_SENT =
  'যদি এই ইমেইলটি অ্যাডমিনের হয়, তাহলে একটি ৬ সংখ্যার কোড পাঠানো হয়েছে। ' +
  'If this email belongs to the admin, a 6-digit code is on its way.';

async function requestCode(req, res) {
  const ip = clientIp(req);
  const { email } = await readJson(req);
  const given = normalizeEmail(email);
  if (!given || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(given) || given.length > 254) {
    throw Object.assign(bad('Enter a valid email address.', 400), { code: 'invalid_email' });
  }
  // This limit is per address and the same for every email, so it reveals
  // nothing about which email is allowed.
  const ipWait = ipRequestWait(ip);
  if (ipWait) {
    throw Object.assign(bad(`Wait ${ipWait} seconds before asking for another code.`, 429), {
      code: 'too_soon',
      retryAfter: ipWait,
    });
  }
  // From here on, the answer is the same whether or not the email matched.
  if (ADMIN_EMAIL && safeEqual(given, ADMIN_EMAIL)) {
    const wait = sendWait();
    if (wait) {
      console.warn(`Admin code not sent: send limit (retry in ${wait}s).`);
    } else {
      const code = newCode();
      sendTimes.push(Date.now());
      try {
        await mailCode(ADMIN_EMAIL, code);
        activeCode = { hash: hashCode(code), expires: Date.now() + CODE.ttlMs, tries: 0 };
        console.log('Admin sign-in code emailed.');
      } catch (e) {
        console.error(`Admin sign-in code could not be emailed: ${e.message}`);
      }
    }
  } else {
    console.warn('Admin code requested for an email that is not the admin email.');
  }
  return send(res, 200, {
    ok: true,
    message: GENERIC_SENT,
    resendAfterSeconds: Math.round(CODE.sendGapMs / 1000),
    expiresInMinutes: Math.round(CODE.ttlMs / 60e3),
  });
}

async function verifyCode(req, res) {
  const { email, code } = await readJson(req);
  const given = normalizeEmail(email);
  const digits = String(code == null ? '' : code).replace(/\D/g, '');
  const wrong = (message, errCode, status = 401) => {
    throw Object.assign(bad(message, status), { code: errCode });
  };
  if (digits.length !== 6) wrong('The code has 6 digits.', 'invalid_code', 400);
  if (!activeCode) wrong('This code is wrong or no longer works. Ask for a new code.', 'invalid_code');
  if (Date.now() > activeCode.expires) {
    activeCode = null;
    wrong('This code has expired. Ask for a new code.', 'expired_code');
  }
  const ok =
    ADMIN_EMAIL && safeEqual(given, ADMIN_EMAIL) && safeEqual(hashCode(digits), activeCode.hash);
  if (!ok) {
    activeCode.tries += 1;
    const left = CODE.maxTries - activeCode.tries;
    console.warn(`Admin code wrong (${activeCode.tries} of ${CODE.maxTries} tries).`);
    if (left <= 0) {
      activeCode = null;
      wrong('Too many wrong tries. Ask for a new code.', 'too_many_tries', 429);
    }
    throw Object.assign(bad(`Wrong code. ${left} ${left === 1 ? 'try' : 'tries'} left.`, 401), {
      code: 'wrong_code',
      triesLeft: left,
    });
  }
  activeCode = null; // single use
  console.log('Admin signed in with an email code.');
  return send(res, 200, { token: signToken(), expiresInDays: TOKEN_DAYS, email: ADMIN_EMAIL });
}

function clientIp(req) {
  const f = req.headers['x-forwarded-for'];
  return (typeof f === 'string' && f.split(',')[0].trim()) || req.socket.remoteAddress || '';
}

// User accounts (sign-up, sign-in, Google, profile). Separate from the admin.
const auth = createAuth({
  env,
  secret: TOKEN_SECRET,
  bad,
  send,
  readJson,
  clientIp,
  sendMail: async ({ to, subject, text, html }) => {
    if (!RESEND_API_KEY) throw new Error('RESEND_API_KEY is not set');
    const r = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: MAIL_FROM, to: [to], subject, text, html }),
      signal: AbortSignal.timeout(15000),
    });
    if (!r.ok) throw new Error(`Resend answered ${r.status}: ${(await r.text().catch(() => '')).slice(0, 300)}`);
  },
  mailReady: () => Boolean(RESEND_API_KEY),
  requireSignIn: () => Boolean(config && config.requireSignIn),
});

/** When the admin requires accounts, chat and voice need a signed-in user. */
async function requireUserIfNeeded(req) {
  if (!config.requireSignIn) return;
  const user = await auth.userOf(req);
  if (!user) throw Object.assign(bad(auth.MSG.signInRequired, 401), { code: 'sign_in_required' });
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

// ---------------------------------------------------------------- usage
//
// Counters for the admin's overview, kept per day (in STATS_TZ, Dhaka by
// default) for the last 120 days and saved in the store every minute. No
// message text, no IP address. A phone is counted by a salted hash of the
// random install id the app sends (X-Device), so it cannot be traced back.

const USAGE_ROW = 3;
const USAGE_DAYS = 120;
const DEVICE_CAP = 20000;
const STATS_TZ = env.STATS_TZ || 'Asia/Dhaka';
const dayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: STATS_TZ, year: 'numeric', month: '2-digit', day: '2-digit' });

function today(d = new Date()) {
  return dayFmt.format(d);
}

let usage = { days: {}, devices: [], errors: [], salt: crypto.randomBytes(16).toString('hex') };
let usageDirty = false;
let deviceSet = new Set();
const recent = { chat: [], call: [], tts: [] }; // the last 50 times, for medians
const startedAt = new Date().toISOString();

function emptyDay() {
  return {
    chats: 0, // text replies asked for
    callTurns: 0, // voice call turns
    userMessages: 0, // = chats + callTurns, kept for clarity
    failures: 0,
    tts: 0,
    ttsChars: 0,
    chatMsSum: 0,
    chatMsN: 0,
    callMsSum: 0,
    callMsN: 0,
    ttsMsSum: 0,
    ttsMsN: 0,
    models: {},
    voices: {},
    errorKinds: {},
    devices: [],
    newDevices: 0,
    agents: {},
    tools: {},
    tasks: 0,
  };
}

function day(d = today()) {
  if (!usage.days[d]) {
    usage.days[d] = emptyDay();
    const keep = Object.keys(usage.days).sort().slice(-USAGE_DAYS);
    for (const k of Object.keys(usage.days)) if (!keep.includes(k)) delete usage.days[k];
  }
  usageDirty = true;
  return usage.days[d];
}

function bump(map, key, n = 1) {
  const k = String(key || 'unknown').slice(0, 80);
  if (!(k in map) && Object.keys(map).length >= 50) return;
  map[k] = (map[k] || 0) + n;
}

function deviceOf(req) {
  const raw = String(req.headers['x-device'] || '').trim();
  if (!/^[A-Za-z0-9-]{8,64}$/.test(raw)) return null;
  return crypto.createHash('sha256').update(`${usage.salt}:device:${raw}`).digest('hex').slice(0, 16);
}

function noteDevice(req) {
  const id = deviceOf(req);
  if (!id) return;
  const d = day();
  if (!d.devices.includes(id) && d.devices.length < DEVICE_CAP) d.devices.push(id);
  if (!deviceSet.has(id) && deviceSet.size < DEVICE_CAP) {
    deviceSet.add(id);
    usage.devices.push(id);
    d.newDevices += 1;
  }
}

function noteTime(kind, ms) {
  const list = recent[kind];
  list.push(ms);
  if (list.length > 50) list.shift();
  const d = day();
  d[`${kind}MsSum`] += ms;
  d[`${kind}MsN`] += 1;
}

function median(list) {
  if (!list.length) return null;
  const a = [...list].sort((x, y) => x - y);
  return a[Math.floor(a.length / 2)];
}

function errorKind(message) {
  const m = String(message);
  if (/rejected the key|401|403/.test(m)) return 'key';
  if (/took longer|timeout|timed out/i.test(m)) return 'timeout';
  if (/429|limit/i.test(m)) return 'limit';
  if (/reach|ECONN|ENOTFOUND|fetch failed/i.test(m)) return 'network';
  return 'other';
}

function noteError(where, message) {
  const d = day();
  d.failures += 1;
  bump(d.errorKinds, `${where}:${errorKind(message)}`);
  usage.errors.unshift({ at: new Date().toISOString(), where, message: String(message).slice(0, 200) });
  usage.errors.length = Math.min(usage.errors.length, 30);
}

let usageLoaded = false;

/** Loads the saved counters and adds what was counted before they loaded. */
async function loadUsage() {
  if (usageLoaded || !store || !storeOk) return;
  try {
    const saved = await store.loadRow(USAGE_ROW);
    usageLoaded = true;
    if (!saved || typeof saved !== 'object' || !saved.days) return;
    const mine = usage;
    usage = {
      days: saved.days || {},
      devices: saved.devices || [],
      errors: saved.errors || [],
      salt: saved.salt || mine.salt,
    };
    for (const [k, d] of Object.entries(usage.days)) usage.days[k] = { ...emptyDay(), ...d };
    for (const [k, d] of Object.entries(mine.days)) {
      const t = (usage.days[k] ||= emptyDay());
      for (const [f, v] of Object.entries(d)) {
        if (typeof v === 'number') t[f] = (t[f] || 0) + v;
        else if (Array.isArray(v)) t[f] = [...new Set([...(t[f] || []), ...v])];
        else if (v && typeof v === 'object') for (const [m, n] of Object.entries(v)) bump((t[f] ||= {}), m, n);
      }
    }
    usage.devices = [...new Set([...usage.devices, ...mine.devices])].slice(0, DEVICE_CAP);
    usage.errors = [...mine.errors, ...usage.errors].slice(0, 30);
    usageDirty = true;
  } catch (e) {
    console.error('Could not load usage counters:', e.message);
  } finally {
    deviceSet = new Set(usage.devices);
  }
}

async function saveUsage() {
  if (!usageDirty || !store || !storeOk) return;
  usageDirty = false;
  try {
    await store.saveRow(USAGE_ROW, usage);
  } catch (e) {
    usageDirty = true;
    console.error('Could not save usage counters:', e.message);
  }
}

function sumDays(keys) {
  const t = emptyDay();
  const devs = new Set();
  for (const k of keys) {
    const d = usage.days[k];
    if (!d) continue;
    for (const f of ['chats', 'callTurns', 'userMessages', 'failures', 'tts', 'ttsChars', 'chatMsSum', 'chatMsN', 'callMsSum', 'callMsN', 'ttsMsSum', 'ttsMsN', 'newDevices']) {
      t[f] += d[f] || 0;
    }
    for (const [m, n] of Object.entries(d.models || {})) bump(t.models, m, n);
    for (const [m, n] of Object.entries(d.voices || {})) bump(t.voices, m, n);
    for (const [m, n] of Object.entries(d.errorKinds || {})) bump(t.errorKinds, m, n);
    for (const id of d.devices || []) devs.add(id);
  }
  const avg = (s, n) => (n ? Math.round(s / n) : null);
  return {
    chats: t.chats,
    callTurns: t.callTurns,
    messages: t.userMessages,
    failures: t.failures,
    tts: t.tts,
    ttsChars: t.ttsChars,
    activeDevices: devs.size,
    newDevices: t.newDevices,
    chatReplyMs: avg(t.chatMsSum, t.chatMsN),
    callReplyMs: avg(t.callMsSum, t.callMsN),
    ttsMs: avg(t.ttsMsSum, t.ttsMsN),
    models: t.models,
    voices: t.voices,
    errorKinds: t.errorKinds,
  };
}

function lastDays(n) {
  const out = [];
  const now = Date.now();
  for (let i = n - 1; i >= 0; i--) out.push(today(new Date(now - i * 86400e3)));
  return [...new Set(out)];
}

function statsView(n = 30) {
  const days = lastDays(Math.min(Math.max(n, 1), USAGE_DAYS));
  return {
    timezone: STATS_TZ,
    today: sumDays([today()]),
    week: sumDays(lastDays(7)),
    month: sumDays(lastDays(30)),
    range: sumDays(days),
    totalDevices: deviceSet.size,
    agents: (() => {
      // Messages per agent, tool uses and background tasks over the range.
      const a = {};
      const t = {};
      let tasksN = 0;
      for (const k of days) {
        const d = usage.days[k];
        if (!d) continue;
        for (const [x, v] of Object.entries(d.agents || {})) a[x] = (a[x] || 0) + v;
        for (const [x, v] of Object.entries(d.tools || {})) t[x] = (t[x] || 0) + v;
        tasksN += d.tasks || 0;
      }
      return { messages: a, tools: t, tasks: tasksN };
    })(),
    series: days.map((k) => {
      const d = usage.days[k] || emptyDay();
      return {
        day: k,
        chats: d.chats,
        callTurns: d.callTurns,
        messages: d.userMessages,
        failures: d.failures,
        tts: d.tts,
        devices: (d.devices || []).length,
        chatReplyMs: d.chatMsN ? Math.round(d.chatMsSum / d.chatMsN) : null,
        callReplyMs: d.callMsN ? Math.round(d.callMsSum / d.callMsN) : null,
      };
    }),
    recent: {
      chatReplyMs: median(recent.chat),
      callReplyMs: median(recent.call),
      ttsMs: median(recent.tts),
    },
    recentErrors: usage.errors.slice(0, 20),
    since: Object.keys(usage.days).sort()[0] || today(),
    serverStartedAt: startedAt,
    uptimeSeconds: Math.round(process.uptime()),
  };
}

// ---------------------------------------------------------------- routes

/** The system prompt the model sees: admin prompt, style, call style, app lines. */
function systemPrompt(cfg, appLines, call) {
  return [cfg.systemPrompt, cfg.stylePrompt, call ? cfg.callPrompt : '', ...appLines]
    .filter((s) => s && s.trim())
    .join('\n\n');
}

async function chat(req, res) {
  if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) throw bad('Unknown app.', 401);
  const cfg = config;
  if (!cfg.enabled) throw Object.assign(bad(cfg.disabledMessage, 503), { code: 'disabled' });
  await requireUserIfNeeded(req);
  const started = Date.now();
  const body = await readJson(req);
  if (body.agent !== undefined && body.agent !== null && body.agent !== '') return agentChat(req, res, body, cfg, started);
  const call = body.call === true;
  let app = cleanMessages(body.messages);
  if (call) {
    // Calls send less history and use a fast model with short replies.
    const sysLines = app.filter((m) => m.role === 'system');
    app = [...sysLines, ...app.filter((m) => m.role !== 'system').slice(-cfg.callHistory)];
  }
  const model = call ? callModelOf(cfg) : cfg.models.includes(body.model) ? body.model : cfg.defaultModel;
  const stream = body.stream !== false;
  // The admin's prompts go first, then the app's own system lines (reply
  // language), then the conversation.
  const sys = systemPrompt(cfg, app.filter((m) => m.role === 'system').map((m) => m.content), call);
  const messages = [
    ...(sys ? [{ role: 'system', content: sys }] : []),
    ...app.filter((m) => m.role !== 'system'),
  ];
  const upstreamBody = { model, messages, stream };
  if (Number.isFinite(body.max_tokens)) upstreamBody.max_tokens = Math.min(Math.max(1, body.max_tokens), 4096);
  if (call) upstreamBody.max_tokens = Math.min(upstreamBody.max_tokens || Infinity, cfg.callMaxTokens);
  if (Number.isFinite(body.temperature)) upstreamBody.temperature = Math.min(Math.max(0, body.temperature), 2);
  {
    const d = day();
    if (call) d.callTurns += 1;
    else d.chats += 1;
    d.userMessages += 1;
    bump(d.models, model);
    noteDevice(req);
  }

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), LIMITS.upstreamTimeoutMs);
  res.on('close', () => ctl.abort());
  try {
    const up = await callOmniRoute(cfg, upstreamBody, ctl.signal);
    if (!up.ok) {
      const text = await up.text();
      const message = upstreamError(up.status, text);
      noteError(call ? 'call' : 'chat', message);
      throw Object.assign(bad(message, up.status === 401 || up.status === 403 ? 502 : up.status), { noted: true });
    }
    res.writeHead(200, {
      'Content-Type': stream ? 'text/event-stream; charset=utf-8' : 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Accel-Buffering': 'no',
      'X-Model': model,
      ...CORS,
    });
    if (!up.body) return res.end();
    let first = true;
    for await (const chunk of up.body) {
      if (first) {
        first = false;
        noteTime(call ? 'call' : 'chat', Date.now() - started);
      }
      if (!res.write(chunk)) await new Promise((r) => res.once('drain', r));
    }
    res.end();
  } catch (e) {
    if (e && e.name !== 'AbortError' && !e.noted && !res.destroyed) noteError(call ? 'call' : 'chat', e.message || e);
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

// ---------------------------------------------------------------- agents

/** The system prompt for an agent: who it is and what it knows about the
 * user first, then the admin's prompt and style, then the app's lines. */
function agentSystem(cfg, agent, ctx, appLines, { call = false, background = false } = {}) {
  return [
    agents.agentPrompt(agent, ctx, { background }),
    cfg.systemPrompt ? `Instructions from the app's owner (follow them; you are still ${agent.nameEn}):\n${cfg.systemPrompt}` : '',
    background ? '' : cfg.stylePrompt,
    call ? cfg.callPrompt : '',
    call ? 'On a voice call: use tools only when the answer needs them (current facts, a reminder, a note), and say a few words first, like "দেখছি...", so the user is not left in silence.' : '',
    ...appLines,
  ]
    .filter((s) => s && s.trim())
    .join('\n\n');
}

let tasks = null;
function taskEngine() {
  return (tasks ||= makeTasks({
    run: async (t, { signal, onStep }) => {
      const agent = agents.agentOf(t.agent) || agents.AGENTS[0];
      const ctx = agents.cleanContext(t.ctx || {});
      const cfg = config;
      const day0 = day();
      day0.tasks = (day0.tasks || 0) + 1;
      const messages = [
        { role: 'system', content: agentSystem(cfg, agent, ctx, [], { background: true }) },
        { role: 'user', content: `Background task: ${t.title}\n\n${t.goal}` },
      ];
      const out = await agents.runAgent({
        cfg,
        model: cfg.defaultModel,
        messages,
        maxTokens: 4096,
        signal,
        maxRounds: 10,
        emit: {
          text: () => {},
          event: (e) => {
            if (e.type === 'tool' && e.phase === 'start') onStep({ tool: e.name, detail: e.detail });
          },
        },
        env: { ctx, agent, ip: `task:${t.id}`, background: true },
        deps: { callOmniRoute, upstreamError },
      });
      // The report is the last answer, without the "let me check" lines.
      return out.finalText || out.text;
    },
  }));
}

async function agentChat(req, res, body, cfg, started) {
  const agent = agents.agentOf(body.agent);
  if (!agent) throw bad('Unknown agent.');
  const call = body.call === true;
  const ctx = agents.cleanContext(body.context);
  let app = cleanMessages(body.messages);
  const appLines = app.filter((m) => m.role === 'system').map((m) => m.content);
  let convo = app.filter((m) => m.role !== 'system');
  if (call) convo = convo.slice(-cfg.callHistory);
  const model = call ? callModelOf(cfg) : cfg.models.includes(body.model) ? body.model : cfg.defaultModel;
  const stream = body.stream !== false;
  const messages = [{ role: 'system', content: agentSystem(cfg, agent, ctx, appLines, { call }) }, ...convo];
  let maxTokens = Number.isFinite(body.max_tokens) ? Math.min(Math.max(1, body.max_tokens), 4096) : undefined;
  if (call) maxTokens = Math.min(maxTokens || Infinity, cfg.callMaxTokens);
  const temperature = Number.isFinite(body.temperature) ? Math.min(Math.max(0, body.temperature), 2) : undefined;
  {
    const d = day();
    if (call) d.callTurns += 1;
    else d.chats += 1;
    d.userMessages += 1;
    bump(d.models, model);
    d.agents = d.agents || {};
    bump(d.agents, agent.id);
    noteDevice(req);
  }

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), LIMITS.upstreamTimeoutMs * 2);
  res.on('close', () => {
    if (!res.writableEnded) ctl.abort();
  });
  const events = [];
  let first = true;
  const head = () => {
    if (res.headersSent) return;
    res.writeHead(200, {
      'Content-Type': stream ? 'text/event-stream; charset=utf-8' : 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Accel-Buffering': 'no',
      'X-Model': model,
      'X-Agent': agent.id,
      ...CORS,
    });
  };
  const write = (obj) => {
    if (!stream || res.destroyed) return;
    head();
    res.write(`data: ${JSON.stringify(obj)}\n\n`);
  };
  const emit = {
    text: (c) => {
      if (first) {
        first = false;
        noteTime(call ? 'call' : 'chat', Date.now() - started);
      }
      write({ choices: [{ index: 0, delta: { content: c } }] });
    },
    event: (e) => {
      if (e.type === 'tool' && e.phase === 'start') {
        const d = day();
        d.tools = d.tools || {};
        bump(d.tools, e.name);
      }
      events.push(e);
      write({ bangla_event: e });
    },
  };
  // Keeps proxies from closing a quiet stream while a tool runs.
  const ping = stream ? setInterval(() => !res.destroyed && res.headersSent && res.write(': ping\n\n'), 15000) : null;
  try {
    if (stream) head();
    const out = await agents.runAgent({
      cfg,
      model,
      messages,
      maxTokens,
      temperature,
      signal: ctl.signal,
      maxRounds: call ? 3 : 6,
      emit,
      env: {
        ctx,
        agent,
        ip: clientIp(req),
        background: false,
        startTask: (o) => taskEngine().start(o),
      },
      deps: { callOmniRoute, upstreamError },
    });
    if (stream) {
      res.write('data: [DONE]\n\n');
      return res.end();
    }
    return send(res, 200, {
      model,
      agent: agent.id,
      choices: [{ index: 0, message: { role: 'assistant', content: out.text }, finish_reason: 'stop' }],
      events,
    });
  } catch (e) {
    const aborted = e && e.name === 'AbortError';
    if (!aborted && !res.destroyed) noteError(call ? 'call' : 'chat', e.message || e);
    if (res.headersSent) {
      if (!aborted && !res.destroyed) res.write(`data: ${JSON.stringify({ error: { message: String(e.message || e) } })}\n\n`);
      return res.end();
    }
    throw e.status ? e : Object.assign(bad(String(e.message || e), 502));
  } finally {
    clearTimeout(timer);
    if (ping) clearInterval(ping);
  }
}

async function startTaskRoute(req, res) {
  if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) throw bad('Unknown app.', 401);
  if (!config.enabled) throw Object.assign(bad(config.disabledMessage, 503), { code: 'disabled' });
  if (!config.baseUrl || !config.apiKey) throw bad('The server has no OmniRoute address or key yet. Set them in the admin app.', 503);
  const body = await readJson(req);
  const agent = agents.agentOf(body.agent);
  if (!agent) throw bad('Unknown agent.');
  const goal = typeof body.goal === 'string' ? body.goal.trim().slice(0, 4000) : '';
  if (!goal) throw bad('A task needs a goal.');
  const title = typeof body.title === 'string' && body.title.trim() ? body.title.trim().slice(0, 120) : goal.slice(0, 60);
  const t = await taskEngine().start({ agent: agent.id, title, goal, ctx: agents.cleanContext(body.context), ip: clientIp(req) });
  noteDevice(req);
  return send(res, 200, { task: { id: t.id, token: t.token, title: t.title, agent: agent.id, status: 'queued' } });
}

async function taskStatusRoute(req, res) {
  const body = await readJson(req);
  return send(res, 200, { tasks: await taskEngine().status(body.tasks) });
}

async function cancelTaskRoute(req, res, id) {
  const body = await readJson(req);
  const t = await taskEngine().cancel(id, String(body.token || ''));
  if (!t) throw bad('Task not found.', 404);
  return send(res, 200, { task: t });
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

// ---------------------------------------------------------------- voice

const ttsIp = new Map(); // ip -> [{ t, n }] chars spoken in the last minute
const ttsCache = new Map(); // recent audio, so repeated lines cost nothing

function ttsAllowance(ip, n) {
  const now = Date.now();
  const list = (ttsIp.get(ip) || []).filter((x) => now - x.t < 60e3);
  const used = list.reduce((a, x) => a + x.n, 0);
  if (used + n > LIMITS.ttsCharsPerMinute) return false;
  list.push({ t: now, n });
  ttsIp.set(ip, list);
  if (ttsIp.size > 5000) ttsIp.clear();
  return true;
}

async function speak(provider, text, cfg) {
  const key = crypto
    .createHash('sha256')
    .update(JSON.stringify([provider.id, provider.type, provider.voice, provider.model, cfg.speed, cfg.pitch, text]))
    .digest('hex');
  const hit = ttsCache.get(key);
  if (hit) return { ...hit, cached: true };
  const started = Date.now();
  const out = await voice.synthesize(provider, text, {
    speed: cfg.speed,
    pitch: cfg.pitch,
    signal: AbortSignal.timeout(20000),
  });
  noteTime('tts', Date.now() - started);
  ttsCache.set(key, out);
  if (ttsCache.size > 80) ttsCache.delete(ttsCache.keys().next().value);
  return out;
}

/** POST /v1/tts { text } -> audio/mpeg from the admin's cloud voice. */
async function tts(req, res) {
  if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) throw bad('Unknown app.', 401);
  const cfg = config;
  if (!cfg.enabled) throw Object.assign(bad(cfg.disabledMessage, 503), { code: 'disabled' });
  await requireUserIfNeeded(req);
  if (!cfg.voiceEnabled) throw Object.assign(bad('Voice is off.', 403), { code: 'voice_off' });
  const provider = activeProvider(cfg);
  if (!provider) throw Object.assign(bad('No cloud voice is set up; use the phone voice.', 409), { code: 'no_provider' });
  const { text } = await readJson(req);
  const t = String(text || '').trim();
  if (!t) throw bad('text is empty.');
  if (t.length > LIMITS.ttsChars) throw bad(`text is too long (${LIMITS.ttsChars} characters at most).`, 413);
  if (cfg.ttsDailyChars && day().ttsChars + t.length > cfg.ttsDailyChars) {
    throw Object.assign(bad('Today\'s voice limit is used up.', 429), { code: 'tts_daily_limit' });
  }
  if (!ttsAllowance(clientIp(req), t.length)) {
    throw Object.assign(bad('Too much speech at once. Wait a moment.', 429), { code: 'tts_rate' });
  }
  let out;
  try {
    out = await speak(provider, t, cfg);
  } catch (e) {
    noteError('voice', e.message || e);
    throw Object.assign(bad(String(e.message || e), 502), { code: 'tts_failed' });
  }
  const d = day();
  if (!out.cached) d.ttsChars += t.length;
  d.tts += 1;
  bump(d.voices, `${provider.type}:${provider.name}`);
  noteDevice(req);
  res.writeHead(200, { 'Content-Type': out.type, 'Content-Length': out.audio.length, 'Cache-Control': 'no-store', ...CORS });
  res.end(out.audio);
}

/** POST /admin/tts-test { provider, text } -> a short sample, base64 MP3. */
async function ttsTest(req, res) {
  requireAdmin(req);
  const body = await readJson(req);
  const [draft] = voice.cleanProviders([body.provider], bad);
  const [p] = voice.mergeProviders(config.voiceProviders, [draft]);
  const text = String(body.text || 'আসসালামু আলাইকুম! আমি বাংলা এআই। কেমন আছেন?').trim().slice(0, 300);
  const started = Date.now();
  try {
    const out = await voice.synthesize(p, text, {
      speed: config.speed,
      pitch: config.pitch,
      signal: AbortSignal.timeout(20000),
    });
    send(res, 200, {
      ok: true,
      ms: Date.now() - started,
      bytes: out.audio.length,
      type: out.type,
      audio: out.audio.toString('base64'),
    });
  } catch (e) {
    send(res, 200, { ok: false, error: String(e.message || e) });
  }
}

/** POST /admin/try-chat { text, call } -> the reply the app would get, for trying prompts. */
async function tryChat(req, res) {
  requireAdmin(req);
  const body = await readJson(req);
  const draft = cleanPatch(body.draft || {});
  const cfg = merge(config, draft);
  const call = body.call === true;
  const text = String(body.text || '').trim().slice(0, 2000);
  if (!text) throw bad('Type a message to try.');
  const lang = /[\u0980-\u09FF]/.test(text)
    ? 'Reply in natural spoken Bangla (Bengali script).'
    : 'Reply in the language the user writes in.';
  const model = call ? callModelOf(cfg) : cfg.defaultModel;
  const started = Date.now();
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 60000);
  try {
    const up = await callOmniRoute(
      cfg,
      {
        model,
        stream: false,
        ...(call ? { max_tokens: cfg.callMaxTokens } : {}),
        messages: [
          { role: 'system', content: systemPrompt(cfg, [lang], call) },
          { role: 'user', content: text },
        ],
      },
      ctl.signal,
    );
    const raw = await up.text();
    if (!up.ok) return send(res, 200, { ok: false, error: upstreamError(up.status, raw) });
    let reply = '';
    try {
      reply = JSON.parse(raw).choices[0].message.content || '';
    } catch {
      return send(res, 200, { ok: false, error: 'OmniRoute answered, but not in the OpenAI format.' });
    }
    send(res, 200, { ok: true, model, reply: reply.trim(), ms: Date.now() - started });
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
    return send(res, 200, {
      ok: true,
      version: VERSION,
      store: store.kind,
      storeOk,
      adminLogin: 'email-code',
      accounts: { ready: auth.ready, store: auth.kind, google: auth.options().google },
      emailReady: Boolean(ADMIN_EMAIL && RESEND_API_KEY),
      time: new Date().toISOString(),
    });
  }
  if (p === '/' && (m === 'GET' || m === 'HEAD')) {
    // Browsers get the web app; API clients asking for JSON get the status.
    if (web.wantsPage(req) && web.serveStatic(req, res, '/')) return;
    return send(res, 200, { name: 'Bangla AI server', ok: true });
  }
  if (p === '/v1/config' && m === 'GET') {
    return send(res, 200, publicConfig(config));
  }
  if (p === '/v1/chat' && m === 'POST') return chat(req, res);
  if (p === '/v1/agents' && m === 'GET') return send(res, 200, { agents: agents.publicAgents() });
  if (p === '/v1/tasks' && m === 'POST') return startTaskRoute(req, res);
  if (p === '/v1/tasks/status' && m === 'POST') return taskStatusRoute(req, res);
  {
    const tm = p.match(/^\/v1\/tasks\/(t[0-9a-f]{12})\/cancel$/);
    if (tm && m === 'POST') return cancelTaskRoute(req, res, tm[1]);
  }
  if ((p.startsWith('/v1/') || p.startsWith('/auth/')) && (await auth.route(req, res, p, m, url))) return;
  if (p === '/v1/tts' && m === 'POST') return tts(req, res);

  if (p === '/admin/setup-mailer' && m === 'POST') return setupMailer(req, res);
  if (p === '/admin/request-code' && m === 'POST') return requestCode(req, res);
  if (p === '/admin/verify-code' && m === 'POST') return verifyCode(req, res);
  if (p === '/admin/login' && m === 'POST') {
    throw Object.assign(
      bad('Password sign-in was replaced by an email code. Update the Admin app to 1.1.0.', 410),
      { code: 'password_login_removed' },
    );
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
  if (p === '/admin/tts-test' && m === 'POST') return ttsTest(req, res);
  if (p === '/admin/try-chat' && m === 'POST') return tryChat(req, res);
  if (p === '/admin/voice-types' && m === 'GET') {
    requireAdmin(req);
    return send(res, 200, { types: voice.providerTypes() });
  }
  if (p === '/admin/stats' && m === 'GET') {
    requireAdmin(req);
    return send(res, 200, {
      stats: statsView(Number(url.searchParams.get('days')) || 30),
      version: VERSION,
      store: store.kind,
      storeOk,
      storeError,
      emailReady: Boolean(ADMIN_EMAIL && RESEND_API_KEY),
      ready: Boolean(config.baseUrl && config.apiKey),
      users: await auth.stats(),
      accounts: auth.options(),
    });
  }
  if (p === '/admin/defaults' && m === 'GET') {
    requireAdmin(req);
    return send(res, 200, { stylePrompt: DEFAULT_STYLE_PROMPT, callPrompt: DEFAULT_CALL_PROMPT });
  }

  // The web app's files (main.dart.js, assets, icons...). API paths never
  // get here unless they are unknown, and public/ has nothing under them.
  if (!p.startsWith('/v1/') && !p.startsWith('/admin/') && web.serveStatic(req, res, url.pathname)) return;

  throw bad('Not found.', 404);
}

function handler(req, res) {
  route(req, res).catch((e) => {
    const status = e.status || 500;
    if (status >= 500 && status !== 503) console.error(e);
    if (res.headersSent) return res.end();
    send(res, status, {
      error: {
        message: String(e.message || e),
        code: e.code || undefined,
        retryAfter: e.retryAfter,
        triesLeft: e.triesLeft,
      },
    });
  });
}

/** Accounts live in the same Postgres database as the config, else memory. */
async function initAccounts() {
  const pool = store && store.kind === 'postgres' ? store.pool : null;
  await auth.init(pool, `${CONFIG_TABLE}_acct`);
}

async function start({ port = PORT } = {}) {
  store = makeStore();
  // Listen first so Render's health check passes while the database wakes.
  const server = http.createServer(handler);
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  await new Promise((r) => server.listen(port, '0.0.0.0', r));
  await loadConfig();
  await loadUsage();
  await initAccounts();
  // Retry the database in the background if it was asleep or unreachable.
  if (!storeOk) {
    const retry = setInterval(async () => {
      if (storeOk) return clearInterval(retry);
      await loadConfig();
      await loadUsage();
      if (!auth.ready) await initAccounts();
    }, 15000);
    retry.unref();
  }
  // Save the usage counters every minute, and before Render stops the server.
  const saver = setInterval(saveUsage, 60000);
  saver.unref();
  server.on('close', () => clearInterval(saver));
  console.log(`Bangla AI server on :${server.address().port} (store: ${store.kind}, ok: ${storeOk})`);
  return server;
}

if (require.main === module) {
  if (!ADMIN_EMAIL) console.warn('Warning: ADMIN_EMAIL is not set; admin sign-in is off.');
  if (!RESEND_API_KEY) console.warn('Warning: RESEND_API_KEY is not set; sign-in codes cannot be emailed.');
  if (!env.TOKEN_SECRET) console.warn('Warning: TOKEN_SECRET is not set; a restart signs the admin out.');
  console.log(`Admin sign-in: email code (admin email set: ${Boolean(ADMIN_EMAIL)}, mailer set: ${Boolean(RESEND_API_KEY)}).`);
  if (ENV_RESEND_KEY) {
    // The key's shape only, never the key: helps spot a bad paste.
    const k = ENV_RESEND_KEY;
    console.log(
      `Resend key shape: ${k.length} chars, starts with re_: ${k.startsWith('re_')}, ` +
        `spaces inside: ${/\s/.test(k)}, non-ASCII: ${/[^\x21-\x7e]/.test(k)}, ` +
        `quotes: ${/["']/.test(k)}, re_ appears ${(k.match(/re_/g) || []).length} time(s).`,
    );
  }
  start();
  for (const sig of ['SIGTERM', 'SIGINT']) {
    process.once(sig, async () => {
      await Promise.race([saveUsage(), new Promise((r) => setTimeout(r, 4000))]);
      process.exit(0);
    });
  }
}

module.exports = {
  start,
  auth,
  saveUsage,
  cleanPatch,
  publicConfig,
  adminConfig,
  seedConfig,
  verifyToken,
  signToken,
  normalizeEmail,
  codeEmail,
  _expireForTest: () => {
    if (activeCode) activeCode.expires = 0;
  },
};
