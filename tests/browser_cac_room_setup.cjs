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
  'build', 'qa', 'room-setup-' + new Date().toISOString().replace(/[:.]/g, '-'));
const viewport = {width:1514, height:970};
const receiveDelay = Number(process.env.CAC_QA_RECEIVE_DELAY || 180);
const report = {url, server, out, receiveDelay, checks:[], steps:[], peers:[], passed:false};
const peers = [];
fs.mkdirSync(out, {recursive:true});

const kinds = ('Hello Welcome ListRooms RoomList CreateRoom JoinRoom RoomState ' +
  'ConfigureRoom ClaimSeat ReleaseSeat Ready StartMatch BeginMatch SubmitCommand ' +
  'CommandAck TickPacket AppliedTick Catchup CaughtUp ReportHash MatchStatus ' +
  'LeaveRoom KickParticipant ReturnLobby FinishMatch Received Keepalive Failure ' +
  'AbortMatch PauseMatch ResizeRoom Prepared ReadyStatus PreparedDuration ServerNotice').split(' ');

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

function decode(data) {
  const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
  assert.ok(bytes.length >= 64 && bytes.toString('ascii', 0, 4) === 'PWRM',
    'Every frame must use the shared room protocol');
  assert.equal(bytes.readUInt32LE(4), 4, 'Room protocol version');
  let offset = 64;
  function u32() { const value=bytes.readUInt32LE(offset); offset+=4; return value; }
  function u64() { const value=bytes.readBigUInt64LE(offset).toString(); offset+=8; return value; }
  function raw() {
    const size=u32();
    assert.ok(offset+size <= bytes.length, 'Bounded wire string');
    const value=bytes.subarray(offset, offset+size); offset+=size; return value;
  }
  function string() { return raw().toString('utf8'); }
  const message={kind:kinds[bytes.readUInt32LE(8)], match:bytes.readUInt32LE(20)};
  if (message.kind === 'Welcome') message.participant=u32();
  if (message.kind === 'Hello') {
    message.game=string(); message.gameplay=u32(); message.protocol=u32(); message.name=string();
  }
  if (['CreateRoom','ConfigureRoom','ResizeRoom'].includes(message.kind)) {
    message.name=string(); message.public=!!u32(); message.rate=u32();
    message.count=u32(); message.config=string();
  }
  if (message.kind === 'JoinRoom') message.room=string();
  if (message.kind === 'ClaimSeat') { message.seat=u32(); message.name=string(); }
  if (message.kind === 'RoomState') {
    message.room=string(); message.name=string(); message.owner=u32(); message.revision=u32();
    message.phase=u32(); message.rate=u32(); message.public=!!u32(); message.config=string();
    message.participants=Array.from({length:u32()},()=>({id:u32(),name:string(),connected:!!u32(),ready:!!u32()}));
    message.seats=Array.from({length:u32()},()=>({owner:u32(),name:string()}));
  }
  if (message.kind === 'SubmitCommand') {
    message.seat=u32(); message.sequence=u64(); Object.assign(message,actionPayload(raw()));
  }
  if (['ReportHash','FinishMatch'].includes(message.kind)) { message.tick=u32(); message.hash=u64(); }
  if (message.kind === 'CommandAck') { message.sequence=u64(); message.tick=u32(); }
  if (message.kind === 'TickPacket') {
    message.tick=u32();
    message.commands=Array.from({length:u32()},()=>({participant:u32(),seat:u32(),sequence:u64(),payload:raw().toString('hex')}));
  }
  if (message.kind === 'Failure') message.detail=string();
  return message;
}

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

async function openPeer(browser,role) {
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  const page=await context.newPage();
  const peer={role,context,page,messages:[],console:[]};
  peers.push(peer); report.peers.push({role,messages:peer.messages,console:peer.console});
  page.on('console',message=>{
    peer.console.push({type:message.type(),text:message.text()});
    if (message.type()==='error') console.error(role+': '+message.text());
  });
  page.on('pageerror',error=>{
    peer.console.push({type:'pageerror',text:String(error)});
    console.error(role+': '+error);
  });
  // Delay genuine relay replies to exercise edits while acknowledgements are
  // pending. Every wire frame is forwarded unchanged; no state is injected.
  await page.routeWebSocket(server,route=>{
    const upstream=route.connectToServer();
    const record=(direction,payload)=>{
      try { peer.messages.push({at:Date.now(),direction,...decode(payload)}); }
      catch(error) { peer.console.push({type:'decode',text:String(error)}); }
    };
    route.onMessage(message=>{record('out',message);upstream.send(message);});
    upstream.onMessage(message=>setTimeout(()=>{
      if(peer.closed) return;
      record('in',message);route.send(message);
    },peer.delayReplies===false ? 0 : receiveDelay));
  });
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


function check(name, passed, detail) {
  report.checks.push({name,passed,detail});
  console.log(JSON.stringify(report.checks.at(-1)));
}
async function rapidClick(page,x,y) {
  await page.mouse.move(x,y); await page.mouse.down();
  await sleep(45); await page.mouse.up(); await sleep(45);
}
async function renameRoom(host,value) {
  await click(host.page,1230,293);
  await host.page.keyboard.press('Meta+A');
  await host.page.keyboard.press('Backspace');
  await host.page.keyboard.type(value,{delay:55});
  report.nameEdits ??= [];
  report.nameEdits.push({desired:value,serverAtTypingEnd:last(host,'RoomState').name});
  await host.page.screenshot({path:path.join(out,'host-room-name-pending.png'),timeout:20000});
  await wait('room name auto-published',()=>last(host,'RoomState').name===value);
}
async function main() {
  const browser=await chromium.launch({channel:'chromium',headless:true,
    executablePath:process.env.CAC_QA_CHROMIUM || undefined,
    args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding','--enable-unsafe-swiftshader']});
  const watchdog=setTimeout(()=>{report.error='Room setup deadline';
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    for(const peer of peers) peer.closed=true;
    browser.close();process.exitCode=1;},240000);
  try {
    const host=await openPeer(browser,'host');
    await configureSettings(host);
    await multiplayer(host);
    await shot(host,'default-room-name');
    await click(host.page,1232,570);
    await wait('room created',()=>last(host,'RoomState')?.room);
    await wait('automatic human seat',()=>last(host,'RoomState')?.seats.some(s=>s.name==='Human'));
    check('default room name follows the saved player name',
      last(host,'CreateRoom','out').name==="Treeform's room",last(host,'CreateRoom','out').name);
    assert.equal(last(host,'RoomState').seats.length,2);
    for(let i=0;i<3;i++) await click(host.page,1438,368);
    await sleep(1200);
    await shot(host,'five-slots');
    const grown=last(host,'RoomState').seats.length===5;
    check('selecting five slots opens five authoritative seats',grown,last(host,'RoomState').seats.length);
    // The last slot must open its picker and accept a bundled bot policy.
    await click(host.page,330,262+72*4);
    await shot(host,'fifth-seat-picker');
    await click(host.page,757,485);
    await sleep(600);
    const fifth=last(host,'RoomState').seats[4];
    check('fifth seat accepts a bot',!!fifth && fifth.owner!==0 && fifth.name!=='Human',fifth);
    await renameRoom(host,"Treeform's automatic room");
    check('paced room-name typing auto-publishes without losing focus',
      last(host,'RoomState').name==="Treeform's automatic room");
    await renameRoom(host,"Treeform's room");
    const seedBefore=JSON.parse(last(host,'RoomState').config).seed;
    for(let i=0;i<5;i++) await rapidClick(host.page,1438,430);
    await wait('rapid seed changes auto-published',()=>
      JSON.parse(last(host,'RoomState').config).seed===seedBefore+5);
    check('rapid seed changes during acknowledgement retain every click',
      JSON.parse(last(host,'RoomState').config).seed===seedBefore+5);
    const limitBefore=JSON.parse(last(host,'RoomState').config).maxActions;
    await click(host.page,1438,492);
    await wait('action limit auto-published',()=>
      JSON.parse(last(host,'RoomState').config).maxActions===limitBefore+1000);
    check('action limit applies automatically',true);
    await click(host.page,820,263);
    await shot(host,'class-picker');
    await click(host.page,820,368);
    await wait('class selection auto-published',()=>
      JSON.parse(last(host,'RoomState').config).classes[0]==='Mage');
    check('class selection applies automatically',true);
    await shot(host,'settings-auto-saved-before-fill');
    await click(host.page,225,790);
    await sleep(1200);
    await shot(host,'filled-with-bots');
    const slots=last(host,'RoomState').seats;
    const filled=slots.length===5 && slots.every(s=>s.owner!==0) && slots.filter(s=>s.name==='Human').length===1;
    check('Fill empty slots assigns all four bots',filled,slots);
    if(filled) {
      await click(host.page,547,914);
      await wait('host and bots ready',()=>last(host,'RoomState').participants.some(p=>p.ready));
      await shot(host,'five-player-ready');
      // Delay is scoped to lobby synchronization. Drain pending replies before
      // starting, so the rendering test does not become a catch-up load test.
      host.delayReplies=false;
      await sleep(receiveDelay+50);
      await click(host.page,1357,914);
      await wait('five-player match starts',()=>last(host,'BeginMatch'),30000);
      await wait('five-player rendered battle',async()=>/Multiplayer match: 5 players/.test(await status(host)),30000);
      await shot(host,'five-player-battle');
      check('filled five-player room starts a real match',true,await status(host));
      await wait('host action and network ready',async()=>{
        const request=last(host,'Catchup','out');
        const reply=last(host,'CaughtUp');
        const settled=!request || (reply && reply.at>=request.at &&
          Date.now()-request.at>250);
        return settled && (await status(host)).includes('Ready for your action.');
      },45000);
      await host.page.keyboard.press('Enter',{delay:140});
      await wait('human action submitted',()=>host.messages.some(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seat===0));
      await wait('bots submit decisions',()=>host.messages.some(m=>m.direction==='out' && m.kind==='SubmitCommand' && m.category===0 && m.seat>0),30000);
      check('human and bot inputs run in five-player match',true);
    }
    const errors=host.console.filter(c=>['decode','pageerror','error'].includes(c.type));
    check('no browser runtime errors',errors.length===0,errors);
    report.passed=report.checks.every(c=>c.passed);
  } catch(error) {
    report.error=String(error.stack||error); console.error(report.error);
    for(const peer of peers) { try{await shot(peer,'failure');}catch{} }
  } finally {
    clearTimeout(watchdog);
    for(const peer of peers) peer.closed=true;
    await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log('Report: '+path.join(out,'report.json'));
    if(!report.passed) process.exitCode=1;
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
