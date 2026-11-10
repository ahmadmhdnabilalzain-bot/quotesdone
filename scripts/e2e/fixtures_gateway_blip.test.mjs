// fixtures_gateway_blip.test.mjs — the edge relay's HTML 502 is a blip the fixture retries; our own JSON
// error is not. Seat: customer_support. Replays nightly run 41410340385 (2 Nov 2026): services_save_rewrite
// for demo supplier 153830 got "<html> <head><title>502 Bad Gateway</title>" and journeys a-h never ran.
// Run: node --test scripts/e2e/fixtures_gateway_blip.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isGatewayBlip } from './fixtures.mjs';

test('the 2 Nov relay 502 is a blip', () => {
  assert.equal(isGatewayBlip({ status: 502, json: null, text: '<html> <head><title>502 Bad Gateway</title></head> <body> <center><h1>502 Bad Gateway</h1></c' }), true);
  assert.equal(isGatewayBlip({ status: 504, json: null, text: 'Gateway Timeout' }), true);
});

test('our handler answering 502 in JSON is a real failure, never retried', () => {
  assert.equal(isGatewayBlip({ status: 502, json: { error: 'save_failed' }, text: '{"error":"save_failed"}' }), false);
  assert.equal(isGatewayBlip({ status: 500, json: null, text: '<html>500</html>' }), false);
  assert.equal(isGatewayBlip({ status: 200, json: { ok: true }, text: '{"ok":true}' }), false);
});
