'use strict';

// User accounts for the Bangla AI app and website: email + password sign-up
// with a 6-digit email check, password reset by emailed code, Google sign-in
// (OpenID Connect, verified on the server), a profile (name and picture) and
// server-side sessions that can be signed out.
//
// Users are kept apart from the admin on purpose: a user session is an opaque
// random token stored (hashed) in the users' own table, never a token signed
// like the admin's, so no user token can open an /admin/ route.
//
// Storage: Postgres (the same Neon database as the config) in three tables,
// or memory (local development and tests).
//
// Routes (all JSON unless noted):
//   POST /v1/auth/signup            {email, password, name} -> {token, user}
//   POST /v1/auth/login             {email, password} -> {token, user}
//   POST /v1/auth/logout            (signed in) ends this session
//   POST /v1/auth/verify/send       (signed in) emails a code to check the email
//   POST /v1/auth/verify            (signed in) {code} -> {user}
//   POST /v1/auth/password/forgot   {email} -> same answer for any email
//   POST /v1/auth/password/reset    {email, code, password} -> {token, user}
//   POST /v1/auth/password/change   (signed in) {current, password} -> {token, user}
//   GET  /v1/me                     (signed in) -> {user}
//   PUT  /v1/me                     (signed in) {name} -> {user}
//   POST /v1/me/avatar              (signed in) {image: base64 JPEG/PNG/WebP} -> {user}
//   POST /v1/me/avatar/remove       (signed in) -> {user}
//   GET  /v1/avatars/<id>           the picture (public, by unguessable id)
//   GET  /auth/google/start         redirects to Google (browser)
//   GET|POST /auth/google/callback  back from Google; redirects to /?auth_ticket=
//   POST /v1/auth/google/exchange   {ticket} -> {token, user, isNew}

const crypto = require('node:crypto');

const SESSION_DAYS = 60;
const CODE_TTL_MS = 15 * 60e3;
const CODE_TRIES = 5;
const TICKET_TTL_MS = 2 * 60e3;
const GOOGLE_STATE_TTL_MS = 10 * 60e3;
const AVATAR_MAX_BYTES = 180 * 1024;
const NAME_MAX = 60;
const PASSWORD_MIN = 8;
const PASSWORD_MAX = 128;
const GOOGLE_AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Bangla first, English after, like the rest of the server's user messages.
const MSG = {
  badEmail: 'সঠিক ইমেইল ঠিকানা লিখুন। Enter a valid email address.',
  shortPassword: `পাসওয়ার্ড অন্তত ${PASSWORD_MIN} অক্ষরের হতে হবে। The password needs at least ${PASSWORD_MIN} characters.`,
  longPassword: 'পাসওয়ার্ডটি অনেক লম্বা। The password is too long.',
  emailTaken: 'এই ইমেইলে আগেই একটি অ্যাকাউন্ট আছে। সাইন ইন করুন। An account with this email already exists. Sign in instead.',
  emailTakenGoogle:
    'এই ইমেইলে Google দিয়ে অ্যাকাউন্ট খোলা আছে। Google দিয়ে চালিয়ে যান। This email already signs in with Google.',
  wrongLogin: 'ইমেইল বা পাসওয়ার্ড ঠিক নয়। The email or password is wrong.',
  useGoogle:
    'এই অ্যাকাউন্টে পাসওয়ার্ড নেই। Google দিয়ে চালিয়ে যান, অথবা "পাসওয়ার্ড ভুলে গেছেন?" থেকে একটি পাসওয়ার্ড দিন। This account signs in with Google.',
  signIn: 'আবার সাইন ইন করুন। Please sign in again.',
  badCode: 'কোডটি ৬ সংখ্যার। The code has 6 digits.',
  wrongCode: 'কোডটি ঠিক নয় বা আর কাজ করে না। নতুন কোড নিন। This code is wrong or no longer works.',
  tooManyTries: 'অনেকবার ভুল হয়েছে। নতুন কোড নিন। Too many wrong tries. Ask for a new code.',
  wrongCurrent: 'বর্তমান পাসওয়ার্ডটি ঠিক নয়। The current password is wrong.',
  badName: `নাম ১ থেকে ${NAME_MAX} অক্ষরের মধ্যে লিখুন। Use 1 to ${NAME_MAX} characters for the name.`,
  badImage: 'ছবিটি JPEG, PNG বা WebP হতে হবে। The picture must be a JPEG, PNG or WebP.',
  bigImage: 'ছবিটি অনেক বড়। The picture is too large.',
  googleOff: 'Google সাইন-ইন এখনও চালু হয়নি। Google sign-in is not set up yet.',
  googleTicket: 'Google সাইন-ইন শেষ হয়নি। আবার চেষ্টা করুন। Google sign-in did not finish. Try again.',
  tooFast: (s) => `একটু অপেক্ষা করুন (${s} সেকেন্ড), তারপর আবার চেষ্টা করুন। Wait ${s} seconds and try again.`,
  signInRequired: 'চ্যাট করতে সাইন ইন করুন। Sign in to chat.',
  storeDown: 'অ্যাকাউন্ট সার্ভার এখন পাওয়া যাচ্ছে না। একটু পরে চেষ্টা করুন। Accounts are unavailable right now.',
  forgotSent:
    'এই ইমেইলে অ্যাকাউন্ট থাকলে একটি ৬ সংখ্যার কোড পাঠানো হয়েছে। If an account uses this email, a 6-digit code is on its way.',
};

function normEmail(s) {
  return String(s == null ? '' : s)
    .normalize('NFC')
    .replace(/[\u200B\u200C\u200D\u2060\uFEFF]/g, '')
    .trim()
    .toLowerCase();
}

function cleanName(s) {
  return String(s == null ? '' : s)
    .normalize('NFC')
    .replace(/[\u0000-\u001f\u007f\u200B\u2060\uFEFF\u202A-\u202E\u2066-\u2069]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function sha256(s) {
  return crypto.createHash('sha256').update(String(s)).digest('hex');
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function newId() {
  return crypto.randomBytes(16).toString('hex');
}

// ---------------------------------------------------------------- passwords

const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };

function scrypt(password, salt, o = SCRYPT) {
  return new Promise((resolve, reject) =>
    crypto.scrypt(password, salt, o.keylen, { N: o.N, r: o.r, p: o.p, maxmem: 64 * 1024 * 1024 }, (e, k) =>
      e ? reject(e) : resolve(k),
    ),
  );
}

function normPassword(p) {
  return String(p == null ? '' : p).normalize('NFC');
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(normPassword(password), salt);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${b64url(salt)}$${b64url(key)}`;
}

const DUMMY_HASH = `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${b64url(Buffer.alloc(16))}$${b64url(Buffer.alloc(64))}`;

async function checkPassword(password, stored) {
  const parts = String(stored || DUMMY_HASH).split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, N, r, p, salt, key] = parts;
  const want = Buffer.from(key, 'base64url');
  const got = await scrypt(normPassword(password), Buffer.from(salt, 'base64url'), {
    N: Number(N),
    r: Number(r),
    p: Number(p),
    keylen: want.length,
  });
  return Boolean(stored) && got.length === want.length && crypto.timingSafeEqual(got, want);
}

function checkNewPassword(password, bad) {
  const p = normPassword(password);
  if ([...p].length < PASSWORD_MIN) throw Object.assign(bad(MSG.shortPassword, 400), { code: 'weak_password' });
  if (p.length > PASSWORD_MAX) throw Object.assign(bad(MSG.longPassword, 400), { code: 'weak_password' });
}

// ---------------------------------------------------------------- images

/** The image type from its first bytes, or '' when it is not one we keep. */
function imageType(buf) {
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return 'image/png';
  }
  if (buf.length > 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return '';
}

// ---------------------------------------------------------------- limits

/** Sliding-window limits kept in memory: returns seconds to wait, 0 = go. */
class Limiter {
  constructor() {
    this.hits = new Map();
    const t = setInterval(() => this.sweep(), 10 * 60e3);
    t.unref();
  }
  wait(key, max, windowMs, { record = true } = {}) {
    const now = Date.now();
    const list = (this.hits.get(key) || []).filter((t) => now - t < windowMs);
    if (list.length >= max) {
      this.hits.set(key, list);
      return Math.max(1, Math.ceil((windowMs - (now - list[0])) / 1000));
    }
    if (record) list.push(now);
    this.hits.set(key, list);
    return 0;
  }
  clear(key) {
    this.hits.delete(key);
  }
  sweep() {
    const now = Date.now();
    for (const [k, list] of this.hits) if (!list.length || now - list[list.length - 1] > 3600e3 * 24) this.hits.delete(k);
  }
}

// ---------------------------------------------------------------- stores

const USER_COLS =
  'id, email, email_verified, password_hash, google_sub, name, avatar_type, avatar_ver, created_at, last_login_at';

function rowToUser(r) {
  if (!r) return null;
  return {
    id: r.id,
    email: r.email,
    emailVerified: Boolean(r.email_verified),
    passwordHash: r.password_hash || null,
    googleSub: r.google_sub || null,
    name: r.name || '',
    avatarType: r.avatar_type || null,
    avatarVer: Number(r.avatar_ver || 0),
    createdAt: r.created_at ? new Date(r.created_at).toISOString() : null,
    lastLoginAt: r.last_login_at ? new Date(r.last_login_at).toISOString() : null,
  };
}

const FIELD_COL = {
  email: 'email',
  emailVerified: 'email_verified',
  passwordHash: 'password_hash',
  googleSub: 'google_sub',
  name: 'name',
  lastLoginAt: 'last_login_at',
};

class PgUserStore {
  constructor(pool, prefix) {
    this.pool = pool;
    this.t = {
      users: `${prefix}_users`,
      sessions: `${prefix}_sessions`,
      codes: `${prefix}_codes`,
    };
    this.kind = 'postgres';
  }
  async init() {
    const { users, sessions, codes } = this.t;
    await this.pool.query(`CREATE TABLE IF NOT EXISTS ${users} (
      id TEXT PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      email_verified BOOLEAN NOT NULL DEFAULT false,
      password_hash TEXT,
      google_sub TEXT UNIQUE,
      name TEXT NOT NULL DEFAULT '',
      avatar BYTEA,
      avatar_type TEXT,
      avatar_ver INT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      last_login_at TIMESTAMPTZ
    )`);
    await this.pool.query(`CREATE TABLE IF NOT EXISTS ${sessions} (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES ${users}(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      expires_at TIMESTAMPTZ NOT NULL,
      last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      user_agent TEXT
    )`);
    await this.pool.query(`CREATE INDEX IF NOT EXISTS ${sessions}_user_idx ON ${sessions}(user_id)`);
    await this.pool.query(`CREATE TABLE IF NOT EXISTS ${codes} (
      id TEXT PRIMARY KEY,
      code_hash TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      tries INT NOT NULL DEFAULT 0
    )`);
  }
  async one(sql, args) {
    const r = await this.pool.query(sql, args);
    return rowToUser(r.rows[0]);
  }
  byId(id) {
    return this.one(`SELECT ${USER_COLS} FROM ${this.t.users} WHERE id = $1`, [id]);
  }
  byEmail(email) {
    return this.one(`SELECT ${USER_COLS} FROM ${this.t.users} WHERE email = $1`, [email]);
  }
  byGoogle(sub) {
    return this.one(`SELECT ${USER_COLS} FROM ${this.t.users} WHERE google_sub = $1`, [sub]);
  }
  async create(u) {
    try {
      return await this.one(
        `INSERT INTO ${this.t.users} (id, email, email_verified, password_hash, google_sub, name, last_login_at)
         VALUES ($1, $2, $3, $4, $5, $6, now()) RETURNING ${USER_COLS}`,
        [u.id, u.email, Boolean(u.emailVerified), u.passwordHash || null, u.googleSub || null, u.name || ''],
      );
    } catch (e) {
      if (e && e.code === '23505') throw Object.assign(new Error('duplicate'), { duplicate: true });
      throw e;
    }
  }
  async update(id, fields) {
    const sets = [];
    const args = [id];
    for (const [k, v] of Object.entries(fields)) {
      if (!FIELD_COL[k]) continue;
      args.push(k === 'lastLoginAt' ? new Date(v) : v);
      sets.push(`${FIELD_COL[k]} = $${args.length}`);
    }
    if (!sets.length) return this.byId(id);
    return this.one(
      `UPDATE ${this.t.users} SET ${sets.join(', ')}, updated_at = now() WHERE id = $1 RETURNING ${USER_COLS}`,
      args,
    );
  }
  setAvatar(id, buf, type) {
    return this.one(
      `UPDATE ${this.t.users} SET avatar = $2, avatar_type = $3, avatar_ver = avatar_ver + 1, updated_at = now()
       WHERE id = $1 RETURNING ${USER_COLS}`,
      [id, buf, type],
    );
  }
  async avatar(id) {
    const r = await this.pool.query(`SELECT avatar, avatar_type, avatar_ver FROM ${this.t.users} WHERE id = $1`, [id]);
    const row = r.rows[0];
    if (!row || !row.avatar) return null;
    return { body: row.avatar, type: row.avatar_type, ver: Number(row.avatar_ver) };
  }
  async countUsers() {
    const r = await this.pool.query(
      `SELECT count(*)::int AS total, count(*) FILTER (WHERE created_at > now() - interval '7 days')::int AS week,
       count(*) FILTER (WHERE last_login_at > now() - interval '1 day')::int AS day FROM ${this.t.users}`,
    );
    return r.rows[0];
  }
  async addSession(hash, userId, expires, ua) {
    await this.pool.query(
      `INSERT INTO ${this.t.sessions} (token_hash, user_id, expires_at, user_agent) VALUES ($1, $2, $3, $4)`,
      [hash, userId, new Date(expires), ua || null],
    );
  }
  async session(hash) {
    const r = await this.pool.query(
      `SELECT s.expires_at, s.last_seen_at, ${USER_COLS.split(', ').map((c) => `u.${c}`).join(', ')}
       FROM ${this.t.sessions} s JOIN ${this.t.users} u ON u.id = s.user_id WHERE s.token_hash = $1`,
      [hash],
    );
    const row = r.rows[0];
    if (!row) return null;
    return { expires: new Date(row.expires_at).getTime(), lastSeen: new Date(row.last_seen_at).getTime(), user: rowToUser(row) };
  }
  async touchSession(hash, expires) {
    await this.pool.query(`UPDATE ${this.t.sessions} SET last_seen_at = now(), expires_at = $2 WHERE token_hash = $1`, [
      hash,
      new Date(expires),
    ]);
  }
  async dropSession(hash) {
    await this.pool.query(`DELETE FROM ${this.t.sessions} WHERE token_hash = $1`, [hash]);
  }
  async dropSessions(userId) {
    await this.pool.query(`DELETE FROM ${this.t.sessions} WHERE user_id = $1`, [userId]);
    await this.pool.query(`DELETE FROM ${this.t.sessions} WHERE expires_at < now()`);
  }
  async putCode(id, codeHash, expires) {
    await this.pool.query(
      `INSERT INTO ${this.t.codes} (id, code_hash, expires_at, tries) VALUES ($1, $2, $3, 0)
       ON CONFLICT (id) DO UPDATE SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, tries = 0`,
      [id, codeHash, new Date(expires)],
    );
  }
  async code(id) {
    const r = await this.pool.query(`SELECT code_hash, expires_at, tries FROM ${this.t.codes} WHERE id = $1`, [id]);
    const row = r.rows[0];
    return row ? { hash: row.code_hash, expires: new Date(row.expires_at).getTime(), tries: row.tries } : null;
  }
  async codeTried(id) {
    await this.pool.query(`UPDATE ${this.t.codes} SET tries = tries + 1 WHERE id = $1`, [id]);
  }
  async dropCode(id) {
    await this.pool.query(`DELETE FROM ${this.t.codes} WHERE id = $1`, [id]);
  }
}

/** Same interface in memory, for tests and local runs without a database. */
class MemoryUserStore {
  constructor() {
    this.users = new Map();
    this.avatars = new Map();
    this.sessions = new Map();
    this.codes = new Map();
    this.kind = 'memory';
  }
  async init() {}
  copy(u) {
    return u ? { ...u } : null;
  }
  async byId(id) {
    return this.copy(this.users.get(id));
  }
  async byEmail(email) {
    return this.copy([...this.users.values()].find((u) => u.email === email));
  }
  async byGoogle(sub) {
    return this.copy([...this.users.values()].find((u) => u.googleSub && u.googleSub === sub));
  }
  async create(u) {
    for (const x of this.users.values()) {
      if (x.email === u.email || (u.googleSub && x.googleSub === u.googleSub)) {
        throw Object.assign(new Error('duplicate'), { duplicate: true });
      }
    }
    const now = new Date().toISOString();
    const user = {
      id: u.id,
      email: u.email,
      emailVerified: Boolean(u.emailVerified),
      passwordHash: u.passwordHash || null,
      googleSub: u.googleSub || null,
      name: u.name || '',
      avatarType: null,
      avatarVer: 0,
      createdAt: now,
      lastLoginAt: now,
    };
    this.users.set(user.id, user);
    return this.copy(user);
  }
  async update(id, fields) {
    const u = this.users.get(id);
    if (!u) return null;
    for (const [k, v] of Object.entries(fields)) {
      if (!FIELD_COL[k]) continue;
      if (k === 'googleSub' && v && [...this.users.values()].some((x) => x.id !== id && x.googleSub === v)) {
        throw Object.assign(new Error('duplicate'), { duplicate: true });
      }
      u[k] = k === 'lastLoginAt' ? new Date(v).toISOString() : v;
    }
    return this.copy(u);
  }
  async setAvatar(id, buf, type) {
    const u = this.users.get(id);
    if (!u) return null;
    u.avatarVer += 1;
    u.avatarType = type;
    if (buf) this.avatars.set(id, Buffer.from(buf));
    else this.avatars.delete(id);
    return this.copy(u);
  }
  async avatar(id) {
    const u = this.users.get(id);
    const body = this.avatars.get(id);
    return u && body ? { body, type: u.avatarType, ver: u.avatarVer } : null;
  }
  async countUsers() {
    const now = Date.now();
    const list = [...this.users.values()];
    return {
      total: list.length,
      week: list.filter((u) => now - Date.parse(u.createdAt) < 7 * 86400e3).length,
      day: list.filter((u) => u.lastLoginAt && now - Date.parse(u.lastLoginAt) < 86400e3).length,
    };
  }
  async addSession(hash, userId, expires) {
    this.sessions.set(hash, { userId, expires, lastSeen: Date.now() });
  }
  async session(hash) {
    const s = this.sessions.get(hash);
    if (!s) return null;
    const user = this.copy(this.users.get(s.userId));
    return user ? { expires: s.expires, lastSeen: s.lastSeen, user } : null;
  }
  async touchSession(hash, expires) {
    const s = this.sessions.get(hash);
    if (s) Object.assign(s, { expires, lastSeen: Date.now() });
  }
  async dropSession(hash) {
    this.sessions.delete(hash);
  }
  async dropSessions(userId) {
    for (const [h, s] of this.sessions) if (s.userId === userId) this.sessions.delete(h);
  }
  async putCode(id, hash, expires) {
    this.codes.set(id, { hash, expires, tries: 0 });
  }
  async code(id) {
    const c = this.codes.get(id);
    return c ? { ...c } : null;
  }
  async codeTried(id) {
    const c = this.codes.get(id);
    if (c) c.tries += 1;
  }
  async dropCode(id) {
    this.codes.delete(id);
  }
}

// ---------------------------------------------------------------- emails

function codeEmail(purpose, code) {
  const verify = purpose === 'verify';
  const subject = verify ? `বাংলা এআই: আপনার ইমেইল যাচাইয়ের কোড ${code}` : `বাংলা এআই: পাসওয়ার্ড রিসেট কোড ${code}`;
  const bn = verify ? 'আপনার ইমেইল যাচাই করতে এই কোডটি দিন:' : 'নতুন পাসওয়ার্ড দিতে এই কোডটি দিন:';
  const en = verify ? 'Your code to confirm your email:' : 'Your code to set a new password:';
  const text =
    `${bn} ${code}\nকোডটি ১৫ মিনিট কাজ করবে। আপনি না চাইলে এই ইমেইলটি উপেক্ষা করুন।\n\n` +
    `${en} ${code}\nIt works for 15 minutes. If you didn't ask for it, ignore this email.`;
  const html = `<div style="font-family:Arial,'Noto Sans Bengali',sans-serif;max-width:420px;margin:auto;padding:24px;color:#13241D">
<div style="background:#006a4e;color:#fff;border-radius:12px;padding:14px 18px;font-size:18px;font-weight:bold">বাংলা এআই</div>
<p style="font-size:15px;margin:20px 0 8px">${bn}<br><span style="color:#4D5B55;font-size:13px">${en}</span></p>
<p style="font-size:34px;letter-spacing:8px;font-weight:bold;margin:0 0 16px;color:#006a4e">${code}</p>
<p style="font-size:13px;color:#4D5B55;line-height:1.6">কোডটি ১৫ মিনিট কাজ করবে। আপনি না চাইলে এই ইমেইলটি উপেক্ষা করুন।<br>It works for 15 minutes. If you didn't ask for it, ignore this email.</p>
</div>`;
  return { subject, text, html };
}

// ---------------------------------------------------------------- the service

/**
 * @param {object} o
 * @param {object} o.env           process.env
 * @param {string} o.secret        server secret (TOKEN_SECRET); keys are derived from it
 * @param {Function} o.bad         (message, status) -> Error
 * @param {Function} o.send        (res, status, body, headers) JSON reply
 * @param {Function} o.readJson    (req) -> body
 * @param {Function} o.clientIp    (req) -> ip
 * @param {Function} o.sendMail    async ({to, subject, text, html}) -> throws on failure
 * @param {Function} o.mailReady   () -> bool
 * @param {Function} o.requireSignIn () -> bool (admin switch)
 * @param {Function} [o.fetch]     fetch, replaceable in tests
 */
function createAuth(o) {
  const { env, bad, send, readJson, clientIp } = o;
  const doFetch = o.fetch || ((...a) => fetch(...a));
  const key = (label) => crypto.createHmac('sha256', o.secret).update(`bangla-ai-users:${label}`).digest();
  const CODE_KEY = key('codes');
  const STATE_KEY = key('google-state');
  const limiter = new Limiter();
  const tickets = new Map(); // ticket hash -> { userId, isNew, expires }
  const cache = new Map(); // token hash -> { user, expires, until }
  let store = null;
  let ready = false;
  let lastError = '';

  const publicUrl = () => String(env.PUBLIC_URL || 'https://ai.banglaai.cloud').replace(/\/+$/, '');
  const googleClientId = () => String(env.GOOGLE_CLIENT_ID || '').trim();
  const googleSecret = () => String(env.GOOGLE_CLIENT_SECRET || '').trim();
  const googleRedirect = () => `${publicUrl()}/auth/google/callback`;

  async function init(pool, prefix) {
    store = pool ? new PgUserStore(pool, prefix) : new MemoryUserStore();
    try {
      await store.init();
      ready = true;
      lastError = '';
    } catch (e) {
      ready = false;
      lastError = String((e && e.message) || e);
      console.error(`User accounts unavailable: ${lastError}`);
    }
    return ready;
  }

  function need() {
    if (!store || !ready) throw Object.assign(bad(MSG.storeDown, 503), { code: 'accounts_unavailable' });
    return store;
  }

  function err(message, status, code, extra = {}) {
    return Object.assign(bad(message, status), { code, ...extra });
  }

  function limit(keyName, max, windowMs) {
    const wait = limiter.wait(keyName, max, windowMs);
    if (wait) throw err(MSG.tooFast(wait), 429, 'too_soon', { retryAfter: wait });
  }

  function options() {
    return {
      email: true,
      google: Boolean(googleClientId()),
      emailCodes: Boolean(o.mailReady()),
      requireSignIn: Boolean(o.requireSignIn()),
      available: ready,
    };
  }

  function view(u) {
    return {
      id: u.id,
      email: u.email,
      emailVerified: u.emailVerified,
      name: u.name,
      avatarUrl: u.avatarVer && u.avatarType ? `/v1/avatars/${u.id}?v=${u.avatarVer}` : null,
      hasPassword: Boolean(u.passwordHash),
      google: Boolean(u.googleSub),
      createdAt: u.createdAt,
    };
  }

  // ------------------------------------------------ sessions

  async function startSession(user, req) {
    const token = `bas_${b64url(crypto.randomBytes(32))}`;
    const expires = Date.now() + SESSION_DAYS * 86400e3;
    await need().addSession(sha256(token), user.id, expires, String(req.headers['user-agent'] || '').slice(0, 200));
    store.update(user.id, { lastLoginAt: Date.now() }).catch(() => {});
    return token;
  }

  function tokenOf(req) {
    const h = String(req.headers.authorization || '');
    const t = h.startsWith('Bearer ') ? h.slice(7).trim() : '';
    return /^bas_[A-Za-z0-9_-]{43}$/.test(t) ? t : '';
  }

  function forget(userId) {
    for (const [h, c] of cache) if (c.user.id === userId) cache.delete(h);
  }

  /** The signed-in user and their session, or null. Never throws for a bad token. */
  async function sessionOf(req) {
    const token = tokenOf(req);
    if (!token || !store || !ready) return null;
    const hash = sha256(token);
    const now = Date.now();
    const hit = cache.get(hash);
    if (hit && hit.until > now && hit.expires > now) return { user: hit.user, hash };
    const s = await store.session(hash);
    if (!s || s.expires <= now) {
      cache.delete(hash);
      if (s) store.dropSession(hash).catch(() => {});
      return null;
    }
    let expires = s.expires;
    // Sliding sessions: an active user stays signed in.
    if (now - s.lastSeen > 86400e3) {
      expires = now + SESSION_DAYS * 86400e3;
      store.touchSession(hash, expires).catch(() => {});
    }
    if (cache.size > 5000) cache.clear();
    cache.set(hash, { user: s.user, expires, until: now + 60e3 });
    return { user: s.user, hash };
  }

  async function userOf(req) {
    try {
      const s = await sessionOf(req);
      return s ? s.user : null;
    } catch {
      return null;
    }
  }

  async function requireUser(req) {
    need();
    const s = await sessionOf(req);
    if (!s) throw err(MSG.signIn, 401, 'signed_out');
    return s;
  }

  // ------------------------------------------------ codes

  function codeHash(id, code) {
    return crypto.createHmac('sha256', CODE_KEY).update(`${id}:${code}`).digest('hex');
  }

  /** Emails a code. Returns true when the mail went out. */
  async function mailCode(purpose, email) {
    const id = `${purpose}:${email}`;
    // Per address: one a minute, six an hour. Whole server: 90 a day, which
    // keeps inside Resend's free daily allowance.
    const wait = limiter.wait(`mail:${id}`, 1, 60e3, { record: false }) || limiter.wait(`mailh:${id}`, 6, 3600e3, { record: false });
    if (wait) throw err(MSG.tooFast(wait), 429, 'too_soon', { retryAfter: wait });
    if (limiter.wait('mail:all', 90, 86400e3, { record: false })) {
      console.warn('User email not sent: the daily email cap is reached.');
      return false;
    }
    limiter.wait(`mail:${id}`, 1, 60e3);
    limiter.wait(`mailh:${id}`, 6, 3600e3);
    limiter.wait('mail:all', 90, 86400e3);
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
    await need().putCode(id, codeHash(id, code), Date.now() + CODE_TTL_MS);
    if (!o.mailReady()) {
      console.warn(`User ${purpose} code not sent: the mailer is not set up.`);
      return false;
    }
    try {
      await o.sendMail({ to: email, ...codeEmail(purpose, code) });
      console.log(`User ${purpose} code emailed.`);
      return true;
    } catch (e) {
      console.error(`User ${purpose} code could not be emailed: ${e.message}`);
      return false;
    }
  }

  async function useCode(purpose, email, given) {
    const digits = String(given == null ? '' : given).replace(/\D/g, '');
    if (digits.length !== 6) throw err(MSG.badCode, 400, 'invalid_code');
    const id = `${purpose}:${email}`;
    const c = await need().code(id);
    if (!c || c.expires < Date.now()) {
      if (c) await store.dropCode(id);
      throw err(MSG.wrongCode, 401, 'wrong_code');
    }
    const ok = crypto.timingSafeEqual(Buffer.from(codeHash(id, digits)), Buffer.from(c.hash));
    if (!ok) {
      if (c.tries + 1 >= CODE_TRIES) {
        await store.dropCode(id);
        throw err(MSG.tooManyTries, 429, 'too_many_tries');
      }
      await store.codeTried(id);
      throw err(MSG.wrongCode, 401, 'wrong_code', { triesLeft: CODE_TRIES - c.tries - 1 });
    }
    await store.dropCode(id);
  }

  // ------------------------------------------------ email + password

  function emailFrom(body) {
    const email = normEmail(body.email);
    if (!email || email.length > 254 || !EMAIL_RE.test(email)) throw err(MSG.badEmail, 400, 'invalid_email');
    return email;
  }

  async function signup(req, res) {
    const ip = clientIp(req);
    const body = await readJson(req);
    const email = emailFrom(body);
    checkNewPassword(body.password, bad);
    const name = cleanName(body.name).slice(0, NAME_MAX);
    limit(`signup:${ip}`, 10, 3600e3);
    const s = need();
    const existing = await s.byEmail(email);
    if (existing) {
      throw existing.passwordHash ? err(MSG.emailTaken, 409, 'email_taken') : err(MSG.emailTakenGoogle, 409, 'use_google');
    }
    let user;
    try {
      user = await s.create({
        id: newId(),
        email,
        emailVerified: false,
        passwordHash: await hashPassword(body.password),
        name: name || email.split('@')[0].slice(0, NAME_MAX),
      });
    } catch (e) {
      if (e.duplicate) throw err(MSG.emailTaken, 409, 'email_taken');
      throw e;
    }
    const token = await startSession(user, req);
    const verificationSent = await mailCode('verify', email).catch(() => false);
    console.log('New account (email).');
    return send(res, 201, { token, user: view(user), verificationSent, isNew: true });
  }

  async function login(req, res) {
    const ip = clientIp(req);
    const body = await readJson(req);
    const email = emailFrom(body);
    limit(`login:${ip}`, 30, 15 * 60e3);
    const failKey = `loginfail:${email}`;
    const locked = limiter.wait(failKey, 8, 15 * 60e3, { record: false });
    if (locked) throw err(MSG.tooFast(locked), 429, 'too_soon', { retryAfter: locked });
    const user = await need().byEmail(email);
    const ok = await checkPassword(body.password, user && user.passwordHash);
    if (!ok) {
      limiter.wait(failKey, 8, 15 * 60e3);
      if (user && !user.passwordHash) throw err(MSG.useGoogle, 401, 'use_google');
      throw err(MSG.wrongLogin, 401, 'wrong_login');
    }
    limiter.clear(failKey);
    const token = await startSession(user, req);
    return send(res, 200, { token, user: view(user) });
  }

  async function logout(req, res) {
    const s = await sessionOf(req).catch(() => null);
    if (s) {
      cache.delete(s.hash);
      await store.dropSession(s.hash);
    }
    return send(res, 200, { ok: true });
  }

  async function verifySend(req, res) {
    const { user } = await requireUser(req);
    if (user.emailVerified) return send(res, 200, { ok: true, sent: false, alreadyVerified: true, user: view(user) });
    const sent = await mailCode('verify', user.email);
    return send(res, 200, { ok: true, sent, expiresInMinutes: CODE_TTL_MS / 60e3 });
  }

  async function verify(req, res) {
    const { user } = await requireUser(req);
    const body = await readJson(req);
    if (user.emailVerified) return send(res, 200, { user: view(user) });
    await useCode('verify', user.email, body.code);
    const next = await store.update(user.id, { emailVerified: true });
    forget(user.id);
    return send(res, 200, { user: view(next) });
  }

  async function forgot(req, res) {
    const ip = clientIp(req);
    const body = await readJson(req);
    const email = emailFrom(body);
    limit(`forgot:${ip}`, 10, 3600e3);
    const user = await need().byEmail(email);
    // The same answer whether or not the account exists.
    if (user) await mailCode('reset', email).catch(() => false);
    return send(res, 200, { ok: true, message: MSG.forgotSent, expiresInMinutes: CODE_TTL_MS / 60e3 });
  }

  async function reset(req, res) {
    const ip = clientIp(req);
    const body = await readJson(req);
    const email = emailFrom(body);
    checkNewPassword(body.password, bad);
    limit(`reset:${ip}`, 20, 3600e3);
    const user = await need().byEmail(email);
    if (!user) {
      // Same reply as a wrong code, so this reveals nothing.
      throw err(MSG.wrongCode, 401, 'wrong_code');
    }
    await useCode('reset', email, body.code);
    // The code proves the email belongs to them.
    const next = await store.update(user.id, { passwordHash: await hashPassword(body.password), emailVerified: true });
    await store.dropSessions(user.id);
    forget(user.id);
    const token = await startSession(next, req);
    return send(res, 200, { token, user: view(next) });
  }

  async function changePassword(req, res) {
    const { user } = await requireUser(req);
    const body = await readJson(req);
    checkNewPassword(body.password, bad);
    limit(`change:${user.id}`, 10, 3600e3);
    if (user.passwordHash && !(await checkPassword(body.current, user.passwordHash))) {
      throw err(MSG.wrongCurrent, 401, 'wrong_password');
    }
    const next = await store.update(user.id, { passwordHash: await hashPassword(body.password) });
    // Other devices are signed out; this one gets a fresh session.
    await store.dropSessions(user.id);
    forget(user.id);
    const token = await startSession(next, req);
    return send(res, 200, { token, user: view(next) });
  }

  // ------------------------------------------------ profile

  async function me(req, res) {
    const { user } = await requireUser(req);
    return send(res, 200, { user: view(user) });
  }

  async function updateMe(req, res) {
    const { user } = await requireUser(req);
    const body = await readJson(req);
    const fields = {};
    if (body.name !== undefined) {
      const name = cleanName(body.name);
      if (!name || [...name].length > NAME_MAX) throw err(MSG.badName, 400, 'invalid_name');
      fields.name = name;
    }
    const next = await store.update(user.id, fields);
    forget(user.id);
    return send(res, 200, { user: view(next) });
  }

  async function setAvatar(req, res) {
    const { user } = await requireUser(req);
    limit(`avatar:${user.id}`, 30, 3600e3);
    const body = await readJson(req);
    const raw = String(body.image || '').replace(/^data:image\/[a-z+]+;base64,/, '');
    if (!raw || !/^[A-Za-z0-9+/=_-]+$/.test(raw)) throw err(MSG.badImage, 400, 'invalid_image');
    const buf = Buffer.from(raw, 'base64');
    if (buf.length > AVATAR_MAX_BYTES) throw err(MSG.bigImage, 413, 'image_too_large');
    const type = imageType(buf);
    if (!type) throw err(MSG.badImage, 400, 'invalid_image');
    const next = await store.setAvatar(user.id, buf, type);
    forget(user.id);
    return send(res, 200, { user: view(next) });
  }

  async function removeAvatar(req, res) {
    const { user } = await requireUser(req);
    const next = await store.setAvatar(user.id, null, null);
    forget(user.id);
    return send(res, 200, { user: view(next) });
  }

  async function avatar(req, res, id, url) {
    if (!/^[a-f0-9]{32}$/.test(id)) throw err('Not found.', 404, 'not_found');
    const a = await need().avatar(id);
    if (!a) throw err('Not found.', 404, 'not_found');
    const etag = `"av-${a.ver}"`;
    const versioned = url.searchParams.get('v') === String(a.ver);
    const headers = {
      'Content-Type': a.type,
      'Cache-Control': versioned ? 'public, max-age=31536000, immutable' : 'no-cache',
      ETag: etag,
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'",
      'Access-Control-Allow-Origin': '*',
    };
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, headers);
      return res.end();
    }
    headers['Content-Length'] = a.body.length;
    res.writeHead(200, headers);
    return res.end(req.method === 'HEAD' ? undefined : a.body);
  }

  // ------------------------------------------------ Google

  let certs = { keys: new Map(), until: 0 };

  async function googleKey(kid) {
    if (Date.now() > certs.until || !certs.keys.has(kid)) {
      const r = await doFetch(GOOGLE_CERTS_URL, { signal: AbortSignal.timeout(10000) });
      if (!r.ok) throw new Error(`Google certs answered ${r.status}`);
      const j = await r.json();
      const age = Number((String(r.headers.get('cache-control') || '').match(/max-age=(\d+)/) || [])[1]) || 3600;
      const keys = new Map();
      for (const k of j.keys || []) keys.set(k.kid, crypto.createPublicKey({ key: k, format: 'jwk' }));
      certs = { keys, until: Date.now() + Math.min(age, 86400) * 1000 };
    }
    const k = certs.keys.get(kid);
    if (!k) throw new Error('unknown Google key');
    return k;
  }

  /** Checks a Google ID token: signature, issuer, audience, expiry, nonce. */
  async function verifyIdToken(idToken, nonce) {
    const parts = String(idToken || '').split('.');
    if (parts.length !== 3) throw new Error('not a JWT');
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    if (header.alg !== 'RS256') throw new Error('unexpected algorithm');
    const k = await googleKey(header.kid);
    const ok = crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), k, Buffer.from(parts[2], 'base64url'));
    if (!ok) throw new Error('bad signature');
    const c = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    const now = Date.now() / 1000;
    if (!GOOGLE_ISSUERS.includes(c.iss)) throw new Error('bad issuer');
    const aud = Array.isArray(c.aud) ? c.aud : [c.aud];
    if (!aud.includes(googleClientId())) throw new Error('bad audience');
    if (!(c.exp > now - 60)) throw new Error('expired');
    if (c.iat && c.iat > now + 300) throw new Error('issued in the future');
    if (nonce && c.nonce !== nonce) throw new Error('bad nonce');
    if (!c.sub) throw new Error('no subject');
    return c;
  }

  function signState(data) {
    const payload = b64url(JSON.stringify(data));
    return `${payload}.${b64url(crypto.createHmac('sha256', STATE_KEY).update(payload).digest())}`;
  }

  function readState(s) {
    const [payload, sig] = String(s || '').split('.');
    if (!payload || !sig) return null;
    const want = b64url(crypto.createHmac('sha256', STATE_KEY).update(payload).digest());
    if (sig.length !== want.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) return null;
    try {
      const d = JSON.parse(Buffer.from(payload, 'base64url').toString());
      return d.exp > Date.now() ? d : null;
    } catch {
      return null;
    }
  }

  function cookie(req, name) {
    for (const part of String(req.headers.cookie || '').split(';')) {
      const i = part.indexOf('=');
      if (i > 0 && part.slice(0, i).trim() === name) return decodeURIComponent(part.slice(i + 1).trim());
    }
    return '';
  }

  function redirect(res, location, extra = {}) {
    res.writeHead(303, { Location: location, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', ...extra });
    res.end();
  }

  const STATE_COOKIE = 'bai_google';

  function googleStart(req, res, url) {
    if (!googleClientId()) return redirect(res, `${publicUrl()}/?auth_error=google_off`);
    // The callback address is fixed (it is registered with Google), so start
    // on that host or the state cookie would be on another one.
    const host = String(req.headers['x-forwarded-host'] || req.headers.host || '');
    const want = new URL(publicUrl()).host;
    if (host && host !== want && !/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host)) {
      return redirect(res, `${publicUrl()}/auth/google/start`);
    }
    limit(`gstart:${clientIp(req)}`, 30, 600e3);
    const state = b64url(crypto.randomBytes(18));
    const nonce = b64url(crypto.randomBytes(18));
    const verifier = b64url(crypto.randomBytes(32));
    const code = Boolean(googleSecret());
    const params = new URLSearchParams({
      client_id: googleClientId(),
      redirect_uri: googleRedirect(),
      scope: 'openid email profile',
      state,
      nonce,
      prompt: 'select_account',
    });
    if (code) {
      params.set('response_type', 'code');
      params.set('code_challenge', b64url(crypto.createHash('sha256').update(verifier).digest()));
      params.set('code_challenge_method', 'S256');
    } else {
      params.set('response_type', 'id_token');
      params.set('response_mode', 'form_post');
    }
    const hint = normEmail(url.searchParams.get('email'));
    if (hint && EMAIL_RE.test(hint)) params.set('login_hint', hint);
    const value = signState({ state, nonce, verifier: code ? verifier : undefined, exp: Date.now() + GOOGLE_STATE_TTL_MS });
    // SameSite=None: Google posts the answer back from its own site.
    const secure = publicUrl().startsWith('https://');
    return redirect(res, `${GOOGLE_AUTH_URL}?${params}`, {
      'Set-Cookie': `${STATE_COOKIE}=${encodeURIComponent(value)}; Path=/auth/google; Max-Age=${GOOGLE_STATE_TTL_MS / 1000}; HttpOnly; ${secure ? 'Secure; SameSite=None' : 'SameSite=Lax'}`,
    });
  }

  function readForm(req) {
    return new Promise((resolve, reject) => {
      let size = 0;
      const chunks = [];
      req.on('data', (c) => {
        size += c.length;
        if (size > 64 * 1024) {
          reject(bad('Request is too large.', 413));
          req.destroy();
          return;
        }
        chunks.push(c);
      });
      req.on('end', () => resolve(new URLSearchParams(Buffer.concat(chunks).toString('utf8'))));
      req.on('error', reject);
    });
  }

  async function googleCallback(req, res, url) {
    const clear = { 'Set-Cookie': `${STATE_COOKIE}=; Path=/auth/google; Max-Age=0; HttpOnly; Secure; SameSite=None` };
    const fail = (why, log) => {
      if (log) console.warn(`Google sign-in failed: ${log}`);
      return redirect(res, `${publicUrl()}/?auth_error=${why}`, clear);
    };
    const params = req.method === 'POST' ? await readForm(req) : url.searchParams;
    if (params.get('error')) return fail(params.get('error') === 'access_denied' ? 'cancelled' : 'google_failed', params.get('error'));
    if (!googleClientId()) return fail('google_off');
    const saved = readState(cookie(req, STATE_COOKIE));
    if (!saved || !params.get('state') || params.get('state') !== saved.state) return fail('google_expired', 'state mismatch');
    let claims;
    try {
      let idToken = params.get('id_token');
      if (saved.verifier) {
        const r = await doFetch(GOOGLE_TOKEN_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            code: params.get('code') || '',
            client_id: googleClientId(),
            client_secret: googleSecret(),
            redirect_uri: googleRedirect(),
            grant_type: 'authorization_code',
            code_verifier: saved.verifier,
          }),
          signal: AbortSignal.timeout(15000),
        });
        const j = await r.json().catch(() => ({}));
        if (!r.ok) throw new Error(`token exchange ${r.status} ${j.error || ''}`);
        idToken = j.id_token;
      }
      claims = await verifyIdToken(idToken, saved.nonce);
    } catch (e) {
      return fail('google_failed', e.message);
    }
    if (!claims.email || claims.email_verified !== true && claims.email_verified !== 'true') {
      return fail('google_unverified', 'email not verified by Google');
    }
    let result;
    try {
      result = await googleUser(claims);
    } catch (e) {
      console.error(e);
      return fail('google_failed', e.message);
    }
    const ticket = b64url(crypto.randomBytes(24));
    for (const [k, t] of tickets) if (t.expires < Date.now()) tickets.delete(k);
    tickets.set(sha256(ticket), { userId: result.user.id, isNew: result.isNew, expires: Date.now() + TICKET_TTL_MS });
    return redirect(res, `${publicUrl()}/?auth_ticket=${ticket}`, clear);
  }

  /** Finds, links or creates the account for a verified Google identity. */
  async function googleUser(c) {
    const s = need();
    const email = normEmail(c.email);
    const name = cleanName(c.name || c.given_name || email.split('@')[0]).slice(0, NAME_MAX);
    let user = await s.byGoogle(c.sub);
    if (user) return { user, isNew: false };
    user = await s.byEmail(email);
    if (user) {
      if (user.googleSub) {
        // The email's account is tied to another Google account: never merge.
        throw new Error('email belongs to an account linked to another Google account');
      }
      const fields = { googleSub: c.sub, emailVerified: true };
      if (!user.emailVerified) {
        // Nobody proved they own this email before; Google just did. Drop the
        // unproven password and its sessions so a stranger who signed up with
        // this email first cannot keep a way in.
        fields.passwordHash = null;
        await s.dropSessions(user.id);
        forget(user.id);
      }
      user = await s.update(user.id, fields);
      console.log('Google linked to an existing account.');
      return { user, isNew: false };
    }
    user = await s.create({ id: newId(), email, emailVerified: true, googleSub: c.sub, name });
    console.log('New account (Google).');
    if (c.picture) await copyGooglePicture(user, c.picture).catch((e) => console.warn(`Google picture not copied: ${e.message}`));
    return { user: (await s.byId(user.id)) || user, isNew: true };
  }

  async function copyGooglePicture(user, picture) {
    const u = new URL(picture);
    if (u.protocol !== 'https:' || !/(^|\.)googleusercontent\.com$/.test(u.hostname)) return;
    // Ask for a 256 px square.
    const src = picture.replace(/=s\d+(-c)?$/, '=s256-c');
    const r = await doFetch(src, { signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error(`picture answered ${r.status}`);
    const buf = Buffer.from(await r.arrayBuffer());
    const type = imageType(buf);
    if (!type || buf.length > AVATAR_MAX_BYTES) return;
    await store.setAvatar(user.id, buf, type);
  }

  async function googleExchange(req, res) {
    const body = await readJson(req);
    limit(`gx:${clientIp(req)}`, 30, 600e3);
    const hash = sha256(String(body.ticket || ''));
    const t = tickets.get(hash);
    tickets.delete(hash); // one use
    if (!t || t.expires < Date.now()) throw err(MSG.googleTicket, 401, 'bad_ticket');
    const user = await need().byId(t.userId);
    if (!user) throw err(MSG.googleTicket, 401, 'bad_ticket');
    const token = await startSession(user, req);
    return send(res, 200, { token, user: view(user), isNew: t.isNew });
  }

  // ------------------------------------------------ routing

  /** Handles an accounts route. Returns false when the path is not one. */
  async function route(req, res, p, m, url) {
    if (p === '/auth/google/start' && m === 'GET') return googleStart(req, res, url), true;
    if (p === '/auth/google/callback' && (m === 'GET' || m === 'POST')) return await googleCallback(req, res, url), true;
    if (p === '/v1/auth/options' && m === 'GET') return send(res, 200, options()), true;
    if (m === 'GET' || m === 'HEAD') {
      const a = p.match(/^\/v1\/avatars\/([^/]+)$/);
      if (a) return await avatar(req, res, a[1], url), true;
    }
    if (p === '/v1/me' && m === 'GET') return await me(req, res), true;
    if (p === '/v1/me' && (m === 'PUT' || m === 'POST' || m === 'PATCH')) return await updateMe(req, res), true;
    if (m !== 'POST') return false;
    const handlers = {
      '/v1/auth/signup': signup,
      '/v1/auth/login': login,
      '/v1/auth/logout': logout,
      '/v1/auth/verify/send': verifySend,
      '/v1/auth/verify': verify,
      '/v1/auth/password/forgot': forgot,
      '/v1/auth/password/reset': reset,
      '/v1/auth/password/change': changePassword,
      '/v1/auth/google/exchange': googleExchange,
      '/v1/me/avatar': setAvatar,
      '/v1/me/avatar/remove': removeAvatar,
    };
    const h = handlers[p];
    if (!h) return false;
    await h(req, res);
    return true;
  }

  async function stats() {
    if (!store || !ready) return null;
    try {
      return await store.countUsers();
    } catch {
      return null;
    }
  }

  return {
    init,
    route,
    options,
    userOf,
    stats,
    get ready() {
      return ready;
    },
    get error() {
      return lastError;
    },
    get kind() {
      return store ? store.kind : 'none';
    },
    MSG,
    // for tests
    _verifyIdToken: verifyIdToken,
    _resetCerts: () => {
      certs = { keys: new Map(), until: 0 };
    },
  };
}

module.exports = { createAuth, imageType, hashPassword, checkPassword, cleanName, MSG };
