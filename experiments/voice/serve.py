#!/usr/bin/env python3
"""Serves the local Voice Lab build and mints short-lived Realtime tokens."""

import argparse
import json
import os
from pathlib import Path
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen


DefaultModel = "gpt-realtime-2.1-mini"
DefaultVoice = "marin"
TokenUrl = "https://api.openai.com/v1/realtime/client_secrets"
MaxRequestBytes = 16384
MaxResponseBytes = 1024 * 1024
AssetTypes = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".data": "application/octet-stream",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".ttf": "font/ttf",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
}


class VoiceServerError(Exception):
    """Carries a safe HTTP status and explanation for the browser."""

    def __init__(self, status, message, code="voice_server_error"):
        """Retains only fields that are safe to return to the browser."""
        super().__init__(message)
        self.status = status
        self.code = code


def configured_key():
    """Reads the same local credential sources as native Voice Lab."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        path = Path.home() / "secrets" / "openai.key"
        try:
            if path.is_file():
                key = path.read_text().strip()
        except (OSError, UnicodeError):
            raise VoiceServerError(500, "Could not read the local OpenAI key.")
    return key


def redact(message, key):
    """Removes credentials even when OpenAI includes one in an error message."""
    if key:
        message = message.replace(key, "[redacted]")
    message = re.sub(r"sk-[A-Za-z0-9_.*-]+", "[redacted]", message)
    return message[:2000]


def create_secret(key, model, voice):
    """Exchanges a trusted server key for a browser Realtime client secret."""
    body = json.dumps({"session": {
        "type": "realtime",
        "model": model,
        "audio": {"output": {"voice": voice}},
    }}).encode()
    request = Request(TokenUrl, data=body, method="POST", headers={
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
    })
    try:
        with urlopen(request, timeout=20) as response:
            data = response.read(MaxResponseBytes + 1)
    except HTTPError as error:
        with error:
            data = error.read(MaxResponseBytes + 1)
        message = "OpenAI rejected the session request."
        code = "openai_error"
        try:
            detail = json.loads(data).get("error", {})
            if isinstance(detail, dict):
                if isinstance(detail.get("message"), str):
                    message = redact(detail["message"], key)
                if isinstance(detail.get("code"), str):
                    code = redact(detail["code"], key)
        except (ValueError, AttributeError):
            pass
        raise VoiceServerError(error.code, message, code)
    except (URLError, TimeoutError, OSError):
        raise VoiceServerError(502, "Could not reach OpenAI. Try connecting again.")
    if len(data) > MaxResponseBytes:
        raise VoiceServerError(502, "OpenAI returned an oversized session response.")
    try:
        payload = json.loads(data)
        value, expires = payload["value"], payload["expires_at"]
        if not isinstance(value, str) or not value or len(value) > 8192:
            raise ValueError("Invalid client secret")
        if not isinstance(expires, int) or isinstance(expires, bool):
            raise ValueError("Invalid token expiration")
    except (ValueError, KeyError, TypeError):
        raise VoiceServerError(502, "OpenAI returned an invalid session response.")
    return {"value": value, "expires_at": expires}


def setting(value, fallback, name):
    """Validates bounded model and voice names without interpreting syntax."""
    if value == "":
        value = fallback
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}", value):
        raise VoiceServerError(400, "Invalid " + name + ".", "invalid_request")
    return value


class VoiceServer(ThreadingHTTPServer):
    """Keeps local serving and upstream calls injectable for offline tests."""

    daemon_threads = True

    def __init__(self, directory, port=8001, key_provider=configured_key,
                 token_provider=create_secret):
        """Binds only loopback and serves the resolved build directory."""
        self.directory = Path(directory).resolve()
        self.key_provider = key_provider
        self.token_provider = token_provider
        self.model = setting(os.environ.get("OPENAI_REALTIME_MODEL", DefaultModel),
                             DefaultModel, "model")
        self.voice = setting(os.environ.get("OPENAI_REALTIME_VOICE", DefaultVoice),
                             DefaultVoice, "voice")
        super().__init__(("127.0.0.1", port), VoiceHandler)


class VoiceHandler(BaseHTTPRequestHandler):
    """Serves compiled assets and accepts same-origin token requests."""

    server_version = "VoiceLab"

    def setup(self):
        """Bounds time spent waiting for incomplete local HTTP requests."""
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, format, *arguments):
        """Avoids logging request paths, browser credentials, or API responses."""
        pass

    def send_headers(self, status, content_type, length):
        """Applies no-cache and same-origin response rules to every route."""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.end_headers()

    def json_response(self, status, payload):
        """Sends a bounded JSON response without exposing arbitrary objects."""
        data = json.dumps(payload).encode()
        self.send_headers(status, "application/json; charset=utf-8", len(data))
        if self.command != "HEAD":
            self.wfile.write(data)

    def failure(self, error):
        """Returns a structured error without tracebacks or credentials."""
        self.json_response(error.status, {"error": {
            "message": str(error), "code": error.code,
        }})

    def check_host(self):
        """Rejects DNS rebinding and unexpected duplicate Host headers."""
        hosts = self.headers.get_all("Host", [])
        port = self.server.server_address[1]
        allowed = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if port == 80:
            allowed.update({"127.0.0.1", "localhost"})
        if len(hosts) != 1 or hosts[0].lower() not in allowed:
            raise VoiceServerError(403, "Use this server through localhost.", "invalid_host")
        return hosts[0].lower()

    def check_origin(self, host):
        """Limits token creation to the page served by this local origin."""
        origins = self.headers.get_all("Origin", [])
        if origins != ["http://" + host]:
            raise VoiceServerError(403, "Token requests must come from this page.", "invalid_origin")
        if self.headers.get("Sec-Fetch-Site", "same-origin") != "same-origin":
            raise VoiceServerError(403, "Cross-origin token requests are not allowed.", "invalid_origin")

    def static_file(self):
        """Resolves only compiled assets without traversal or symbolic links."""
        path = unquote(urlsplit(self.path).path)
        if path == "/":
            path = "/voice.html"
        parts = path.split("/")[1:]
        if not path.startswith("/") or "\\" in path or "\0" in path or any(
            part in {"", ".", ".."} for part in parts
        ):
            raise VoiceServerError(404, "File not found.", "not_found")
        candidate = self.server.directory
        for part in parts:
            candidate /= part
            if candidate.is_symlink():
                raise VoiceServerError(404, "File not found.", "not_found")
        resolved = candidate.resolve()
        if not resolved.is_relative_to(self.server.directory) or not resolved.is_file():
            raise VoiceServerError(404, "File not found.", "not_found")
        content_type = AssetTypes.get(resolved.suffix.lower())
        if content_type is None:
            raise VoiceServerError(404, "File not found.", "not_found")
        return resolved, content_type

    def do_GET(self):
        """Serves the app or public connection defaults without any credentials."""
        try:
            self.check_host()
            path = urlsplit(self.path).path
            if path == "/api/config":
                self.json_response(200, {
                    "keyAvailable": bool(self.server.key_provider()),
                    "model": self.server.model,
                    "voice": self.server.voice,
                })
                return
            file, content_type = self.static_file()
            with file.open("rb") as source:
                self.send_headers(200, content_type, os.fstat(source.fileno()).st_size)
                if self.command != "HEAD":
                    while data := source.read(65536):
                        self.wfile.write(data)
        except VoiceServerError as error:
            self.failure(error)
        except (BrokenPipeError, ConnectionResetError):
            return
        except (OSError, ValueError):
            self.failure(VoiceServerError(404, "File not found.", "not_found"))

    def do_HEAD(self):
        """Returns the same headers as GET without sending a response body."""
        self.do_GET()

    def do_POST(self):
        """Mints one short-lived token after validating its local request."""
        try:
            host = self.check_host()
            self.check_origin(host)
            if urlsplit(self.path).path != "/api/realtime/token":
                raise VoiceServerError(404, "Endpoint not found.", "not_found")
            if self.headers.get("Transfer-Encoding") is not None:
                raise VoiceServerError(400, "Transfer encoding is not supported.", "invalid_request")
            if self.headers.get_content_type() != "application/json":
                raise VoiceServerError(415, "Send an application/json request.", "invalid_request")
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not re.fullmatch(r"[0-9]+", lengths[0]):
                raise VoiceServerError(400, "A valid Content-Length is required.", "invalid_request")
            if len(lengths[0]) > 8:
                raise VoiceServerError(413, "The token request is too large.", "invalid_request")
            length = int(lengths[0])
            if length < 1 or length > MaxRequestBytes:
                raise VoiceServerError(413, "The token request is too large or empty.", "invalid_request")
            body = self.rfile.read(length)
            if len(body) != length:
                raise VoiceServerError(400, "The token request is incomplete.", "invalid_request")
            try:
                payload = json.loads(body)
            except (ValueError, UnicodeError):
                raise VoiceServerError(400, "The token request is not valid JSON.", "invalid_request")
            if not isinstance(payload, dict) or set(payload) - {"model", "voice", "apiKey"}:
                raise VoiceServerError(400, "Invalid token request fields.", "invalid_request")
            model = setting(payload.get("model", self.server.model), self.server.model, "model")
            voice = setting(payload.get("voice", self.server.voice), self.server.voice, "voice")
            supplied = payload.get("apiKey", "")
            if not isinstance(supplied, str):
                raise VoiceServerError(400, "The API key must be text.", "invalid_request")
            key = self.server.key_provider() or supplied.strip()
            if not key:
                raise VoiceServerError(400,
                    "Add an API key above, set OPENAI_API_KEY, or add ~/secrets/openai.key.",
                    "missing_api_key")
            if len(key) > 4096 or any(ord(character) < 33 or ord(character) > 126 for character in key):
                raise VoiceServerError(400, "The API key contains invalid characters.", "invalid_request")
            self.json_response(200, self.server.token_provider(key, model, voice))
        except VoiceServerError as error:
            self.failure(error)
        except ValueError:
            self.failure(VoiceServerError(400, "Invalid request target.", "invalid_request"))
        except TimeoutError:
            self.failure(VoiceServerError(408, "The token request timed out.", "request_timeout"))
        except (BrokenPipeError, ConnectionResetError):
            return


def main():
    """Runs the local development server without publishing the application."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8001)
    options = parser.parse_args()
    if not 1 <= options.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    directory = Path(__file__).resolve().parent / "emscripten"
    if not (directory / "voice.html").is_file():
        parser.error("Build Voice Lab for Emscripten before starting the server.")
    with VoiceServer(directory, options.port) as server:
        print(f"Voice Lab: http://localhost:{options.port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
