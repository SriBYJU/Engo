#!/usr/bin/env python3
"""Free, local OpenLens AI bridge.

Runs on the user's Mac, forwards to Ollama bound to 127.0.0.1, and exposes
only authenticated /openlens/health and /openlens on the chosen interface.
No provider account, OpenAI key, cloud upload, third-party Python packages,
prompt logging, or persistent conversation history.
"""
from __future__ import annotations

import argparse
import hmac
import json
import os
from pathlib import Path
import secrets
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_MODEL = "qwen2.5:3b"
OLLAMA_BASE = "http://127.0.0.1:11434"
TOKEN_FILE = Path.home() / ".openlens" / "local-ai-token"
MAX_BODY = 8192
MAX_PROMPT = 3000
TASKS = {"general", "explain", "summarize", "rewrite", "brainstorm"}
LANGUAGES = {
    "en": "English", "es": "Spanish", "fr": "French",
    "hi": "Hindi", "te": "Telugu",
}


def create_or_read_token(file_path: Path = TOKEN_FILE) -> str:
    file_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not file_path.exists():
        try:
            fd = os.open(str(file_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(secrets.token_urlsafe(40))
    token = file_path.read_text(encoding="utf-8").strip()
    if len(token) < 32:
        raise RuntimeError(f"Invalid pairing token file: {file_path}")
    if os.name == "posix":
        file_path.chmod(0o600)
    return token


def instructions(mode: str, task: str, language: str) -> str:
    if mode == "translate":
        return ("Translate faithfully into " + LANGUAGES[language] +
                ". Return only the translation, preserving proper nouns, addresses, "
                "street names, numbers and meaning.")
    base = ("You are OpenLens, a concise smart-glasses assistant. "
            "Use plain text, usually under 120 words. Be factual. Never claim "
            "you can see the user's surroundings, live location, or the internet.")
    suffix = {
        "general": "Answer the question directly.",
        "explain": "Explain the concept simply with one good example.",
        "summarize": "Summarize the input faithfully without inventing facts.",
        "rewrite": "Rewrite for natural clarity while preserving meaning.",
        "brainstorm": "Suggest 4 distinct practical ideas, one short line each.",
    }
    return base + " " + suffix[task]


def ollama_request(path: str, payload: dict | None = None, timeout: int = 120) -> dict:
    raw = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(
        OLLAMA_BASE + path, data=raw,
        headers={"Content-Type": "application/json"}, method="POST" if raw else "GET"
    )
    with urlopen(req, timeout=timeout) as response:
        answer = response.read(512 * 1024)
    return json.loads(answer)


def available_models() -> set[str]:
    try:
        response = ollama_request("/api/tags", timeout=4)
        return {entry.get("name", "") for entry in response.get("models", [])}
    except (OSError, ValueError, HTTPError, URLError):
        return set()


class OpenLensBridge(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, server_address, token: str, model: str, transport=ollama_request):
        self.pairing_token = token
        self.ollama_model = model
        self.transport = transport
        super().__init__(server_address, OpenLensHandler)


class OpenLensHandler(BaseHTTPRequestHandler):
    server: OpenLensBridge
    server_version = "OpenLensLocal/1"
    sys_version = ""

    def log_message(self, fmt, *args):
        # Never log prompts, authorization headers, or returned AI content.
        pass

    def _send(self, code: int, payload: dict):
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _authorized(self) -> bool:
        candidate = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.pairing_token
        return hmac.compare_digest(candidate.encode(), expected.encode())

    def _preflight(self, method: str) -> bool:
        if self.path not in ("/openlens", "/openlens/health"):
            self._send(404, {"error": "Not found"})
            return False
        if not self._authorized():
            self._send(401, {"error": "Invalid local pairing token"})
            return False
        if self.headers.get("Origin"):
            self._send(403, {"error": "Browser requests are not supported"})
            return False
        if method == "POST" and self.path != "/openlens":
            self._send(405, {"error": "Method not allowed"})
            return False
        return True

    def do_GET(self):
        if not self._preflight("GET"):
            return
        if self.path != "/openlens/health":
            self._send(405, {"error": "Method not allowed"})
            return
        try:
            result = self.server.transport("/api/tags", None, 5)
            installed = {row.get("name", "") for row in result.get("models", [])}
            configured = self.server.ollama_model in installed
        except (HTTPError, URLError, OSError, ValueError, KeyError):
            configured = False
        self._send(200, {
            "status": "ok", "configured": configured, "service": "openlens-local",
            "model": self.server.ollama_model, "offline": True,
        })

    def do_POST(self):
        if not self._preflight("POST"):
            return
        try:
            size = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            size = -1
        if size < 1 or size > MAX_BODY:
            self._send(413, {"error": "Request size must be 1-8192 bytes"})
            return
        try:
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict):
                raise ValueError()
        except (ValueError, UnicodeDecodeError):
            self._send(400, {"error": "Invalid JSON"})
            return
        mode = payload.get("mode")
        task = payload.get("task", "general")
        text = payload.get("text")
        lang = payload.get("target_language", "en")
        if mode not in ("ai", "translate") or not isinstance(text, str) or not text.strip() or len(text) > MAX_PROMPT:
            self._send(400, {"error": "Provide mode=ai or translate and 1-3000 characters"})
            return
        if task not in TASKS:
            self._send(400, {"error": "Unsupported AI task"})
            return
        if mode == "translate" and lang not in LANGUAGES:
            self._send(400, {"error": "Unsupported translation language"})
            return

        request_body = {
            "model": self.server.ollama_model,
            "stream": False,
            "keep_alive": "5m",
            "messages": [
                {"role": "system", "content": instructions(mode, task, lang)},
                {"role": "user", "content": text.strip()},
            ],
            "options": {"num_predict": 500, "temperature": 0.4},
        }
        try:
            response = self.server.transport("/api/chat", request_body, 120)
            output = response.get("message", {}).get("content", "").strip()
            if not output:
                self._send(502, {"error": "The local model returned no answer"})
            else:
                self._send(200, {"text": output[:4000]})
        except HTTPError as exc:
            if exc.code == 404:
                self._send(503, {"error": "Local Ollama model not installed. Run: ollama pull " + self.server.ollama_model})
            else:
                self._send(502, {"error": "Ollama reported an error"})
        except (OSError, ValueError, URLError):
            self._send(503, {"error": "Cannot connect to Ollama. Start Ollama on this Mac and try again."})


def main():
    parser = argparse.ArgumentParser(description="Free Mac-local OpenLens AI, no OpenAI key.")
    parser.add_argument("--host", default="127.0.0.1",
                        help="Use 0.0.0.0 to allow iPhone access on a trusted home Wi-Fi.")
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--model", default=os.environ.get("OPENLENS_MODEL", DEFAULT_MODEL))
    args = parser.parse_args()
    token = create_or_read_token()
    server = OpenLensBridge((args.host, args.port), token, args.model)
    print("\nOpenLens local AI is running on your Mac.")
    print("Model:", args.model)
    print("Local pairing token (enter into OpenLens iPhone settings):", token)
    print("Server:", f"http://{args.host}:{args.port}/openlens")
    if args.host == "0.0.0.0":
        print("IMPORTANT: LAN HTTP is not encrypted. Use ONLY on a trusted home Wi-Fi.")
        print("Never expose this port to the internet or forward it on your router.")
        print("On the Mac, run: ipconfig getifaddr en0")
        print("Your iPhone URL is http://<MAC_WIFI_IP>:" + str(args.port) + "/openlens")
    print("Press Ctrl+C to stop (and stop sharing local AI).")
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
