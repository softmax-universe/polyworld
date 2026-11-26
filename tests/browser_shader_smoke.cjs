#!/usr/bin/env node
'use strict';

// Serve the repository root, then run with Playwright and pngjs on NODE_PATH:
// SHADER_SMOKE_BASE=http://127.0.0.1:18934/ node tests/browser_shader_smoke.cjs
// Pass game names as arguments, or set SHADER_SMOKE_GAMES=gota,lvd.
// SHADER_SMOKE_URLS accepts a JSON object of per-game URL overrides.
// This observes WebGL and uses ordinary launch arguments, without game-state
// injection. Screenshots and the JSON report go into tmp/backends/browser.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const {PNG} = require('pngjs');

const Root = path.resolve(__dirname, '..');
const Output = path.resolve(process.env.SHADER_SMOKE_OUT ||
  path.join(Root, 'tmp', 'backends', 'browser'));
const Base = process.env.SHADER_SMOKE_BASE || 'http://127.0.0.1:18934/';
const Timeout = Number(process.env.SHADER_SMOKE_TIMEOUT || 180000);
const Observe = Number(process.env.SHADER_SMOKE_OBSERVE || 3000);
const Viewport = {width: 1280, height: 800};
const ResizedViewport = {width: 960, height: 640};
const Games = {
  gota: ['gods_of_the_arena', 'bot=../players/base.bas:10&speed=8'],
  lvd: ['light_vs_dark', 'bot=../players/base.bas:2'],
  cta: ['call_to_adventure', 'bot=../players/base.bas:4'],
  cac: ['cac', 'players=2'],
  heartleaf: ['heartleaf', 'bot=../players/base.bas:9'],
  crewrift: ['crewrift', ''],
  monster: ['monster', '']
};
const Urls = JSON.parse(process.env.SHADER_SMOKE_URLS || '{}');
const Selected = process.argv.length > 2 ? process.argv.slice(2) :
  (process.env.SHADER_SMOKE_GAMES || Object.keys(Games).join(',')).split(',');

function observeWebgl() {
  // Keep original WebGL calls, arguments, return values, and exceptions intact.
  const state = window.polyworldShaderSmoke = {
    contexts: [], shaders: 0, programs: 0, drawCalls: 0,
    lastDraw: 0, shaderErrors: [], contextLosses: 0,
    presentedTick: null, presentedFrames: 0, mismatches: 0
  };
  const contexts = new WeakMap();
  const originalContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(...args) {
    const gl = originalContext.apply(this, args);
    if (gl && /^(webgl2?|experimental-webgl)$/.test(args[0]) &&
        !contexts.has(gl)) {
      const extension = gl.getExtension('WEBGL_debug_renderer_info');
      const entry = {
        kind: args[0], version: gl.getParameter(gl.VERSION),
        shadingLanguage: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
        renderer: gl.getParameter(extension ?
          extension.UNMASKED_RENDERER_WEBGL : gl.RENDERER)
      };
      contexts.set(gl, entry);
      state.contexts.push(entry);
      this.addEventListener('webglcontextlost', () => state.contextLosses++);
    }
    return gl;
  };
  const patched = new Set();
  for (const name of ['WebGLRenderingContext', 'WebGL2RenderingContext']) {
    const prototype = window[name]?.prototype;
    if (!prototype) continue;
    for (const method of ['compileShader', 'linkProgram', 'drawArrays',
      'drawElements', 'drawArraysInstanced', 'drawElementsInstanced',
      'drawRangeElements']) {
      // A browser may inherit WebGL 1 methods from the same prototype.
      let owner = prototype;
      while (owner && !Object.hasOwn(owner, method)) {
        owner = Object.getPrototypeOf(owner);
      }
      if (!owner) continue;
      const original = owner[method];
      if (patched.has(original)) continue;
      const wrapper = function(...args) {
        const result = original.apply(this, args);
        if (method === 'compileShader') {
          state.shaders++;
          if (!this.getShaderParameter(args[0], this.COMPILE_STATUS)) {
            state.shaderErrors.push({
              kind: 'compile', log: this.getShaderInfoLog(args[0]),
              source: this.getShaderSource(args[0])
            });
          }
        } else if (method === 'linkProgram') {
          state.programs++;
          if (!this.getProgramParameter(args[0], this.LINK_STATUS)) {
            state.shaderErrors.push({
              kind: 'link', log: this.getProgramInfoLog(args[0]),
              sources: (this.getAttachedShaders(args[0]) || []).map(shader =>
                this.getShaderSource(shader))
            });
          }
        } else {
          state.drawCalls++;
          state.lastDraw = performance.now();
        }
        return result;
      };
      patched.add(wrapper);
      owner[method] = wrapper;
    }
  }
}

function summarizePixels(file) {
  // Sample quantized colors to reject blank canvases without image baselines.
  const png = PNG.sync.read(fs.readFileSync(file));
  const colors = new Set();
  let low = 255, high = 0, opaque = 0, samples = 0;
  for (let y = 0; y < png.height; y += 8) {
    for (let x = 0; x < png.width; x += 8) {
      const i = (y * png.width + x) * 4;
      const [r, g, b, a] = png.data.subarray(i, i + 4);
      colors.add((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3));
      low = Math.min(low, r, g, b);
      high = Math.max(high, r, g, b);
      opaque += Number(a > 0);
      samples++;
    }
  }
  return {width: png.width, height: png.height, colors: colors.size,
    range: high - low, visibleFraction: opaque / samples};
}

async function snapshot(page) {
  return page.evaluate(() => ({
    ...window.polyworldShaderSmoke,
    canvas: {
      width: document.querySelector('#canvas')?.width,
      height: document.querySelector('#canvas')?.height
    },
    status: document.querySelector('#game-status')?.textContent || '',
    tick: window.polyworldShaderSmoke.presentedTick,
    speed: window.Module?.polyworldPlaybackSpeed ?? null,
    loading: document.querySelector('#loading')?.textContent || '',
    loadingHidden: document.querySelector('#loading')?.hidden ?? true
  }));
}

async function renderedScreenshot(page, game, name) {
  const file = path.join(Output, game + '-' + name + '.png');
  await page.locator('#canvas').screenshot({path: file, timeout: Timeout});
  const pixels = summarizePixels(file);
  assert(pixels.colors >= 32 && pixels.range > 20 &&
    pixels.visibleFraction > 0.9,
  'Canvas is blank or nearly uniform: ' + JSON.stringify(pixels));
  return {file, pixels};
}

async function waitForDrawing(page, after) {
  await page.waitForFunction(({drawCalls, lastDraw, observe}) => {
    const current = window.polyworldShaderSmoke;
    if (current.shaderErrors.length || current.contextLosses) {
      throw new Error('WebGL shader or context failure');
    }
    if (document.querySelector('#loading')?.classList.contains('error')) {
      throw new Error(document.querySelector('#loading').textContent);
    }
    return current.drawCalls > drawCalls + 10 &&
      current.lastDraw > lastDraw + observe;
  }, {...after, observe: Observe}, {timeout: Timeout, polling: 100});
}

async function waitForGameplay(page, game) {
  // GotA allows ten 10-second draft picks and a 30-second preparation phase.
  // The ordinary speed=8 launch option advances them without skipping rules.
  // Read the existing presented-frame callback without changing simulation.
  await page.evaluate(() => {
    const module = window.Module;
    const original = module.polyworldFrame;
    module.polyworldFrame = function(...args) {
      const state = window.polyworldShaderSmoke;
      state.presentedTick = args[0] ?? null;
      state.mismatches = Math.max(state.mismatches, args[1] || 0);
      state.presentedFrames++;
      return original?.apply(this, args);
    };
  });
  if (game === 'gota') {
    await page.waitForFunction(() =>
      window.polyworldShaderSmoke.presentedTick > (100 + 30) * 24,
    null, {timeout: Timeout, polling: 100});
  } else if (game === 'cac') {
    await page.waitForFunction(() =>
      /\bTurn \d+\./.test(
        document.querySelector('#game-status')?.textContent || ''),
    null, {timeout: Timeout, polling: 100});
  }
}

async function checkCrewriftControls(page) {
  // Keyboard events must survive the browser loop until the game consumes them.
  await page.locator('#canvas').focus();
  const before = await snapshot(page);
  assert(Number.isInteger(before.tick), 'Crewrift must report simulation ticks');
  await page.keyboard.press('p', {delay: 120});
  await page.waitForFunction(frames =>
    window.polyworldShaderSmoke.presentedFrames > frames + 2,
  before.presentedFrames, {timeout: Timeout});
  const paused = await snapshot(page);
  await page.waitForFunction(after => {
    const state = window.polyworldShaderSmoke;
    return state.presentedFrames > after.presentedFrames + 2 &&
      state.lastDraw > after.lastDraw + 600;
  }, paused, {timeout: Timeout});
  const stillPaused = await snapshot(page);
  assert.equal(stillPaused.tick, paused.tick,
    'P must pause simulation while the renderer continues drawing');
  await page.keyboard.press('p', {delay: 120});
  await page.waitForFunction(tick =>
    window.polyworldShaderSmoke.presentedTick > tick + 5,
  paused.tick, {timeout: Timeout});
  const resumed = await snapshot(page);
  await page.keyboard.press('Escape', {delay: 120});
  await page.waitForFunction(tick =>
    window.polyworldShaderSmoke.presentedTick > tick + 5,
  resumed.tick, {timeout: Timeout});
  const afterEscape = await snapshot(page);
  return {pause: {before: before.tick, paused: paused.tick,
    after: stillPaused.tick}, resumed: resumed.tick,
  afterEscape: afterEscape.tick, passed: true};
}

async function runGame(browser, game) {
  const [directory, query] = Games[game];
  const url = Urls[game] || new URL(
    `games/${directory}/emscripten/${game}.html?seed=42&mute=1&${query}`,
    Base
  ).href;
  const result = {game, url, passed: false, console: [], errors: [],
    responses: [], screenshots: []};
  const context = await browser.newContext({viewport: Viewport,
    deviceScaleFactor: 1});
  await context.addInitScript(observeWebgl);
  const page = await context.newPage();
  page.on('pageerror', error => result.errors.push(String(error.stack || error)));
  page.on('console', message => {
    const location = message.location();
    const item = {type: message.type(), text: message.text(), location};
    if (result.console.length < 1000) result.console.push(item);
    if (location.url?.endsWith('/favicon.ico')) return;
    if (message.type() === 'error' ||
        /WebGL.*(?:INVALID_|GL_INVALID_|error)|GL_INVALID_|shader.*failed/i
          .test(message.text())) {
      result.errors.push(item.text);
    }
  });
  page.on('response', response => {
    if (response.status() >= 400 &&
        !new URL(response.url()).pathname.endsWith('/favicon.ico')) {
      const item = {url: response.url(), status: response.status()};
      result.responses.push(item);
      result.errors.push('HTTP ' + item.status + ': ' + item.url);
    }
  });
  try {
    await page.goto(url, {waitUntil: 'domcontentloaded', timeout: Timeout});
    await page.waitForFunction(() => {
      const state = window.polyworldShaderSmoke;
      const loading = document.querySelector('#loading');
      if (state?.shaderErrors.length || state?.contextLosses) {
        throw new Error('WebGL shader or context failure during startup');
      }
      if (loading?.classList.contains('error')) {
        throw new Error(loading.textContent);
      }
      return state?.programs > 0 && state.drawCalls > 0 &&
        (!loading || loading.hidden);
    }, null, {timeout: Timeout});
    await waitForGameplay(page, game);
    result.started = await snapshot(page);
    await waitForDrawing(page, result.started);
    result.screenshots.push(await renderedScreenshot(page, game, 'webgl'));
    result.running = await snapshot(page);
    assert(!/\/ (HomeMenu|SingleMenu|SettingsMenu)/.test(result.running.status),
      'The game remained in its menus: ' + result.running.status);
    await page.setViewportSize(ResizedViewport);
    await waitForDrawing(page, result.running);
    result.screenshots.push(await renderedScreenshot(page, game, 'resized'));
    result.resized = await snapshot(page);
    assert(result.resized.canvas.width !== result.running.canvas.width ||
      result.resized.canvas.height !== result.running.canvas.height,
    'The WebGL drawing buffer did not resize');
    if (game === 'crewrift') {
      result.controls = await checkCrewriftControls(page);
    }
    result.final = await snapshot(page);
    assert.equal(result.final.shaderErrors.length, 0,
      'All generated shaders must compile and link');
    assert.equal(result.final.contextLosses, 0,
      'The WebGL context must remain available');
    assert.equal(result.final.mismatches, 0,
      'Presented frames must report no replay divergence');
    assert.equal(result.errors.length, 0,
      'Browser errors: ' + result.errors.join('\n'));
    result.passed = true;
  } catch (error) {
    result.failure = String(error.stack || error);
    try {
      result.failedState = await snapshot(page);
      const file = path.join(Output, game + '-failure.png');
      await page.screenshot({path: file, timeout: 10000});
      result.failureScreenshot = file;
    } catch (captureError) {
      result.captureError = String(captureError);
    }
  } finally {
    await context.close();
  }
  console.log(JSON.stringify({game, passed: result.passed,
    programs: result.resized?.programs,
    drawCalls: result.resized?.drawCalls,
    failure: result.failure, errors: result.errors}));
  return result;
}

(async () => {
  assert(Selected.length > 0, 'Select at least one game');
  for (const game of Selected) assert(game in Games, 'Unknown game: ' + game);
  assert(Timeout > 0 && Observe > 0, 'Timeouts must be positive');
  fs.mkdirSync(Output, {recursive: true});
  const report = {started: new Date().toISOString(), base: Base, games: [],
    passed: false};
  const reportFile = path.join(Output, 'report.json');
  const browser = await chromium.launch({headless: true,
    executablePath: process.env.SHADER_SMOKE_CHROMIUM || undefined,
    args: ['--enable-unsafe-swiftshader',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding']});
  try {
    for (const game of Selected) {
      report.games.push(await runGame(browser, game));
      fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
    }
    report.passed = report.games.every(game => game.passed);
  } finally {
    report.finished = new Date().toISOString();
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
    await browser.close();
  }
  console.log('Shader smoke report: ' + reportFile);
  process.exitCode = report.passed ? 0 : 1;
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
