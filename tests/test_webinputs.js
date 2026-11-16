// Check the browser input handoff without fetching or compiling a game.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
const source = fs.readFileSync("src/polyworld/webinputs.js", "utf8");
const cacSource = fs.readFileSync("games/cac/web/inputs.js", "utf8");

function configure(query, cac = false) {
  const Module = {};
  const context = {
    Module, URL, URLSearchParams,
    window: {location: {search: query,
      href: "https://example.com/games/game.html" + query}}
  };
  vm.runInNewContext(source, context);
  if (cac) vm.runInNewContext(cacSource, context);
  return Array.from(Module.arguments);
}

assert.deepEqual(configure(""), []);
assert.deepEqual(configure("?mute"), ["--mute"]);
for (const value of ["", "1", "true", "on", "yes", " TRUE "]) {
  assert.deepEqual(configure("?mute=" + encodeURIComponent(value)), ["--mute"]);
}
for (const value of ["0", "false", "off", "no", " OFF "]) {
  assert.deepEqual(configure("?mute=" + encodeURIComponent(value)), ["--unmute"]);
}
for (const value of ["2", "maybe", "false,true"]) {
  assert.throws(() => configure("?mute=" + value), /mute query parameter must/);
}
for (const query of ["?mute=1&mute=0", "?mute=false&mute=false", "?mute&mute"]) {
  assert.throws(() => configure(query), /Only one mute query parameter/);
}
assert.deepEqual(configure("?replay=query.replay&mute=false"), [
  "--replay", "/web/replay.replay", "--unmute"
]);
assert.deepEqual(configure("?mute=0&human=true&players=2", true), [
  "--unmute", "--human", "true", "--players", "2"
]);
assert.deepEqual(configure("?human=true&players=2", true), [
  "--human", "true", "--players", "2"
]);

assert.deepEqual(configure("?bot=../bots/Dragon.bas:3&bot=other/Dragon.bas"), [
  "--bot", "/web/bot0/Dragon.bas:3", "--bot", "/web/bot1/Dragon.bas"
]);
assert.deepEqual(configure("?bot=my%2520bot.BAS"), [
  "--bot", "/web/bot0/my bot.BAS"
]);
assert.deepEqual(configure("?replay=query.replay"), [
  "--replay", "/web/replay.replay"
]);
assert.deepEqual(configure("?bot=base.bas:9&player=6&play=false"), [
  "--bot", "/web/bot0/base.bas:9", "--player=6", "--play", "false"
]);
assert.deepEqual(configure("?bot=https://example.com/%252Fescape.bas"), [
  "--bot", "/web/bot0/_escape.bas"
]);
assert.deepEqual(configure("?draft-mode=open&player=1"), [
  "--draft-mode", "open", "--player=1"
]);
console.log("Browser input names and audio controls passed");
