#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
machin encode framework/machweb.src src/hart.src > build/hart.mfl
machin build build/hart.mfl -o hart
echo "built ./hart"
