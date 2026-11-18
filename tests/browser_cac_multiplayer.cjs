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
  'build', 'qa', 'browser-' + new Date().toISOString().replace(/[:.]/g, '-'));
const viewport = {width:1514, height:970};
const report = {url, server, out, steps:[], peers:[], passed:false};
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
  if (process.env.CAC_QA_SCREENSHOTS!=='0')
    await peer.page.screenshot({path:path.join(out,peer.role+'-'+name+'.png'),timeout:20000});
}
async function status(peer) { return await peer.page.locator('#game-status').textContent(); }

async function openPeer(browser,role) {
  const context=await browser.newContext({viewport,deviceScaleFactor:1});
  const page=await context.newPage();
  const peer={role,context,page,messages:[],console:[],websockets:0};
  peers.push(peer); report.peers.push({role,messages:peer.messages,console:peer.console});
  page.on('console',message=>{
    peer.console.push({type:message.type(),text:message.text()});
    if (message.type()==='error') console.error(role+': '+message.text());
  });
  page.on('pageerror',error=>{
    peer.console.push({type:'pageerror',text:String(error)});
    console.error(role+': '+error);
  });
  page.on('websocket',socket=>{
    peer.websockets++;
    for (const [event,direction] of [['framesent','out'],['framereceived','in']]) {
      socket.on(event,({payload})=>{
        try { peer.messages.push({at:Date.now(),direction,...decode(payload)}); }
        catch (error) { peer.console.push({type:'decode',text:String(error)}); }
      });
    }
  });
  const launchUrl=new URL(url);
  launchUrl.searchParams.set('server',server);
  await page.goto(launchUrl.href,{waitUntil:'load',timeout:120000});
  await page.waitForFunction(()=>window.Module && document.querySelector('#loading')?.hidden,
    null,{timeout:120000});
  await wait(role+' starts on the main menu with a server URL',async()=>
    (await status(peer)).includes('/ HomeMenu'));
  assert.equal(peer.messages.length,0,
    'A server URL must not connect before choosing Multiplayer');
  await shot(peer,'home');
  return peer;
}

async function reloadFromLink(peer,room='') {
  // Saved valid names must not allow URL parameters to bypass the main menu.
  const launchUrl=new URL(url);
  launchUrl.searchParams.set('server',server);
  if(room) launchUrl.searchParams.set('room',room);
  const before=peer.websockets;
  await peer.page.goto(launchUrl.href,{waitUntil:'load',timeout:120000});
  await peer.page.waitForFunction(()=>window.Module && document.querySelector('#loading')?.hidden,
    null,{timeout:120000});
  await wait(peer.role+' saved-name link opens HomeMenu',async()=>
    (await status(peer)).includes('/ HomeMenu'));
  await sleep(1200);
  assert.equal(peer.websockets,before,'Saved-name links must not open any WebSocket');
  const saved=await peer.page.evaluate(()=>JSON.parse(localStorage.getItem('Polyworld CaC:settings.json')));
  assert.equal(saved.name,'QA '+peer.role);
  step(peer.role+': '+(room?'server and room invite':'server-only link')+' stays at HomeMenu with saved valid name and no connection');
}

async function multiplayer(peer) {
  // CaC's shared-theme home uses 480-pixel buttons, 80 pixels apart.
  const scale=Math.min(viewport.width/760,viewport.height/940);
  await click(peer.page,viewport.width/2,viewport.height/2+(-130+80+26)*scale);
  await wait(peer.role+' connected to relay',()=>last(peer,'Welcome'));
  assert.equal(last(peer,'Hello','out').game,'awm');
  assert.equal(last(peer,'Hello','out').name,'QA '+peer.role,
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
  await text(peer.page,origin.x+465*scale,origin.y+82*scale,'QA '+peer.role);
  await text(peer.page,origin.x+465*scale,origin.y+130*scale,server);
  await shot(peer,'settings-networking');
  await click(peer.page,origin.x+80*scale,origin.y+426*scale);
  await shot(peer,'settings-saved');
  step(peer.role+': opened Settings and saved name/server through the shared panel');
}

async function localBattle(peer) {
  const scale=Math.min(viewport.width/760,viewport.height/940);
  await click(peer.page,757,485+(-130+30)*scale);
  await shot(peer,'single-player-setup');
  await click(peer.page,1357,914);
  await wait('local human battle ready',async()=>
    (await status(peer)).includes('Ready for your action.'),40000);
  assert.match(await status(peer),/2 players/);
  assert.match(await status(peer),/Tower Arena\./);
  assert.ok((await status(peer)).includes('Active QA '+peer.role));
  await shot(peer,'single-player-battle');
  await peer.page.keyboard.press('Enter',{delay:140});
  await wait('local End Turn advanced battle',async()=>
    /Turn [2-9][0-9]*\./.test(await status(peer)),20000);
  await peer.page.keyboard.press('Escape',{delay:120});
  await shot(peer,'single-player-menu');
  await click(peer.page,551,571);
  await wait('return to main menu without click-through',async()=>
    (await status(peer)).includes('/ HomeMenu'),5000);
  await shot(peer,'returned-home');
  assert.equal(peer.messages.filter(message=>message.kind==='SubmitCommand').length,0,
    'Local battle must not send network commands');
  step('Single-player setup launched, accepted End Turn and returned to the main menu');
}

async function confirmAction(peer, command) {
  const seat=peers.indexOf(peer);
  assert.equal(command.seat,seat);
  assert.equal(command.player,seat);
  for (const receiver of peers) {
    await wait(receiver.role+' confirmed '+peer.role+' action '+command.sequence,()=>
      receiver.messages.some(message=>message.direction==='in' &&
        message.kind==='TickPacket' && message.commands.some(receipt=>
          receipt.participant===last(peer,'Welcome').participant &&
          receipt.sequence===command.sequence && receipt.payload===command.payload)));
  }
  const receipt=peer.messages.find(message=>message.direction==='in' &&
    message.kind==='TickPacket' && message.commands.some(candidate=>
      candidate.sequence===command.sequence && candidate.seat===seat));
  report.peers[seat].actionTick=receipt.tick;
}

async function playTowerCards(host, guest) {
  // The compact table's near hand spans the bottom center from either seat.
  // Try visible cards through normal clicks, and target the opposite hero when
  // needed. Later turns give expensive starting hands enough energy to play.
  const played=new Set();
  for (let turn=0;turn<6 && played.size<2;turn++) {
    const peer=(await status(host)).includes('Active QA host.') ? host : guest;
    await peer.page.bringToFront();
    await wait(peer.role+' card input ready',async()=>
      (await status(peer)).includes('Ready for your action.'),30000);
    if (!played.has(peer.role)) {
      const before=peer.messages.length;
      const cardCommand=()=>peer.messages.slice(before).find(message=>
        message.direction==='out' && message.kind==='SubmitCommand' &&
        message.category===0 && message.action===1);
      for (const x of [1000,900,800,700,600,500,400]) {
        await click(peer.page,x,745);
        if (!cardCommand()) await click(peer.page,1250,330);
        if (cardCommand()) break;
        await peer.page.mouse.click(1100,760,{button:'right',delay:120});
      }
      if (cardCommand()) {
        await confirmAction(peer,cardCommand());
        played.add(peer.role);
        await sleep(1200);
        await shot(peer,'tower-card-play');
        step(peer.role+': Tower Arena card click confirmed by both clients');
      }
    }
    await peer.page.mouse.click(1100,760,{button:'right',delay:120});
    await wait(peer.role+' ready after card play',async()=>
      (await status(peer)).includes('Ready for your action.'),30000);
    const before=peer.messages.length;
    await peer.page.keyboard.press('Enter',{delay:140});
    await wait(peer.role+' next turn submission',()=>peer.messages.slice(before).some(message=>
      message.direction==='out' && message.kind==='SubmitCommand' && message.action===3));
    await confirmAction(peer,last(peer,'SubmitCommand','out'));
    const nextName='QA '+(peer===host?'guest':'host');
    for (const receiver of peers) await wait(receiver.role+' next card turn',async()=>
      (await status(receiver)).includes('Active '+nextName));
  }
  assert.deepEqual([...played].sort(),['guest','host'],
    'Both mirrored Tower Arena seats must accept a real card click');
}

async function main() {
  const browser=await chromium.launch({channel:'chromium',headless:process.env.CAC_QA_HEADLESS!=='0',
    executablePath:process.env.CAC_QA_CHROMIUM || undefined,args:[
    '--mute-audio','--disable-background-timer-throttling','--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding','--enable-unsafe-swiftshader']});
  const watchdog=setTimeout(()=>{
    report.error='Global acceptance deadline'; process.exitCode=1;
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    browser.close();
  },600000);
  try {
    const host=await openPeer(browser,'host');
    if (process.env.CAC_QA_INSPECT==='1') {
      step('Home inspected; diagnostic pause is not an acceptance pass');
      await sleep(30000);
      return;
    }
    await configureSettings(host);
    await reloadFromLink(host);
    if (process.env.CAC_QA_SKIP_LOCAL!=='1') await localBattle(host);
    await multiplayer(host);
    const guest=await openPeer(browser,'guest');
    await configureSettings(guest);
    await click(host.page,1349,472);
    await shot(host,'create-private');
    await click(host.page,1232,570);
    await wait('private room created',()=>last(host,'RoomState')?.room);
    assert.equal(last(host,'CreateRoom','out').public,false);
    const room=last(host,'RoomState').room; report.room=room;
    await reloadFromLink(guest,room);
    await localBattle(guest);
    assert.equal(guest.websockets,0,'Local play must preserve invite without connecting');
    await multiplayer(guest);
    assert.notEqual(last(host,'Welcome').participant,last(guest,'Welcome').participant);
    await wait('guest joined',()=>last(guest,'RoomState')?.room===room);
    step('Distinct clients created and joined a private Polyworld room');
    assert.equal(last(host,'RoomState').seats.length,2);
    for (const [seat,peer] of peers.entries()) {
      await click(peer.page,330,262+72*seat);
      await shot(peer,'seat-picker');
      await click(peer.page,757,339);
      await wait(peer.role+' owns human seat',()=>{
        const slot=last(peer,'RoomState').seats[seat];
        return slot.owner===last(peer,'Welcome').participant && slot.kind===0;
      });
    }
    for (const peer of peers) {
      await wait(peer.role+' sees both human seats',()=>
        last(peer,'RoomState').seats.every(seat=>seat.owner!==0 && seat.kind===0));
      assert.ok(last(peer,'RoomState').participants.every(participant=>!participant.ready),
        'Nobody must have readied before the host starts');
      assert.ok(!peer.messages.some(message=>message.direction==='out' &&
        message.kind==='ReadyStatus'),
        'Starting must not require a cosmetic ready toggle');
    }
    await shot(host,'unready-start');
    await click(host.page,1357,914);
    for (const peer of peers) await wait(peer.role+' BeginMatch',()=>last(peer,'BeginMatch'));
    const initialization=last(host,'BeginMatch');
    assert.equal(initialization.hash,last(host,'StartMatch','out').hash);
    for (const peer of peers) {
      const begin=last(peer,'BeginMatch');
      assert.equal(begin.config,initialization.config);
      assert.equal(begin.hash,initialization.hash);
      assert.deepEqual(begin.seats,initialization.seats);
      assert.deepEqual(begin.participants,initialization.participants);
    }
    await sleep(3000);
    for (const peer of peers) {
      assert.match(await status(peer),/Tower Arena\./);
      await shot(peer,'started');
    }
    step('Host started both human seats with nobody ready');
    const first=(await status(host)).includes('Active QA host.') ? host : guest;
    const order=[first,first===host?guest:host];
    for (const peer of order) {
      const seat=peers.indexOf(peer);
      await peer.page.bringToFront();
      await wait(peer.role+' human action enabled',async()=>
        (await status(peer)).includes('Ready for your action.'),30000);
      const count=peer.messages.filter(message=>message.direction==='out'&&message.kind==='SubmitCommand').length;
      await peer.page.keyboard.press('Enter',{delay:140});
      await wait(peer.role+' End Turn submission',()=>peer.messages.filter(
        message=>message.direction==='out'&&message.kind==='SubmitCommand').length>count);
      const command=last(peer,'SubmitCommand','out');
      assert.equal(command.category,0); assert.equal(command.action,3);
      assert.equal(command.seatKind,0,'human input carries a human controller kind');
      assert.equal(command.seat,seat); assert.equal(command.player,seat);
      for (const receiver of peers) {
        await wait(receiver.role+' received '+peer.role+' action',()=>receiver.messages.some(message=>
          message.direction==='in' && message.kind==='TickPacket' && message.commands.some(receipt=>
            receipt.participant===last(peer,'Welcome').participant && receipt.sequence===command.sequence &&
            receipt.seat===seat && receipt.seatKind===command.seatKind &&
            receipt.payload===command.payload)));
      }
      const receipt=peer.messages.find(message=>message.direction==='in' && message.kind==='TickPacket' &&
        message.commands.some(candidate=>candidate.sequence===command.sequence && candidate.seat===seat));
      report.peers[seat].actionTick=receipt.tick;
      const nextName='QA '+(seat===0?'guest':'host');
      for (const receiver of peers) await wait(receiver.role+' applied next turn',async()=>
        (await status(receiver)).includes('Active '+nextName));
      await sleep(1700); await shot(peer,'after-end-turn');
      step(peer.role+': End Turn acknowledged identically by both clients');
    }
    await playTowerCards(host,guest);
    const finalTick=Math.max(...report.peers.map(peer=>peer.actionTick));
    await wait('matching post-action hash',()=>host.messages.some(hostHash=>
      hostHash.direction==='out' && hostHash.kind==='ReportHash' && hostHash.tick>finalTick &&
      guest.messages.some(guestHash=>guestHash.direction==='out' && guestHash.kind==='ReportHash' &&
        guestHash.match===hostHash.match && guestHash.tick===hostHash.tick && guestHash.hash===hostHash.hash)),30000);
    for (const peer of peers) {
      assert.deepEqual(peer.console.filter(entry=>['decode','pageerror'].includes(entry.type)),[]);
      assert.ok(!peer.messages.some(message=>message.kind==='RoomState'&&message.phase===4),'No desynchronization');
    }
    const firstMatch=last(host,'BeginMatch').match;
    await host.page.bringToFront();
    await host.page.keyboard.press('Escape',{delay:120});
    await shot(host,'online-match-menu');
    await click(host.page,551,571);
    for (const peer of peers) {
      await wait(peer.role+' returned to same lobby',()=>
        last(peer,'RoomState')?.room===room && last(peer,'RoomState')?.phase===0,30000);
      await wait(peer.role+' displays returned lobby',async()=>
        (await status(peer)).includes('/ LobbyMenu'));
      await shot(peer,'returned-lobby');
    }
    const rematchRevision=last(host,'RoomState').revision;
    for (const [peer,flag] of [[guest,true],[guest,false],[host,true]]) {
      const participantId=last(peer,'Welcome').participant;
      await click(peer.page,547,914);
      await wait(peer.role+' cosmetic ReadyStatus '+flag,()=>
        last(peer,'ReadyStatus','out')?.flag===flag);
      for (const receiver of peers) {
        await wait(receiver.role+' sees '+peer.role+' ready='+flag,()=>
          last(receiver,'RoomState').participants.some(participant=>
            participant.id===participantId && participant.ready===flag));
        assert.equal(last(receiver,'RoomState').revision,rematchRevision,
          'Cosmetic readiness must not change the setup revision');
      }
    }
    for (const peer of peers) {
      const participants=last(peer,'RoomState').participants;
      assert.equal(participants.find(participant=>
        participant.id===last(host,'Welcome').participant).ready,true);
      assert.equal(participants.find(participant=>
        participant.id===last(guest,'Welcome').participant).ready,false);
    }
    await shot(host,'mixed-readiness');
    await click(host.page,1357,914);
    for (const peer of peers) await wait(peer.role+' same-room rematch',()=>
      last(peer,'BeginMatch')?.match>firstMatch);
    assert.equal(last(host,'BeginMatch').match,last(guest,'BeginMatch').match);
    await wait('rematch authoritative hash agreement',()=>host.messages.some(hostHash=>
      hostHash.direction==='out' && hostHash.kind==='ReportHash' && hostHash.match>firstMatch &&
      guest.messages.some(guestHash=>guestHash.direction==='out' && guestHash.kind==='ReportHash' &&
        guestHash.match===hostHash.match && guestHash.tick===hostHash.tick && guestHash.hash===hostHash.hash)),30000);
    for (const peer of peers) {
      assert.match(await status(peer),/Tower Arena\./);
      await shot(peer,'rematch');
      assert.deepEqual(peer.console.filter(entry=>['decode','pageerror'].includes(entry.type)),[]);
      assert.ok(!peer.messages.some(message=>message.kind==='RoomState'&&message.phase===4),
        'No desynchronization during return and rematch');
    }
    step('Ready toggled on and off cosmetically; host started a synchronized rematch with guest unready');
    await host.page.keyboard.press('Escape',{delay:120});
    await click(host.page,551,571);
    for (const peer of peers) await wait(peer.role+' returned for ring setup',async()=>
      (await status(peer)).includes('/ LobbyMenu'));
    const towerMatch=last(host,'BeginMatch').match;
    await click(host.page,1438,368);
    await wait('third seat published',()=>last(host,'RoomState').seats.length===3);
    await click(host.page,225,790);
    await wait('third seat filled with a bot',()=>last(host,'RoomState').seats.every(seat=>seat.owner!==0));
    await click(host.page,1357,914);
    for (const peer of peers) {
      await wait(peer.role+' three-player match',()=>last(peer,'BeginMatch')?.match>towerMatch);
      await wait(peer.role+' Ring Arena rendered',async()=>
        /3 players.*Ring Arena\./.test(await status(peer)),30000);
      await shot(peer,'ring-three-player');
    }
    step('Three-player rematch switches both clients back to Ring Arena');
    await host.page.keyboard.press('Escape',{delay:120});
    await click(host.page,551,571);
    for (const peer of peers) await wait(peer.role+' returned from Ring Arena',async()=>
      (await status(peer)).includes('/ LobbyMenu'));
    const ringMatch=last(host,'BeginMatch').match;
    await click(host.page,1220,368);
    await wait('two seats restored',()=>last(host,'RoomState').seats.length===2);
    await click(host.page,1357,914);
    for (const peer of peers) {
      await wait(peer.role+' restored two-player match',()=>last(peer,'BeginMatch')?.match>ringMatch);
      await wait(peer.role+' Tower Arena restored',async()=>
        /2 players.*Tower Arena\./.test(await status(peer)),30000);
      await sleep(2500);
      await peer.page.mouse.move(757,200);
      await shot(peer,'tower-restored');
      assert.deepEqual(peer.console.filter(entry=>['error','decode','pageerror'].includes(entry.type)),[]);
      assert.ok(!peer.messages.some(message=>message.kind==='Failure' ||
        (message.kind==='RoomState'&&message.phase===4)),
        'No protocol failures or desynchronization while changing arenas');
    }
    step('Returning from three to two seats restores Tower Arena on both clients');
    report.passed=true;
    step('PASS: real human inputs and later authoritative hashes agree');
  } catch (error) {
    report.error=error.stack; console.error(error.stack); process.exitCode=1;
    for (const peer of peers) {
      try { await shot(peer,'failure'); report.peers.find(item=>item.role===peer.role).status=await status(peer); }
      catch {}
    }
  } finally {
    clearTimeout(watchdog);
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    await browser.close(); console.log('Artifacts: '+out);
  }
}

main().catch(error=>{console.error(error);process.exitCode=1;});
