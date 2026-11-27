"""Exercise Moss's saved conversation boundary through a compiled headless launcher."""

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread


class Planner(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/responses":
            self.send_error(404)
            return
        size = int(self.headers["Content-Length"])
        assert size <= 64 * 1024
        context = json.loads(self.rfile.read(size))["input"]
        prompt = context[-1]["content"].split("[Teacher says]\n")[-1]
        self.server.prompts.append(prompt)
        self.server.context = context
        actions = []
        if prompt == "Walk to Willow.":
            actions.append(dict(kind="move", target="village", x=0, z=0, duration=0))
        elif prompt == "Go home.":
            actions.append(dict(kind="move", target="home", x=0, z=0, duration=0))
        lessons = ["Use wild berries."] if prompt == "Use wild berries." else []
        decision = dict(speech="OK", actions=actions, lessons=lessons)
        body = json.dumps({"status": "completed", "output": [{
            "type": "message", "role": "assistant",
            "content": [{"type": "output_text", "text": json.dumps(decision)}],
        }]}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def check_session(binary, root, server):
    # Keep both inference traffic and saves independent of the caller's setup.
    env = {**os.environ, "COWORLD_LLM_ENDPOINT": f"http://127.0.0.1:{server.server_port}",
           "COGAME_LLM": "on", "NO_PROXY": "127.0.0.1", "no_proxy": "127.0.0.1"}
    for key in ("COGAME_LLM_INTERVAL", "COGAME_LLM_TIMEOUT_MS", "COGAME_LLM_MODEL",
                "COWORLD_LLM_MODEL", "COGAME_ORACLE_MODEL"):
        env.pop(key, None)

    def launch(save, prompt):
        return subprocess.run([binary, "--save-dir", save, "--prompt", prompt],
                              env=env, text=True, capture_output=True, timeout=10)

    save = root / "session"
    # 125 conversational turns plus two movement turns with one world event each.
    orders = ["Use wild berries."] + [f"Remember order {i}." for i in range(124)]
    orders.extend(["Walk to Willow.", "Go home."])
    for prompt in orders:
        result = launch(save, prompt)
        assert result.returncode == 0, result.stderr
    assert "Arrived at home." in result.stdout
    assert server.prompts == orders
    history = [entry["content"] for entry in server.context[:-1] if entry["role"] == "user"]
    assert [text for text in history if not text.startswith("[World event]")] == orders[:-1]
    assert "[World event] Arrived at village." in history

    memory = save / "conversation.json"
    full = memory.read_bytes()
    saved = json.loads(full)
    assert saved["lessons"] == ["Use wild berries."]
    messages = saved["messages"]
    assert len(messages) == 256
    assert messages[-1] == {"role": "event", "text": "Arrived at home."}
    assert [m["text"] for m in messages if m["role"] == "player"] == orders

    for _ in range(2):
        result = launch(save, "Walk to Willow.")
        assert result.returncode == 1, result.stderr
        assert "Conversation memory is full" in result.stderr
        assert "new --save-dir" in result.stderr
        assert memory.read_bytes() == full
        assert server.prompts == orders

    result = launch(root / "fresh", "Walk to Willow.")
    assert result.returncode == 0 and "Arrived at village." in result.stdout, result
    assert server.prompts == orders + ["Walk to Willow."]
    assert not any(m["role"] == "user" for m in server.context[:-1])
    print("256 saved messages survived two rejected launches. A fresh save reached Willow.")


if __name__ == "__main__":
    with TemporaryDirectory() as directory, HTTPServer(("127.0.0.1", 0), Planner) as server:
        server.prompts = []
        thread = Thread(target=server.serve_forever)
        thread.start()
        try:
            check_session(Path(sys.argv[1]).resolve(), Path(directory), server)
        finally:
            server.shutdown()
            thread.join()
