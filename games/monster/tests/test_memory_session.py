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
        elif prompt in ("Gather berries.", "Gather stone."):
            source = "berries" if prompt == "Gather berries." else "stone"
            actions.append(dict(kind="gather", target=source, x=0, z=0, duration=0))
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


def planner_state(context):
    observation = context[-1]["content"].split("\n[Teacher says]\n", 1)[0]
    return json.loads(observation.split("\n", 1)[1])


def position(state):
    return state["x"], state["z"]


def check_session(binary, root, server):
    # Keep both inference traffic and saves independent of the caller's setup.
    env = {**os.environ, "COWORLD_LLM_ENDPOINT": f"http://127.0.0.1:{server.server_port}",
           "COGAME_LLM": "on", "NO_PROXY": "127.0.0.1", "no_proxy": "127.0.0.1"}
    for key in ("COGAME_LLM_INTERVAL", "COGAME_LLM_TIMEOUT_MS", "COGAME_LLM_MODEL",
                "COWORLD_LLM_MODEL", "COGAME_ORACLE_MODEL"):
        env.pop(key, None)

    def launch(save, prompt, *options):
        return subprocess.run([binary, *options, "--save-dir", save, "--prompt", prompt],
                              env=env, text=True, capture_output=True, timeout=10)

    save = root / "session"
    # 125 conversational turns plus two physical turns with one world event each.
    orders = ["Use wild berries."] + [f"Remember order {i}." for i in range(124)]
    orders.extend(["Walk to Willow.", "Gather berries."])
    for prompt in orders:
        result = launch(save, prompt)
        assert result.returncode == 0, result.stderr
    berry_state = json.loads(result.stdout.splitlines()[-1])
    home = next(place for place in berry_state["places"] if place["id"] == "home")
    assert berry_state["carrying"] == "6 berries"
    assert position(berry_state) != position(home)
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
    assert messages[-1]["role"] == "event" and "Gathered 6 berries" in messages[-1]["text"]
    assert [m["text"] for m in messages if m["role"] == "player"] == orders

    world_file = save / "world.json"
    original_world = world_file.read_bytes()
    for _ in range(2):
        result = launch(save, "Gather stone.")
        assert result.returncode == 1, result.stderr
        assert "Conversation memory is full" in result.stderr
        assert "new --save-dir to start a separate world" in result.stderr
        assert memory.read_bytes() == full
        assert server.prompts == orders

    fresh = root / "fresh"
    result = launch(fresh, "Gather stone.")
    assert result.returncode == 0, result.stderr
    start = planner_state(server.context)
    assert position(start) == position(home) and start["carrying"] == "empty"
    assert not any(m["role"] in ("user", "assistant") for m in server.context[:-1])
    stone_state = json.loads(result.stdout.splitlines()[-1])
    assert stone_state["carrying"] == "6 stone" and position(stone_state) != position(home)
    fresh_memory = fresh / "conversation.json"
    first_turn = json.loads(fresh_memory.read_bytes())
    assert first_turn["lessons"] == []
    assert [m["role"] for m in first_turn["messages"]] == ["player", "creature", "event"]
    assert first_turn["messages"][0]["text"] == "Gather stone."

    result = launch(fresh, "Walk to Willow.")
    assert result.returncode == 0 and "Arrived at village." in result.stdout, result
    reopened = planner_state(server.context)
    assert position(reopened) == position(stone_state) and reopened["carrying"] == "6 stone"
    arrived = json.loads(result.stdout.splitlines()[-1])
    assert arrived["carrying"] == "6 stone" and position(arrived) != position(reopened)
    second_turn = json.loads(fresh_memory.read_bytes())
    assert second_turn["messages"][:3] == first_turn["messages"]
    assert [m["text"] for m in second_turn["messages"][3:]] == [
        "Walk to Willow.", "OK", "Arrived at village."
    ]
    assert server.prompts == orders + ["Gather stone.", "Walk to Willow."]
    assert memory.read_bytes() == full and world_file.read_bytes() == original_world
    # Each process restores the same full save. The tick proves it saved again.
    previous = json.loads(original_world)
    for _ in range(2):
        result = launch(save, "stop", "--offline")
        assert result.returncode == 0, result.stderr
        assert "Moss: I stopped." in result.stdout
        assert "no room to record this turn" in result.stdout
        current = json.loads(world_file.read_bytes())
        assert current["tick"] > previous["tick"]
        assert not current["creature"]["moving"]
        assert current["creature"]["position"] == previous["creature"]["position"]
        assert current["creature"]["cargo"] == previous["creature"]["cargo"]
        assert memory.read_bytes() == full
        assert server.prompts == orders + ["Gather stone.", "Walk to Willow."]
        previous = current

    print("New Moss carried six stone to Willow after reload. Offline stop saved the "
          "full world on both launches without changing history or calling the planner.")


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
