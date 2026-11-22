#!/usr/bin/env node
'use strict';

// Observes actual WebAudio playback while driving only real canvas controls.
// Chrome is muted at its output, so the test never plays through speakers.
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const dependencies = process.env.CAC_QA_DEPS
  ? createRequire(path.resolve(process.env.CAC_QA_DEPS, 'package.json')) : require;
const {chromium} = dependencies('playwright');
const url = process.env.CAC_QA_URL || 'http://127.0.0.1:18931/cac.html';
const out = process.env.CAC_QA_OUT || path.join(__dirname, '..', 'games', 'cac',
  'build', 'qa', 'audio-' + new Date().toISOString().replace(/[:.]/g, '-'));
const viewport = {width:1514, height:970};
const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'polyworld',
  'soundassets.nim'), 'utf8');
const clips = [];
for (const match of source.matchAll(/SoundClip\(cue:\s*(\w+),\s*path:\s*"([^"]+)"\)/g)) {
  let clip = clips.find(item=>item.path===match[2]);
  if (!clip) { clip={path:match[2],cues:[]}; clips.push(clip); }
  clip.cues.push(match[1]);
}
const combat = new Set(['SwordSound','ImpactSound','BowSound','MagicSound',
  'FireSound','HealSound','HumanDeathSound','CreatureDeathSound']);
const cards = new Set(['CardDrawSound','CardPlaySound']);
const report = {url, out, passed:false, cases:[]};
fs.mkdirSync(out, {recursive:true});
const delay = ms=>new Promise(resolve=>setTimeout(resolve,ms));
const status = page=>page.locator('#game-status').textContent();
const preferences = page=>page.evaluate(()=>
  JSON.parse(localStorage.getItem('Polyworld CaC:settings.json') || '{}'));
const events = page=>page.evaluate(()=>window.__cacAudioEvents.slice());
const isEffect = event=>event.cues.some(cue=>cards.has(cue)||combat.has(cue));
function record(result, check, passed, evidence) {
  result.checks.push({check,passed,evidence});
  console.log(JSON.stringify({mode:result.mode,check,passed,evidence}));
  if (!passed) throw new Error(check);
}
async function wait(label,predicate,timeout=45000) {
  const until=Date.now()+timeout;
  while(Date.now()<until) { if(await predicate()) return; await delay(100); }
  throw new Error('Timeout: '+label);
}
async function click(page,x,y) {
  await page.mouse.move(x,y); await delay(90); await page.mouse.down();
  await delay(90); await page.mouse.up(); await delay(250);
}
async function escape(page) {
  await page.keyboard.press('Escape',{delay:100}); await delay(250);
}
async function battleClick(page,y) {
  const scale=Math.min(viewport.width/1000,viewport.height/800);
  await click(page,viewport.width/2,viewport.height/2+(y-280)*scale);
}
function settingsPoint(x,y) {
  const scale=Math.min(viewport.width/1000,viewport.height/800);
  return {x:(viewport.width-720*scale)/2+x*scale,
    y:(viewport.height-440*scale)/2+y*scale};
}
async function settingsClick(page,x,y) {
  const point=settingsPoint(x,y); await click(page,point.x,point.y);
}
async function openSoundSettings(page) {
  await escape(page); await battleClick(page,286);
  const tabWidth=(720-160-24)/4;
  await settingsClick(page,160+(tabWidth+8)+tabWidth/2,20);
}
async function volume(page,row,value) {
  const from=settingsPoint(420,row+12);
  const to=settingsPoint(value===0?210:630,row+12);
  await page.mouse.move(from.x,from.y); await page.mouse.down();
  await page.mouse.move(to.x,to.y,{steps:8}); await delay(150);
  await page.mouse.up(); await delay(200);
}
async function closeSettings(page) {
  await settingsClick(page,70,426); await battleClick(page,161);
  await page.mouse.move(30,200); await delay(300);
}
async function nextHumanTurn(page) {
  const before=Number((await status(page)).match(/Turn (\d+)\./)?.[1]);
  await page.keyboard.press('Enter',{delay:100});
  await wait('next human turn',async()=>{
    const text=await status(page);
    return Number(text.match(/Turn (\d+)\./)?.[1])>before &&
      text.includes('Ready for your action.');
  },60000);
  await delay(300);
}
async function startGame(page,mode) {
  await page.goto(mode==='duel'?url+'?player=1&players=2&seed=42':url,
    {waitUntil:'load',timeout:120000});
  await page.waitForFunction(()=>document.querySelector('#loading')?.hidden,
    null,{timeout:120000});
  if(mode==='duel') {
    await wait('hero chooser',async()=>/Choose your (class|hero)/.test(await status(page)));
    await page.keyboard.press('1',{delay:100});
  } else {
    await wait('home',async()=>(await status(page)).includes('/ HomeMenu'));
    await page.keyboard.press('ArrowUp',{delay:100});
    await page.keyboard.press('Enter',{delay:100});
    await wait('home settings',async()=>(await status(page)).includes('/ SettingsMenu'));
    const settingsScale=Math.min(viewport.width/800,viewport.height/640);
    const origin={x:(viewport.width-720*settingsScale)/2,y:150*settingsScale};
    await click(page,origin.x+633*settingsScale,origin.y+20*settingsScale);
    await click(page,origin.x+465*settingsScale,origin.y+82*settingsScale);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type('Audio QA',{delay:20});
    await click(page,origin.x+80*settingsScale,origin.y+426*settingsScale);
    await wait('home after naming player',async()=>(await status(page)).includes('/ HomeMenu'));
    const scale=Math.min(viewport.width/760,viewport.height/940);
    await click(page,757,485-100*scale);
    await wait('single-player setup',async()=>(await status(page)).includes('/ SingleMenu'));
    await click(page,1357,914);
  }
  await wait('human ready',async()=>(await status(page)).includes('Ready for your action.'),60000);
  await page.mouse.move(30,200); await delay(300);
}
async function runCase(browser,mode) {
  const result={mode,checks:[],errors:[]}; report.cases.push(result);
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  await context.addInitScript(manifest=>{
    window.__cacAudioEvents=[];
    const destinations=new WeakMap();
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args) {
      destinations.set(this,destination);
      return connect.call(this,destination,...args);
    };
    const start=AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start=function(...args) {
      const buffers=typeof AL==='undefined'?[]:Object.values(AL.buffers)
        .filter(buffer=>buffer.audioBuf).sort((a,b)=>a.id-b.id);
      const index=buffers.findIndex(buffer=>buffer.audioBuf===this.buffer);
      const clip=manifest[index] || {path:'unknown',cues:[]};
      const samples=this.buffer?.getChannelData(0);
      let peak=0;
      if(samples) for(let i=0;i<samples.length;i++) peak=Math.max(peak,Math.abs(samples[i]));
      window.__cacAudioEvents.push({time:performance.now(),path:clip.path,
        cues:clip.cues,frames:this.buffer?.length,peak,
        gain:destinations.get(this)?.gain?.value ?? null});
      return start.apply(this,args);
    };
  },clips);
  const page=await context.newPage();
  page.on('pageerror',error=>result.errors.push(String(error)));
  page.on('console',message=>{if(message.type()==='error')result.errors.push(message.text());});
  try {
    await startGame(page,mode);
    const buffers=await page.evaluate(()=>Object.values(AL.buffers)
      .filter(buffer=>buffer.audioBuf).map(buffer=>({frames:buffer.audioBuf.length,
        rate:buffer.audioBuf.sampleRate,channels:buffer.audioBuf.numberOfChannels})));
    const effects=buffers.filter(buffer=>buffer.channels===1);
    record(result,'curated audio buffers decode',effects.length===clips.length &&
      effects.every(buffer=>buffer.frames>0),{expected:clips.length,loaded:effects.length});
    record(result,'opening deal plays decoded card audio',(await events(page))
      .some(event=>event.cues.includes('CardDrawSound') && event.peak>0 && event.gain>0));
    let mark=(await events(page)).length;
    await delay(1500);
    record(result,'idle frames do not repeat card effects',
      !(await events(page)).slice(mark).some(isEffect));
    for(let turn=0;turn<4 && !(await events(page)).some(event=>
      event.cues.some(cue=>combat.has(cue)));turn++) await nextHumanTurn(page);
    const played=await events(page);
    record(result,'confirmed gameplay plays card and combat audio',
      played.some(event=>event.cues.includes('CardPlaySound')) &&
      played.some(event=>event.cues.some(cue=>combat.has(cue))),
      [...new Set(played.flatMap(event=>event.cues))]);

    await page.keyboard.press('Enter',{delay:100});
    await openSoundSettings(page);
    await page.mouse.move(30,200); await delay(300);
    mark=(await events(page)).length;
    await delay(2200);
    record(result,'Settings suppresses battle effects',
      !(await events(page)).slice(mark).some(isEffect));
    await volume(page,160,0);
    const effectsOff=await preferences(page);
    record(result,'effects slider reaches zero',effectsOff.fxVolume===0,effectsOff.fxVolume);
    mark=(await events(page)).length;
    await settingsClick(page,400,282);
    record(result,'UI audio remains audible with effects muted',
      (await events(page)).slice(mark).some(event=>event.cues.includes('ClickSound')&&event.gain>0));
    mark=(await events(page)).length;
    await closeSettings(page);
    await wait('human turn after menu',async()=>(await status(page)).includes('Ready for your action.'),60000);
    record(result,'effects zero suppresses real gameplay audio',
      !(await events(page)).slice(mark).some(isEffect));

    await openSoundSettings(page);
    await volume(page,64,0);
    record(result,'Master slider reaches zero',(await preferences(page)).mainVolume===0);
    mark=(await events(page)).length;
    await settingsClick(page,400,282);
    await closeSettings(page);
    await nextHumanTurn(page);
    record(result,'Master zero suppresses UI and gameplay audio',
      (await events(page)).length===mark);
    await openSoundSettings(page);
    await volume(page,64,100); await volume(page,160,100);
    const restored=await preferences(page);
    record(result,'saved channel levels restore',restored.mainVolume===100&&restored.fxVolume===100);
    await closeSettings(page);
    mark=(await events(page)).length;
    await page.keyboard.press('Enter',{delay:100});
    await wait('resumed gameplay sound',async()=>
      (await events(page)).slice(mark).some(isEffect));
    record(result,'gameplay audio resumes after unmuting',
      (await events(page)).slice(mark).some(isEffect));
    result.events=await events(page);
    result.passed=result.errors.length===0;
  } catch(error) {
    result.failure=String(error.stack||error);
    result.lastStatus=await status(page).catch(()=>null);
    result.events=await events(page).catch(()=>[]);
    result.preferences=await preferences(page).catch(()=>null);
    result.passed=false;
  } finally { await context.close(); }
  console.log(JSON.stringify({mode,passed:result.passed,checks:result.checks,
    failure:result.failure,lastStatus:result.lastStatus,errors:result.errors}));
}
(async()=>{
  const browser=await chromium.launch({channel:'chromium',headless:true,
    executablePath:process.env.CAC_QA_CHROMIUM || undefined,
    args:['--mute-audio','--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding',
      '--enable-unsafe-swiftshader']});
  try {
    for(const mode of (process.env.CAC_AUDIO_MODES || 'duel,ring').split(','))
      await runCase(browser,mode);
    report.passed=report.cases.length>0&&report.cases.every(result=>result.passed);
  } finally {
    await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log('Report: '+path.join(out,'report.json'));
    if(!report.passed) process.exitCode=1;
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
