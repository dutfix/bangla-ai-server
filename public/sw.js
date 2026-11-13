/* Bangla AI service worker (the web app at https://ai.banglaai.cloud).
 *
 * - Makes the site installable and lets the app shell open offline.
 * - Network first for every app file, so a new deploy shows up on the next
 *   online visit exactly as before; the cache is only the offline fallback.
 * - Never touches the API: /v1/*, /admin/*, /health, anything that is not a
 *   GET, anything with an Authorization header, other sites, and JSON at /.
 *   Chats, admin sign-in and settings always go straight to the network and
 *   are never stored here.
 *
 * Flutter's own flutter_service_worker.js is not used (build_web.sh deletes
 * it and flutter_bootstrap.js no longer asks for it), so this is the only
 * worker for the site.
 */
'use strict';

const CACHE = 'bangla-ai-shell-v1';

// Small core of the shell. The rest (engine, fonts, assets) is added from the
// page after it loads, or the first time it is fetched while this worker runs.
const CORE = [
  '/',
  '/manifest.json',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/main.dart.js',
  '/favicon.png',
  '/splash-logo.png',
  '/pwa.js',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/apple-touch-icon.png',
];

function isPrivatePath(pathname) {
  return (
    pathname.startsWith('/v1/') ||
    pathname.startsWith('/admin/') ||
    pathname === '/v1' ||
    pathname === '/admin' ||
    pathname === '/health' ||
    pathname === '/sw.js'
  );
}

/** True for requests this worker may answer and store. */
function cacheable(request) {
  if (request.method !== 'GET') return false;
  if (request.headers.has('authorization')) return false;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return false;
  if (isPrivatePath(url.pathname)) return false;
  const accept = request.headers.get('accept') || '';
  if (url.pathname === '/' && accept.includes('application/json') && !accept.includes('text/html')) return false;
  return true;
}

function storable(response) {
  if (!response || response.status !== 200 || response.type !== 'basic') return false;
  const cc = response.headers.get('cache-control') || '';
  return !/no-store|private/i.test(cc);
}

function keyFor(request) {
  const url = new URL(request.url);
  // Every page in the app is the same shell at "/".
  if (request.mode === 'navigate') return '/';
  return url.pathname + url.search;
}

async function put(key, response) {
  if (!storable(response)) return;
  const cache = await caches.open(CACHE);
  await cache.put(key, response);
}

async function addAll(urls) {
  const cache = await caches.open(CACHE);
  await Promise.all(
    urls.map(async (u) => {
      try {
        const url = new URL(u, self.location.origin);
        if (url.origin !== self.location.origin || isPrivatePath(url.pathname)) return;
        const key = url.pathname + url.search;
        // The page has just loaded these, so this is usually served from the
        // browser's HTTP cache (or a small 304) rather than downloaded again.
        const res = await fetch(new Request(key, { headers: { Accept: key === '/' ? 'text/html' : '*/*' } }));
        if (storable(res)) await cache.put(key, res);
      } catch (_) {
        /* offline or gone: skip it */
      }
    }),
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(addAll(CORE).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.filter((n) => n.startsWith('bangla-ai-') && n !== CACHE).map((n) => caches.delete(n)));
      await self.clients.claim();
    })(),
  );
});

// The page sends the files it loaded (engine, fonts...) once it is running.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'cache-urls' && Array.isArray(data.urls)) {
    event.waitUntil(addAll(data.urls.slice(0, 200)));
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (!cacheable(request)) return; // straight to the network, untouched
  const key = keyFor(request);
  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request);
        if (storable(response)) {
          const copy = response.clone();
          event.waitUntil(put(key, copy).catch(() => {}));
        }
        return response;
      } catch (err) {
        const cache = await caches.open(CACHE);
        const hit = (await cache.match(key)) || (request.mode === 'navigate' ? await cache.match('/', { ignoreSearch: true }) : null);
        if (hit) return hit;
        if (request.mode === 'navigate') {
          return new Response(
            '<!doctype html><html lang="bn"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
              '<title>Bangla AI</title><body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;' +
              'background:#006A4E;color:#fff;font-family:system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box">' +
              '<div><h1 style="font-size:22px">ইন্টারনেট সংযোগ নেই</h1>' +
              '<p style="opacity:.9">Bangla AI খুলতে একবার ইন্টারনেট লাগবে। সংযোগ ফিরলে আবার চেষ্টা করুন।</p>' +
              '<button onclick="location.reload()" style="margin-top:12px;padding:12px 22px;border:0;border-radius:999px;background:#fff;color:#006A4E;font-size:16px;font-weight:700">আবার চেষ্টা করুন</button></div>',
            { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } },
          );
        }
        throw err;
      }
    })(),
  );
});
