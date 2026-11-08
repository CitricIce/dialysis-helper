"""Development Cartesia gateway. Keep API keys here, never in the phone build."""
import hmac
import io
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "2026-08-14"
SESSION_HOSTS = {"api.cartesia.ai", "api-us.cartesia.ai"}
TEMPLATE = Path(__file__).resolve().parents[2] / "ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/Resources/RoutineTemplate.json"
INSTRUCTIONS = (TEMPLATE.parent / "VoiceInstructions.txt").read_text()

def agent_payload(check_id, voice_id, phase="checking"):
    template = json.loads(TEMPLATE.read_text())
    check = next((c for c in template["checks"] if c["id"] == check_id), None)
    if not check and check_id not in ("finished", "review"):
        raise ValueError("Unknown practice check")
    initial = check["prompt"] if check else (
        "Pause and follow your dialysis team's instructions about possible contact. What would you like to ask?"
        if check_id == "review" else "Is there anything you'd like to go back over?")
    if phase == "paused":
        initial = "We're paused. Say resume when you're ready, or ask me a question."
    elif phase == "reviewRequired":
        initial = "We're paused after possible contact. Follow your dialysis team's instructions. What would you like to ask?"
    elif phase == "preparationOnly":
        initial = "Preparation practice is finished. The connection wasn't monitored. Is there anything you'd like to ask?"
    elif phase == "monitoring":
        initial = "I'm listening. Tell me when you've finished, or say pause."
    context = {"starting_phase": phase, "starting_check_id": check_id, "checks": template["checks"]}
    return {"config_overrides": {
        "instructions": INSTRUCTIONS + json.dumps(context),
        "initial_message": initial,
        "language": {"primary": "en"},
        "audio": {"output": {"voice_id": voice_id, "speed": 1.0}},
    }}


LOCAL_STATE = Path(__file__).with_name("agent-setup.local.json")


def load_local_config(path=None):
    """Simple literal KEY=value reader: no shell execution, expansion or secret output."""
    path = Path(path) if path else Path(__file__).with_name(".env")
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, separator, value = line.partition("=")
            if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", name.strip()):
                raise ValueError("Invalid local configuration line")
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '\"'):
                value = value[1:-1]
            os.environ.setdefault(name.strip(), value)
    if not os.environ.get("CARTESIA_AGENT_ID") and LOCAL_STATE.exists():
        agent_id = json.loads(LOCAL_STATE.read_text()).get("agent_id")
        if agent_id:
            os.environ["CARTESIA_AGENT_ID"] = agent_id


def cartesia(path, payload, api_key, *, agent=False):
    headers = {"Content-Type": "application/json", "Cartesia-Version": VERSION}
    headers["X-API-Key" if agent else "Authorization"] = api_key if agent else "Bearer " + api_key
    request = urllib.request.Request("https://api.cartesia.ai/" + path,
                                     data=json.dumps(payload).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=15) as response:
        content = response.read(5_000_001)
        if len(content) > 5_000_000:
            raise ValueError("Upstream response too large")
        return content, response.headers.get_content_type()


def finalized_wav(content):
    """Finalize streaming WAV lengths before handing a complete clip to iOS."""
    with wave.open(io.BytesIO(content), "rb") as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getframerate() != 44100:
            raise ValueError("Unexpected speech format")
        # Provider streaming headers may declare 0xffffffff bytes. Bound the read
        # by the complete response length, then write actual PCM lengths.
        frames = source.readframes(len(content) // 2)
    if not frames or len(frames) % 2:
        raise ValueError("Invalid speech data")
    result = io.BytesIO()
    with wave.open(result, "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(44100)
        target.writeframes(frames)
    return result.getvalue()


class Gateway(BaseHTTPRequestHandler):
    # One request at a time bounds spending/concurrency on this single-phone dev gateway.
    upstream_slot = threading.BoundedSemaphore(1)
    budget_lock = threading.Lock()
    request_times = []

    def log_message(self, *_args):
        pass  # Never log tokens, URLs, conversations, audio, or provider error bodies.

    def reply(self, code, body, mime="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        self.connection.settimeout(20)
        self.close_connection = True
        expected = os.environ.get("ARMGUARD_GATEWAY_TOKEN", "")
        provided = self.headers.get("Authorization", "")
        if len(expected) < 24 or not hmac.compare_digest(provided.encode(), ("Bearer " + expected).encode()):
            self.reply(401, b'{"error":"Unauthorized"}')
            return
        if self.path not in ("/speak", "/agent-session"):
            self.reply(404, b'{"error":"Not found"}')
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 8192 or self.headers.get_content_type() != "application/json":
                raise ValueError("Invalid body")
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("Expected object")
            voice = os.environ["CARTESIA_VOICE_ID"]
            key = os.environ["CARTESIA_API_KEY"]
            if self.path == "/speak":
                text = body.get("text")
                if not isinstance(text, str) or not 1 <= len(text.strip()) <= 2000:
                    raise ValueError("Invalid text")
                payload = {"model_id": "sonic-3.6", "voice": voice, "transcript": text,
                           "language": "en", "output_format": {"container": "wav", "encoding": "pcm_s16le", "sample_rate": 44100}}
                path, agent = "tts/bytes", False
            else:
                agent_id = os.environ["CARTESIA_AGENT_ID"]
                if not re.fullmatch(r"[A-Za-z0-9_-]{1,150}", agent_id):
                    raise ValueError("Invalid agent ID")
                phase = body.get("phase", "checking")
                if phase not in ("checking", "paused", "monitoring", "reviewRequired", "completed", "preparationOnly"):
                    raise ValueError("Unknown phase")
                payload = agent_payload(body.get("check_id"), voice, phase)
                path, agent = f"v1/agents/websocket/{agent_id}/sessions", True
        except KeyError:
            self.reply(503, b'{"error":"Gateway configuration incomplete"}')
            return
        except (ValueError, TypeError, TimeoutError):
            self.reply(400, b'{"error":"Invalid request"}')
            return
        with self.budget_lock:
            now = time.monotonic()
            self.request_times[:] = [t for t in self.request_times if now - t < 60]
            if len(self.request_times) >= 20:
                self.reply(429, b'{"error":"Rate limit; use local voice"}')
                return
            self.request_times.append(now)
        if not self.upstream_slot.acquire(blocking=False):
            self.reply(429, b'{"error":"Voice busy; use local voice"}')
            return
        try:
            data, mime = cartesia(path, payload, key, agent=agent)
            if agent:
                session = json.loads(data)
                url = urllib.parse.urlparse(session["url"])
                if (url.scheme != "wss" or url.hostname not in SESSION_HOSTS
                        or url.username or url.password or url.port not in (None, 443)
                        or not isinstance(session["token"], str)):
                    raise ValueError("Unexpected session")
                data = json.dumps({"url": session["url"], "token": session["token"]}).encode()
                mime = "application/json"
            elif not mime.startswith("audio/"):
                raise ValueError("Unexpected audio")
            else:
                data = finalized_wav(data)
            self.reply(200, data, mime)
        except (OSError, ValueError, TypeError, KeyError, EOFError, wave.Error, urllib.error.URLError):
            self.reply(502, b'{"error":"Cartesia unavailable; use local voice"}')
        finally:
            self.upstream_slot.release()


def main():
    load_local_config()
    if len(os.environ.get("ARMGUARD_GATEWAY_TOKEN", "")) < 24:
        raise SystemExit("Set ARMGUARD_GATEWAY_TOKEN to a random token of at least 24 characters.")
    host = os.environ.get("ARMGUARD_GATEWAY_HOST", "127.0.0.1")
    port = int(os.environ.get("ARMGUARD_GATEWAY_PORT", "8765"))
    print(f"ArmGuard development voice gateway on {host}:{port}; no request logging")
    ThreadingHTTPServer((host, port), Gateway).serve_forever()


if __name__ == "__main__":
    main()
