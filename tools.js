'use strict';

// The tools the agents run on the server: web search, reading a page, the
// weather, the time and a calculator. Each returns a small JSON-able object
// that goes back to the model as the tool result. Nothing here runs code the
// user or the model wrote, and pages are fetched only from public addresses.

const http = require('node:http');
const https = require('node:https');
const dns = require('node:dns');
const net = require('node:net');
const zlib = require('node:zlib');

const UA = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36 BanglaAI/1.3';
const env = process.env;

// ---------------------------------------------------------------- safe fetch

/** True for addresses a server must never fetch for a user (SSRF). */
function isPrivateIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    return (
      a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || // carrier NAT
      (a === 169 && b === 254) || // link-local, cloud metadata
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      (a === 192 && b === 0) ||
      (a === 198 && (b === 18 || b === 19))
    );
  }
  if (net.isIPv6(ip)) {
    const x = ip.toLowerCase();
    if (x === '::' || x === '::1') return true;
    const mapped = x.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return isPrivateIp(mapped[1]);
    return /^(fc|fd|fe8|fe9|fea|feb|ff)/.test(x) || x.startsWith('64:ff9b:') || x.startsWith('2001:db8');
  }
  return true;
}

// Tests talk to a fake site on 127.0.0.1; only they may turn the check off.
const ALLOW_PRIVATE = env.TOOLS_ALLOW_PRIVATE === '1';

/** dns.lookup that refuses private addresses, so a redirect or a DNS answer
 * cannot point the server at itself or its network. */
function guardedLookup(hostname, options, cb) {
  dns.lookup(hostname, { ...options, all: true }, (err, list) => {
    if (err) return cb(err);
    const ok = list.filter((a) => ALLOW_PRIVATE || !isPrivateIp(a.address));
    if (!ok.length) return cb(Object.assign(new Error('blocked address'), { code: 'EBLOCKED' }));
    if (options && options.all) return cb(null, ok);
    cb(null, ok[0].address, ok[0].family);
  });
}

/**
 * GET or POST a public http(s) URL. Follows up to 4 redirects, stops after
 * maxBytes, gives up after timeoutMs. Resolves { status, url, type, text }.
 */
function safeFetch(url, { method = 'GET', body = null, headers = {}, maxBytes = 1_500_000, timeoutMs = 12000, redirects = 4 } = {}) {
  return new Promise((resolve, reject) => {
    let u;
    try {
      u = new URL(url);
    } catch {
      return reject(new Error('That is not a valid web address.'));
    }
    if (!['http:', 'https:'].includes(u.protocol)) return reject(new Error('Only http and https pages can be read.'));
    if (u.username || u.password) return reject(new Error('Addresses with a login inside are not allowed.'));
    if (u.port && !['80', '443', '8080', '8443'].includes(u.port) && !ALLOW_PRIVATE) {
      return reject(new Error('That port is not allowed.'));
    }
    const host = u.hostname.replace(/^\[|\]$/g, '');
    if (net.isIP(host) && !ALLOW_PRIVATE && isPrivateIp(host)) return reject(new Error('Private addresses cannot be read.'));
    if (/^(localhost|.*\.local|.*\.internal|metadata\.google\.internal)$/i.test(host) && !ALLOW_PRIVATE) {
      return reject(new Error('Private addresses cannot be read.'));
    }
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.request(
      u,
      {
        method,
        lookup: guardedLookup,
        headers: {
          'User-Agent': UA,
          Accept: 'text/html,application/xhtml+xml,application/json,text/plain;q=0.9,*/*;q=0.5',
          'Accept-Language': 'bn,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          ...(body ? { 'Content-Length': Buffer.byteLength(body) } : {}),
          ...headers,
        },
        timeout: timeoutMs,
      },
      (res) => {
        const status = res.statusCode || 0;
        if (status >= 300 && status < 400 && res.headers.location) {
          res.resume();
          if (redirects <= 0) return reject(new Error('Too many redirects.'));
          const next = new URL(res.headers.location, u).toString();
          const again = status === 307 || status === 308;
          return resolve(
            safeFetch(next, {
              method: again ? method : 'GET',
              body: again ? body : null,
              headers: again ? headers : {},
              maxBytes,
              timeoutMs,
              redirects: redirects - 1,
            }),
          );
        }
        let stream = res;
        const enc = String(res.headers['content-encoding'] || '').toLowerCase();
        if (enc === 'gzip') stream = res.pipe(zlib.createGunzip());
        else if (enc === 'deflate') stream = res.pipe(zlib.createInflate());
        else if (enc === 'br') stream = res.pipe(zlib.createBrotliDecompress());
        const chunks = [];
        let size = 0;
        let done = false;
        const finish = () => {
          if (done) return;
          done = true;
          const buf = Buffer.concat(chunks);
          const type = String(res.headers['content-type'] || '');
          const cs = (type.match(/charset=([\w-]+)/i) || [])[1];
          let text;
          try {
            text = new TextDecoder(cs && /^(utf-?8|iso-8859-1|windows-1252|latin1)$/i.test(cs) ? cs : 'utf-8').decode(buf);
          } catch {
            text = buf.toString('utf8');
          }
          resolve({ status, url: u.toString(), type, text });
        };
        stream.on('data', (c) => {
          size += c.length;
          chunks.push(c);
          if (size > maxBytes) {
            res.destroy();
            finish();
          }
        });
        stream.on('end', finish);
        stream.on('error', (e) => (size > maxBytes ? finish() : reject(e)));
      },
    );
    req.on('timeout', () => req.destroy(Object.assign(new Error('The page took too long to answer.'), { code: 'ETIMEDOUT' })));
    req.on('error', (e) => {
      if (e.code === 'EBLOCKED') reject(new Error('Private addresses cannot be read.'));
      else if (e.code === 'ENOTFOUND') reject(new Error(`No website found at ${u.hostname}.`));
      else reject(new Error(e.message || String(e)));
    });
    if (body) req.write(body);
    req.end();
  });
}

// ---------------------------------------------------------------- html to text

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', hellip: '…', laquo: '«', raquo: '»', copy: '©', reg: '®', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“' };

function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const n = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try {
        return String.fromCodePoint(n);
      } catch {
        return m;
      }
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

function htmlToText(html) {
  const title = decodeEntities(((html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1] || '').replace(/\s+/g, ' ').trim());
  let body = html
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(script|style|noscript|svg|template|iframe|head|form|button|select)\b[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<(nav|footer|aside)\b[\s\S]*?<\/\1>/gi, ' ');
  const main = body.match(/<(main|article)\b[\s\S]*?<\/\1>/i);
  if (main && main[0].length > 1500) body = main[0];
  const text = decodeEntities(
    body
      .replace(/<(br|hr)\b[^>]*>/gi, '\n')
      .replace(/<\/(p|div|section|article|li|tr|h[1-6]|pre|blockquote|table|ul|ol|dd|dt)>/gi, '\n')
      .replace(/<li\b[^>]*>/gi, '\n• ')
      .replace(/<h([1-6])\b[^>]*>/gi, '\n\n')
      .replace(/<[^>]+>/g, ' '),
  )
    .replace(/[ \t\f\v\u00a0]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return { title, text };
}

function clip(s, n) {
  s = String(s || '');
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

// ---------------------------------------------------------------- web search

async function ddgSearch(query, count) {
  const r = await safeFetch('https://lite.duckduckgo.com/lite/', {
    method: 'POST',
    body: `q=${encodeURIComponent(query)}&kl=wt-wt`,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    timeoutMs: 9000,
  });
  if (r.status !== 200) throw new Error(`search answered ${r.status}`);
  const results = [];
  const re = /<a[^>]+href="([^"]+)"[^>]*class=['"]result-link['"][^>]*>([\s\S]*?)<\/a>[\s\S]*?<td[^>]*class=['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>/gi;
  let m;
  while ((m = re.exec(r.text)) && results.length < count) {
    let link = decodeEntities(m[1]);
    const uddg = link.match(/[?&]uddg=([^&]+)/);
    if (uddg) link = decodeURIComponent(uddg[1]);
    if (/duckduckgo\.com\/y\.js|ad_provider/.test(link)) continue; // ads
    results.push({
      title: decodeEntities(m[2].replace(/<[^>]+>/g, '')).trim(),
      url: link,
      snippet: decodeEntities(m[3].replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim(),
    });
  }
  return results;
}

async function wikiSearch(query, count) {
  const lang = /[\u0980-\u09FF]/.test(query) ? 'bn' : 'en';
  const r = await safeFetch(
    `https://${lang}.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=${count}&srsearch=${encodeURIComponent(query)}`,
    { timeoutMs: 8000 },
  );
  const j = JSON.parse(r.text);
  return ((j.query && j.query.search) || []).map((s) => ({
    title: s.title,
    url: `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(s.title.replace(/ /g, '_'))}`,
    snippet: decodeEntities(String(s.snippet).replace(/<[^>]+>/g, '')),
  }));
}

async function webSearch({ query, count }) {
  const q = String(query || '').trim().slice(0, 300);
  if (!q) throw new Error('Give a search query.');
  const n = Math.min(Math.max(Number(count) || 6, 1), 10);
  let results = [];
  let source = 'DuckDuckGo';
  try {
    results = await ddgSearch(q, n);
  } catch (e) {
    console.warn(`web_search: DuckDuckGo failed (${e.message}), trying Wikipedia`);
  }
  if (!results.length) {
    source = 'Wikipedia';
    results = await wikiSearch(q, n);
  }
  return { query: q, source, results };
}

async function readWebpage({ url, offset }) {
  let target = String(url || '').trim();
  if (target && !/^https?:\/\//i.test(target)) target = `https://${target}`;
  const r = await safeFetch(target);
  if (r.status >= 400) throw new Error(`The page answered ${r.status}.`);
  let title = '';
  let text = r.text;
  if (/json/i.test(r.type)) {
    try {
      text = JSON.stringify(JSON.parse(r.text), null, 1);
    } catch {}
  } else if (/html|xml/i.test(r.type) || /^\s*</.test(r.text)) {
    ({ title, text } = htmlToText(r.text));
  } else if (!/text|javascript|markdown|yaml|csv/i.test(r.type) && r.type) {
    throw new Error(`That is a ${r.type.split(';')[0]} file, not a page with text.`);
  }
  const start = Math.max(0, Number(offset) || 0);
  const size = 7000;
  return {
    url: r.url,
    title,
    offset: start,
    total_chars: text.length,
    more: start + size < text.length ? `call again with offset ${start + size} for more` : undefined,
    text: text.slice(start, start + size),
  };
}

// ---------------------------------------------------------------- weather

const WMO = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast', 45: 'fog', 48: 'fog',
  51: 'light drizzle', 53: 'drizzle', 55: 'heavy drizzle', 61: 'light rain', 63: 'rain', 65: 'heavy rain',
  66: 'freezing rain', 67: 'freezing rain', 71: 'light snow', 73: 'snow', 75: 'heavy snow', 77: 'snow grains',
  80: 'rain showers', 81: 'rain showers', 82: 'violent rain showers', 85: 'snow showers', 86: 'snow showers',
  95: 'thunderstorm', 96: 'thunderstorm with hail', 99: 'thunderstorm with hail',
};

async function weather({ place }) {
  const name = String(place || 'Dhaka').trim().slice(0, 100);
  const g = JSON.parse(
    (await safeFetch(`https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&name=${encodeURIComponent(name)}`, { timeoutMs: 8000 })).text,
  );
  const loc = g.results && g.results[0];
  if (!loc) throw new Error(`Could not find a place called "${name}". Try the city name in English.`);
  const f = JSON.parse(
    (
      await safeFetch(
        `https://api.open-meteo.com/v1/forecast?latitude=${loc.latitude}&longitude=${loc.longitude}&timezone=auto&forecast_days=4` +
          '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation' +
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
        { timeoutMs: 8000 },
      )
    ).text,
  );
  const c = f.current || {};
  const d = f.daily || {};
  return {
    place: [loc.name, loc.admin1, loc.country].filter(Boolean).join(', '),
    timezone: f.timezone,
    now: {
      time: c.time,
      temperature_c: c.temperature_2m,
      feels_like_c: c.apparent_temperature,
      humidity_pct: c.relative_humidity_2m,
      wind_kmh: c.wind_speed_10m,
      precipitation_mm: c.precipitation,
      sky: WMO[c.weather_code] || `code ${c.weather_code}`,
    },
    days: (d.time || []).map((t, i) => ({
      date: t,
      sky: WMO[d.weather_code[i]] || `code ${d.weather_code[i]}`,
      min_c: d.temperature_2m_min[i],
      max_c: d.temperature_2m_max[i],
      rain_chance_pct: d.precipitation_probability_max ? d.precipitation_probability_max[i] : undefined,
      sunrise: d.sunrise && d.sunrise[i],
      sunset: d.sunset && d.sunset[i],
    })),
    source: 'Open-Meteo',
  };
}

// ---------------------------------------------------------------- time

function currentTime({ timezone }) {
  const tz = String(timezone || 'Asia/Dhaka').trim();
  let fmt;
  try {
    fmt = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz, weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: false, timeZoneName: 'shortOffset',
    });
  } catch {
    throw new Error(`Unknown time zone "${tz}". Use a name like Asia/Dhaka or Europe/London.`);
  }
  return { timezone: tz, now: fmt.format(new Date()), iso_utc: new Date().toISOString() };
}

// ---------------------------------------------------------------- calculator

const BN_DIGITS = '০১২৩৪৫৬৭৮৯';
const FUNCS = {
  sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
  ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
};
const CONSTS = { pi: Math.PI, e: Math.E };

/** A small recursive-descent calculator: + - * / % ^, brackets, functions.
 * It parses numbers and names only, so it can never run code. */
function calculate({ expression }) {
  let s = String(expression || '')
    .replace(/[০-৯]/g, (d) => String(BN_DIGITS.indexOf(d)))
    .replace(/[×xX]/g, '*')
    .replace(/÷/g, '/')
    .replace(/,/g, '')
    .replace(/\*\*/g, '^')
    .toLowerCase();
  if (!s.trim()) throw new Error('Give an expression, like 12*(3+4).');
  if (s.length > 300) throw new Error('That expression is too long.');
  let i = 0;
  const peek = () => {
    while (s[i] === ' ') i++;
    return s[i];
  };
  const expr = () => {
    let v = term();
    for (;;) {
      const c = peek();
      if (c === '+') { i++; v += term(); } else if (c === '-') { i++; v -= term(); } else return v;
    }
  };
  const term = () => {
    let v = power();
    for (;;) {
      const c = peek();
      if (c === '*') { i++; v *= power(); } else if (c === '/') { i++; v /= power(); } else if (c === '%') { i++; v %= power(); } else return v;
    }
  };
  const power = () => {
    const b = unary();
    if (peek() === '^') { i++; return b ** power(); }
    return b;
  };
  const unary = () => {
    const c = peek();
    if (c === '-') { i++; return -unary(); }
    if (c === '+') { i++; return unary(); }
    return atom();
  };
  const atom = () => {
    const c = peek();
    if (c === '(') {
      i++;
      const v = expr();
      if (peek() !== ')') throw new Error('A bracket is not closed.');
      i++;
      return v;
    }
    const num = s.slice(i).match(/^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/);
    if (num) {
      i += num[0].length;
      return parseFloat(num[0]);
    }
    const name = s.slice(i).match(/^[a-z][a-z0-9]*/);
    if (name) {
      i += name[0].length;
      if (name[0] in CONSTS) return CONSTS[name[0]];
      const f = FUNCS[name[0]];
      if (!f) throw new Error(`Unknown name "${name[0]}".`);
      if (peek() !== '(') throw new Error(`${name[0]} needs brackets, like ${name[0]}(2).`);
      i++;
      const v = expr();
      if (peek() !== ')') throw new Error('A bracket is not closed.');
      i++;
      return f(v);
    }
    throw new Error(`Unexpected "${c ?? 'end'}" in the expression.`);
  };
  const v = expr();
  if (peek() !== undefined) throw new Error(`Unexpected "${s[i]}" in the expression.`);
  if (!Number.isFinite(v)) throw new Error('The result is not a finite number.');
  return { expression: String(expression), result: Number(v.toPrecision(15)) };
}

module.exports = { safeFetch, isPrivateIp, htmlToText, webSearch, readWebpage, weather, currentTime, calculate, clip };
