/* Bangla AI: "add to phone" invitation, service worker and offline note for
 * the web app. Plain script, loaded by index.html next to Flutter.
 *
 * - Chrome, Edge, Samsung Internet (Android and desktop): when the browser
 *   says the site can be installed (beforeinstallprompt), a Bangla card
 *   offers "যোগ করুন"; tapping it opens the browser's own install dialog,
 *   which the visitor approves or cancels.
 * - iPhone / iPad: there is no install dialog, so the card shows the
 *   Share > Add to Home Screen steps instead.
 * - Firefox on Android: the card points to the browser menu.
 * - Never shown inside the installed app, after it was installed, or for 30
 *   days after the visitor closes it ("এখন না" or cancelling the dialog).
 */
(function () {
  'use strict';

  var KEY_DISMISSED = 'bai.install.dismissedAt';
  var KEY_INSTALLED = 'bai.install.installed';
  var QUIET_DAYS = 30;
  var SHOW_DELAY_MS = 2500;

  function get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } }
  function set(k, v) { try { localStorage.setItem(k, v); } catch (_) {} }

  var ua = navigator.userAgent || '';
  var isIOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var isAndroid = /Android/i.test(ua);
  var inAppBrowser = /FBAN|FBAV|FB_IAB|Instagram|Messenger|Line\/|MicroMessenger|; wv\)|TikTok|Snapchat/i.test(ua);
  var isFirefoxAndroid = isAndroid && /Firefox|FxiOS/i.test(ua);

  function standalone() {
    try {
      if (navigator.standalone === true) return true;
      var modes = ['standalone', 'fullscreen', 'minimal-ui', 'window-controls-overlay'];
      for (var i = 0; i < modes.length; i++) {
        if (window.matchMedia('(display-mode: ' + modes[i] + ')').matches) return true;
      }
    } catch (_) {}
    return document.referrer.indexOf('android-app://') === 0;
  }

  function quiet() {
    if (standalone() || get(KEY_INSTALLED) === '1') return true;
    var at = Number(get(KEY_DISMISSED) || 0);
    return at && Date.now() - at < QUIET_DAYS * 864e5;
  }

  /* ---------- service worker ---------- */

  function sendLoadedFiles() {
    if (!navigator.serviceWorker || !navigator.serviceWorker.controller) return;
    try {
      var urls = performance.getEntriesByType('resource')
        .map(function (e) { return e.name; })
        .filter(function (u) {
          var url = new URL(u, location.href);
          return url.origin === location.origin && !/^\/(v1|admin)(\/|$)|^\/health$/.test(url.pathname);
        });
      navigator.serviceWorker.controller.postMessage({ type: 'cache-urls', urls: urls });
    } catch (_) {}
  }

  var secure = location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1';
  if ('serviceWorker' in navigator && secure) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).then(function () {
        if (navigator.serviceWorker.controller) setTimeout(sendLoadedFiles, 4000);
        else navigator.serviceWorker.addEventListener('controllerchange', function () { setTimeout(sendLoadedFiles, 1500); }, { once: true });
      }).catch(function (e) { console.warn('Service worker not registered:', e); });
    });
  }

  /* ---------- styles ---------- */

  var css =
    '#bai-install{position:fixed;left:0;right:0;bottom:0;z-index:2147483000;display:flex;justify-content:center;' +
    'padding:0 12px calc(12px + env(safe-area-inset-bottom));pointer-events:none;' +
    'font-family:"Noto Sans Bengali",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}' +
    '#bai-install .card{pointer-events:auto;width:100%;max-width:440px;box-sizing:border-box;background:#fff;color:#13241D;' +
    'border-radius:20px;padding:16px 16px 14px;box-shadow:0 12px 40px rgba(0,0,0,.22),0 0 0 1px rgba(0,106,78,.10);' +
    'transform:translateY(130%);transition:transform 320ms cubic-bezier(.2,.8,.2,1)}' +
    '#bai-install.show .card{transform:none}' +
    '#bai-install .top{display:flex;gap:12px;align-items:center}' +
    '#bai-install img{width:52px;height:52px;border-radius:14px;flex:none}' +
    '#bai-install .t{font-size:17px;font-weight:700;line-height:1.35;margin:0}' +
    '#bai-install .s{font-size:14px;line-height:1.5;margin:2px 0 0;color:#4A5753}' +
    '#bai-install .x{margin-left:auto;align-self:flex-start;flex:none;width:36px;height:36px;border:0;border-radius:50%;' +
    'background:transparent;color:#4A5753;font-size:22px;line-height:36px;cursor:pointer}' +
    '#bai-install ol{margin:12px 0 0;padding:0 0 0 22px;font-size:14.5px;line-height:1.6}' +
    '#bai-install ol li{margin:4px 0}' +
    '#bai-install .ic{display:inline-block;vertical-align:-4px;width:20px;height:20px;color:#006A4E}' +
    '#bai-install .en{color:#4A5753;font-size:13px}' +
    '#bai-install .row{display:flex;gap:8px;justify-content:flex-end;margin-top:14px}' +
    '#bai-install .b{min-height:44px;padding:0 20px;border-radius:999px;font-size:15.5px;font-weight:700;cursor:pointer;' +
    'font-family:inherit;border:0}' +
    '#bai-install .b.p{background:#006A4E;color:#fff}' +
    '#bai-install .b.g{background:transparent;color:#006A4E}' +
    '#bai-install .b:focus-visible,#bai-install .x:focus-visible{outline:3px solid #2DBE8A;outline-offset:2px}' +
    '@media (prefers-color-scheme: dark){#bai-install .card{background:#17221E;color:#E8F0EC;' +
    'box-shadow:0 12px 40px rgba(0,0,0,.5),0 0 0 1px rgba(169,220,200,.14)}' +
    '#bai-install .s,#bai-install .x,#bai-install .en{color:#B9C4BF}#bai-install .ic{color:#2DBE8A}' +
    '#bai-install .b.g{color:#A9DCC8}#bai-install .b.p{background:#0E8C67}}' +
    '@media (prefers-reduced-motion: reduce){#bai-install .card,#bai-offline{transition:none}}' +
    '#bai-offline{position:fixed;left:0;right:0;margin:0 auto;width:max-content;top:calc(10px + env(safe-area-inset-top));' +
    'z-index:2147483001;transform:translateY(-160%);transition:transform 260ms ease;pointer-events:none;max-width:calc(100% - 24px);' +
    'box-sizing:border-box;background:#13241D;color:#fff;border-radius:999px;padding:8px 16px;font-size:13.5px;' +
    'line-height:1.4;text-align:center;box-shadow:0 6px 20px rgba(0,0,0,.25);' +
    'font-family:"Noto Sans Bengali",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}' +
    '#bai-offline.show{transform:none}' +
    '#bai-offline b{color:#FF6B7B;font-weight:700}';

  function addStyles() {
    if (document.getElementById('bai-pwa-css')) return;
    var s = document.createElement('style');
    s.id = 'bai-pwa-css';
    s.textContent = css;
    document.head.appendChild(s);
  }

  /* ---------- offline note ---------- */

  var offlineEl;
  function updateOnline() {
    addStyles();
    if (!offlineEl) {
      offlineEl = document.createElement('div');
      offlineEl.id = 'bai-offline';
      offlineEl.setAttribute('role', 'status');
      offlineEl.setAttribute('aria-live', 'polite');
      offlineEl.innerHTML = '<b>অফলাইন</b> · উত্তর পেতে ইন্টারনেট লাগবে';
      document.body.appendChild(offlineEl);
    }
    offlineEl.classList.toggle('show', navigator.onLine === false);
  }
  window.addEventListener('online', updateOnline);
  window.addEventListener('offline', updateOnline);

  /* ---------- install card ---------- */

  var deferred = null;   // the beforeinstallprompt event
  var shown = false;
  var appReady = false;
  var root = null;

  var SHARE_ICON = '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="M8 7l4-4 4 4"/><path d="M6 11H5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-1"/></svg>';
  var PLUS_ICON = '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/></svg>';
  var MENU_ICON = '<svg class="ic" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>';

  function build(kind) {
    addStyles();
    root = document.createElement('div');
    root.id = 'bai-install';
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-labelledby', 'bai-install-t');
    root.setAttribute('data-kind', kind);
    var top =
      '<div class="top"><img src="/icons/Icon-192.png" alt="">' +
      '<div><p class="t" id="bai-install-t">Bangla AI ফোনে যোগ করুন</p>' +
      '<p class="s">অ্যাপের মতো এক ট্যাপে খুলুন, পুরো স্ক্রিনে।</p></div>' +
      '<button class="x" type="button" data-act="close" aria-label="বন্ধ করুন">×</button></div>';
    var body;
    if (kind === 'ios') {
      body =
        '<ol>' +
        '<li>ব্রাউজারের শেয়ার বোতামে ' + SHARE_ICON + ' ট্যাপ করুন</li>' +
        '<li>' + PLUS_ICON + ' <b>হোম স্ক্রিনে যোগ করুন</b> <span class="en">(Add to Home Screen)</span> বেছে নিন</li>' +
        '<li>উপরে <b>যোগ</b> <span class="en">(Add)</span> চাপুন</li>' +
        '</ol>' +
        '<div class="row"><button class="b p" type="button" data-act="close">বুঝেছি</button></div>';
    } else if (kind === 'menu') {
      body =
        '<ol>' +
        '<li>ব্রাউজারের মেনু ' + MENU_ICON + ' খুলুন</li>' +
        '<li><b>ইনস্টল</b> বা <b>হোম স্ক্রিনে যোগ করুন</b> <span class="en">(Install / Add to Home screen)</span> বেছে নিন</li>' +
        '</ol>' +
        '<div class="row"><button class="b p" type="button" data-act="close">বুঝেছি</button></div>';
    } else {
      body =
        '<div class="row"><button class="b g" type="button" data-act="close">এখন না</button>' +
        '<button class="b p" type="button" data-act="install">যোগ করুন</button></div>';
    }
    root.innerHTML = '<div class="card">' + top + body + '</div>';
    root.addEventListener('click', function (e) {
      var t = e.target.closest && e.target.closest('[data-act]');
      if (!t) return;
      if (t.getAttribute('data-act') === 'install') install();
      else dismiss();
    });
    document.body.appendChild(root);
    // next frame so the slide-in animates
    requestAnimationFrame(function () { requestAnimationFrame(function () { root && root.classList.add('show'); }); });
  }

  function hide() {
    if (!root) return;
    var r = root;
    root = null;
    r.classList.remove('show');
    setTimeout(function () { r.remove(); }, 350);
  }

  function dismiss() {
    set(KEY_DISMISSED, String(Date.now()));
    hide();
  }

  function install() {
    var ev = deferred;
    deferred = null;
    if (!ev) return hide();
    hide();
    try {
      ev.prompt();
      Promise.resolve(ev.userChoice).then(function (choice) {
        if (choice && choice.outcome === 'accepted') set(KEY_INSTALLED, '1');
        else set(KEY_DISMISSED, String(Date.now()));
      }).catch(function () {});
    } catch (e) {
      console.warn('Install prompt failed:', e);
    }
  }

  function maybeShow() {
    if (shown || !appReady || quiet()) return;
    var kind = null;
    if (deferred) kind = 'prompt';
    else if (isIOS && !inAppBrowser) kind = 'ios';
    else if (isFirefoxAndroid) kind = 'menu';
    if (!kind) return;
    shown = true;
    build(kind);
  }

  window.addEventListener('beforeinstallprompt', function (e) {
    // Keep the browser's own mini-bar back and offer our Bangla card instead.
    e.preventDefault();
    deferred = e;
    if (quiet()) return;
    setTimeout(maybeShow, appReady ? 600 : 0);
  });

  window.addEventListener('appinstalled', function () {
    set(KEY_INSTALLED, '1');
    deferred = null;
    hide();
  });

  function onAppReady() {
    if (appReady) return;
    appReady = true;
    updateOnline();
    setTimeout(maybeShow, SHOW_DELAY_MS);
  }
  window.addEventListener('flutter-first-frame', onAppReady);
  // If Flutter never paints (offline with nothing cached), still show the
  // offline note and say so on the splash.
  window.addEventListener('load', function () {
    setTimeout(function () {
      if (appReady) return;
      updateOnline();
      if (navigator.onLine === false) {
        var s = document.querySelector('#splash .name');
        if (s) s.textContent = 'ইন্টারনেট সংযোগ নেই';
      }
    }, 8000);
  });

  // Small hook for tests and for a future "install" menu item in the app.
  window.baiInstall = {
    canPrompt: function () { return !!deferred; },
    show: function () { shown = false; set(KEY_DISMISSED, ''); appReady = true; maybeShow(); },
    state: function () { return { standalone: standalone(), quiet: !!quiet(), ios: isIOS, prompt: !!deferred }; },
  };
})();
