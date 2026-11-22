import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const code = readFileSync(new URL('../browsertransport.js', import.meta.url), 'utf8');

function runtime(fieldValue = '') {
  // Model browser networking without connecting to OpenAI or reading any key.
  const requests = [];
  const sockets = [];
  let library;
  class Socket {
    static OPEN = 1;
    constructor(url, protocols) {
      this.url = url;
      this.protocols = protocols;
      this.readyState = 0;
      this.bufferedAmount = 0;
      this.sent = [];
      sockets.push(this);
    }
    send(message) { this.sent.push(message); }
    close() { this.readyState = 3; }
  }
  const context = {
    AbortController,
    WebSocket: Socket,
    document: {getElementById() { return {value: fieldValue}; }},
    UTF8ToString: value => value,
    lengthBytesUTF8: value => Buffer.byteLength(value),
    stringToUTF8: (value, output) => { output.value = value; },
    fetch: (url, options) => new Promise((resolve, reject) => {
      requests.push({url, options, resolve, reject});
    }),
    addToLibrary: value => { library = value; },
  };
  vm.runInNewContext(code, context);
  context.voiceTransports = library.$voiceTransports;
  return {requests, sockets, library, context};
}

async function tick() {
  // Resolve the mocked fetch and JSON promises without a wall-clock delay.
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function open(runtime, key = '') {
  // All credentials in this test are deliberately invalid synthetic strings.
  return runtime.library.voice_transport_open('gpt-realtime-2.1-mini', 'marin', key);
}

function resolve(runtime, request = runtime.requests.at(-1)) {
  // Return the temporary-token response shape supplied by the local server.
  request.resolve({ok: true, status: 200, json: async () => ({value: 'ek_test-only'})});
}

{
  const test = runtime();
  const handle = open(test, 'sk-test-only');
  const request = test.requests[0];
  assert.equal(request.url, '/api/realtime/token');
  assert.equal(JSON.parse(request.options.body).apiKey, 'sk-test-only');
  test.library.voice_transport_close(handle);
  assert.equal(request.options.signal.aborted, true);
  resolve(test);
  await tick();
  assert.equal(test.sockets.length, 0);
  assert.equal(Object.keys(test.context.voiceTransports.sessions).length, 0);
}

{
  const test = runtime('sk-form-test-only');
  const oldHandle = open(test);
  const oldRequest = test.requests[0];
  assert.equal(JSON.parse(oldRequest.options.body).apiKey, 'sk-form-test-only');
  test.library.voice_transport_close(oldHandle);
  const newHandle = open(test);
  resolve(test);
  resolve(test, oldRequest);
  await tick();
  assert.equal(test.sockets.length, 1, 'A late token must not reopen an old session.');
  test.library.voice_transport_close(newHandle);
}

{
  const test = runtime();
  const handle = open(test);
  resolve(test);
  await tick();
  const socket = test.sockets[0];
  assert.deepEqual(Array.from(socket.protocols), [
    'realtime', 'openai-insecure-api-key.ek_test-only',
  ]);
  socket.readyState = 1;
  assert.equal(test.library.voice_transport_ready(handle), true);
  assert.equal(test.library.voice_transport_send(handle, 'hello'), 1);
  assert.equal(socket.sent[0], 'hello');
  const event = JSON.stringify({
    type: 'error', error: {message: 'Invalid voice', code: 'bad_voice'},
  });
  socket.onmessage({data: event});
  socket.onerror();
  assert.equal(test.library.voice_transport_error_length(handle), 0,
    'Detailed service errors must be delivered before a generic close.');
  const output = {};
  test.library.voice_transport_next_into(handle, output, 1000);
  assert.equal(output.value, event);
  assert.ok(test.library.voice_transport_error_length(handle) > 0);
  test.library.voice_transport_close(handle);
  assert.equal(Object.keys(test.context.voiceTransports.sessions).length, 0);
}

{
  const test = runtime();
  const handle = open(test, 'custom-test-only');
  test.requests[0].resolve({
    ok: false,
    status: 401,
    json: async () => ({error: {message: 'Invalid custom-test-only'}}),
  });
  await tick();
  await tick();
  const output = {};
  test.library.voice_transport_error_into(handle, output, 1000);
  assert.ok(output.value.includes('[redacted]'));
  assert.ok(!output.value.includes('custom-test-only'));
  test.library.voice_transport_close(handle);
}

{
  const test = runtime();
  const handle = open(test);
  resolve(test);
  await tick();
  const socket = test.sockets[0];
  socket.readyState = 1;
  socket.bufferedAmount = 2 * 1024 * 1024;
  assert.equal(test.library.voice_transport_send(handle, 'full'), 0);
  assert.equal(socket.readyState, 3);
  test.library.voice_transport_close(handle);
}

{
  const test = runtime();
  const handle = open(test);
  resolve(test);
  await tick();
  const socket = test.sockets[0];
  socket.readyState = 1;
  socket.onmessage({data: 'x'.repeat(2 * 1024 * 1024 + 1)});
  assert.equal(socket.readyState, 3);
  assert.ok(test.library.voice_transport_error_length(handle) > 0);
  test.library.voice_transport_close(handle);
}

console.log('Browser transport cancellation, reconnect, key handling, events, and bounds passed.');
