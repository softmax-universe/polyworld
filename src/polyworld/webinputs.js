(function configurePolyworldWebInputs() {
  "use strict";

  if (typeof window === "undefined") {
    return;
  }

  var parameters = new URLSearchParams(window.location.search);
  var replayUrls = parameters.getAll("replay").filter(Boolean);
  var botSpecifications = parameters.getAll("bot").filter(Boolean);
  var commandArguments = [];
  var inputs = [];
  var maxReplayBytes = 64 * 1024 * 1024;

  if (replayUrls.length === 0) {
    var fragment = new URLSearchParams((window.location.hash || "").slice(1));
    replayUrls = fragment.getAll("replay").filter(Boolean);
  }

  if (replayUrls.length > 1) {
    throw new Error("Only one replay URL is allowed.");
  }

  function resolveUrl(source) {
    var url = new URL(source, window.location.href);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw new Error("Web inputs must use an HTTP or HTTPS URL: " + source);
    }
    return url.href;
  }

  function addInput(kind, source, name, suffix) {
    var path = "/web/" + name;
    inputs.push({
      kind: kind,
      source: source,
      url: resolveUrl(source),
      directory: path.slice(0, path.lastIndexOf("/")),
      name: path.slice(path.lastIndexOf("/") + 1)
    });
    commandArguments.push("--" + kind, path + suffix);
  }

  if (replayUrls.length === 1) {
    addInput("replay", replayUrls[0], "replay.replay", "");
  }

  botSpecifications.forEach(function addBot(specification, index) {
    var match = specification.match(/^(.*):([0-9]+)$/);
    var source = match ? match[1] : specification;
    var suffix = match ? ":" + match[2] : "";
    var filename = new URL(resolveUrl(source)).pathname.split("/").pop();
    try {
      filename = decodeURIComponent(filename);
    } catch (error) {
      // Keep a literal percent sign when the URL has no encoded filename.
    }
    filename = filename.replace(/[\/\\\x00-\x1f\x7f]/g, "_");
    if (!filename || filename === "." || filename === "..") {
      filename = "bot" + index + ".bas";
    }
    addInput("bot", source, "bot" + index + "/" + filename, suffix);
  });

  [
    "seed",
    "draft-mode",
    "seconds",
    "spawn-interval",
    "view",
    "ticks",
    "speed",
    "player",
    "play"
  ].forEach(function addValueParameter(name) {
    parameters.getAll(name).forEach(function addValue(value) {
      if (name === "player") {
        commandArguments.push("--player=" + value);
      } else {
        commandArguments.push("--" + name, value);
      }
    });
  });

  if (parameters.has("verbose")) {
    commandArguments.push("--verbose");
  }

  var muteValues = parameters.getAll("mute");
  if (muteValues.length > 1) {
    throw new Error("Only one mute query parameter is allowed.");
  }
  if (muteValues.length === 1) {
    switch (muteValues[0].trim().toLowerCase()) {
      case "":
      case "1":
      case "true":
      case "on":
      case "yes":
        commandArguments.push("--mute");
        break;
      case "0":
      case "false":
      case "off":
      case "no":
        commandArguments.push("--unmute");
        break;
      default:
        throw new Error("The mute query parameter must be true or false.");
    }
  }

  Module["arguments"] = commandArguments;
  if (inputs.length === 0) {
    return;
  }

  function showError(message) {
    console.error(message);
    if (Module["polyworldError"]) {
      Module["polyworldError"](message);
      return;
    }
    var output = document.createElement("pre");
    output.textContent = message;
    output.style.background = "#220b0b";
    output.style.color = "#ffb4a9";
    output.style.font = "16px monospace";
    output.style.left = "24px";
    output.style.margin = "0";
    output.style.padding = "18px";
    output.style.position = "fixed";
    output.style.right = "24px";
    output.style.top = "24px";
    output.style.whiteSpace = "pre-wrap";
    output.style.zIndex = "1000";
    document.body.appendChild(output);
  }

  async function readReplayBody(stream) {
    var reader = stream.getReader();
    var chunks = [];
    var length = 0;
    try {
      for (;;) {
        var item = await reader.read();
        if (item.done) {
          break;
        }
        length += item.value.byteLength;
        if (length > maxReplayBytes) {
          await reader.cancel();
          throw new Error("Replay exceeds the 64 MiB size limit.");
        }
        chunks.push(item.value);
      }
    } finally {
      reader.releaseLock();
    }
    var bytes = new Uint8Array(length);
    var offset = 0;
    for (var chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  }

  async function readReplay(response) {
    var bytes = await readReplayBody(response.body);
    if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
      if (typeof DecompressionStream === "undefined") {
        throw new Error("This browser cannot open gzip-compressed replays.");
      }
      return readReplayBody(new Blob([bytes]).stream().pipeThrough(
        new DecompressionStream("gzip")
      ));
    }
    return bytes;
  }

  (Module["preRun"] || (Module["preRun"] = [])).push(
    function loadPolyworldWebInputs() {
      Module["FS_createPath"]("/", "web", true, true);
      inputs.forEach(function loadInput(input, index) {
        var dependency = "polyworld-web-input-" + index;
        Module["FS_createPath"]("/", input.directory.slice(1), true, true);
        Module["addRunDependency"](dependency);
        fetch(input.url, {credentials: "same-origin"})
          .then(function checkResponse(response) {
            if (!response.ok) {
              throw new Error(response.status + " " + response.statusText);
            }
            return input.kind === "replay"
              ? readReplay(response)
              : response.arrayBuffer().then(function bytes(buffer) {
                return new Uint8Array(buffer);
              });
          })
          .then(function installInput(bytes) {
            Module["FS_createDataFile"](
              input.directory,
              input.name,
              bytes,
              true,
              false,
              true
            );
            Module["removeRunDependency"](dependency);
          })
          .catch(function reportInputError(error) {
            showError(
              "Failed to load " + input.kind + " from " + input.source +
              ".\n" + error.message
            );
          });
      });
    }
  );
})();
