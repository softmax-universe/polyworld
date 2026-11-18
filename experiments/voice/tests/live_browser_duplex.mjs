import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.VOICE_PLAYWRIGHT_PATH ||
  '../build/web-tests/node_modules/playwright');
const fixture = process.argv.find(value => value.startsWith('--audio='))?.slice(8);
assert.ok(fixture, 'Supply --audio=/absolute/path/to/synthetic-speech.wav');
const screenshot = process.argv.find(value => value.startsWith('--screenshot='))?.slice(13);
const browser = await chromium.launch({args:[
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  `--use-file-for-fake-audio-capture=${fixture}`,
]});
const page = await browser.newPage({viewport:{width:1280,height:980}});
const errors=[];
page.on('pageerror',error=>errors.push(error.message));
await page.addInitScript(() => {
  window.voiceTest={streams:[],inputs:0,outputs:0,speechStarts:0,interrupts:0,duplex:false,states:[]};
  const get=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  navigator.mediaDevices.getUserMedia=async(...args)=>{
    const stream=await get(...args); voiceTest.streams.push(stream); return stream;
  };
  const OriginalSocket=window.WebSocket;
  window.WebSocket=class extends OriginalSocket {
    constructor(...args){
      super(...args);
      this.addEventListener('message',event=>{
        const message=JSON.parse(event.data);
        if(message.type==='response.output_audio.delta') voiceTest.outputs++;
        if(message.type==='input_audio_buffer.speech_started') voiceTest.speechStarts++;
      });
    }
    send(data){
      const message=JSON.parse(data);
      if(message.type==='input_audio_buffer.append') voiceTest.inputs++;
      if(['response.cancel','conversation.item.truncate'].includes(message.type)) voiceTest.interrupts++;
      return super.send(data);
    }
  };
});
try {
  await page.goto(process.env.VOICE_WEB_URL || 'http://127.0.0.1:8001/');
  await page.waitForFunction(()=>!document.getElementById('conversation').disabled);
  await page.evaluate(()=>window.voiceTestTimer=setInterval(()=>{
    const state=JSON.parse(Module.UTF8ToString(Module._voiceBrowserState()));
    if(state.speaking && state.listening) voiceTest.duplex=true;
  },20));
  await page.click('#conversation');
  await page.waitForFunction(()=>{
    const state=JSON.parse(Module.UTF8ToString(Module._voiceBrowserState()));
    return state.connected && state.listening;
  },{timeout:30000});
  await page.waitForFunction(()=>voiceTest.duplex,{timeout:45000});
  await page.waitForFunction(()=>voiceTest.speechStarts>=2,{timeout:45000});
  await page.waitForFunction(()=>{
    const state=JSON.parse(Module.UTF8ToString(Module._voiceBrowserState()));
    return state.lines.some(line=>!line.user && /blue/i.test(line.text));
  },{timeout:30000});
  const result=await page.evaluate(()=>({
    state:JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())),
    inputChunks:voiceTest.inputs, outputChunks:voiceTest.outputs,
    speechStarts:voiceTest.speechStarts, interrupts:voiceTest.interrupts, duplex:voiceTest.duplex,
  }));
  console.log(JSON.stringify(result));
  assert.ok(result.inputChunks>10 && result.outputChunks>0 && result.duplex);
  assert.ok(result.interrupts>0,'Spoken interruption must cancel or truncate the reply.');
  await page.click('#conversation');
  await page.waitForFunction(()=>voiceTest.streams.every(stream=>stream.getTracks().every(track=>track.readyState==='ended')));
  await page.waitForFunction(()=>{
    const state=JSON.parse(Module.UTF8ToString(Module._voiceBrowserState()));
    return !state.conversationRequested && !state.listening;
  });
  const state=await page.evaluate(()=>JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())));
  assert.equal(state.conversationRequested,false);
  assert.equal(state.listening,false);
  if(screenshot) {
    await page.waitForFunction(() => document.getElementById('conversation').textContent === 'Start conversation');
    await page.screenshot({path:screenshot});
  }
  await page.click('#disconnect');
  assert.deepEqual(errors,[]);
  console.log('Live synthetic spoken conversation, duplex playback, voice interruption, and microphone shutdown passed.');
} catch(error) {
  console.log(await page.evaluate(()=>({state:typeof Module._voiceBrowserState==='function'?JSON.parse(Module.UTF8ToString(Module._voiceBrowserState())):null, metrics:{inputs:voiceTest.inputs,outputs:voiceTest.outputs,speechStarts:voiceTest.speechStarts,interrupts:voiceTest.interrupts,duplex:voiceTest.duplex}})));
  throw error;
} finally {await browser.close();}
