#!/bin/bash
# Service script for stat1090
# Launches the stat1090 python server and optional background pre-render daemon

trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND"' ERR
trap "pkill -P $$ || true; exit 0" SIGTERM SIGINT SIGHUP SIGQUIT

renice 20 $$ || true

IPATH="/usr/share/stat1090"
if [[ ! -d "$IPATH" ]]; then
    IPATH="$(cd "$(dirname "$0")" && pwd)"
fi

PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"

echo "Starting stat1090 service on ${HOST}:${PORT}..."
export PORT HOST

exec python3 "${IPATH}/stat1090-server.py"
