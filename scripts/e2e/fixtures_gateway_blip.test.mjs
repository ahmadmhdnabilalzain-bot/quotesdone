// fixtures_gateway_blip.test.mjs — the edge relay's HTML 502 is a blip the fixture retries; our own JSON
// error is not. Seat: customer_support. Replays nightly run 41410340385 (2 Nov 2026): services_save_rewrite
// for demo supplier 153830 got "<html> <head><title>502 Bad Gateway</title>" and journeys a-h never ran.
// Run: node --test scripts/e2e/fixtures_gateway_blip.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isGatewayBlip, isLockWait } from './fixtures.mjs';

test('the 2 Nov relay 502 is a blip', () => {
  assert.equal(isGatewayBlip({ status: 502, json: null, text: '<html> <head><title>502 Bad Gateway</title></head> <body> <center><h1>502 Bad Gateway</h1></c' }), true);
  assert.equal(isGatewayBlip({ status: 504, json: null, text: 'Gateway Timeout' }), true);
});

test('our handler answering 502 in JSON is a real failure, never retried', () => {
  assert.equal(isGatewayBlip({ status: 502, json: { error: 'save_failed' }, text: '{"error":"save_failed"}' }), false);
  assert.equal(isGatewayBlip({ status: 500, json: null, text: '<html>500</html>' }), false);
  assert.equal(isGatewayBlip({ status: 200, json: { ok: true }, text: '{"ok":true}' }), false);
});

// Replays run 2026-11-10T14-20-25 (10 Nov 2026): demo supplier 156068's services_save_rewrite waited on another session's
// rolled-back demo-purge probe and PostgREST's 8 s statement_timeout refused it. A lock wait is retried; any other 500 is not.
test('the 10 Nov statement timeout behind a locked row is retried, another 500 is not', () => {
  const body = '{"error":"services_rewrite_write_failed","code":"services_rewrite_write_failed","detail":"canceling statement due to statement timeout"}';
  assert.equal(isLockWait({ status: 500, json: JSON.parse(body), text: body }), true);
  assert.equal(isLockWait({ status: 500, json: {}, text: '{"detail":"canceling statement due to lock timeout"}' }), true);
  assert.equal(isLockWait({ status: 500, json: {}, text: '{"error":"services_rewrite_write_failed","detail":"null value in column \\"supplier_id\\""}' }), false);
  assert.equal(isLockWait({ status: 400, json: {}, text: '{"detail":"canceling statement due to statement timeout"}' }), false);
});
