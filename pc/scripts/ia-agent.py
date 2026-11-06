"""Agent IA du PC : permet au NAS (pc-wake) de demarrer / arreter la pile IA a distance.

- Ecoute sur l'adresse "listen" de pc/stack.json (IP Tailscale par defaut), port "agent_port".
- Chaque requete doit porter le jeton de pc/secrets/agent-token.txt ("Authorization: Bearer ...").
- Ne sait faire que 3 choses, avec des commandes fixes (aucune commande arbitraire) :
    GET  /status : la pile tourne-t-elle (llama-swap lance et joignable) ?
    POST /start  : lance start-ai.ps1 -IfNotRunning (ne fait rien si la pile tourne deja)
    POST /stop   : lance stop-ai.ps1 (arrete la pile, l'agent reste actif)
- Pas de tache planifiee ni de service : lance par "Demarrer IA.bat", il survit a la veille.
"""
import hmac
import json
import socket
import subprocess
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
PC_ROOT = SCRIPTS.parent
CFG = json.loads((PC_ROOT / "stack.json").read_text(encoding="utf-8-sig"))
TOKEN = (PC_ROOT / "secrets" / "agent-token.txt").read_text(encoding="ascii").strip()
LOG = PC_ROOT / "logs" / "ia-agent.log"
NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW
ROUTES = ["GET /status", "POST /start", "POST /stop"]


def log(msg):
    LOG.parent.mkdir(exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} agent : {msg}\n")


def listen_ip():
    if CFG.get("listen", "tailscale") != "tailscale":
        return CFG["listen"]
    out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True,
                         creationflags=NO_WINDOW).stdout.strip().splitlines()
    return out[0].strip() if out else None


def stack_up(ip):
    tasks = subprocess.run(["tasklist", "/FI", "IMAGENAME eq llama-swap.exe", "/NH"], capture_output=True,
                           text=True, creationflags=NO_WINDOW).stdout
    if "llama-swap.exe" not in tasks.lower():
        return False
    try:
        socket.create_connection((ip, int(CFG["llama_swap_port"])), timeout=2).close()
        return True
    except OSError:
        return False


def run_script(name, *args):
    subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                      "-File", str(SCRIPTS / name), *args], creationflags=NO_WINDOW)


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        return hmac.compare_digest(self.headers.get("Authorization", ""), f"Bearer {TOKEN}")

    def do_GET(self):
        if not self.authorized():
            return self.reply(401, {"error": "unauthorized"})
        if self.path.startswith("/status"):
            return self.reply(200, {"agent": True, "stack_up": stack_up(self.server.ip)})
        self.reply(404, {"routes": ROUTES})

    def do_POST(self):
        if not self.authorized():
            return self.reply(401, {"error": "unauthorized"})
        if self.path.startswith("/start"):
            if stack_up(self.server.ip):
                return self.reply(200, {"started": False, "stack_up": True})
            log("demarrage demande a distance")
            run_script("start-ai.ps1", "-IfNotRunning")
            return self.reply(202, {"started": True})
        if self.path.startswith("/stop"):
            log("arret demande a distance")
            run_script("stop-ai.ps1")
            return self.reply(202, {"stopping": True})
        self.reply(404, {"routes": ROUTES})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ip = listen_ip()
    if not ip:
        log("Tailscale indisponible : agent non demarre")
        raise SystemExit(1)
    srv = ThreadingHTTPServer((ip, int(CFG["agent_port"])), Handler)
    srv.ip = ip
    log(f"demarre sur {ip}:{CFG['agent_port']}")
    srv.serve_forever()
