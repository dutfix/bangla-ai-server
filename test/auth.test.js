'use strict';

// User accounts: sign-up, sign-in, codes, profile, Google, admin separation.
// Runs on memory, and on Postgres too when TEST_DATABASE_URL is set.
const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const crypto = require('node:crypto');
const { createAuth, imageType, cleanName } = require('../auth');

function bad(message, status = 400) {
  return Object.assign(new Error(message), { status });
}
function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
  res.end(JSON.stringify(body));
}
function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {});
      } catch {
        reject(bad('Body is not valid JSON.'));
      }
    });
  });
}

// A fake Google: signing key, certs and token endpoints.
const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256', use: 'sig' };
const CLIENT_ID = 'test-client.apps.googleusercontent.com';
function idToken(claims, { key = privateKey, kid = 'k1' } = {}) {
  const h = Buffer.from(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' })).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const p = Buffer.from(
    JSON.stringify({ iss: 'https://accounts.google.com', aud: CLIENT_ID, iat: now, exp: now + 3600, ...claims }),
  ).toString('base64url');
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${h}.${p}`), key).toString('base64url');
  return `${h}.${p}.${sig}`;
}
let nextGoogleToken = null;
const fakeFetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.includes('/oauth2/v3/certs')) {
    return new Response(JSON.stringify({ keys: [jwk] }), { headers: { 'cache-control': 'max-age=600' } });
  }
  if (u.includes('oauth2.googleapis.com/token')) {
    const body = new URLSearchParams(String(opts.body));
    if (body.get('code') !== 'good-code' || !body.get('code_verifier')) {
      return new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 });
    }
    return new Response(JSON.stringify({ id_token: nextGoogleToken() }));
  }
  if (u.includes('googleusercontent.com')) {
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(40)]);
    return new Response(png);
  }
  throw new Error(`unexpected fetch ${u}`);
};

const mails = [];
function lastCode(to) {
  const m = [...mails].reverse().find((x) => x.to === to);
  return m && m.text.match(/\b(\d{6})\b/)[1];
}

async function makeServer(pool) {
  const env = {
    PUBLIC_URL: 'https://ai.example.test',
    GOOGLE_CLIENT_ID: CLIENT_ID,
    GOOGLE_CLIENT_SECRET: 'shh',
  };
  const auth = createAuth({
    env,
    secret: 'test-secret',
    bad,
    send,
    readJson,
    clientIp: (req) => req.headers['x-test-ip'] || '1.1.1.1',
    sendMail: async (m) => mails.push(m),
    mailReady: () => true,
    requireSignIn: () => false,
    fetch: fakeFetch,
  });
  await auth.init(pool, `t${Date.now()}_acct`);
  assert.ok(auth.ready, auth.error);
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    try {
      if (!(await auth.route(req, res, url.pathname, req.method, url))) send(res, 404, { error: { message: 'nf' } });
    } catch (e) {
      if (res.headersSent) return res.end();
      send(res, e.status || 500, { error: { message: e.message, code: e.code, triesLeft: e.triesLeft } });
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, p, body, { token, headers = {}, raw } = {}) => {
    const r = await fetch(base + p, {
      method,
      redirect: 'manual',
      headers: {
        ...(body !== undefined && !raw ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined,
    });
    const text = await r.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {}
    return { status: r.status, json, headers: r.headers, text };
  };
  return { auth, server, call, env };
}

function suite(label, getPool) {
  test(`${label}: email sign-up, verify, sign-in, sign-out`, async () => {
    const { server, call } = await makeServer(await getPool());
    try {
      const email = `Rahim.${label}@Example.com `;
      const norm = email.trim().toLowerCase();
      let r = await call('POST', '/v1/auth/signup', { email, password: 'short', name: 'Rahim' });
      assert.equal(r.status, 400);
      assert.equal(r.json.error.code, 'weak_password');
      r = await call('POST', '/v1/auth/signup', { email: 'nope', password: 'longenough1' });
      assert.equal(r.json.error.code, 'invalid_email');

      r = await call('POST', '/v1/auth/signup', { email, password: 'পাসওয়ার্ড১২৩৪', name: '  রহিম   উদ্দিন ' });
      assert.equal(r.status, 201, r.text);
      assert.match(r.json.token, /^bas_/);
      assert.equal(r.json.user.email, norm);
      assert.equal(r.json.user.name, 'রহিম উদ্দিন');
      assert.equal(r.json.user.emailVerified, false);
      assert.equal(r.json.verificationSent, true);
      assert.equal(r.json.user.passwordHash, undefined, 'no hash leaks');
      const token = r.json.token;

      r = await call('POST', '/v1/auth/signup', { email: norm, password: 'anotherpass' });
      assert.equal(r.status, 409);
      assert.equal(r.json.error.code, 'email_taken');

      r = await call('GET', '/v1/me', undefined, { token });
      assert.equal(r.status, 200);
      assert.equal(r.json.user.email, norm);
      r = await call('GET', '/v1/me');
      assert.equal(r.status, 401);
      r = await call('GET', '/v1/me', undefined, { token: 'bas_' + 'x'.repeat(43) });
      assert.equal(r.status, 401);

      // Wrong code, then the right one.
      const code = lastCode(norm);
      assert.ok(code);
      const wrong = code === '000000' ? '111111' : '000000';
      r = await call('POST', '/v1/auth/verify', { code: wrong }, { token });
      assert.equal(r.status, 401);
      assert.equal(r.json.error.triesLeft, 4);
      r = await call('POST', '/v1/auth/verify', { code: ` ${code.slice(0, 3)} ${code.slice(3)} ` }, { token });
      assert.equal(r.status, 200, r.text);
      assert.equal(r.json.user.emailVerified, true);
      r = await call('POST', '/v1/auth/verify', { code }, { token });
      assert.equal(r.status, 200, 'already verified is fine');

      r = await call('POST', '/v1/auth/login', { email: norm, password: 'wrongpass1' });
      assert.equal(r.status, 401);
      assert.equal(r.json.error.code, 'wrong_login');
      r = await call('POST', '/v1/auth/login', { email: 'nobody@example.com', password: 'wrongpass1' });
      assert.equal(r.json.error.code, 'wrong_login', 'same answer for unknown emails');
      r = await call('POST', '/v1/auth/login', { email: email.toUpperCase(), password: 'পাসওয়ার্ড১২৩৪' });
      assert.equal(r.status, 200, r.text);
      const token2 = r.json.token;
      assert.notEqual(token2, token);

      r = await call('POST', '/v1/auth/logout', undefined, { token: token2 });
      assert.equal(r.status, 200);
      r = await call('GET', '/v1/me', undefined, { token: token2 });
      assert.equal(r.status, 401, 'signed out');
      r = await call('GET', '/v1/me', undefined, { token });
      assert.equal(r.status, 200, 'the other device stays signed in');
    } finally {
      server.close();
    }
  });

  test(`${label}: password reset and change`, async () => {
    const { server, call } = await makeServer(await getPool());
    try {
      const email = `karim.${label}@example.com`;
      let r = await call('POST', '/v1/auth/signup', { email, password: 'firstpass1', name: 'Karim' }, { headers: { 'x-test-ip': '2.2.2.2' } });
      const oldToken = r.json.token;
      r = await call('POST', '/v1/auth/password/forgot', { email: 'ghost@example.com' });
      assert.equal(r.status, 200, 'unknown email: same answer');
      const before = mails.length;
      r = await call('POST', '/v1/auth/password/forgot', { email });
      assert.equal(r.status, 200);
      assert.equal(mails.length, before + 1);
      const code = lastCode(email);
      r = await call('POST', '/v1/auth/password/reset', { email, code, password: 'x' });
      assert.equal(r.json.error.code, 'weak_password');
      r = await call('POST', '/v1/auth/password/reset', { email, code, password: 'secondpass2' });
      assert.equal(r.status, 200, r.text);
      assert.equal(r.json.user.emailVerified, true);
      const t2 = r.json.token;
      r = await call('GET', '/v1/me', undefined, { token: oldToken });
      assert.equal(r.status, 401, 'reset signs other sessions out');
      r = await call('POST', '/v1/auth/password/reset', { email, code, password: 'thirdpass3' });
      assert.equal(r.status, 401, 'a code works once');
      r = await call('POST', '/v1/auth/login', { email, password: 'secondpass2' });
      assert.equal(r.status, 200);

      r = await call('POST', '/v1/auth/password/change', { current: 'nope-nope', password: 'fourthpass4' }, { token: t2 });
      assert.equal(r.json.error.code, 'wrong_password');
      r = await call('POST', '/v1/auth/password/change', { current: 'secondpass2', password: 'fourthpass4' }, { token: t2 });
      assert.equal(r.status, 200);
      r = await call('GET', '/v1/me', undefined, { token: r.json.token });
      assert.equal(r.status, 200);
      r = await call('POST', '/v1/auth/login', { email, password: 'fourthpass4' });
      assert.equal(r.status, 200);
    } finally {
      server.close();
    }
  });

  test(`${label}: profile name and picture`, async () => {
    const { server, call } = await makeServer(await getPool());
    try {
      let r = await call('POST', '/v1/auth/signup', { email: `pic.${label}@example.com`, password: 'picpass123' }, { headers: { 'x-test-ip': '3.3.3.3' } });
      const token = r.json.token;
      assert.equal(r.json.user.name, `pic.${label}`, 'name defaults to the email name');
      r = await call('PUT', '/v1/me', { name: '   ' }, { token });
      assert.equal(r.json.error.code, 'invalid_name');
      r = await call('PUT', '/v1/me', { name: 'ফাতেমা\u202E' }, { token });
      assert.equal(r.status, 200);
      assert.equal(r.json.user.name, 'ফাতেমা');

      r = await call('POST', '/v1/me/avatar', { image: Buffer.from('<svg onload=alert(1)>').toString('base64') }, { token });
      assert.equal(r.json.error.code, 'invalid_image', 'only real images');
      r = await call('POST', '/v1/me/avatar', { image: Buffer.alloc(200 * 1024, 0xff).toString('base64') }, { token });
      assert.equal(r.status, 413);
      const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100, 7)]);
      r = await call('POST', '/v1/me/avatar', { image: `data:image/jpeg;base64,${jpeg.toString('base64')}` }, { token });
      assert.equal(r.status, 200, r.text);
      const avatarUrl = r.json.user.avatarUrl;
      assert.match(avatarUrl, /^\/v1\/avatars\/[a-f0-9]{32}\?v=1$/);
      r = await call('GET', avatarUrl);
      assert.equal(r.status, 200);
      assert.equal(r.headers.get('content-type'), 'image/jpeg');
      assert.match(r.headers.get('cache-control'), /immutable/);
      r = await call('POST', '/v1/me/avatar/remove', undefined, { token });
      assert.equal(r.json.user.avatarUrl, null);
      r = await call('GET', avatarUrl);
      assert.equal(r.status, 404);
      r = await call('POST', '/v1/me/avatar', { image: jpeg.toString('base64') });
      assert.equal(r.status, 401, 'needs sign-in');
    } finally {
      server.close();
    }
  });

  test(`${label}: Google sign-in (code flow), linking rules`, async () => {
    const { server, call } = await makeServer(await getPool());
    try {
      // Start: redirect to Google with PKCE, state cookie set.
      let r = await call('GET', '/auth/google/start', undefined, {});
      assert.equal(r.status, 303);
      const to = new URL(r.headers.get('location'));
      assert.equal(to.origin + to.pathname, 'https://accounts.google.com/o/oauth2/v2/auth');
      assert.equal(to.searchParams.get('client_id'), CLIENT_ID);
      assert.equal(to.searchParams.get('redirect_uri'), 'https://ai.example.test/auth/google/callback');
      assert.equal(to.searchParams.get('code_challenge_method'), 'S256');
      const state = to.searchParams.get('state');
      const nonce = to.searchParams.get('nonce');
      const cookie = r.headers.get('set-cookie').split(';')[0];
      assert.match(r.headers.get('set-cookie'), /HttpOnly; Secure; SameSite=None/);

      // Another host is sent to the public one first.
      r = await call('GET', '/auth/google/start', undefined, { headers: { 'x-forwarded-host': 'other.onrender.com' } });
      assert.equal(r.headers.get('location'), 'https://ai.example.test/auth/google/start');

      const email = `g.${label}@gmail.com`;
      nextGoogleToken = () => idToken({ sub: `sub-${label}`, email, email_verified: true, name: 'Gita Rani', nonce, picture: 'https://lh3.googleusercontent.com/a/x=s96-c' });

      // Wrong state: refused.
      r = await call('GET', `/auth/google/callback?state=nope&code=good-code`, undefined, { headers: { cookie } });
      assert.match(r.headers.get('location'), /auth_error=google_expired/);
      // No cookie: refused.
      r = await call('GET', `/auth/google/callback?state=${state}&code=good-code`);
      assert.match(r.headers.get('location'), /auth_error=google_expired/);
      // Cancelled at Google.
      r = await call('GET', `/auth/google/callback?error=access_denied&state=${state}`, undefined, { headers: { cookie } });
      assert.match(r.headers.get('location'), /auth_error=cancelled/);
      // Good.
      r = await call('GET', `/auth/google/callback?state=${state}&code=good-code`, undefined, { headers: { cookie } });
      assert.equal(r.status, 303);
      const back = new URL(r.headers.get('location'));
      const ticket = back.searchParams.get('auth_ticket');
      assert.ok(ticket, r.headers.get('location'));
      r = await call('POST', '/v1/auth/google/exchange', { ticket });
      assert.equal(r.status, 200, r.text);
      assert.equal(r.json.isNew, true);
      assert.equal(r.json.user.name, 'Gita Rani');
      assert.equal(r.json.user.emailVerified, true);
      assert.equal(r.json.user.google, true);
      assert.equal(r.json.user.hasPassword, false);
      assert.ok(r.json.user.avatarUrl, 'Google picture copied');
      r = await call('POST', '/v1/auth/google/exchange', { ticket });
      assert.equal(r.status, 401, 'a ticket works once');

      // The Google account cannot sign in with a password, and cannot sign up again with email.
      r = await call('POST', '/v1/auth/login', { email, password: 'whatever1' });
      assert.equal(r.json.error.code, 'use_google');
      r = await call('POST', '/v1/auth/signup', { email, password: 'whatever1' }, { headers: { 'x-test-ip': '4.4.4.4' } });
      assert.equal(r.json.error.code, 'use_google');

      // Linking: an unverified email account is taken over safely by Google.
      const squat = `squat.${label}@gmail.com`;
      r = await call('POST', '/v1/auth/signup', { email: squat, password: 'squatter1' }, { headers: { 'x-test-ip': '5.5.5.5' } });
      const squatToken = r.json.token;
      r = await call('GET', '/auth/google/start', undefined, {});
      const st2 = new URL(r.headers.get('location')).searchParams;
      const cookie2 = r.headers.get('set-cookie').split(';')[0];
      nextGoogleToken = () => idToken({ sub: `sub2-${label}`, email: squat, email_verified: true, name: 'Real Owner', nonce: st2.get('nonce') });
      r = await call('GET', `/auth/google/callback?state=${st2.get('state')}&code=good-code`, undefined, { headers: { cookie: cookie2 } });
      const t2 = new URL(r.headers.get('location')).searchParams.get('auth_ticket');
      r = await call('POST', '/v1/auth/google/exchange', { ticket: t2 });
      assert.equal(r.json.isNew, false);
      assert.equal(r.json.user.hasPassword, false, 'unproven password removed');
      r = await call('GET', '/v1/me', undefined, { token: squatToken });
      assert.equal(r.status, 401, 'squatter session ended');
      r = await call('POST', '/v1/auth/login', { email: squat, password: 'squatter1' });
      assert.equal(r.status, 401);

      // Bad nonce / unverified Google email / forged signature are refused.
      for (const [claims, opts] of [
        [{ sub: 'x1', email: 'x1@gmail.com', email_verified: true, nonce: 'wrong' }, {}],
        [{ sub: 'x2', email: 'x2@gmail.com', email_verified: false }, {}],
        [{ sub: 'x3', email: 'x3@gmail.com', email_verified: true }, { key: crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey }],
        [{ sub: 'x4', email: 'x4@gmail.com', email_verified: true, aud: 'someone-else' }, {}],
      ]) {
        r = await call('GET', '/auth/google/start', undefined, {});
        const sp = new URL(r.headers.get('location')).searchParams;
        const ck = r.headers.get('set-cookie').split(';')[0];
        nextGoogleToken = () => idToken({ nonce: sp.get('nonce'), ...claims }, opts);
        r = await call('GET', `/auth/google/callback?state=${sp.get('state')}&code=good-code`, undefined, { headers: { cookie: ck } });
        assert.match(r.headers.get('location'), /auth_error=google_/, JSON.stringify(claims));
      }
    } finally {
      server.close();
    }
  });
}

suite('memory', async () => null);

if (process.env.TEST_DATABASE_URL) {
  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 3 });
  suite('postgres', async () => pool);
  test.after(() => pool.end());
}

test('code tries run out, rate limits answer 429', async () => {
  const { server, call } = await makeServer(null);
  try {
    const email = 'tries@example.com';
    let r = await call('POST', '/v1/auth/signup', { email, password: 'triespass1' }, { headers: { 'x-test-ip': '9.9.9.9' } });
    const token = r.json.token;
    const code = lastCode(email);
    const wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 4; i++) {
      r = await call('POST', '/v1/auth/verify', { code: wrong }, { token });
      assert.equal(r.status, 401);
    }
    r = await call('POST', '/v1/auth/verify', { code: wrong }, { token });
    assert.equal(r.status, 429);
    r = await call('POST', '/v1/auth/verify', { code }, { token });
    assert.equal(r.status, 401, 'the code is gone after too many tries');
    r = await call('POST', '/v1/auth/verify/send', undefined, { token });
    assert.equal(r.status, 429, 'one email a minute');
    for (let i = 0; i < 8; i++) await call('POST', '/v1/auth/login', { email, password: 'badbadbad' + i }, { headers: { 'x-test-ip': '8.8.8.8' } });
    r = await call('POST', '/v1/auth/login', { email, password: 'triespass1' }, { headers: { 'x-test-ip': '8.8.8.8' } });
    assert.equal(r.status, 429, 'locked after 8 wrong passwords');
  } finally {
    server.close();
  }
});

test('helpers', () => {
  assert.equal(imageType(Buffer.from([0xff, 0xd8, 0xff, 0x00])), 'image/jpeg');
  assert.equal(imageType(Buffer.from('RIFF0000WEBPVP8 ')), 'image/webp');
  assert.equal(imageType(Buffer.from('<svg>')), '');
  assert.equal(cleanName('  a\u0000b   c '), 'ab c');
});
