#!/usr/bin/env node
'use strict';
// Real canvas input only. No injected gameplay commands, native clients or bots.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');
const {decodePayload,runSocial} = require('./browser_lvd_social.cjs');
const socialEnabled = process.env.LVD_QA_SOCIAL === '1';
const buildingEnabled = process.env.LVD_QA_BUILDING === '1';
const scratch = process.env.LVD_QA_DEPS || '/Users/me/.hermes/cache/scratch/lvd-browser-qa';
const deps = createRequire(path.join(scratch, 'package.json'));
const {chromium} = deps('playwright');
const {PNG} = deps('pngjs');
// In the fixed fresh-match camera this ROI contains only the selected worker's
// yellow outline (not HUD/building banners). Pixel proof is not game-state mutation.
function outlinedWorker(file) {
 const p=PNG.sync.read(fs.readFileSync(file));let n=0,xsum=0,ysum=0;
 for(let y=380;y<610;y++)for(let x=590;x<800;x++){
  const i=(y*p.width+x)*4,[r,g,b]=p.data.subarray(i,i+3);
  if(r>200&&g>180&&b<100){n++;xsum+=x;ysum+=y;}
 }
 assert.ok(n>50,'selected worker yellow outline must be visible');
 return {x:xsum/n,y:ysum/n,pixels:n};
}
const url = process.env.LVD_QA_URL || 'http://10.10.11.114:4173/gameshowcase/games/light-vs-dark/play/?server=ws%3A%2F%2F127.0.0.1%3A9911%2Fws';
const out = process.env.LVD_QA_OUT || path.join(scratch, 'run-' + new Date().toISOString().replace(/[:.]/g, '-'));
fs.mkdirSync(out, {recursive:true});
const report = {url, out, socialEnabled, buildingEnabled, steps:[], peers:[], passed:false};
const {decodeRoom} = require('./room_protocol.cjs');
function decode(data) { return decodeRoom(data, decodePayload); }

const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function wait(label, fn, timeout=12000){const end=Date.now()+timeout;while(Date.now()<end){if(await fn())return;await sleep(100);}throw new Error('Timeout: '+label);}
function step(s){report.steps.push(s);console.log(s);}
async function click(p,x,y,button='left'){await p.bringToFront();await p.mouse.move(x,y);await p.waitForTimeout(100);await p.mouse.down({button});await p.waitForTimeout(140);await p.mouse.up({button});await p.waitForTimeout(300);}
async function text(p,x,y,s){await click(p,x,y);await p.keyboard.press('Meta+A');await p.keyboard.press('Backspace');await p.keyboard.type(s,{delay:70});}
async function shot(peer,name){await peer.page.bringToFront();await peer.page.waitForTimeout(150);await peer.page.screenshot({path:path.join(out,peer.role+'-'+name+'.png'),timeout:10000});}
function last(peer,kind,direction='in'){return peer.messages.findLast(m=>m.direction===direction&&m.kind===kind);}
async function main(){
 const browser=await chromium.launch({executablePath:process.env.LVD_QA_CHROMIUM || undefined,headless:process.env.LVD_QA_HEADLESS==='1',args:['--disable-background-timer-throttling','--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding','--enable-unsafe-swiftshader']});
 const deadlineMs=buildingEnabled?420000:(socialEnabled?300000:180000);
 const watchdog=setTimeout(()=>{report.error='Global '+deadlineMs/1000+'-second deadline';process.exitCode=1;fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));browser.close();},deadlineMs);
 try{
  for(const role of ['host','guest']){
   const context=await browser.newContext({viewport:{width:1514,height:970},deviceScaleFactor:1});
   const page=await context.newPage();const peer={role,context,page,messages:[],console:[]};report.peers.push({role,messages:peer.messages,console:peer.console});peers.push(peer);
   const cdp=await context.newCDPSession(page);await cdp.send('Network.enable');await cdp.send('Network.setCacheDisabled',{cacheDisabled:true});
   page.on('console',m=>peer.console.push({type:m.type(),text:m.text()}));page.on('pageerror',e=>peer.console.push({type:'pageerror',text:String(e)}));
   page.on('websocket',ws=>{peer.socketUrl=ws.url();for(const [event,direction] of [['framesent','out'],['framereceived','in']])ws.on(event,({payload})=>{try{peer.messages.push({at:Date.now(),direction,...decode(payload)});}catch(e){peer.console.push({type:'decode',text:String(e)});}});});
   await page.goto(url,{waitUntil:'load',timeout:60000});
   await page.waitForFunction(()=>window.Module && document.querySelector('#loading')?.hidden,null,{timeout:60000});
   await page.evaluate(()=>{window.__lvdFrames=[];const original=Module.polyworldFrame;Module.polyworldFrame=function(tick,mismatches){window.__lvdFrames.push({tick,mismatches,at:performance.now()});if(window.__lvdFrames.length>10000)window.__lvdFrames.shift();return original.apply(this,arguments);};});
   await shot(peer,'home');await click(page,757,633);await text(page,757,435,'QA '+role);await page.keyboard.press('Enter',{delay:140});
   await wait(role+' welcomed',()=>last(peer,'Welcome'));await shot(peer,'multiplayer');step(role+': Main menu → Multiplayer, named QA '+role+', welcomed');
  }
  const [host,guest]=peers;assert.notEqual(host.context,guest.context);assert.notEqual(last(host,'Welcome').participant,last(guest,'Welcome').participant);
  await click(host.page,1349,472);await host.page.waitForTimeout(500);
  await click(host.page,1349,472);await shot(host,'create-private');await click(host.page,1232,570);
  await wait('private created',()=>last(host,'RoomState')?.room);
  assert.equal(last(host,'CreateRoom','out').public,false,'room must be explicitly private');
  const room=last(host,'RoomState').room;report.room=room;
  await text(guest.page,1232,738,room);await click(guest.page,1232,832);
  await wait('guest joined',()=>last(guest,'RoomState')?.room===room);step('Private room created; guest joined through invite field');
  // Shrink default roster through host UI to exactly two human slots.
  for(let n=last(host,'RoomState').seats.length;n>2;n--){await click(host.page,375,669);await wait('roster resized to '+(n-1),()=>last(host,'RoomState').seats.length===n-1);}
  for(const [index,peer] of peers.entries()){
   await click(peer.page,index?710:260,321);await shot(peer,'seat-picker');await click(peer.page,757,339);
   await wait(peer.role+' owns human seat',()=>last(peer,'RoomState').seats[index]?.owner===last(peer,'Welcome').participant && last(peer,'RoomState').seats[index]?.kind===0);
   await shot(peer,'human-seat');
  }
  for(const peer of peers)await wait(peer.role+' sees both occupied human seats',()=>
    last(peer,'RoomState').seats.every(seat=>seat.owner!==0&&seat.kind===0));
  const setupRevision=last(host,'RoomState').revision;
  await click(host.page,547,914);
  for(const peer of peers)await wait(peer.role+' sees cosmetic host readiness',()=>
    last(peer,'RoomState').participants.some(p=>p.id===last(host,'Welcome').participant&&p.ready));
  for(const peer of peers){
   const snapshot=last(peer,'RoomState');
   assert.equal(snapshot.revision,setupRevision,'Cosmetic readiness preserves setup revision');
   assert.equal(snapshot.participants.find(p=>p.id===last(guest,'Welcome').participant).ready,false);
  }
  await shot(host,'mixed-readiness');step('Both participants own Human seats; host starts with guest unready');await click(host.page,1357,914);
  for(const peer of peers)await wait(peer.role+' BeginMatch',()=>last(peer,'BeginMatch'),25000);
  const initialization=last(host,'BeginMatch');
  assert.equal(initialization.hash,last(host,'StartMatch','out').hash);
  for(const peer of peers){
   const begin=last(peer,'BeginMatch');
   assert.equal(begin.config,initialization.config);assert.equal(begin.hash,initialization.hash);
   assert.deepEqual(begin.seats,initialization.seats);assert.deepEqual(begin.participants,initialization.participants);
  }
  await sleep(2500);for(const peer of peers)await shot(peer,'started');step('Host started match; both browsers received BeginMatch');
  if(process.env.LVD_QA_STOP_AFTER_START==='1')throw new Error('Diagnostic stop after Start (not an acceptance pass)');
  // QA read-only snapshot contract documented in the adjacent README.
  const movementFailures=[];
  for(const peer of peers){
   try {
   const hasSnapshot=await peer.page.evaluate(()=>typeof Module.polyworldLvdQA==='function');
   const before=hasSnapshot?await peer.page.evaluate(()=>Module.polyworldLvdQA()):null;
   // Before an instrumented build exists, still exercise the real failing input.
   // These points were verified on the 1514x970 fresh-match screenshots.
   const unit=before?before.units.find(u=>u.owner===before.humanPlayer&&u.alive&&u.screen&&u.moveTarget):{screen:{x:755,y:447},moveTarget:{x:680,y:510}};
   assert.ok(unit,peer.role+': a visible owned movable unit and legal ground target are required');
   await click(peer.page,unit.screen.x,unit.screen.y);await shot(peer,'selected');
   const count=peer.messages.filter(m=>m.direction==='out'&&m.kind==='SubmitCommand').length;
   await click(peer.page,unit.moveTarget.x,unit.moveTarget.y,'right');
   await wait(peer.role+' right-click SubmitCommand',()=>peer.messages.filter(m=>m.direction==='out'&&m.kind==='SubmitCommand').length>count);
   const command=last(peer,'SubmitCommand','out');assert.equal(command.action[0],1,'right-click clear ground must submit ActionMove');
   assert.equal(command.seat,peers.indexOf(peer),'command must target own human seat');
   assert.equal(command.seatKind,0,'human input carries a human controller kind');
   if(hasSnapshot){
    await wait(peer.role+' authoritative unit displacement',async()=>{const after=await peer.page.evaluate(()=>Module.polyworldLvdQA());const moved=after.units.find(u=>u.id===unit.id);return after.tick>before.tick&&moved&&Math.hypot(moved.x-unit.x,moved.y-unit.y)>0.5;});
   }else{
    const initial=outlinedWorker(path.join(out,peer.role+'-selected.png'));
    await sleep(3500);await shot(peer,'after-rightclick');
    const final=outlinedWorker(path.join(out,peer.role+'-after-rightclick.png'));
    const delta=Math.hypot(final.x-initial.x,final.y-initial.y);
    report.peers.find(p=>p.role===peer.role).visualMovement={initial,final,delta};
    assert.ok(delta>15,peer.role+': selected worker must move >15 screen pixels after real ActionMove; observed '+delta.toFixed(2));
   }
   // New commands are acknowledged by inclusion in an authoritative tick;
   // A standalone discarded CommandAck must never count as acceptance.
   const owner=last(peer,'Welcome').participant;
   const acknowledged=()=>peer.messages.find(m=>m.direction==='in'&&(
     (m.kind==='CommandAck'&&!m.discarded&&m.sequence===command.sequence)||
     (m.kind==='TickPacket'&&m.commands.some(c=>c.participant===owner&&c.seat===command.seat&&c.seatKind===command.seatKind&&c.sequence===command.sequence))));
   await wait(peer.role+' authoritative command receipt',acknowledged);
   report.peers.find(p=>p.role===peer.role).commandTick=acknowledged().tick;
   await shot(peer,'moved');step(peer.role+': own-unit left click, ground right click, SubmitCommand and actual movement');
   }catch(e){movementFailures.push(String(e));await shot(peer,'movement-failure');}
  }
  assert.deepEqual(movementFailures,[],'both human movement paths must pass');
  await wait('shared post-command checkpoint',()=>{const hs=host.messages.filter(m=>m.direction==='out'&&m.kind==='ReportHash');const gs=guest.messages.filter(m=>m.direction==='out'&&m.kind==='ReportHash');const finalAck=Math.max(...report.peers.map(p=>p.commandTick));return hs.some(h=>h.tick>finalAck&&gs.some(g=>g.match===h.match&&g.tick===h.tick&&g.hash===h.hash));},20000);
  if(socialEnabled)await runSocial({peers,report,wait,click,shot,last,step});
  if(buildingEnabled)await require('./browser_lvd_building.cjs').runBuilding({peers,report,wait,click,shot,last,step});
  for(const peer of peers){const frames=await peer.page.evaluate(()=>window.__lvdFrames);assert.ok(frames.some(f=>f.tick>0));assert.ok(frames.every(f=>f.mismatches===0));assert.deepEqual(peer.console.filter(c=>c.type==='decode'),[],'wire decoder must not silently lose evidence');}
  report.passed=true;step('PASS: both human moves'+(socialEnabled?', both chats and reciprocal peace/alliance UI actions':'')+(buildingEnabled?', left-click overlapping farm and completed FOOD capacity':'')+' and same-match/same-tick peer hashes agree');
 }catch(e){report.error=e.stack;console.error(e.stack);for(const peer of peers){try{await shot(peer,'failure');report.peers.find(p=>p.role===peer.role).frames=await peer.page.evaluate(()=>window.__lvdFrames);}catch{}}process.exitCode=1;
 }finally{clearTimeout(watchdog);fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));await browser.close();console.log('Artifacts: '+out);}
}
const peers=[];
main().catch(e=>{console.error(e);process.exitCode=1;});
