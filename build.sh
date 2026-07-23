#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
mkdir -p build
machin encode framework/machweb.src src/dash/ui.src src/dash/badge.src src/dash/card.src src/dash/stat.src src/dash/table.src src/dash/code_block.src src/dash/list_group.src src/dash/footer.src src/dash/separator.src src/dash/status.src src/dash_css.src src/chrome.src src/hart.src > build/hart.mfl
machin build build/hart.mfl -o hart
echo "built ./hart"
