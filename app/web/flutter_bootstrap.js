{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own (deprecated) service worker is not
// used. pwa.js registers /sw.js, which handles offline and install.
_flutter.loader.load();
