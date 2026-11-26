## Compile Shady's desktop stages with explicit native resource bindings.
## Both drivers consume the same reflected layout and zero-to-one clip depth.
import std/[compilesettings, hashes, os, strutils], shady

proc shaderTool(args: varargs[string]) {.compileTime.} =
  var command: seq[string]
  for arg in args: command.add os.quoteShell(arg)
  let (output, status) = gorgeEx(command.join(" "))
  if status != 0:
    raise newException(ValueError, args[0] & " failed:\n" & output)

proc compiledStage(source: string, stage: ShaderStage, label: string): string {.compileTime.} =
  when defined(nimcheck):
    return ""
  else:
    let
      vertex = stage == shaderVertex
      name = if vertex: "vert" else: "frag"
      target = if vertex: "vs_6_0" else: "ps_6_0"
      dir = querySetting(SingleValueSetting.nimcacheDir) / "polyworld-shaders"
      stem = dir / ($hash(source) & "." & name)
      sourcePath = stem & ".glsl"
      spirv = stem & ".spv"
      reflection = stem & ".json"
      hlsl = stem & ".hlsl"
      output = stem & (when defined(useDirectX): ".dxil" else: ".vk.spv")
      dxc = getEnv("SHADY_HLSL_COMPILER", "dxc")
      cross = getEnv("SPIRV_CROSS", "spirv-cross")
    let cached = output & ".stage"
    const version = $hash(staticRead(currentSourcePath()))
    if fileExists(cached) and fileExists(sourcePath) and readFile(sourcePath) == source and
        fileExists(cached & ".version") and readFile(cached & ".version") == version:
      return label & "\n" & readFile(cached)
    createDir(dir)
    writeFile(sourcePath, source)
    shaderTool(getEnv("SHADY_SPIRV_COMPILER", "glslangValidator"), "-V", "-R", "-S", name,
      "--auto-map-bindings", "--auto-map-locations", "--sdub", "FrameUniforms", "1",
      (if vertex: "0" else: "1"), "--rsb", name, (if vertex: "2" else: "0"), "-o", spirv, sourcePath)
    shaderTool(cross, spirv, "--reflect", "--output", reflection)
    shaderTool(cross, spirv, "--hlsl", "--shader-model", "60", "--fixup-clipspace", "--output", hlsl)
    when defined(useDirectX):
      shaderTool(dxc, "-T", target, "-E", "main", "-Fo", output, hlsl)
    else:
      # Use separate image and sampler bindings for the same Shady sampler.
      if vertex:
        shaderTool(dxc, "-spirv", "-fvk-use-dx-layout", "-fvk-invert-y", "-fvk-s-shift", "32", "2",
          "-T", target, "-E", "main", "-Fo", output, hlsl)
      else:
        shaderTool(dxc, "-spirv", "-fvk-use-dx-layout", "-fvk-s-shift", "32", "0",
          "-T", target, "-E", "main", "-Fo", output, hlsl)
    let packed = readFile(reflection) & '\0' & readFile(output)
    writeFile(cached, packed)
    writeFile(cached & ".version", version)
    label & "\n" & packed

template nativeStage*(fn, stage: untyped): string =
  const packed = compiledStage(toShader(fn, glsl4Desktop, stage), stage, astToStr(fn))
  packed
