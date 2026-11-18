addToLibrary({
  $voiceTransports: {
    nextHandle: 1,
    sessions: {},
    limit: 2 * 1024 * 1024,
    detail: function(message) {
      return String(message).replace(/(?:sk-|ek[_-])[A-Za-z0-9_.*-]+/g,
        '[redacted]').slice(0, 500);
    },
    release: function(session) {
      session.controller.abort();
      if (session.socket) {
        session.socket.onopen = null;
        session.socket.onmessage = null;
        session.socket.onerror = null;
        session.socket.onclose = null;
        session.socket.close();
        session.socket = null;
      }
    },
    fail: function(session, message) {
      if (session.closed || session.error) return;
      session.error = voiceTransports.detail(message);
      voiceTransports.release(session);
    }
  },
  voice_transport_open__deps: ['$voiceTransports', '$UTF8ToString'],
  voice_transport_open: function(modelPointer, voicePointer, keyPointer) {
    const handle = voiceTransports.nextHandle++;
    const session = {
      socket: null,
      controller: new AbortController(),
      closed: false,
      error: '',
      messages: [],
      bytes: 0
    };
    voiceTransports.sessions[handle] = session;
    const model = UTF8ToString(modelPointer);
    const voice = UTF8ToString(voicePointer);
    let apiKey = UTF8ToString(keyPointer).trim();
    if (!apiKey && typeof document !== 'undefined') {
      const field = document.getElementById('api-key');
      if (field) apiKey = field.value.trim();
    }
    const request = {model, voice};
    if (apiKey) request.apiKey = apiKey;
    fetch('/api/realtime/token', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      cache: 'no-store',
      credentials: 'same-origin',
      signal: session.controller.signal,
      body: JSON.stringify(request)
    }).then(async function(response) {
      const data = await response.json();
      if (session.closed) return;
      if (!response.ok) {
        const detail = data.error && data.error.message
          ? data.error.message : data.error || 'Could not create a voice session.';
        throw new Error('Voice token request failed (' + response.status + '): ' + detail);
      }
      if (typeof data.value !== 'string' || !data.value) {
        throw new Error('The voice server returned no temporary session token.');
      }
      apiKey = '';
      delete request.apiKey;
      if (session.closed) return;
      const socket = new WebSocket(
        'wss://api.openai.com/v1/realtime?model=' + encodeURIComponent(model),
        ['realtime', 'openai-insecure-api-key.' + data.value]
      );
      data.value = '';
      session.socket = socket;
      socket.onmessage = function(event) {
        if (session.closed || session.error) return;
        if (typeof event.data !== 'string') {
          voiceTransports.fail(session, 'Unexpected binary voice event.');
          return;
        }
        if (session.bytes + event.data.length > voiceTransports.limit ||
            session.messages.length >= 1024) {
          voiceTransports.fail(session, 'Voice events cannot keep up. Reconnect to continue.');
          return;
        }
        session.messages.push(event.data);
        session.bytes += event.data.length;
      };
      socket.onerror = function() {
        voiceTransports.fail(session, 'Browser voice connection failed. Reconnect to try again.');
      };
      socket.onclose = function(event) {
        voiceTransports.fail(session, 'Voice connection closed (' + event.code + ')' +
          (event.reason ? ': ' + event.reason : '. Reconnect to try again.'));
      };
    }).catch(function(error) {
      if (session.closed) return;
      let message = error.message || String(error);
      if (apiKey) message = message.split(apiKey).join('[redacted]');
      apiKey = '';
      delete request.apiKey;
      voiceTransports.fail(session, message);
    });
    return handle;
  },
  voice_transport_close__deps: ['$voiceTransports'],
  voice_transport_close: function(handle) {
    const session = voiceTransports.sessions[handle];
    if (!session) return;
    session.closed = true;
    voiceTransports.release(session);
    session.messages.length = 0;
    session.bytes = 0;
    delete voiceTransports.sessions[handle];
  },
  voice_transport_ready__deps: ['$voiceTransports'],
  voice_transport_ready: function(handle) {
    const session = voiceTransports.sessions[handle];
    return !!(session && !session.error && session.socket &&
      session.socket.readyState === WebSocket.OPEN);
  },
  voice_transport_send__deps: ['$voiceTransports', '$UTF8ToString'],
  voice_transport_send: function(handle, pointer) {
    const session = voiceTransports.sessions[handle];
    if (!session || session.error || !session.socket ||
        session.socket.readyState !== WebSocket.OPEN) return 0;
    const message = UTF8ToString(pointer);
    if (session.socket.bufferedAmount + message.length > voiceTransports.limit) {
      voiceTransports.fail(session, 'Network cannot keep up with audio. Reconnect to try again.');
      return 0;
    }
    try {
      session.socket.send(message);
      return 1;
    } catch (error) {
      voiceTransports.fail(session, error.message || String(error));
      return 0;
    }
  },
  voice_transport_next_length__deps: ['$voiceTransports', '$lengthBytesUTF8'],
  voice_transport_next_length: function(handle) {
    const session = voiceTransports.sessions[handle];
    return session && session.messages.length ? lengthBytesUTF8(session.messages[0]) : 0;
  },
  voice_transport_next_into__deps: ['$voiceTransports', '$stringToUTF8'],
  voice_transport_next_into: function(handle, destination, capacity) {
    const session = voiceTransports.sessions[handle];
    const message = session && session.messages.length ? session.messages.shift() : '';
    if (session) session.bytes -= message.length;
    stringToUTF8(message, destination, capacity);
  },
  voice_transport_error_length__deps: ['$voiceTransports', '$lengthBytesUTF8'],
  voice_transport_error_length: function(handle) {
    const session = voiceTransports.sessions[handle];
    // Let the shared parser see detailed API errors before a generic close.
    return session && !session.messages.length ? lengthBytesUTF8(session.error) : 0;
  },
  voice_transport_error_into__deps: ['$voiceTransports', '$stringToUTF8'],
  voice_transport_error_into: function(handle, destination, capacity) {
    const session = voiceTransports.sessions[handle];
    stringToUTF8(session ? session.error : '', destination, capacity);
  }
});
