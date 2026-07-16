#!/usr/bin/env bash
# deploy.sh — ship a freshly-built ./hart to a systemd host, with backup rotation.
#
# Encodes the swap-and-restart flow (stage -> canary sha -> backup -> swap -> restart -> health)
# and caps retained backups so they never need manual pruning again (see machin-hart#3).
#
# Usage:
#   ./scripts/deploy.sh [--build] [--db-backup] [--dry-run]
#
# Config (env, with defaults for the intrane instance on dk1):
#   HART_DEPLOY_HOST=dk1                 ssh target (an alias in ~/.ssh/config, or user@host)
#   HART_DEPLOY_DIR=/opt/hart            install dir on the host (holds `hart` + `hart.db`)
#   HART_DEPLOY_SERVICE=hart.service     systemd unit to restart
#   HART_DEPLOY_PORT=8799                local port on the host for the health check
#   HART_KEEP_BINARY_BACKUPS=3           how many timestamped binary backups to retain
#   HART_KEEP_DB_BACKUPS=3               how many timestamped DB snapshots to retain (--db-backup)
#
# Flags:
#   --build       run ./build.sh first
#   --db-backup   snapshot hart.db before swapping (use for schema-migrating releases)
#   --dry-run     print what would happen; touch nothing
#
# Rollback: the newest hart.bin.bak-<ts> is the previous binary —
#   ssh $HOST "sudo mv $DIR/hart.bin.bak-<ts> $DIR/hart && sudo systemctl restart $SERVICE"
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${HART_DEPLOY_HOST:-dk1}"
DIR="${HART_DEPLOY_DIR:-/opt/hart}"
SERVICE="${HART_DEPLOY_SERVICE:-hart.service}"
PORT="${HART_DEPLOY_PORT:-8799}"
KEEP_BIN="${HART_KEEP_BINARY_BACKUPS:-3}"
KEEP_DB="${HART_KEEP_DB_BACKUPS:-3}"

BUILD=0; DB_BACKUP=0; DRY=0
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    --db-backup) DB_BACKUP=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "deploy: unknown flag $arg" >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "DRY  $*"; else eval "$*"; fi; }

[ "$BUILD" = 1 ] && run "./build.sh"
[ -x ./hart ] || { echo "deploy: ./hart not found (pass --build)" >&2; exit 1; }
LSHA=$(sha256sum ./hart | awk '{print $1}')
TS=$(date -u +%Y%m%dT%H%M%SZ)
echo "deploy: ./hart ($LSHA) -> $HOST:$DIR  [keep bin=$KEEP_BIN db=$KEEP_DB]"

# 1. stage + verify the transfer was byte-identical
run "scp -q ./hart $HOST:$DIR/hart.new"
if [ "$DRY" != 1 ]; then
  RSHA=$(ssh "$HOST" "sha256sum $DIR/hart.new | awk '{print \$1}'")
  [ "$RSHA" = "$LSHA" ] || { echo "deploy: sha mismatch after scp ($RSHA)" >&2; exit 1; }
  echo "deploy: staged + sha verified"
fi

# 2. remote: (optional DB snapshot) -> backup+swap binary -> restart -> rotate -> health.
#    `rotate <glob> <keep>` deletes all but the newest <keep> matches.
REMOTE=$(cat <<REMOTE_EOF
set -euo pipefail
# rotate <name-glob> <keep>: keep the newest <keep> matches in \$DIR, delete the rest.
# find does the wildcard match (no shell glob needed) so this is portable across bash/zsh/sh.
DIR="$DIR"
rotate() { find "\$DIR" -maxdepth 1 -name "\$1" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | tail -n +\$(( \$2 + 1 )) | cut -f2- | xargs -r sudo rm -f; }
sudo chmod +x "\$DIR/hart.new"
if [ "$DB_BACKUP" = 1 ] && [ -f "\$DIR/hart.db" ]; then
  sudo cp -a "\$DIR/hart.db" "\$DIR/hart.db.bak-$TS"
  rotate "hart.db.bak-*" $KEEP_DB
  echo "  db snapshot: hart.db.bak-$TS"
fi
sudo cp -a "\$DIR/hart" "\$DIR/hart.bin.bak-$TS"
sudo mv "\$DIR/hart.new" "\$DIR/hart"
sudo systemctl restart $SERVICE
sleep 1
rotate "hart.bin.bak-*" $KEEP_BIN
echo "  binary backup: hart.bin.bak-$TS ; service: \$(systemctl is-active $SERVICE)"
curl -fsS "http://127.0.0.1:$PORT/_health" && echo
REMOTE_EOF
)
# Pipe the script to the host's shell via stdin — no outer quoting to collide with the
# single-quotes inside REMOTE (e.g. find's -printf format). set -e on the remote aborts on error.
if [ "$DRY" = 1 ]; then
  echo "DRY  ssh $HOST bash -s <<'REMOTE'"; echo "$REMOTE"; echo "REMOTE"
else
  printf '%s\n' "$REMOTE" | ssh "$HOST" bash -s
fi

if [ "$DRY" = 1 ]; then echo "deploy: done (dry-run)"; else echo "deploy: done"; fi
