"""
Python Script Manager - backend
--------------------------------
- CRUD des fichiers .py dans /share/addon-python/scripts
- start/stop/status des scripts (subprocess, un process par script)
- allocation d'un port depuis un pool configurable pour les scripts
  qui exposent un service web, régénération de la conf nginx
  (/etc/nginx/conf.d/dynamic_scripts.conf) + reload à chaud
- wrapper minimal pour l'API Supervisor HA (SUPERVISOR_TOKEN)

Limites connues (v0.1, cf. README "pistes d'amélioration") :
- l'état des process vit en mémoire : si le backend redémarre seul
  (sans redémarrer tout le conteneur), les scripts déjà lancés
  continuent de tourner mais deviennent "orphelins" pour l'UI.
  -> amélioration prévue : fichier PID par script + réconciliation au boot.
- pas de limite CPU/RAM par script (tous dans le même cgroup que le conteneur).
- pas d'isolation entre scripts (même filesystem, même réseau).
"""
import json
import os
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

SCRIPTS_DIR = Path("/share/addon-python/scripts")
LOGS_DIR = Path("/data/logs")
STATE_FILE = Path("/data/state.json")
NGINX_DYNAMIC_CONF = Path("/etc/nginx/conf.d/dynamic_scripts.conf")

PORT_RANGE_START = int(os.environ.get("PORT_RANGE_START", 9000))
PORT_RANGE_END = int(os.environ.get("PORT_RANGE_END", 9099))

SUPERVISOR_TOKEN = os.environ.get("SUPERVISOR_TOKEN")
SUPERVISOR_URL = "http://supervisor"

SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Python Script Manager")

_lock = threading.Lock()
# état en mémoire : name -> {"process": Popen|None, "port": int|None, "autostart": bool}
_runtime: dict[str, dict] = {}


# --------------------------------------------------------------------------
# Persistance légère (métadonnées seulement, pas le code : le code = .py)
# --------------------------------------------------------------------------
def _load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def _save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2))


def _script_path(name: str) -> Path:
    # sécurité basique anti path-traversal : un seul segment de nom autorisé
    if "/" in name or ".." in name or not name.endswith(".py"):
        raise HTTPException(400, "Nom de script invalide (doit finir par .py, sans '/')")
    return SCRIPTS_DIR / name


def _next_free_port() -> int:
    used = {v["port"] for v in _runtime.values() if v.get("port")}
    for p in range(PORT_RANGE_START, PORT_RANGE_END + 1):
        if p not in used:
            return p
    raise HTTPException(409, "Plus de port disponible dans le pool configuré")


def _regen_nginx_conf() -> None:
    """Régénère le bloc de proxy dynamique (port externe unique 8090) et recharge nginx."""
    lines = []
    for name, info in _runtime.items():
        if info.get("process") is not None and info.get("port"):
            slug = name.removesuffix(".py")
            lines.append(
                f"location /s/{slug}/ {{\n"
                f"    proxy_pass http://127.0.0.1:{info['port']}/;\n"
                f"    proxy_http_version 1.1;\n"
                f"    proxy_set_header Upgrade $http_upgrade;\n"
                f"    proxy_set_header Connection $connection_upgrade;\n"
                f"    proxy_set_header Host $host;\n"
                f"}}\n"
            )
    NGINX_DYNAMIC_CONF.write_text("\n".join(lines))
    subprocess.run(["nginx", "-s", "reload"], check=False)


# --------------------------------------------------------------------------
# Modèles API
# --------------------------------------------------------------------------
class ScriptCreate(BaseModel):
    name: str          # ex: "mon_script.py"
    content: str = ""
    needs_port: bool = False   # True si le script doit recevoir un $PORT (serveur web)
    autostart: bool = False


class ScriptContent(BaseModel):
    content: str


# --------------------------------------------------------------------------
# CRUD scripts (fichiers dans /share/addon-python/scripts)
# --------------------------------------------------------------------------
@app.get("/api/scripts")
def list_scripts():
    out = []
    for f in sorted(SCRIPTS_DIR.glob("*.py")):
        info = _runtime.get(f.name, {})
        proc = info.get("process")
        out.append({
            "name": f.name,
            "running": proc is not None and proc.poll() is None,
            "pid": proc.pid if proc and proc.poll() is None else None,
            "port": info.get("port"),
            "autostart": info.get("autostart", False),
            "size": f.stat().st_size,
            "modified": f.stat().st_mtime,
        })
    return out


@app.post("/api/scripts", status_code=201)
def create_script(payload: ScriptCreate):
    path = _script_path(payload.name)
    if path.exists():
        raise HTTPException(409, "Un script porte déjà ce nom")
    path.write_text(payload.content)
    state = _load_state()
    state[payload.name] = {"needs_port": payload.needs_port, "autostart": payload.autostart}
    _save_state(state)
    _runtime.setdefault(payload.name, {"process": None, "port": None, "autostart": payload.autostart})
    return {"ok": True}


@app.get("/api/scripts/{name}")
def get_script(name: str):
    path = _script_path(name)
    if not path.exists():
        raise HTTPException(404, "Script introuvable")
    return {"name": name, "content": path.read_text()}


@app.put("/api/scripts/{name}")
def update_script(name: str, payload: ScriptContent):
    path = _script_path(name)
    if not path.exists():
        raise HTTPException(404, "Script introuvable")
    path.write_text(payload.content)
    return {"ok": True}


@app.delete("/api/scripts/{name}")
def delete_script(name: str):
    path = _script_path(name)
    if name in _runtime and _runtime[name].get("process") is not None:
        raise HTTPException(409, "Arrêtez le script avant de le supprimer")
    if path.exists():
        path.unlink()
    state = _load_state()
    state.pop(name, None)
    _save_state(state)
    _runtime.pop(name, None)
    return {"ok": True}


# --------------------------------------------------------------------------
# Cycle de vie (start / stop / status / logs)
# --------------------------------------------------------------------------
@app.post("/api/scripts/{name}/start")
def start_script(name: str):
    path = _script_path(name)
    if not path.exists():
        raise HTTPException(404, "Script introuvable")

    with _lock:
        info = _runtime.setdefault(name, {"process": None, "port": None, "autostart": False})
        if info["process"] is not None and info["process"].poll() is None:
            raise HTTPException(409, "Déjà en cours d'exécution")

        state = _load_state()
        needs_port = state.get(name, {}).get("needs_port", False)
        port = _next_free_port() if needs_port else None

        env = os.environ.copy()
        env["SCRIPT_DATA_DIR"] = str(SCRIPTS_DIR)
        if port:
            env["PORT"] = str(port)

        log_file = LOGS_DIR / f"{name}.log"
        log_fh = open(log_file, "ab")

        proc = subprocess.Popen(
            ["python3", "-u", str(path)],
            cwd=str(SCRIPTS_DIR),
            env=env,
            stdout=log_fh,
            stderr=subprocess.STDOUT,
            start_new_session=True,  # process group dédié -> stop propre
        )
        info["process"] = proc
        info["port"] = port
        _regen_nginx_conf()

    return {"ok": True, "pid": proc.pid, "port": port}


@app.post("/api/scripts/{name}/stop")
def stop_script(name: str):
    with _lock:
        info = _runtime.get(name)
        if not info or info.get("process") is None or info["process"].poll() is not None:
            raise HTTPException(409, "Le script n'est pas en cours d'exécution")
        proc = info["process"]
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
        info["process"] = None
        info["port"] = None
        _regen_nginx_conf()
    return {"ok": True}


@app.get("/api/scripts/{name}/status")
def status_script(name: str):
    info = _runtime.get(name, {})
    proc = info.get("process")
    running = proc is not None and proc.poll() is None
    return {
        "running": running,
        "pid": proc.pid if running else None,
        "port": info.get("port") if running else None,
        "external_url": f"/s/{name.removesuffix('.py')}/" if running and info.get("port") else None,
    }


@app.get("/api/scripts/{name}/logs", response_class=PlainTextResponse)
def get_logs(name: str, lines: int = 200):
    log_file = LOGS_DIR / f"{name}.log"
    if not log_file.exists():
        return ""
    with open(log_file, "rb") as f:
        content = f.read().decode(errors="replace").splitlines()
    return "\n".join(content[-lines:])


# --------------------------------------------------------------------------
# Wrapper API Supervisor (exemple minimal, à étendre selon besoin)
# --------------------------------------------------------------------------
def supervisor_get(path: str) -> dict:
    if not SUPERVISOR_TOKEN:
        raise HTTPException(500, "SUPERVISOR_TOKEN absent (hassio_api doit être activé dans config.yaml)")
    r = requests.get(
        f"{SUPERVISOR_URL}{path}",
        headers={"Authorization": f"Bearer {SUPERVISOR_TOKEN}"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


@app.get("/api/supervisor/info")
def supervisor_info():
    """Exemple : infos générales du Supervisor. Étendre avec /addons/self/info,
    /core/api/states, etc. selon les besoins des scripts."""
    return supervisor_get("/supervisor/info")


@app.get("/api/supervisor/addons")
def supervisor_addons():
    return supervisor_get("/addons")


# --------------------------------------------------------------------------
# UI statique (servie derrière l'ingress, donc chemins relatifs uniquement)
# --------------------------------------------------------------------------
app.mount("/", StaticFiles(directory="static", html=True), name="static")
