#!/bin/bash
set -euo pipefail

OPTIONS_FILE=/data/options.json
mkdir -p /share/addon-python/scripts /data/logs /etc/nginx/conf.d

# --- Lecture des options HA (pas de bashio : parsing JSON direct en Python) ---
read_opt() {
  python3 - "$1" "$2" <<'PY'
import json, sys
key, default = sys.argv[1], sys.argv[2]
try:
    with open("/data/options.json") as f:
        data = json.load(f)
    print(data.get(key, default))
except FileNotFoundError:
    print(default)
PY
}

export TERM_USER="$(read_opt terminal_user admin)"
export TERM_PASS="$(read_opt terminal_password changeme)"
export PORT_RANGE_START="$(read_opt script_port_range_start 9000)"
export PORT_RANGE_END="$(read_opt script_port_range_end 9099)"

# Fichier de conf nginx généré dynamiquement par le backend à chaque start/stop de script
touch /etc/nginx/conf.d/dynamic_scripts.conf
cp /etc/nginx/templates/nginx.conf.template /etc/nginx/nginx.conf

echo "[entrypoint] démarrage nginx"
nginx -g "daemon off;" &
NGINX_PID=$!

echo "[entrypoint] démarrage ttyd (terminal web, auth basique)"
ttyd --port 7681 --interface 127.0.0.1 -c "${TERM_USER}:${TERM_PASS}" \
     tmux new -A -s main &
TTYD_PID=$!

echo "[entrypoint] démarrage backend (FastAPI/uvicorn)"
cd /opt/backend
uvicorn app:app --host 127.0.0.1 --port 8000 &
BACKEND_PID=$!

term() {
  echo "[entrypoint] arrêt en cours..."
  kill -TERM "$NGINX_PID" "$TTYD_PID" "$BACKEND_PID" 2>/dev/null || true
  wait
  exit 0
}
trap term SIGTERM SIGINT

# Si un des trois processus meurt, on arrête proprement tout le conteneur
wait -n
term
