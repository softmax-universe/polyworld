#!/usr/bin/env node
'use strict';

// Generate input with `nim c -r --hints:off tests/room_protocol_fixture.nim`.
// This verifies the decoder used by browser probes against the real Nim codec.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {decodeRoom, kinds} = require('./room_protocol.cjs');
assert.ok(process.argv[2], 'Pass the Nim-generated fixture JSON path');
const fixtures = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
assert.deepEqual(fixtures.map(fixture => fixture.kind), kinds,
  'Browser probes must recognize every actual relay operation in wire order');

const config = '{"arbitrary":[1,true,"opaque"]}';
const sequence = '9007199254740995';
const hash = '18446744073709551610';
const seats = [{owner:13, kind:0, name:'any-human'},
  {owner:29, kind:1, name:'any-bot'}];
const participants = [{id:13, name:'Alpha', connected:true, ready:false},
  {id:29, name:'Beta', connected:false, ready:true}];
const setup = {room:'R42', name:'Arbitrary room', owner:13, revision:7,
  phase:2, rate:30, flag:true, public:true, config, participants, seats};
const configuration = {name:'Arbitrary room', public:true, rate:30, count:2, config};
const expected = {
  Hello: {game:'g'.repeat(80), gameplay:23, protocol:0, name:'Arbitrary room'},
  Welcome: {participant:13},
  ListRooms: {},
  RoomList: {rooms:[{id:'R42', name:'Arbitrary room', phase:1, occupied:1, seats:2}]},
  CreateRoom: configuration,
  JoinRoom: {room:'R42'},
  RoomState: setup,
  ConfigureRoom: configuration,
  ClaimSeat: {seat:1, participant:13, seatKind:1, name:'Arbitrary room'},
  ReleaseSeat: {seat:1},
  StartMatch: {revision:7, hash},
  BeginMatch: {...setup, hash},
  SubmitCommand: {seat:1, seatKind:1, sequence, payload:Buffer.from(config).toString('hex')},
  CommandAck: {sequence, tick:94, discarded:true, flag:true},
  TickPacket: {tick:94, commands:[{participant:29, seat:1, seatKind:1,
    sequence, payload:'00ff01'}], seats},
  AppliedTick: {tick:94},
  Catchup: {tick:94},
  CaughtUp: {tick:94, number:2},
  ReportHash: {tick:94, hash},
  MatchStatus: {paused:true, phase:2, tick:94, detail:'detail'},
  LeaveRoom: {},
  KickParticipant: {participant:13},
  ReturnLobby: {},
  FinishMatch: {tick:94, hash},
  Received: {sequence},
  Keepalive: {},
  Failure: {detail:'detail'},
  AbortMatch: {detail:'detail'},
  PauseMatch: {flag:true},
  ResizeRoom: configuration,
  ReadyStatus: {flag:true},
};

for (const fixture of fixtures) {
  const bytes = Buffer.from(fixture.hex, 'hex');
  const actual = decodeRoom(bytes);
  assert.deepEqual(actual, {kind:fixture.kind, match:73, ...expected[fixture.kind]},
    fixture.kind + ' preserves the complete current wire body');
  assert.ok(!JSON.stringify(actual).includes('fixture-only-credential'),
    'Reconnect credentials stay out of browser reports');
  assert.throws(() => decodeRoom(bytes.subarray(0, -1)),
    fixture.kind + ' rejects a truncated packet');
  assert.throws(() => decodeRoom(Buffer.concat([bytes, Buffer.from([0])])),
    fixture.kind + ' rejects trailing bytes');
}

function packet(kind) {
  return Buffer.from(fixtures.find(fixture => fixture.kind === kind).hex, 'hex');
}
function invalidWord(kind, offset, value) {
  const bytes = packet(kind); bytes.writeUInt32LE(value, offset);
  assert.throws(() => decodeRoom(bytes), kind + ' rejects invalid word at ' + offset);
}
invalidWord('Hello', 4, 4); // Old wire versions are not accepted.
invalidWord('Hello', 8, 999);
invalidWord('Hello', 64, 97); // Game identifiers are bounded to 96 bytes.
invalidWord('ClaimSeat', 72, 2);
invalidWord('SubmitCommand', 68, 2);
invalidWord('CommandAck', 76, 2);
invalidWord('TickPacket', 68, 1025);
invalidWord('TickPacket', 80, 2);
invalidWord('ReadyStatus', 64, 2);
const accepted = packet('CommandAck'); accepted.writeUInt32LE(0, 76);
assert.equal(decodeRoom(accepted).discarded, false,
  'Accepted retransmission receipts stay distinct from cancellation');
let payloadCalls = 0;
const submitted = decodeRoom(packet('SubmitCommand'), payload => {
  payloadCalls++;
  assert.equal(payload.toString(), config);
  return {gameAction:'decoded by client test'};
});
assert.equal(payloadCalls, 1);
assert.equal(submitted.gameAction, 'decoded by client test');
assert.equal(submitted.seatKind, 1);
console.log('PASS: all ' + kinds.length + ' Nim-encoded room operations, bounds, roles and cancellation receipts');
