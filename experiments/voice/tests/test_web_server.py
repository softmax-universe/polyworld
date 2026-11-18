"""Checks the localhost credential bridge without contacting OpenAI."""

from contextlib import contextmanager
from http.client import HTTPConnection
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
from unittest.mock import patch
from urllib.error import HTTPError, URLError


Source = Path(__file__).resolve().parents[1] / "serve.py"
Spec = importlib.util.spec_from_file_location("voice_serve", Source)
serve = importlib.util.module_from_spec(Spec)
Spec.loader.exec_module(serve)


@contextmanager
def running(directory, key, calls):
    """Starts an ephemeral loopback server backed by a deterministic token stub."""
    def token_provider(credential, model, voice):
        """Records only test credentials and returns a distinct temporary token."""
        calls.append((credential, model, voice))
        return {"value": "ek_test_only", "expires_at": 1234567890}

    server = serve.VoiceServer(directory, 0, lambda: key[0], token_provider)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def request(server, path="/", method="GET", body=None, headers=None):
    """Returns complete local HTTP responses and permits malformed header tests."""
    port = server.server_address[1]
    entries = list(headers or [])
    if not any(name.lower() == "host" for name, value in entries):
        entries.append(("Host", f"127.0.0.1:{port}"))
    connection = HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.putrequest(method, path, skip_host=True)
        for name, value in entries:
            connection.putheader(name, value)
        connection.endheaders(body)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


def token(server, payload=None, origin=True, extra_headers=None):
    """Sends an ordinary browser JSON token request to the local test server."""
    body = json.dumps(payload if payload is not None else {}).encode()
    headers = [("Content-Type", "application/json"),
               ("Content-Length", str(len(body)))]
    if origin:
        headers.append(("Origin", f"http://127.0.0.1:{server.server_address[1]}"))
    headers.extend(extra_headers or [])
    return request(server, "/api/realtime/token", "POST", body, headers)


def expect_error(status, callback):
    """Requires a safe structured library error from the token exchange."""
    try:
        callback()
    except serve.VoiceServerError as error:
        assert error.status == status, (error.status, str(error))
        return error
    raise AssertionError("Expected VoiceServerError")


with tempfile.TemporaryDirectory(prefix="voice-web-test-") as temporary:
    root = Path(temporary)
    assets = root / "emscripten"
    assets.mkdir()
    (assets / "voice.html").write_text("Voice Lab test page")
    (assets / "voice.js").write_text("console.log('test');")
    (assets / "voice.wasm").write_bytes(b"\0asm")
    (assets / "voice.data").write_bytes(b"assets")
    (assets / "secret.key").write_text("should not be served")
    (assets / "tmp").mkdir()
    (assets / "tmp" / "generated.c").write_text("source code")
    (root / "outside.js").write_text("private outside artifact")
    (assets / "escape.js").symlink_to(root / "outside.js")
    (assets / "alias.js").symlink_to(assets / "voice.js")
    key, calls = ["sk-server-test-secret"], []

    with running(assets, key, calls) as server:
        status, headers, body = request(server)
        assert status == 200 and body == b"Voice Lab test page"
        assert headers["Cache-Control"] == "no-store"
        assert headers["X-Frame-Options"] == "DENY"
        status, headers, body = request(server, "/voice.wasm")
        assert status == 200 and headers["Content-Type"] == "application/wasm"
        assert body == b"\0asm"
        assert request(server, "/voice.data")[0] == 200
        assert request(server, "/voice.js", "HEAD")[2] == b""
        for path in ["/secret.key", "/tmp/", "/tmp/generated.c", "/../outside.js",
                     "/%2e%2e/outside.js", "/escape.js", "/alias.js",
                     "/%5c..%5coutside.js", "/voice.js%00"]:
            assert request(server, path)[0] == 404, path
        assert request(server, headers=[("Host", "attacker.example")])[0] == 403
        assert request(server, headers=[("Host", "localhost:1")])[0] == 403
        assert request(server, headers=[("Host", "localhost:1"), ("Host", "localhost:1")])[0] == 403
        status, _, body = request(server, "/api/config")
        config = json.loads(body)
        assert status == 200 and config["keyAvailable"] is True
        assert config["model"] == serve.DefaultModel
        assert key[0].encode() not in body
        assert "apiKey" not in config
        status, headers, body = token(server, {"model": "gpt-realtime-2.1-mini", "voice": "marin"})
        assert status == 200 and headers["Cache-Control"] == "no-store"
        assert json.loads(body) == {"value": "ek_test_only", "expires_at": 1234567890}
        assert calls[-1] == (key[0], "gpt-realtime-2.1-mini", "marin")
        assert key[0].encode() not in body
        token(server, {"apiKey": "sk-ignored-test"})
        assert calls[-1][0] == key[0]
        key[0] = ""
        assert json.loads(request(server, "/api/config")[2])["keyAvailable"] is False
        assert token(server)[0] == 400
        status, _, body = token(server, {"apiKey": "sk-browser-test"})
        assert status == 200 and calls[-1][0] == "sk-browser-test"
        assert b"sk-browser-test" not in body
        for payload in [{"apiKey": 123}, {"apiKey": "sk-test\r\nHeader: injected"},
                        {"model": []}, {"voice": "voice\ninvalid"}, {"extra": True}]:
            assert token(server, payload)[0] == 400, payload
        before = len(calls)
        assert token(server, origin=False)[0] == 403
        for origin in ["null", "http://evil.example", "http://localhost:1"]:
            assert token(server, origin=False, extra_headers=[("Origin", origin)])[0] == 403
        assert token(server, extra_headers=[("Sec-Fetch-Site", "cross-site")])[0] == 403
        assert token(server, extra_headers=[("Origin", "null")])[0] == 403
        assert len(calls) == before

        origin = ("Origin", f"http://127.0.0.1:{server.server_address[1]}")
        common = [origin, ("Content-Type", "application/json")]
        for lengths in [[("Content-Length", "²")], [("Content-Length", "-1")], [("Content-Length", "999999999")],
                        [("Content-Length", "2"), ("Content-Length", "2")],
                        [("Transfer-Encoding", "chunked")]]:
            status, _, _ = request(server, "/api/realtime/token", "POST", b"{}", common + lengths)
            assert status in {400, 413}, lengths
        assert request(server, "/api/realtime/token", "POST", b"{}",
                       [origin, ("Content-Length", "2")])[0] == 415
        assert request(server, "/api/realtime/token", "POST", b"x!",
                       common + [("Content-Length", "2")])[0] == 400
        assert request(server, "/api/realtime/token", "POST", b"[]",
                       common + [("Content-Length", "2")])[0] == 400
        assert request(server, "http://[", "POST", b"{}",
                       common + [("Content-Length", "2")])[0] == 400
        assert len(calls) == before

    secrets = root / "secrets"
    secrets.mkdir()
    (secrets / "openai.key").write_text(" sk-file-test \n")
    with patch.object(serve.Path, "home", return_value=root):
        with patch.dict(os.environ, {"OPENAI_API_KEY": ""}):
            assert serve.configured_key() == "sk-file-test"
        with patch.dict(os.environ, {"OPENAI_API_KEY": " sk-environment-test "}):
            assert serve.configured_key() == "sk-environment-test"


calls = []
credential = "sk-redaction-test-secret"


def upstream_success(request, timeout):
    """Validates exact upstream authentication and strips unrelated reply fields."""
    assert request.full_url == serve.TokenUrl and timeout == 20
    assert request.get_header("Authorization") == "Bearer " + credential
    payload = json.loads(request.data)
    assert payload == {"session": {"type": "realtime", "model": serve.DefaultModel,
                                  "audio": {"output": {"voice": "marin"}}}}
    calls.append(request)
    return io.BytesIO(json.dumps({"value": "ek-short-lived", "expires_at": 123,
                                 "internal": credential}).encode())


with patch.object(serve, "urlopen", upstream_success):
    assert serve.create_secret(credential, serve.DefaultModel, "marin") == {
        "value": "ek-short-lived", "expires_at": 123,
    }
assert len(calls) == 1


for status in [401, 429]:
    detail = {"error": {"message": "Incorrect key " + credential + " or sk-part***test",
                        "code": "invalid_api_key"}}
    error = HTTPError(serve.TokenUrl, status, "Rejected", {},
                      io.BytesIO(json.dumps(detail).encode()))
    with patch.object(serve, "urlopen", side_effect=error):
        safe = expect_error(status, lambda: serve.create_secret(credential, serve.DefaultModel, "marin"))
        assert credential not in str(safe) and "sk-part" not in str(safe)
        assert safe.code == "invalid_api_key"

with patch.object(serve, "urlopen", side_effect=URLError("Offline")):
    expect_error(502, lambda: serve.create_secret(credential, serve.DefaultModel, "marin"))
for invalid in [b"not JSON", b"{}", b'[]', b'{"value":"ek-test","expires_at":true}',
                b"x" * (serve.MaxResponseBytes + 1)]:
    with patch.object(serve, "urlopen", return_value=io.BytesIO(invalid)):
        expect_error(502, lambda: serve.create_secret(credential, serve.DefaultModel, "marin"))

print("Voice web server tests passed without network or real credentials.")
