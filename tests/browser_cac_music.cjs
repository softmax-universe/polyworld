#!/usr/bin/env node
'use strict';

// Reads actual WebAudio nodes while using real canvas settings and navigation.
// Muted browser output keeps automated checks off the user's speakers.
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const dependencies = process.env.CAC_QA_DEPS
  ? createRequire(path.resolve(process.env.CAC_QA_DEPS, 'package.json')) : require;
const {chromium} = dependencies('playwright');
const url = process.env.CAC_QA_URL || 'http://127.0.0.1:18931/cac.html';
const out = process.env.CAC_QA_OUT || path.join(__dirname, '..', 'games', 'cac',
  'build', 'qa', 'music-' + new Date().toISOString().replace(/[:.]/g, '-'));
const viewport = {width:1514, height:970};
const report = {url, out, passed:false, cases:[]};
fs.mkdirSync(out, {recursive:true});
const delay = ms=>new Promise(resolve=>setTimeout(resolve,ms));
const status = page=>page.locator('#game-status').textContent();
const preferences = page=>page.evaluate(()=>
  JSON.parse(localStorage.getItem('Polyworld CaC:settings.json') || '{}'));
const audio = page=>page.evaluate(()=>window.__cacMusicSnapshot());
const near = (a,b)=>Math.abs(a-b)<0.002;
function record(result,check,passed,evidence) {
  result.checks.push({check,passed,evidence});
  console.log(JSON.stringify({profile:result.profile,check,passed,evidence}));
  if(!passed) throw new Error(check);
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
function settingsPoint(x,y,battle=false) {
  const scale=battle?Math.min(viewport.width/1000,viewport.height/800):
    Math.min(viewport.width/800,viewport.height/640);
  const origin={x:(viewport.width-720*scale)/2,
    y:battle?(viewport.height-440*scale)/2:150*scale};
  return {x:origin.x+x*scale,y:origin.y+y*scale};
}
async function settingsClick(page,x,y,battle=false) {
  const point=settingsPoint(x,y,battle); await click(page,point.x,point.y);
}
async function volume(page,row,value,battle=false) {
  const from=settingsPoint(420,row+12,battle);
  const to=settingsPoint(210+420*value/100,row+12,battle);
  await page.mouse.move(from.x,from.y); await page.mouse.down();
  await page.mouse.move(to.x,to.y,{steps:8}); await delay(150);
  await page.mouse.up(); await delay(200);
}
async function openSettings(page) {
  await page.keyboard.press('ArrowUp',{delay:100});
  await page.keyboard.press('Enter',{delay:100});
  await wait('home settings',async()=>(await status(page)).includes('/ SettingsMenu'));
  await settingsClick(page,269,20);
}
async function loadHome(page,reload=false) {
  if(reload) await page.reload({waitUntil:'load',timeout:120000});
  else await page.goto(url,{waitUntil:'load',timeout:120000});
  await page.waitForFunction(()=>document.querySelector('#loading')?.hidden,
    null,{timeout:120000});
  await wait('home',async()=>(await status(page)).includes('/ HomeMenu'));
  await click(page,30,200);
  await wait('decoded looping theme',async()=>
    (await audio(page)).music.some(node=>node.loop&&node.frames>0));
}
async function contextFor(browser,seed) {
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  await context.addInitScript(saved=>{
    const key='Polyworld CaC:settings.json';
    if(saved && localStorage.getItem(key)===null)
      localStorage.setItem(key,JSON.stringify(saved));
    const destinations=new WeakMap();
    const music=[];
    const events=[];
    let serial=0;
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args) {
      destinations.set(this,destination);
      return connect.call(this,destination,...args);
    };
    const start=AudioBufferSourceNode.prototype.start;
    const stop=AudioBufferSourceNode.prototype.stop;
    AudioBufferSourceNode.prototype.start=function(...args) {
      const entry={id:++serial,node:this,gain:destinations.get(this),stopped:false};
      this.__cacMusicEntry=entry;
      if(this.loop) music.push(entry);
      events.push({id:entry.id,loop:this.loop,duration:this.buffer?.duration,
        gain:entry.gain?.gain?.value??null});
      return start.apply(this,args);
    };
    AudioBufferSourceNode.prototype.stop=function(...args) {
      if(this.__cacMusicEntry) this.__cacMusicEntry.stopped=true;
      return stop.apply(this,args);
    };
    window.__cacMusicSnapshot=()=>({
      music:music.map(entry=>({id:entry.id,loop:entry.node.loop,
        stopped:entry.stopped,gain:entry.gain?.gain?.value??null,
        frames:entry.node.buffer?.length,rate:entry.node.buffer?.sampleRate,
        channels:entry.node.buffer?.numberOfChannels,
        duration:entry.node.buffer?.duration})),
      events:events.slice()
    });
  },seed);
  return context;
}
async function testButton(page,x) {
  const before=(await audio(page)).events.length;
  await settingsClick(page,x,282);
  return (await audio(page)).events.slice(before).filter(event=>!event.loop);
}
async function runProfile(browser,profile,seed,expectedMusic,full=false) {
  const result={profile,checks:[],errors:[]}; report.cases.push(result);
  const context=await contextFor(browser,seed);
  const page=await context.newPage();
  page.on('pageerror',error=>result.errors.push(String(error)));
  page.on('console',message=>{if(message.type()==='error')result.errors.push(message.text());});
  try {
    await loadHome(page);
    const initial=(await audio(page)).music.at(-1);
    record(result,'theme decodes as a looping stereo source',
      initial.loop&&initial.channels===2&&initial.duration>5&&!initial.stopped,initial);
    const master=seed?.mainVolume??100;
    record(result,'initial Music level uses the expected default or saved value',
      near(initial.gain,master*expectedMusic/10000),initial.gain);
    await openSettings(page);
    await settingsClick(page,70,426);
    await wait('home after saving',async()=>(await status(page)).includes('/ HomeMenu'));
    record(result,'saved preferences preserve the expected Music value',
      (await preferences(page)).musicVolume===expectedMusic,await preferences(page));
    if(!full) {
      await loadHome(page,true);
      record(result,'reloading preserves explicit saved Music volume',
        near((await audio(page)).music.at(-1).gain,master*expectedMusic/10000));
      result.passed=result.errors.length===0;
      return;
    }
    // Pointer navigation leaves keyboard focus independent of prior menu tabs.
    const homeScale=Math.min(viewport.width/760,viewport.height/940);
    await click(page,757,485+60*homeScale);
    await wait('home settings again',async()=>(await status(page)).includes('/ SettingsMenu'));
    await settingsClick(page,269,20);
    const themeId=(await audio(page)).music.at(-1).id;
    await volume(page,112,0);
    record(result,'Music zero silences only the existing theme source',
      (await preferences(page)).musicVolume===0&&
      near((await audio(page)).music.at(-1).gain,0)&&
      (await audio(page)).music.at(-1).id===themeId);
    record(result,'combat effects remain audible with Music zero',
      (await testButton(page,80)).some(event=>event.gain>0));
    record(result,'UI effects remain audible with Music zero',
      (await testButton(page,400)).some(event=>event.gain>0));
    await volume(page,160,0);
    record(result,'FX zero disables combat without silencing UI',
      (await preferences(page)).fxVolume===0&&
      (await testButton(page,80)).length===0&&
      (await testButton(page,400)).some(event=>event.gain>0));
    await volume(page,160,100); await volume(page,208,0);
    record(result,'UI zero disables UI without silencing combat',
      (await preferences(page)).uiVolume===0&&
      (await testButton(page,400)).length===0&&
      (await testButton(page,80)).some(event=>event.gain>0));
    await volume(page,112,100); await volume(page,208,100);
    await volume(page,64,0);
    record(result,'Master zero silences Music, FX and UI',
      (await preferences(page)).mainVolume===0&&
      near((await audio(page)).music.at(-1).gain,0)&&
      (await testButton(page,80)).length===0&&
      (await testButton(page,400)).length===0);
    await volume(page,64,50); await volume(page,112,40);
    await volume(page,160,60); await volume(page,208,30);
    const levels=await preferences(page);
    const effects=await testButton(page,80);
    const ui=await testButton(page,400);
    record(result,'restored sliders apply Master once to each independent channel',
      near((await audio(page)).music.at(-1).gain,levels.mainVolume*levels.musicVolume/10000)&&
      effects.some(event=>near(event.gain,0.36*levels.mainVolume*levels.fxVolume/10000))&&
      ui.some(event=>near(event.gain,0.40*levels.mainVolume*levels.uiVolume/10000)),levels);
    await settingsClick(page,633,20);
    await settingsClick(page,465,82);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type('Music QA',{delay:20});
    await settingsClick(page,70,426);
    await wait('home after naming',async()=>(await status(page)).includes('/ HomeMenu'));
    await click(page,757,485-100*homeScale);
    await wait('single-player setup',async()=>(await status(page)).includes('/ SingleMenu'));
    await click(page,1357,914);
    await wait('battle ready',async()=>(await status(page)).includes('Ready for your action.'),60000);
    const during=await audio(page);
    record(result,'menu to battle retains one uninterrupted theme source',
      during.music.length===1&&during.music[0].id===themeId&&!during.music[0].stopped&&
      near(during.music[0].gain,levels.mainVolume*levels.musicVolume/10000));
    await page.keyboard.press('Escape',{delay:100}); await delay(300);
    record(result,'Escape overlay leaves music playing at its saved level',
      !(await audio(page)).music.at(-1).stopped&&
      near((await audio(page)).music.at(-1).gain,levels.mainVolume*levels.musicVolume/10000));
    await loadHome(page,true);
    const reloaded=await preferences(page);
    record(result,'all four customized volumes survive reload',
      ['mainVolume','musicVolume','fxVolume','uiVolume'].every(key=>
        reloaded[key]===levels[key]),reloaded);
    record(result,'reloaded theme uses saved Master times Music',
      near((await audio(page)).music.at(-1).gain,levels.mainVolume*levels.musicVolume/10000));
    result.passed=result.errors.length===0;
  } catch(error) {
    result.failure=String(error.stack||error);
    result.lastStatus=await status(page).catch(()=>null);
    result.preferences=await preferences(page).catch(()=>null);
    result.audio=await audio(page).catch(()=>null);
    result.passed=false;
  } finally { await context.close(); }
}
(async()=>{
  const browser=await chromium.launch({channel:'chromium',headless:true,
    executablePath:process.env.CAC_QA_CHROMIUM||undefined,
    args:['--mute-audio','--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding',
      '--enable-unsafe-swiftshader']});
  try {
    await runProfile(browser,'fresh',null,25,true);
    await runProfile(browser,'partial',{name:'Partial QA',mainVolume:80,
      fxVolume:60,uiVolume:70},25);
    await runProfile(browser,'saved mute',{name:'Muted QA',musicVolume:0},0);
    await runProfile(browser,'saved full',{name:'Full QA',musicVolume:100},100);
    report.passed=report.cases.every(result=>result.passed);
  } finally {
    await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log('Report: '+path.join(out,'report.json'));
    if(!report.passed) process.exitCode=1;
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
