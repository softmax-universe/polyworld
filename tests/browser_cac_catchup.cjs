#!/usr/bin/env node
'use strict';

// Acceptance uses real canvas input and reads protocol evidence from WebSockets.
// It never injects commands or mutates the game's authoritative state.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
// Install Playwright locally, or point CAC_QA_DEPS at an existing package root.
const dependencies = process.env.CAC_QA_DEPS
  ? createRequire(path.resolve(process.env.CAC_QA_DEPS, 'package.json')) : require;
const {chromium} = dependencies('playwright');
const url = process.env.CAC_QA_URL || 'http://127.0.0.1:18931/cac.html';
const server = process.env.CAC_QA_SERVER || 'ws://127.0.0.1:19931/ws';
const out = process.env.CAC_QA_OUT || path.join(__dirname, '..', 'games', 'cac',
  'build', 'qa', 'catchup-' + new Date().toISOString().replace(/[:.]/g, '-'));
const viewport = {width:1514, height:970};
const delays = (process.env.CAC_QA_DELAYS || '0,180').split(',').map(Number);
const observeMs = Number(process.env.CAC_QA_OBSERVE_MS || 25000);
const report = {url, server, out, delays, observeMs, checks:[], cases:[], steps:[], peers:[], passed:false};
const peers = [];
fs.mkdirSync(out, {recursive:true});

const {decodeRoom} = require('./room_protocol.cjs');

function actionPayload(bytes) {
  assert.ok(bytes.length >= 12, 'CaC command header must be complete');
  const result = {category:bytes.readUInt32LE(0), revision:bytes.readUInt32LE(4),
    player:bytes.readInt32LE(8), payload:bytes.toString('hex')};
  if (result.category === 0) {
    assert.ok(bytes.length >= 32, 'CaC action must be complete');
    result.action = bytes.readUInt32LE(12);
    result.hand = bytes.readInt32LE(16);
    result.attacker = bytes.readInt32LE(20);
  }
  return result;
}

function decode(data) { return decodeRoom(data, actionPayload); }

const sleep = ms => new Promise(resolve=>setTimeout(resolve,ms));
async function wait(label, predicate, timeout=20000) {
  const deadline=Date.now()+timeout;
  while (Date.now()<deadline) {
    if (await predicate()) return;
    await sleep(100);
  }
  throw new Error('Timeout: '+label);
}
function step(text) { report.steps.push(text); console.log(text); }
function last(peer,kind,direction='in') {
  return peer.messages.findLast(message=>message.direction===direction && message.kind===kind);
}
async function click(page,x,y) {
  await page.bringToFront(); await page.mouse.move(x,y);
  await page.waitForTimeout(80); await page.mouse.down();
  await page.waitForTimeout(120); await page.mouse.up(); await page.waitForTimeout(250);
}
async function text(page,x,y,value) {
  await click(page,x,y); await page.keyboard.press('Meta+A');
  await page.keyboard.press('Backspace'); await page.keyboard.type(value,{delay:25});
}
async function shot(peer,name) {
  await peer.page.bringToFront(); await peer.page.waitForTimeout(200);
  await peer.page.screenshot({path:path.join(out,peer.role+'-'+name+'.png'),timeout:20000});
}
async function status(peer) { return await peer.page.locator('#game-status').textContent(); }

async function openPeer(browser,role,receiveDelay) {
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  const page=await context.newPage();
  const peer={role,context,page,messages:[],console:[],receiveDelay};
  peers.push(peer); report.peers.push({role,messages:peer.messages,console:peer.console});
  page.on('console',message=>{
    peer.console.push({type:message.type(),text:message.text()});
    if (message.type()==='error') console.error(role+': '+message.text());
  });
  page.on('pageerror',error=>{
    peer.console.push({type:'pageerror',text:String(error)});
    console.error(role+': '+error);
  });
  const record=(direction,payload)=>{
    try { peer.messages.push({at:Date.now(),direction,...decode(payload)}); }
    catch(error) { peer.console.push({type:'decode',text:String(error)}); }
  };
  if(receiveDelay>0) {
    // Delay unchanged genuine relay frames; preserve message order.
    await page.routeWebSocket(server,route=>{
      const upstream=route.connectToServer();
      route.onMessage(message=>{record('out',message);upstream.send(message);});
      upstream.onMessage(message=>setTimeout(()=>{
        if(peer.closed) return;
        record('in',message);route.send(message);
      },receiveDelay));
    });
  } else {
    // The normal case uses the browser's direct WebSocket, without routing.
    page.on('websocket',socket=>{
      socket.on('framesent',({payload})=>record('out',payload));
      socket.on('framereceived',({payload})=>record('in',payload));
    });
  }
  await page.goto(url,{waitUntil:'load',timeout:120000});
  await page.waitForFunction(()=>window.Module && document.querySelector('#loading')?.hidden,
    null,{timeout:120000});
  await shot(peer,'home');
  return peer;
}

async function multiplayer(peer) {
  // CaC's shared-theme home uses 480-pixel buttons, 80 pixels apart.
  const scale=Math.min(viewport.width/760,viewport.height/940);
  await click(peer.page,viewport.width/2,viewport.height/2+(-130+80+26)*scale);
  await wait(peer.role+' connected to relay',()=>last(peer,'Welcome'));
  assert.equal(last(peer,'Hello','out').game,'awm');
  assert.equal(last(peer,'Hello','out').name,'Treeform',
    'The name saved through Settings must be used by the connection');
  await shot(peer,'multiplayer');
}

async function configureSettings(peer) {
  const homeScale=Math.min(viewport.width/760,viewport.height/940);
  await click(peer.page,757,485+(-130+160+30)*homeScale);
  await shot(peer,'settings-display');
  const scale=Math.min(viewport.width/800,viewport.height/640);
  const origin={x:(viewport.width-720*scale)/2,y:150*scale};
  await click(peer.page,origin.x+633*scale,origin.y+20*scale);
  await text(peer.page,origin.x+465*scale,origin.y+82*scale,'Treeform');
  await text(peer.page,origin.x+465*scale,origin.y+130*scale,server);
  await shot(peer,'settings-networking');
  await click(peer.page,origin.x+80*scale,origin.y+426*scale);
  await shot(peer,'settings-saved');
  step(peer.role+': opened Settings and saved name/server through the shared panel');
}


function check(name,passed,detail) {
  report.checks.push({name,passed,detail});
  console.log(JSON.stringify(report.checks.at(-1)));
}
async function startFive(host) {
  await configureSettings(host);
  await multiplayer(host);
  await click(host.page,1232,570);
  await wait('room created',()=>last(host,'RoomState')?.room);
  await wait('human seat claimed',()=>{
    const seat=last(host,'RoomState')?.seats[0];
    return seat?.kind===0 && seat.owner===last(host,'Welcome').participant;
  });
  for(let i=0;i<3;i++) await click(host.page,1438,368);
  await wait('five seats',()=>last(host,'RoomState').seats.length===5);
  await click(host.page,225,790);
  await wait('all five occupied',()=>last(host,'RoomState').seats.every(seat=>seat.owner!==0));
  assert.ok(last(host,'RoomState').participants.every(p=>!p.ready),
    'Catch-up scenario starts without a ready toggle');
  await click(host.page,1357,914);
  await wait('match begins',()=>last(host,'BeginMatch'),30000);
  await wait('rendered battle',async()=>/Multiplayer match: 5 players/.test(await status(host)),30000);
}
async function observe(host) {
  const result={role:host.role,receiveDelay:host.receiveDelay,samples:[],polls:[],attempts:[]};
  report.cases.push(result);
  await startFive(host);
  const begin=Date.now();
  result.begin=begin;
  let lastStatus='', nextAttempt=begin+2000;
  let capturedCatchup=false;
  while(Date.now()-begin<observeMs) {
    const text=await status(host), now=Date.now();
    result.polls.push({at:now,ready:text.includes('Ready for your action.'),catching:text.includes('Catching up with the match')});
    if(text!==lastStatus) {
      result.samples.push({at:now,text}); lastStatus=text;
    }
    if(!capturedCatchup && text.includes('Catching up with the match')) {
      capturedCatchup=true;
      await shot(host,'catching-up');
    }
    const human=host.messages.filter(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seat===0);
    if(human.length===0 && result.attempts.length<5 && now>=nextAttempt && text.includes('Ready for your action.')) {
      const attempt={at:Date.now(),text,lastCatchup:last(host,'Catchup','out'),lastCaughtUp:last(host,'CaughtUp')};
      result.attempts.push(attempt);
      await host.page.keyboard.press('Enter',{delay:140});
      await sleep(400);
      attempt.accepted=host.messages.some(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seat===0 && m.at>=attempt.at);
      nextAttempt=Date.now()+1800;
    }
    await sleep(80);
  }
  result.end=Date.now();
  const messages=host.messages.filter(m=>m.at>=begin);
  result.catchups=messages.filter(m=>m.direction==='out' && m.kind==='Catchup');
  result.caughtUp=messages.filter(m=>m.direction==='in' && m.kind==='CaughtUp');
  result.applied=messages.filter(m=>m.direction==='out' && m.kind==='AppliedTick');
  result.botActions=messages.filter(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seatKind===1 && m.seat>0).length;
  result.humanActions=messages.filter(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seatKind===0 && m.seat===0).length;
  const entries=result.polls.filter((poll,index)=>poll.catching && (index===0 || !result.polls[index-1].catching));
  result.catchupStatusChanges=entries.length;
  result.steadyCatchups=result.catchups.filter(m=>m.at>=begin+5000).length;
  result.steadyCatchupStatusChanges=entries.filter(poll=>poll.at>=begin+5000).length;
  let readyStart=0;
  result.longestReadyMs=0;
  for(const poll of result.polls) {
    if(poll.ready && !poll.catching) {
      if(!readyStart) readyStart=poll.at;
      result.longestReadyMs=Math.max(result.longestReadyMs,poll.at-readyStart);
    } else readyStart=0;
  }
  result.lastApplied=last(host,'AppliedTick','out');
  result.lastPacket=last(host,'TickPacket');
  result.errors=host.console.filter(m=>['pageerror','error','decode'].includes(m.type));
  await shot(host,'after-observation');
  // History probes can remain healthy even when the browser is already caught
  // up. The regression is repeated recovery UI/input blocking, not wire polling.
  check(host.role+': no repeated catch-up status on an intact connection',result.steadyCatchupStatusChanges<=1,{wireProbes:result.catchups.length,statusChanges:result.catchupStatusChanges,steadyStatusChanges:result.steadyCatchupStatusChanges});
  check(host.role+': human Ready state remains stable',result.longestReadyMs>=500,result.longestReadyMs);
  check(host.role+': a ready human action is accepted',result.attempts.length>0 && result.attempts[0].accepted,result.attempts.map(m=>({at:m.at,accepted:m.accepted})));
  check(host.role+': bots make progress',result.botActions>0,result.botActions);
  check(host.role+': no browser errors',result.errors.length===0,result.errors);
  console.log(JSON.stringify({role:host.role,catchups:result.catchups.length,steadyCatchups:result.steadyCatchups,statusChanges:result.catchupStatusChanges,attempts:result.attempts.map(m=>m.accepted),lastApplied:result.lastApplied?.tick,lastPacket:result.lastPacket?.tick}));
  host.closed=true;
  await host.context.close();
}
(async()=>{
  const browser=await chromium.launch({channel:'chromium',headless:true,
    executablePath:process.env.CAC_QA_CHROMIUM || undefined,
    args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding','--enable-unsafe-swiftshader']});
  const watchdog=setTimeout(()=>{report.error='Catchup regression deadline';
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    for(const peer of peers) peer.closed=true;
    browser.close();process.exitCode=1;},300000);
  try {
    for(const delay of delays) {
      const host=await openPeer(browser,delay===0?'direct':'delay-'+delay,delay);
      await observe(host);
    }
    report.passed=report.checks.every(c=>c.passed);
  } catch(error) {
    report.error=String(error.stack||error); console.error(report.error);
    for(const peer of peers) { if(!peer.closed) try{await shot(peer,'failure');}catch{} }
  } finally {
    clearTimeout(watchdog);
    for(const peer of peers) peer.closed=true;
    await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log('Report: '+path.join(out,'report.json'));
    if(!report.passed) process.exitCode=1;
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
