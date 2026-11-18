'use strict';

const assert = require('node:assert/strict');

const kinds = ('Hello Welcome ListRooms RoomList CreateRoom JoinRoom RoomState ' +
  'ConfigureRoom ClaimSeat ReleaseSeat StartMatch BeginMatch SubmitCommand ' +
  'CommandAck TickPacket AppliedTick Catchup CaughtUp ReportHash MatchStatus ' +
  'LeaveRoom KickParticipant ReturnLobby FinishMatch Received Keepalive Failure ' +
  'AbortMatch PauseMatch ResizeRoom ReadyStatus').split(' ');

function decodeRoom(data, decodePayload) {
  const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
  assert.ok(bytes.length >= 64 && bytes.length <= 256 * 1024 &&
    bytes.toString('ascii', 0, 4) === 'PWRM', 'Shared room envelope');
  assert.equal(bytes.readUInt32LE(4), 5, 'Room protocol version');
  const kind = kinds[bytes.readUInt32LE(8)];
  assert.ok(kind, 'Known room operation');
  let offset = 64;
  function u32() {
    assert.ok(offset + 4 <= bytes.length, 'Complete uint32');
    const value = bytes.readUInt32LE(offset); offset += 4; return value;
  }
  function u64() {
    assert.ok(offset + 8 <= bytes.length, 'Complete uint64');
    const value = bytes.readBigUInt64LE(offset).toString(); offset += 8; return value;
  }
  function raw(limit = 64 * 1024) {
    const size = u32();
    assert.ok(size <= limit && offset + size <= bytes.length, 'Bounded wire string');
    const value = bytes.subarray(offset, offset + size); offset += size; return value;
  }
  function string(limit) { return raw(limit).toString('utf8'); }
  function flag() {
    const value = u32(); assert.ok(value <= 1, 'Boolean flag'); return value === 1;
  }
  function seatKind() {
    const value = u32(); assert.ok(value <= 1, 'Human or bot controller'); return value;
  }
  function phase() {
    const value = u32(); assert.ok(value <= 4, 'Room phase'); return value;
  }
  function list(limit, read) {
    const count = u32(); assert.ok(count <= limit, 'Bounded collection');
    return Array.from({length: count}, read);
  }
  function seats() {
    return list(64, () => ({owner: u32(), kind: seatKind(), name: string(96)}));
  }
  const message = {kind, match: bytes.readUInt32LE(20)};
  switch (kind) {
    case 'Hello':
      message.game = string(96); message.gameplay = u32();
      message.protocol = u32(); message.name = string(64);
      string(64); // Reconnect credentials must never appear in browser reports.
      break;
    case 'Welcome':
      message.participant = u32(); string(64);
      break;
    case 'CreateRoom': case 'ConfigureRoom': case 'ResizeRoom':
      message.name = string(96); message.public = flag(); message.rate = u32();
      message.count = u32(); message.config = string();
      break;
    case 'JoinRoom':
      message.room = string(64);
      break;
    case 'RoomList':
      message.rooms = list(64, () => ({id: string(64), name: string(96),
        phase: phase(), occupied: u32(), seats: u32()}));
      break;
    case 'RoomState': case 'BeginMatch':
      message.room = string(64); message.name = string(96); message.owner = u32();
      message.revision = u32(); message.phase = phase(); message.rate = u32();
      message.flag = flag(); message.public = message.flag;
      message.config = string();
      message.participants = list(64, () => ({id: u32(), name: string(64),
        connected: flag(), ready: flag()}));
      message.seats = seats();
      if (kind === 'BeginMatch') message.hash = u64();
      break;
    case 'ClaimSeat':
      message.seat = u32(); message.participant = u32();
      message.seatKind = seatKind(); message.name = string(96);
      break;
    case 'ReleaseSeat':
      message.seat = u32();
      break;
    case 'StartMatch':
      message.revision = u32(); message.hash = u64();
      break;
    case 'SubmitCommand': {
      message.seat = u32(); message.seatKind = seatKind(); message.sequence = u64();
      const payload = raw(4096);
      message.payload = payload.toString('hex');
      if (decodePayload) Object.assign(message, decodePayload(payload));
      break;
    }
    case 'CommandAck':
      message.sequence = u64(); message.tick = u32();
      message.discarded = flag(); message.flag = message.discarded;
      break;
    case 'TickPacket':
      message.tick = u32();
      message.commands = list(1024, () => ({participant: u32(), seat: u32(),
        seatKind: seatKind(), sequence: u64(), payload: raw(4096).toString('hex')}));
      message.seats = seats();
      break;
    case 'AppliedTick': case 'Catchup':
      message.tick = u32();
      break;
    case 'CaughtUp':
      message.tick = u32(); message.number = u32();
      break;
    case 'ReportHash': case 'FinishMatch':
      message.tick = u32(); message.hash = u64();
      break;
    case 'PauseMatch': case 'ReadyStatus':
      message.flag = flag();
      break;
    case 'MatchStatus':
      message.paused = flag(); message.phase = phase();
      message.tick = u32(); message.detail = string(4096);
      break;
    case 'KickParticipant':
      message.participant = u32();
      break;
    case 'Received':
      message.sequence = u64();
      break;
    case 'Failure': case 'AbortMatch':
      message.detail = string(4096);
      break;
    case 'ListRooms': case 'LeaveRoom': case 'ReturnLobby': case 'Keepalive':
      break;
    default:
      assert.fail('Unhandled room operation');
  }
  assert.equal(offset, bytes.length, 'No trailing room packet bytes');
  return message;
}

module.exports = {decodeRoom, kinds};
