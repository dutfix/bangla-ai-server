'use strict';

// Serves the web version of the Bangla AI app (a Flutter web build in
// public/, made by app/tool/build_web.sh) from the same server, so
// https://ai.banglaai.cloud opens the app and its chats go to /v1/chat on the
// same address. API routes are matched first in server.js and never reach here.

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');

const ROOT = path.join(__dirname, 'public');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.css': 'text/css; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
  '.frag': 'application/octet-stream',
  '.bin': 'application/octet-stream',
  '.txt': 'text/plain; charset=utf-8',
};

// Text-like files are gzipped once and kept in memory.
const COMPRESS = new Set(['.html', '.js', '.mjs', '.json', '.wasm', '.ttf', '.otf', '.css', '.map', '.symbols', '.frag', '.bin', '.txt', '.svg']);

const cache = new Map(); // file -> { mtimeMs, body, gz, etag }

function available() {
  return fs.existsSync(path.join(ROOT, 'index.html'));
}

function load(file) {
  const st = fs.statSync(file);
  if (!st.isFile()) return null;
  const hit = cache.get(file);
  if (hit && hit.mtimeMs === st.mtimeMs) return hit;
  const body = fs.readFileSync(file);
  const ext = path.extname(file).toLowerCase();
  const entry = {
    mtimeMs: st.mtimeMs,
    body,
    gz: COMPRESS.has(ext) && body.length > 1024 ? zlib.gzipSync(body, { level: 6 }) : null,
    etag: '"' + crypto.createHash('sha1').update(body).digest('base64url').slice(0, 20) + '"',
  };
  cache.set(file, entry);
  return entry;
}

/** Serves a file from public/. Returns false when there is no such file. */
function serveStatic(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return false;
  let rel;
  try {
    rel = decodeURIComponent(pathname);
  } catch {
    return false;
  }
  if (rel === '/' || rel === '') rel = '/index.html';
  const file = path.normalize(path.join(ROOT, rel));
  if (!file.startsWith(ROOT + path.sep)) return false;
  let entry;
  try {
    entry = load(file);
  } catch {
    return false;
  }
  if (!entry) return false;

  const ext = path.extname(file).toLowerCase();
  // The engine files never change for a given build name; everything else is
  // revalidated so a new deploy shows up on the next visit.
  const cacheControl = rel.startsWith('/canvaskit/') ? 'public, max-age=604800' : 'no-cache';
  const headers = {
    'Content-Type': TYPES[ext] || 'application/octet-stream',
    'Cache-Control': cacheControl,
    ETag: entry.etag,
    'X-Content-Type-Options': 'nosniff',
    Vary: 'Accept-Encoding',
  };
  if (req.headers['if-none-match'] === entry.etag) {
    res.writeHead(304, headers);
    return res.end(), true;
  }
  const gzipOk = entry.gz && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
  const body = gzipOk ? entry.gz : entry.body;
  if (gzipOk) headers['Content-Encoding'] = 'gzip';
  headers['Content-Length'] = body.length;
  res.writeHead(200, headers);
  res.end(req.method === 'HEAD' ? undefined : body);
  return true;
}

/** True when the request at "/" is from a browser (wants a page, not JSON). */
function wantsPage(req) {
  const accept = String(req.headers.accept || '');
  if (accept.includes('text/html')) return true;
  return !accept.includes('application/json');
}

module.exports = { serveStatic, wantsPage, available, ROOT };
