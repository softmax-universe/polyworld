#!/usr/bin/env node
'use strict';

// Serve the repository root and provide Playwright through NODE_PATH.
// MONSTER_QA_URL can select another server or browser build.
const assert = require('node:assert/strict');
const {chromium} = require('playwright');

const Url = process.env.MONSTER_QA_URL ||
  'http://127.0.0.1:18934/games/monster/emscripten/monster.html';
const Seed = 42;
const WorldKey = `Polyworld Monster:/monster/${Seed}/world.json`;
const BrainKey = `Polyworld Monster:/monster/${Seed}/conversation.json`;

async function ready(page, url) {
  // Wait for a presented frame, including fresh simulation and asset loading.
  await page.goto(url, {waitUntil: 'load', timeout: 180000});
  await page.waitForFunction(() => document.querySelector('#loading').hidden,
    null, {timeout: 180000});
  await page.locator('#canvas').click({
    position: {x: 600, y: 782}, delay: 150
  });
}

async function main() {
  // A fresh isolated context verifies reload persistence without user saves.
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.MONSTER_QA_CHROMIUM || undefined,
    args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader']
  });
  try {
    const context = await browser.newContext({
      viewport: {width: 1280, height: 800}
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await ready(page, `${Url}?seed=${Seed}&mute=true`);
    await page.keyboard.type('stop', {delay: 150});
    await page.keyboard.press('Enter', {delay: 150});
    await page.waitForFunction(key => {
      const save = localStorage.getItem(key);
      return save && JSON.parse(save).messages.some(message =>
        message.role === 'creature' && message.text === 'I stopped.');
    }, BrainKey, {timeout: 30000});
    await page.waitForFunction(key => {
      const save = localStorage.getItem(key);
      return save && JSON.parse(save).tick > 0;
    }, WorldKey, {timeout: 30000});
    const before = await page.evaluate(({world, brain}) => ({
      tick: JSON.parse(localStorage.getItem(world)).tick,
      brain: localStorage.getItem(brain)
    }), {world: WorldKey, brain: BrainKey});
    await ready(page, `${Url}?seed=${Seed}&mute=true&play=false`);
    await page.evaluate(() => {
      const original = Module.polyworldFrame;
      Module.polyworldFrame = function(tick, ...rest) {
        window.monsterSaveTick = tick;
        return original.call(this, tick, ...rest);
      };
    });
    await page.waitForFunction(() => window.monsterSaveTick !== undefined);
    assert.equal(await page.evaluate(() => window.monsterSaveTick), before.tick);
    assert.equal(await page.evaluate(key => localStorage.getItem(key), BrainKey),
      before.brain);
    // A new local command appends to the restored conversation after reload.
    await page.keyboard.type('stop', {delay: 150});
    await page.keyboard.press('Enter', {delay: 150});
    await page.waitForFunction(key => {
      const save = JSON.parse(localStorage.getItem(key));
      return save.messages.filter(message =>
        message.role === 'creature' && message.text === 'I stopped.').length === 2;
    }, BrainKey, {timeout: 30000});
    assert.deepEqual(errors, []);
    console.log(`Monster browser world tick ${before.tick} and conversation survived reload.`);
    await context.close();
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
