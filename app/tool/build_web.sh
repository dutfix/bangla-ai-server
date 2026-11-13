#!/usr/bin/env bash
# Builds the web version of Bangla AI and copies it to ../public, which the
# server (web.js) serves at "/" (https://ai.banglaai.cloud). Commit public/
# afterwards; Render only runs npm install, so it cannot build Flutter itself.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --no-web-resources-cdn --no-wasm-dry-run

out=../public
rm -rf "$out"
cp -r build/web "$out"

# The JavaScript build only loads canvaskit.wasm (or its chromium variant).
# The wasm-only renderers, the experimental paragraph engine and debug
# symbols are never fetched, so they are left out to keep the repo small.
rm -rf "$out"/canvaskit/skwasm* "$out"/canvaskit/wimp* "$out"/canvaskit/webparagraph
find "$out" -name '*.symbols' -delete
find "$out" -name '*.map' -delete
# Flutter's own service worker is not used: web/sw.js (registered by
# web/pwa.js) handles install and offline, and web/flutter_bootstrap.js loads
# the app without asking for flutter_service_worker.js.
rm -f "$out"/flutter_service_worker.js "$out"/.last_build_id
grep -q 'serviceWorkerVersion: "' "$out"/flutter_bootstrap.js && { echo 'flutter_bootstrap.js still registers the Flutter service worker' >&2; exit 1; }

du -sh "$out"
