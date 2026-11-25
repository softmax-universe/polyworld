## Run from the repository root. Binaries and browser bundles are produced by
## the build command. Each process gets a fresh world and one GPU to itself.
import std/[asynchttpserver, asyncdispatch, httpcore, json,
  monotimes, os, osproc, strformat, strutils, times, uri]

const
  Games = ["crewrift", "cta", "gota", "lvd", "cac", "heartleaf", "monster"]
  Dirs = ["crewrift", "call_to_adventure", "gods_of_the_arena", "light_vs_dark",
    "cac", "heartleaf", "monster"]
  Bots = [0, 4, 10, 2, 0, 9, 0]
  Backends = ["OpenGL", "WebGL", "DirectX", "Vulkan"]
  BuildDir = "tmp/bench-build"
  Output = "tmp/livetest/benchmarks"
  Marker = "POLYWORLD_FRAME_BENCH "
  PortNumber = 18946
  BrowserHook = """<style>#canvas{width:800px!important;height:560px!important;max-width:none!important;max-height:none!important}</style>
<script>
(() => {
  let done = false;
  const post = data => {
    if (done) return;
    done = true;
    navigator.sendBeacon('/__framebench', JSON.stringify(data));
  };
  for (const method of ['log', 'info']) {
    const original = console[method];
    console[method] = function(...args) {
      original.apply(this, args);
      const value = args.join(' '), marker = 'POLYWORLD_FRAME_BENCH ';
      if (!value.includes(marker)) return;
      const result = JSON.parse(value.slice(value.indexOf(marker) + marker.length));
      const gl = document.querySelector('#canvas').getContext('webgl2');
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      result.renderer = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      result.webgl = gl.getParameter(gl.VERSION);
      result.antialias = gl.getContextAttributes().antialias;
      result.browser = navigator.userAgent;
      post(result);
    };
  }
  window.addEventListener('error', e => {if (e.message) post({error:e.message});});
  window.addEventListener('unhandledrejection', e => post({error:String(e.reason)}));
})();
</script>"""

proc suffix(backend: string): string =
  if backend in ["DirectX", "Vulkan"]: "use" & backend else: backend

proc executable(game, backend: string): string =
  BuildDir / (game & "-" & backend.suffix).addFileExt(ExeExt)

proc build(game, backend: string, i: int) =
  var args = @["c", "--hints:off", "-d:frameBench"]
  if backend == "WebGL":
    args.add "-d:emscripten"
  else:
    let key = game & "-" & backend.suffix
    args.add "--nimcache:tmp/cache/" & key
    args.add "-o:" & executable(game, backend)
    if backend != "OpenGL": args.add "-d:" & backend.suffix
  args.add "games" / Dirs[i] / (game & ".nim")
  let p = startProcess(findExe("nim"), args = args, options = {poParentStreams})
  let status = p.waitForExit()
  p.close()
  if status != 0: raise newException(IOError, "Build failed for " & game & " " & backend)

proc serve(record: string) =
  let root = absolutePath("games")
  proc handle(req: Request) {.async.} =
    let url = req.url.path
    if url == "/__ready":
      await req.respond(Http200, "ready")
    elif url == "/__framebench" and req.reqMethod == HttpPost:
      let parsed = parseJson(req.body)
      writeFile(record & ".new", $parsed)
      moveFile(record & ".new", record)
      await req.respond(Http200, "ok")
    else:
      let path = absolutePath(decodeUrl(url.strip(chars = {'/'}))).normalizedPath
      if req.reqMethod != HttpGet or not path.startsWith(root & DirSep) or not fileExists(path):
        await req.respond(Http404, "")
        return
      var content = readFile(path)
      let mime = case path.splitFile.ext
        of ".html": "text/html"
        of ".js": "text/javascript"
        of ".wasm": "application/wasm"
        of ".svg": "image/svg+xml"
        of ".png": "image/png"
        else: "application/octet-stream"
      if mime == "text/html": content = content.replace("</head>", BrowserHook & "</head>")
      await req.respond(Http200, content, newHttpHeaders({"Content-Type": mime, "Cache-Control": "no-store"}))
  let server = newAsyncHttpServer()
  server.listen(Port(PortNumber), "127.0.0.1")
  writeFile(record & ".ready", "")
  while true: waitFor server.acceptRequest(handle)

proc web(i: int, entry, record: string): JsonNode =
  let chrome = getEnv("BENCH_CHROMIUM", "C:/Program Files/Google/Chrome/Application/chrome.exe")
  let ready = record & ".ready"
  if fileExists(ready): removeFile(ready)
  if fileExists(record): removeFile(record)
  let server = startProcess(getAppFilename(), args = ["serve", record], options = {poParentStreams})
  defer:
    if server.running: server.terminate()
    discard server.waitForExit()
    server.close()
  let deadline = getMonoTime() + initDuration(seconds = 240)
  while not fileExists(ready):
    if not server.running or getMonoTime() >= deadline:
      raise newException(IOError, "Benchmark HTTP server could not start")
    sleep(25)
  var url = &"http://127.0.0.1:{PortNumber}/games/{Dirs[i]}/emscripten/{Games[i]}.html?seed=42&mute=1"
  if Bots[i] > 0: url.add "&bot=../players/base.bas:" & $Bots[i]
  if Games[i] == "cac": url.add "&players=2"
  let profile = absolutePath(BuildDir / ("chrome-" & entry))
  let browser = startProcess(chrome, args = ["--headless=new", "--enable-gpu", "--use-angle=d3d11",
    "--disable-software-rasterizer", "--ignore-gpu-blocklist", "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding", "--force-device-scale-factor=1", "--window-size=800,640",
    "--no-first-run", "--no-default-browser-check", "--disable-extensions",
    "--user-data-dir=" & profile, url], options = {poParentStreams})
  defer:
    if browser.running: browser.terminate()
    discard browser.waitForExit()
    browser.close()
  while not fileExists(record):
    if not browser.running or getMonoTime() >= deadline:
      raise newException(IOError, "Browser exited or timed out for " & entry)
    sleep(100)
  result = parseFile(record)
  if result.hasKey("error"): raise newException(IOError, $result)
  if result["antialias"].getBool or result["renderer"].getStr.toLowerAscii.contains("swiftshader"):
    raise newException(IOError, "Expected hardware WebGL 2 with antialiasing disabled")

proc native(i: int, backend, entry: string): JsonNode =
  var args = @["--seed", "42", "--mute", "--vsync", "off", "--windowSize", "800x560"]
  if Bots[i] > 0: args.add ["--bot", "games/" & Dirs[i] & "/players/base.bas:" & $Bots[i]]
  if Games[i] == "cac": args.add ["--players", "2"]
  if Games[i] == "monster":
    args.add ["--offline", "--no-voice", "--save-dir", absolutePath(BuildDir / ("save-" & entry & "-" & $getTime().toUnix))]
  let (output, status) = execCmdEx(quoteShellCommand(@[absolutePath(executable(Games[i], backend))] & args))
  writeFile(BuildDir / (entry & ".log"), output)
  if status == 0:
    for line in output.splitLines:
      if line.startsWith(Marker): return parseJson(line[Marker.len .. ^1])
  raise newException(IOError, "No completed measurement. See " & BuildDir / (entry & ".log"))

proc measure(i: int, backend, runId: string, repetition: int) =
  let entry = Games[i] & "-" & backend & "-" & runId & "-" & $repetition
  let path = Output / (entry & ".json")
  echo "Measuring ", entry
  if fileExists(path):
    raise newException(IOError, "Run ID already has a result for " & entry)
  let data = if backend == "WebGL": web(i, entry, BuildDir / (entry & ".json"))
    else: native(i, backend, entry)
  doAssert data["backend"].getStr == backend and data["width"].getInt == 800 and
    data["height"].getInt == 560 and data["frame_ms"].len > 0
  data["game"] = %Games[i]
  data["repetition"] = %repetition
  data["revision"] = %execCmdEx("git rev-parse HEAD").output.strip
  writeFile(path, $data)
  var total = 0.0
  for sample in data["frame_ms"]: total += sample.getFloat
  echo &"  {data[\"frame_ms\"].len} frames, {total / data[\"frame_ms\"].len.float:.2f} ms mean"

when isMainModule:
  createDir(BuildDir)
  createDir(Output)
  let args = commandLineParams()
  if args.len == 2 and args[0] == "serve":
    serve(args[1])
  elif args.len >= 1 and args[0] in ["build", "run"]:
    let games = if args.len > 1 and args[1] != "all": args[1].split(',') else: @Games
    let backends = if args.len > 2 and args[2] != "all": args[2].split(',') else: @Backends
    let repeats = if args.len > 3: parseInt(args[3]) else: 3
    let runId = if args.len > 4: args[4] else: $getTime().toUnix
    doAssert repeats > 0 and runId.len > 0 and runId.allCharsInSet(Letters + Digits + {'-'})
    for game in games: doAssert game in Games
    for backend in backends: doAssert backend in Backends
    var failures: seq[string]
    for rep in 1 .. (if args[0] == "build": 1 else: repeats):
      for game in games:
        let i = Games.find(game)
        for j in 0 ..< backends.len:
          let backend = backends[(j + rep - 1 + i) mod backends.len]
          if args[0] == "build": build(game, backend, i)
          else:
            try: measure(i, backend, runId, rep)
            except CatchableError as error:
              let failure = game & " " & backend & " run " & $rep & ": " & error.msg
              stderr.writeLine(failure)
              failures.add failure
    if failures.len > 0:
      quit(failures.join("\n"), 1)
  else:
    quit("bench_backends build|run [games|all] [backends|all] [repetitions] [run-id]", 2)
