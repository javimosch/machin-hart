#!/usr/bin/env bash
# Static export for GitHub Pages: the SSR page + wasm client -> ../docs
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../docs
./app --render > ../docs/index.html
cp app.wasm ../docs/app.wasm
touch ../docs/.nojekyll
echo "exported ../docs ($(wc -c < ../docs/index.html)B html + $(wc -c < ../docs/app.wasm)B wasm)"
