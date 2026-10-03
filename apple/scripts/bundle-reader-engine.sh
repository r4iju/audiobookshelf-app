#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
# esbuild 0.25.12 is a build tool only. All parser sources and WASM are retained with the app.
esbuild="${ESBUILD:-/Volumes/ai-ssd/developer-caches/bun-cache/@esbuild/darwin-arm64@0.25.12@@@1/bin/esbuild}"
"$esbuild" "$root/ReaderEngine/engine.js" --bundle --format=iife --platform=browser --target=safari14 --loader:.wasm=binary --external:module --define:import.meta.url='"file:///ReaderAssets/libarchive.js"' --minify --outfile="$root/App/ReaderAssets/engine.min.js"
