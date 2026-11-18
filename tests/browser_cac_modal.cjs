#!/usr/bin/env node
'use strict';

// Drives only real canvas events. Browser storage and rendered pixels are read
// to verify settings ownership; game state is never injected or mutated.
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
// Install Playwright and pngjs locally, or set CAC_QA_DEPS to their package root.
const dependencies = process.env.CAC_QA_DEPS
  ? createRequire(path.resolve(process.env.CAC_QA_DEPS, 'package.json')) : require;
const {chromium} = dependencies('playwright');
const {PNG} = dependencies('pngjs');
const viewport = {width:1514, height:970};
const url = process.env.CAC_QA_URL || 'http://127.0.0.1:18931/cac.html';
const out = process.env.CAC_QA_OUT || path.join(__dirname, '..', 'games', 'cac',
  'build', 'qa', 'modal-' + new Date().toISOString().replace(/[:.]/g, '-'));
const report = {url, out, passed:false, cases:[]};
fs.mkdirSync(out, {recursive:true});
const delay = ms => new Promise(resolve=>setTimeout(resolve,ms));
function battleMenuPoint(y) {
  const scale=Math.min(viewport.width/1000,viewport.height/800);
  return {x:viewport.width/2,y:viewport.height/2+(y-280)*scale};
}
async function battleMenuClick(page,y) {
  const point=battleMenuPoint(y);
  await click(page,point.x,point.y);
}
async function wait(label, predicate, timeout=30000) {
  const until=Date.now()+timeout;
  while(Date.now()<until) { if(await predicate()) return; await delay(100); }
  throw new Error('Timeout: '+label);
}
async function click(page,x,y) {
  await page.mouse.move(x,y); await delay(100); await page.mouse.down();
  await delay(100); await page.mouse.up(); await delay(300);
}
async function replaceText(page,x,y,value) {
  await click(page,x,y); await page.keyboard.press('Meta+A');
  await page.keyboard.press('Backspace'); await page.keyboard.type(value,{delay:20});
}
const status = page => page.locator('#game-status').textContent();
const preferences = page => page.evaluate(()=>JSON.parse(localStorage.getItem('Polyworld CaC:settings.json') || '{}'));
async function shot(page,mode,name) {
  const file=path.join(out,mode+'-'+name+'.png');
  await page.screenshot({path:file,timeout:30000});
  return PNG.sync.read(fs.readFileSync(file));
}
function difference(a,b,roi) {
  let changed=0,total=0;
  for(let y=roi.y;y<roi.y+roi.height;y++) for(let x=roi.x;x<roi.x+roi.width;x++) {
    const offset=(y*a.width+x)*4;
    const distance=Math.abs(a.data[offset]-b.data[offset])+
      Math.abs(a.data[offset+1]-b.data[offset+1])+Math.abs(a.data[offset+2]-b.data[offset+2]);
    if(distance>45) changed++;
    total++;
  }
  return changed/total;
}
async function configureName(page,result) {
  await wait('home ready',async()=>(await status(page)).includes('/ HomeMenu'));
  await page.mouse.move(30,200);
  await shot(page,'home','normal');
  // The browser has three home actions. Up wraps from Single Player to Settings.
  await page.keyboard.press('ArrowUp',{delay:120});
  await page.keyboard.press('Enter',{delay:120});
  await wait('keyboard opens home Settings',async()=>(await status(page)).includes('/ SettingsMenu'));
  result.checks.push({check:'home keyboard navigation opens Settings',passed:true});
  const scale=Math.min(viewport.width/800,viewport.height/640);
  const origin={x:(viewport.width-720*scale)/2,y:150*scale};
  await click(page,origin.x+633*scale,origin.y+20*scale);
  await replaceText(page,origin.x+465*scale,origin.y+82*scale,'Modal QA');
  await click(page,origin.x+80*scale,origin.y+426*scale);
  await wait('home after saving name',async()=>(await status(page)).includes('/ HomeMenu'));
}
async function startRing(page,result) {
  await configureName(page,result);
  const scale=Math.min(viewport.width/760,viewport.height/940);
  await page.mouse.move(30,200); await delay(300);
  const homeNeutral=await shot(page,'home','buttons-normal');
  await page.mouse.move(757,485-100*scale); await delay(300);
  const homeHover=await shot(page,'home','button-hover');
  const homeDifference=difference(homeNeutral,homeHover,
    {x:510,y:360,width:490,height:80});
  result.checks.push({check:'custom home button reacts to pointer hover',
    passed:homeDifference>0.01,value:homeDifference});
  await click(page,757,485-100*scale);
  await wait('pointer opens single-player setup',async()=>(await status(page)).includes('/ SingleMenu'));
  result.checks.push({check:'home pointer opens single-player setup',passed:true});
  await click(page,1357,914);
  await wait('human ring turn',async()=>(await status(page)).includes('Ready for your action.'),45000);
}
async function runCase(browser,mode) {
  const result={mode,errors:[],checks:[]}; report.cases.push(result);
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  const page=await context.newPage();
  page.on('pageerror',error=>result.errors.push(String(error)));
  page.on('console',message=>{if(message.type()==='error')result.errors.push(message.text());});
  try {
    await page.goto(mode==='duel'?url+'?human=1&players=2&seed=42':url,{waitUntil:'load',timeout:120000});
    await page.waitForFunction(()=>document.querySelector('#loading')?.hidden,null,{timeout:120000});
    if(mode==='ring') await startRing(page,result);
    else {
      await wait('hero chooser',async()=>/Choose your (class|hero)/.test(await status(page)));
      await page.keyboard.press('1',{delay:120});
      await wait('human duel ready',async()=>(await status(page)).includes('Ready for your action.'),45000);
    }
    result.before=await status(page);
    await page.mouse.move(30,200); await delay(300);
    const exposedNeutral=await shot(page,mode,'battle');
    const handPoint={x:510,y:890};
    await page.mouse.move(handPoint.x,handPoint.y); await delay(400);
    const exposedHover=await shot(page,mode,'battle-over-card');
    const handRoi={x:465,y:845,width:75,height:65};
    result.exposedHoverDifference=difference(exposedNeutral,exposedHover,handRoi);
    result.checks.push({check:'positive control: uncovered card reacts to hover',
      passed:result.exposedHoverDifference>0.10,value:result.exposedHoverDifference});
    await page.mouse.move(30,200); await delay(300);
    await page.keyboard.press('Escape',{delay:120}); await delay(400);
    await shot(page,mode,'escape-menu');
    if(mode==='ring') {
      await page.setViewportSize({width:960,height:640}); await delay(400);
      await shot(page,mode,'escape-menu-small');
      await page.setViewportSize(viewport); await delay(400);
    }
    await battleMenuClick(page,226);
    await shot(page,mode,'paused-menu');
    // Escape dismisses the panel but leaves an explicitly paused battle paused.
    await page.keyboard.press('Escape',{delay:120}); await delay(400);
    await page.keyboard.press('Enter',{delay:120}); await delay(500);
    result.checks.push({check:'Pause blocks End Turn after dismissing the panel',
      passed:(await status(page))===result.before});
    await page.keyboard.press('Escape',{delay:120}); await delay(400);
    await battleMenuClick(page,226);
    await battleMenuClick(page,286); await delay(400);
    await page.mouse.move(30,200); await delay(300);
    const beforeHover=await shot(page,mode,'settings-neutral');
    // The same opaque hand-art region must stop reacting beneath the modal.
    // This excludes the animated sky and is calibrated by the exposed control.
    await page.mouse.move(handPoint.x,handPoint.y); await delay(400);
    const afterHover=await shot(page,mode,'settings-over-card');
    result.backgroundDifference=difference(beforeHover,afterHover,handRoi);
    result.checks.push({check:'no background inspector while settings owns input',
      passed:result.backgroundDifference<0.06,value:result.backgroundDifference});
    await click(page,handPoint.x,handPoint.y);
    await page.keyboard.press('Enter',{delay:120});
    result.checks.push({check:'card click and End Turn are blocked behind settings',
      passed:(await status(page))===result.before});
    const initial=await preferences(page);
    // Overlay scale and origin come from shared beginOverlay(720,440).
    const scale=Math.min(viewport.width/1000,viewport.height/800);
    const origin={x:(viewport.width-720*scale)/2,y:(viewport.height-440*scale)/2};
    const tabWidth=(720-160-24)/4;
    const tab=column=>({x:origin.x+(160+column*(tabWidth+8)+tabWidth/2)*scale,y:origin.y+20*scale});
    const display=tab(0), network=tab(3);
    await click(page,display.x,display.y);
    await click(page,origin.x+225*scale,origin.y+218*scale);
    await delay(500);
    result.afterFps=await preferences(page);
    result.checks.push({check:'display FPS radio responds to pointer input',passed:result.afterFps.fps===30,
      before:initial.fps,after:result.afterFps.fps});
    await shot(page,mode,'settings-fps');
    await click(page,network.x,network.y);
    // Resume's old location is blank on this tab. It must not activate the
    // Escape menu beneath Settings or let the subsequent Enter end the turn.
    const underlyingResume=battleMenuPoint(161);
    await click(page,underlyingResume.x,underlyingResume.y);
    await page.keyboard.press('Enter',{delay:120});
    result.checks.push({check:'underlying Escape Resume is inactive in Settings',
      passed:(await status(page))===result.before});
    await replaceText(page,origin.x+460*scale,origin.y+82*scale,'Modal edited '+mode);
    await shot(page,mode,'settings-networking');
    // Save and Back must leave only the Escape menu on screen.
    await click(page,origin.x+70*scale,origin.y+426*scale);
    await delay(400);
    result.saved=await preferences(page);
    result.checks.push({check:'networking tab edits and save work',
      passed:result.saved.name==='Modal edited '+mode,name:result.saved.name});
    await shot(page,mode,'settings-saved');
    // Resume from the Escape menu, then End Turn to prove input ownership returns.
    await battleMenuClick(page,161); await delay(400);
    await shot(page,mode,'resumed');
    result.after=await status(page);
    result.checks.push({check:'settings and underlying clicks leave battle state unchanged',
      passed:result.after===result.before});
    if(result.checks.every(check=>check.passed)) {
      await page.keyboard.press('Enter',{delay:120});
      const startingTurn=Number(result.before.match(/Turn (\d+)\./)[1]);
      await wait('resumed End Turn changes battle',async()=>
        Number((await status(page)).match(/Turn (\d+)\./)?.[1])>startingTurn,15000);
      result.checks.push({check:'battle input resumes after closing modal',passed:true});
    }
    await page.keyboard.press('Escape',{delay:120}); await delay(400);
    await battleMenuClick(page,362);
    await wait('Escape menu returns to main menu',async()=>(await status(page)).includes('/ HomeMenu'));
    result.checks.push({check:'Escape menu returns to the main menu',passed:true});
    await shot(page,mode,'returned-home');
    if(mode==='ring') {
      await page.setViewportSize({width:960,height:640}); await delay(400);
      await shot(page,'home','small');
    }
    result.passed=result.errors.length===0 && result.checks.every(check=>check.passed);
  } catch(error) {
    result.failure=String(error.stack||error);
    result.passed=false;
    try{await shot(page,mode,'failure'); result.lastStatus=await status(page);}catch{}
  } finally { await context.close(); }
  console.log(JSON.stringify({mode:result.mode,checks:result.checks,passed:result.passed,failure:result.failure,errors:result.errors}));
}
(async()=>{
  const browser=await chromium.launch({channel:'chromium',headless:true,
    executablePath:process.env.CAC_QA_CHROMIUM || undefined,
    args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding','--enable-unsafe-swiftshader']});
  const watchdog=setTimeout(()=>{report.error='Modal regression deadline';
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    browser.close();process.exitCode=1;},300000);
  try {
    for(const mode of (process.env.CAC_MODAL_MODE || 'ring,duel').split(',')) await runCase(browser,mode);
    report.passed=report.cases.length>0 && report.cases.every(result=>result.passed);
  } finally {
    clearTimeout(watchdog); await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log('Report: '+path.join(out,'report.json'));
    if(!report.passed) process.exitCode=1;
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
