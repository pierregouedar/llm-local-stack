"""Server agent: lets the waker (waker/) start or stop the stack remotely. Windows and Linux.

- Listens on the "listen" address of server/config.json (Tailscale IP by default), port "agent_port".
- Every request must carry the token from server/secrets/agent-token.txt ("Authorization: Bearer ...").
- It can only do 3 things, with fixed commands (no arbitrary command execution):
    GET  /status : is the stack running (llama-swap process up and its port reachable)?
    POST /start  : runs the start script with "if not running" (does nothing if the stack is up)
    POST /stop   : runs the stop script (stops the stack; the agent keeps running)
- Not a service or scheduled task: started by windows/start.bat or linux/start-agent.sh, survives sleep.
"""
import hmac
import json
import socket
import subprocess
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parent
CFG = json.loads((SERVER_DIR / "config.json").read_text(encoding="utf-8-sig"))
TOKEN = (SERVER_DIR / "secrets" / "agent-token.txt").read_text(encoding="ascii").strip()
LOG = SERVER_DIR / "logs" / "agent.log"
WINDOWS = sys.platform == "win32"
FLAGS = {"creationflags": 0x08000000} if WINDOWS else {}  # CREATE_NO_WINDOW
ROUTES = ["GET /status", "POST /start", "POST /stop"]

if WINDOWS:
    def _ps(script, *args):
        return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                "-File", str(SERVER_DIR / "windows" / script), *args]
    START_CMD = _ps("start.ps1", "-IfNotRunning")
    STOP_CMD = _ps("stop.ps1")
else:
    START_CMD = ["bash", str(SERVER_DIR / "linux" / "start.sh"), "--if-not-running"]
    STOP_CMD = ["bash", str(SERVER_DIR / "linux" / "stop.sh")]


def log(msg):
    LOG.parent.mkdir(exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} agent: {msg}\n")


def listen_ip():
    if CFG.get("listen", "tailscale") != "tailscale":
        return CFG["listen"]
    try:
        out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True, **FLAGS).stdout
    except OSError:
        return None
    lines = out.strip().splitlines()
    return lines[0].strip() if lines else None


def swap_running():
    if WINDOWS:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq llama-swap.exe", "/NH"],
                             capture_output=True, text=True, **FLAGS).stdout
        return "llama-swap.exe" in out.lower()
    return subprocess.run(["pgrep", "-x", "llama-swap"], capture_output=True).returncode == 0


def stack_up(ip):
    if not swap_running():
        return False
    try:
        socket.create_connection((ip, int(CFG["llama_swap_port"])), timeout=2).close()
        return True
    except OSError:
        return False


def run(cmd):
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=not WINDOWS, **FLAGS)


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
            log("remote start requested")
            run(START_CMD)
            return self.reply(202, {"started": True})
        if self.path.startswith("/stop"):
            log("remote stop requested")
            run(STOP_CMD)
            return self.reply(202, {"stopping": True})
        self.reply(404, {"routes": ROUTES})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ip = listen_ip()
    if not ip:
        log("Tailscale unavailable: agent not started")
        raise SystemExit(1)
    srv = ThreadingHTTPServer((ip, int(CFG["agent_port"])), Handler)
    srv.ip = ip
    log(f"started on {ip}:{CFG['agent_port']}")
    srv.serve_forever()
