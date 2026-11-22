// Check replay-shell launch controls without loading WASM or opening audio.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import {setImmediate} from "node:timers/promises";

const html = fs.readFileSync("src/polyworld/replay.html", "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function configure(query = "", hash = "") {
  const status = {hidden: false, className: ""};
  const detail = {textContent: ""};
  const canvas = {addEventListener() {}};
  const messages = [], fetched = [], writes = [], dependencies = new Set();
  const window = {
    parent: {postMessage(message) { messages.push(message); }},
    addEventListener() {}
  };
  const context = vm.createContext({
    URLSearchParams, console, window,
    location: {search: query, hash},
    document: {getElementById(id) {
      return {status, "status-detail": detail, canvas}[id];
    }},
    setTimeout() {},
    addRunDependency(name) { dependencies.add(name); },
    removeRunDependency(name) { dependencies.delete(name); },
    fetch: async url => {
      fetched.push(url);
      return {ok: true, arrayBuffer: async () => Uint8Array.of(1, 2, 3).buffer};
    },
    FS: {
      mkdirTree() {},
      writeFile(name, bytes) { writes.push({name, bytes: Array.from(bytes)}); }
    }
  });
  vm.runInContext(script, context, {filename: "replay.html"});
  return {Module: context.Module, status, detail, messages, fetched, writes,
    dependencies};
}

assert.deepEqual(Array.from(configure().Module.arguments), []);
assert.equal(configure().Module.noInitialRun, false);

for (const value of ["", "1", "true", "on", "yes", " TRUE "]) {
  const result = configure("?mute=" + encodeURIComponent(value));
  assert.deepEqual(Array.from(result.Module.arguments), ["--mute"]);
  assert.equal(result.Module.noInitialRun, false);
}
assert.deepEqual(Array.from(configure("?mute").Module.arguments), ["--mute"]);

for (const value of ["0", "false", "off", "no", " FALSE "]) {
  const result = configure("?mute=" + encodeURIComponent(value));
  assert.deepEqual(Array.from(result.Module.arguments), ["--unmute"]);
  assert.equal(result.Module.noInitialRun, false);
}

for (const query of [
  "?mute=invalid", "?mute=2", "?mute=true&mute=true", "?mute=0&mute=1"
]) {
  const result = configure(query + "&replay=episode.replay");
  assert.equal(result.Module.noInitialRun, true);
  assert.equal(result.status.hidden, false);
  assert.equal(result.status.className, "error");
  assert.match(result.detail.textContent, /mute query parameter/);
  assert.equal(result.messages.at(-1).type, "error");
  result.Module.preRun[0]();
  assert.deepEqual(result.fetched, []);
  assert.equal(result.dependencies.size, 0);
}

for (const [query, hash, expectedUrl, audio] of [
  ["?replay=query.replay", "", "query.replay", []],
  ["?replay=query.replay&mute=false", "", "query.replay", ["--unmute"]],
  ["?replay=query.replay&mute=true", "#replay=hash.replay", "hash.replay", ["--mute"]],
  ["?mute=0", "#replay=hash.replay", "hash.replay", ["--unmute"]]
]) {
  const result = configure(query, hash);
  assert.deepEqual(Array.from(result.Module.arguments), [
    "--replay", "/episode.replay", ...audio
  ]);
  result.Module.preRun[0]();
  await setImmediate();
  assert.deepEqual(result.fetched, [expectedUrl]);
  assert.deepEqual(result.writes, [{name: "/episode.replay", bytes: [1, 2, 3]}]);
  assert.equal(result.dependencies.size, 0);
}

console.log("Replay audio launch controls passed");
