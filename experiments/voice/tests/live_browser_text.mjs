import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.VOICE_PLAYWRIGHT_PATH ||
  '../build/web-tests/node_modules/playwright');
const browser = await chromium.launch();
const page = await browser.newPage({viewport:{width:1280,height:980}});
const errors = [];
page.on('pageerror', error => errors.push(error.message));
try {
  await page.goto(process.env.VOICE_WEB_URL || 'http://127.0.0.1:8001/');
  await page.waitForFunction(() => !document.getElementById('connect').disabled);
  await page.click('#connect');
  await page.waitForFunction(() => JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())).connected, {timeout:30000});
  await page.fill('#message', 'Please say exactly: Voice Lab is ready.');
  await page.click('#send');
  await page.waitForFunction(() => {
    const state=JSON.parse(Module.UTF8ToString(Module._voiceBrowserState()));
    return state.lines.some(line => !line.user && line.text.length > 0) && state.speaking;
  }, {timeout:30000});
  const state=await page.evaluate(() => JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())));
  console.log(JSON.stringify({connected:state.connected,speaking:state.speaking,listening:state.listening,latencyMs:state.latencyMs,lines:state.lines,error:state.error}));
  await page.click('#disconnect');
  await page.waitForFunction(() => !JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())).connected);
  await page.click('#connect');
  await page.waitForFunction(() => JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())).connected);
  await page.click('#disconnect');
  assert.deepEqual(errors,[]);
  console.log('Live browser typed reply, audible playback state, disconnect and reconnect passed.');
} catch(error) {
  console.log(await page.evaluate(() => typeof Module._voiceBrowserState === 'function' ? Module.UTF8ToString(Module._voiceBrowserState()) : document.body.innerText));
  throw error;
} finally { await browser.close(); }
