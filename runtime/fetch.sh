#!/usr/bin/env bash
# Download the same-origin JSX runtime hart serves at /_hart/runtime/*. Run once per deploy.
set -e
cd "$(dirname "$0")"
curl -sSL https://unpkg.com/react@18/umd/react.production.min.js        -o react.js
curl -sSL https://unpkg.com/react-dom@18/umd/react-dom.production.min.js -o react-dom.js
curl -sSL https://unpkg.com/@babel/standalone/babel.min.js              -o babel.js
echo "runtime: $(ls -la react.js react-dom.js babel.js | awk '{print $9": "$5" bytes"}' | tr '\n' ' ')"
