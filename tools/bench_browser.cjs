#!/usr/bin/env node
'use strict';

// Build games with -d:backendBench -d:emscripten, serve the repository, then:
// NODE_PATH=... node tools/bench_browser.cjs --games gota,lvd --trials 3
// Runs are sequential. Do not run native benchmarks or builds concurrently.
// Frame timing and GPU synchronization come from the shared Nim benchmark.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');

const Root = path.resolve(__dirname, '..');
const Games = {
  gota: {directory: 'gods_of_the_arena', bot: '../players/base.bas:10'},
  lvd: {directory: 'light_vs_dark', bot: '../players/base.bas:2'},
  cta: {directory: 'call_to_adventure', bot: '../players/base.bas:4'},
  cac: {directory: 'cac', players: 2},
  heartleaf: {directory: 'heartleaf', bot: '../players/base.bas:9'},
  crewrift: {directory: 'crewrift'},
  monster: {directory: 'monster'}
};
const Viewport = {width: 1280, height: 800};

function positiveInteger(value, name, allowZero = false) {
  // Reject malformed sizes rather than silently changing the measured run.
  const number = Number(value);
  assert(Number.isSafeInteger(number) && number >= (allowZero ? 0 : 1),
    name + ' must be ' + (allowZero ? 'nonnegative' : 'positive'));
  return number;
}

function options(arguments_) {
  // Accept one-game invocations so a parent runner can rotate backend order.
  const result = {
    games: Object.keys(Games),
    trials: 3,
    firstTrial: 1,
    warmup: 120,
    frames: 600,
    base: process.env.BENCH_BASE || 'http://127.0.0.1:18934/',
    output: process.env.BENCH_OUT || path.join(Root, 'tmp/benchmarks/webgl'),
    executable: process.env.BENCH_CHROMIUM ||
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    timeout: 300000,
    headless: process.env.BENCH_HEADLESS !== '0',
    screenshots: false,
    url: null,
    outputFile: null
  };
  for (let i = 0; i < arguments_.length; i++) {
    const name = arguments_[i];
    if (name === '--headful') {
      result.headless = false;
    } else if (name === '--screenshots') {
      result.screenshots = true;
    } else {
      const value = arguments_[++i];
      assert(value !== undefined, 'Missing value for ' + name);
      switch (name) {
        case '--game':
          result.games = [value];
          if (!arguments_.includes('--trials')) result.trials = 1;
          break;
        case '--games': result.games = value.split(','); break;
        case '--trials':
          result.trials = positiveInteger(value, name); break;
        case '--trial':
          result.firstTrial = positiveInteger(value, name); break;
        case '--warmup':
          result.warmup = positiveInteger(value, name, true); break;
        case '--frames':
          result.frames = positiveInteger(value, name); break;
        case '--timeout':
          result.timeout = positiveInteger(value, name); break;
        case '--base': result.base = value; break;
        case '--out': result.output = value; break;
        case '--url': result.url = value; break;
        case '--output': result.outputFile = path.resolve(value); break;
        default: throw new Error('Unknown option ' + name);
      }
    }
  }
  assert(result.games.length > 0, 'Select at least one game');
  assert(new Set(result.games).size === result.games.length,
    'Do not repeat game names');
  for (const game of result.games) assert(game in Games, 'Unknown game ' + game);
  if (result.url || result.outputFile) {
    assert(result.games.length === 1 && result.trials === 1,
      '--url and --output require one game and one trial');
  }
  if (result.outputFile) result.output = path.dirname(result.outputFile);
  result.output = path.resolve(result.output);
  return result;
}

function gameUrl(config, game) {
  // Use the same normal bot rosters as native benchmark launches.
  const settings = Games[game];
  const url = new URL(config.url ||
    `games/${settings.directory}/emscripten/${game}.html`, config.base);
  url.searchParams.set('seed', '42');
  url.searchParams.set('mute', '1');
  url.searchParams.set('benchWarmup', String(config.warmup));
  url.searchParams.set('benchFrames', String(config.frames));
  if (settings.bot) {
    const count = settings.bot.split(':').pop();
    const policy = new URL(`games/${settings.directory}/players/base.bas`,
      config.base).href;
    url.searchParams.set('bot', policy + ':' + count);
  }
  if (settings.players) url.searchParams.set('players', String(settings.players));
  return url.href;
}

function observeContext() {
  // Record context creation only; no wrappers run around timed drawing calls.
  const state = window.polyworldBenchBrowser = {
    contexts: [],
    contextLosses: 0
  };
  const contexts = new WeakSet();
  const original = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(...args) {
    const gl = original.apply(this, args);
    if (gl && /^(webgl2?|experimental-webgl)$/.test(args[0]) &&
        !contexts.has(gl)) {
      contexts.add(gl);
      const extension = gl.getExtension('WEBGL_debug_renderer_info');
      state.contexts.push({
        kind: args[0],
        version: gl.getParameter(gl.VERSION),
        shadingLanguage: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
        renderer: gl.getParameter(extension ?
          extension.UNMASKED_RENDERER_WEBGL : gl.RENDERER),
        vendor: gl.getParameter(extension ?
          extension.UNMASKED_VENDOR_WEBGL : gl.VENDOR),
        attributes: gl.getContextAttributes(),
        samples: gl.getParameter(gl.SAMPLES),
        width: gl.drawingBufferWidth,
        height: gl.drawingBufferHeight,
        timerQueriesAvailable: Boolean(
          gl.getExtension('EXT_disjoint_timer_query_webgl2'))
      });
      this.addEventListener('webglcontextlost', () => state.contextLosses++);
    }
    return gl;
  };
}

function summarize(values) {
  // Keep cadence statistics distinct from the synchronized frame samples.
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  return {
    count: values.length,
    meanMs: mean,
    p50Ms: sorted[Math.floor(sorted.length * 0.5)],
    p95Ms: sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1)],
    minMs: sorted[0],
    maxMs: sorted[sorted.length - 1],
    meanFps: mean > 0 ? 1000 / mean : null
  };
}

function validateRun(result, config) {
  // Reject runs with unmatched resolution, sampling, or software rendering.
  const benchmark = result.benchmark;
  assert(benchmark?.done, 'The benchmark did not complete');
  assert.equal(benchmark.backend, 'webgl');
  assert.equal(benchmark.game, result.game);
  assert.equal(benchmark.width, Viewport.width);
  assert.equal(benchmark.height, Viewport.height);
  assert.equal(benchmark.samples, 1);
  assert.equal(benchmark.warmup, config.warmup);
  assert.equal(benchmark.frames, config.frames);
  assert.equal(benchmark.framesData.length, config.frames);
  assert(Math.abs(benchmark.fixedStepSeconds - 1 / 60) < 1e-8);
  assert.equal(result.canvas.width, Viewport.width);
  assert.equal(result.canvas.height, Viewport.height);
  assert.equal(result.drawingBuffer.width, Viewport.width);
  assert.equal(result.drawingBuffer.height, Viewport.height);
  assert.equal(result.devicePixelRatio, 1);
  assert.equal(result.contextLosses, 0);
  assert.equal(result.errors.length, 0, result.errors.join('\n'));
  assert(result.contexts.length > 0, 'No WebGL context was observed');
  for (const context of result.contexts) {
    assert.equal(context.kind, 'webgl2');
    assert.equal(context.attributes.antialias, false,
      'The benchmark must disable canvas MSAA');
    assert(context.samples === 0 || context.samples === 1,
      'Unexpected default framebuffer sample count');
    assert(!/swiftshader|llvmpipe|software|softpipe/i.test(context.renderer),
      'Hardware acceleration required: ' + context.renderer);
  }
  for (const sample of benchmark.framesData) {
    for (const name of ['cpuMs', 'gpuWaitMs', 'workMs', 'intervalMs']) {
      assert(Number.isFinite(sample[name]) && sample[name] >= 0,
        'Invalid ' + name + ' in frame ' + sample.frame);
    }
  }
}

async function runGame(browser, config, game, trial) {
  // Use fresh page storage and GPU resources for each measured trial.
  const result = {
    game, trial, backend: 'webgl', url: gameUrl(config, game),
    browserVersion: browser.version(), headless: config.headless,
    started: new Date().toISOString(), passed: false,
    errors: [], console: [], failedResponses: []
  };
  const context = await browser.newContext({
    viewport: Viewport, deviceScaleFactor: 1
  });
  await context.addInitScript(observeContext);
  const page = await context.newPage();
  page.on('pageerror', error => result.errors.push(String(error.stack || error)));
  page.on('console', message => {
    const text = message.text();
    const location = message.location();
    if (location.url?.endsWith('/favicon.ico')) return;
    if (message.type() === 'error') result.errors.push(text);
    if (result.console.length < 100) {
      result.console.push({type: message.type(), text});
    }
  });
  page.on('response', response => {
    if (response.status() >= 400 &&
        !new URL(response.url()).pathname.endsWith('/favicon.ico')) {
      const item = {url: response.url(), status: response.status()};
      result.failedResponses.push(item);
      result.errors.push('HTTP ' + item.status + ': ' + item.url);
    }
  });
  try {
    await page.goto(result.url, {waitUntil: 'domcontentloaded',
      timeout: config.timeout});
    await page.waitForFunction(() => {
      const loading = document.querySelector('#loading');
      if (loading?.classList.contains('error')) {
        throw new Error(loading.textContent);
      }
      return window.Module?.polyworldBenchmark?.done;
    }, null, {timeout: config.timeout, polling: 250});
    Object.assign(result, await page.evaluate(() => {
      const state = window.polyworldBenchBrowser;
      const canvas = document.querySelector('#canvas');
      const gl = canvas.getContext('webgl2');
      return {
        benchmark: window.Module.polyworldBenchmark,
        contexts: state.contexts,
        contextLosses: state.contextLosses,
        canvas: {width: canvas.width, height: canvas.height},
        drawingBuffer: {width: gl.drawingBufferWidth, height: gl.drawingBufferHeight},
        devicePixelRatio: window.devicePixelRatio,
        navigationToCompletionMs: performance.now(),
        status: document.querySelector('#game-status')?.textContent || ''
      };
    }));
    result.cadenceMs = result.benchmark.framesData.map(frame => frame.intervalMs);
    result.cadence = summarize(result.cadenceMs);
    validateRun(result, config);
    if (config.screenshots) {
      result.screenshot = path.join(config.output,
        `${game}-webgl-trial${trial}.png`);
      await page.locator('#canvas').screenshot({path: result.screenshot,
        timeout: 10000});
    }
    result.passed = true;
  } catch (error) {
    result.failure = String(error.stack || error);
  } finally {
    result.finished = new Date().toISOString();
    await context.close();
  }
  const filename = config.outputFile || path.join(config.output,
    `${game}-webgl-trial${trial}.json`);
  fs.writeFileSync(filename, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({game, trial, passed: result.passed,
    summary: result.benchmark?.summary, failure: result.failure, filename}));
  return result;
}

async function main() {
  // Keep one browser process while running exactly one active page at a time.
  const config = options(process.argv.slice(2));
  fs.mkdirSync(config.output, {recursive: true});
  const report = {started: new Date().toISOString(), config, runs: [],
    passed: false, methodology: {
      measuredWork: 'Shared simulation and rendering through one-pixel readback completion',
      excludedFromWork: 'Loading, event-loop wait, presentation, RAF pacing',
      cadence: 'Measured gameplay frame-start intervals including browser scheduling',
      hardwareRequired: true,
      storage: 'Fresh browser context for every trial'
    }};
  const browser = await chromium.launch({
    headless: config.headless,
    executablePath: config.executable,
    args: ['--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding']
  });
  report.browserVersion = browser.version();
  try {
    for (let offset = 0; offset < config.trials; offset++) {
      const trial = config.firstTrial + offset;
      // Rotate game order across rounds to reduce order-related bias.
      const shift = offset % config.games.length;
      const games = config.games.slice(shift).concat(config.games.slice(0, shift));
      for (const game of games) {
        report.runs.push(await runGame(browser, config, game, trial));
        if (!config.outputFile) {
          fs.writeFileSync(path.join(config.output, 'report.json'),
            JSON.stringify(report, null, 2) + '\n');
        }
      }
    }
    report.passed = report.runs.every(run => run.passed);
  } finally {
    report.finished = new Date().toISOString();
    if (!config.outputFile) {
      fs.writeFileSync(path.join(config.output, 'report.json'),
        JSON.stringify(report, null, 2) + '\n');
    }
    await browser.close();
  }
  process.exitCode = report.passed ? 0 : 1;
}

module.exports = {options, gameUrl, summarize, validateRun};

if (require.main === module) {
  main().catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
