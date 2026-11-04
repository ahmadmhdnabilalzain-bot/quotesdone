// Journey e's refund ladder on a ZZ DEMO reveal (scripts/e2e/demo_refund_ladder.mjs, accountant, 3 Nov 2026).
// On main the journey read handoffs a demo row never files (founder instruction 1199) and failed five steps
// (nightly 41598217377). These pin the two doors it now uses. Offline: no database is touched.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { handoffProbeSql, ladderSql, parseChk } from './demo_refund_ladder.mjs';

const TX = '30e17bdd-043e-41d1-a343-d8ec88791bd3';

test('the handoff probe files demo handoffs in its own transaction and always rolls back', () => {
  const s = handoffProbeSql(TX);
  assert.match(s, /set_config\('qd\.probe_files_demo_handoff', 'on', true\)/);
  assert.match(s, /fn_refund_open_from_customer\('30e17bdd-[0-9a-f-]+'::uuid, 'customer'\)/);
  assert.match(s, /raise exception 'CHK<<%>>'/);
});

test('the ladder runs only on a ZZ DEMO reveal, delivers to the demo address only, and never marks a message sent', () => {
  const s = ladderSql(TX, 78197);
  assert.match(s, /set_config\('qd\.probe_files_demo_handoff', 'on', true\)/);
  assert.match(s, /c\.is_demo and c\.email like '%@example\.invalid'/);
  assert.match(s, /array\['chase', 'final_call'\]/);
  assert.equal((s.match(/like '%@example\.invalid'/g) || []).length, 3);
  assert.doesNotMatch(s, /status\s*=\s*'sent'/);
  assert.match(s, /78197::bigint/);
});

test('a CHK verdict is read back out of the management API error body', () => {
  // The shape measured on 3 Nov 2026 (refund 78196 probe).
  const err = { body: JSON.stringify({ message: 'Failed to run sql query: ERROR:  P0001: CHK<<{"to_accountant": "accountant", "confirm_locale": "en"}>>\nCONTEXT:  PL/pgSQL function inline_code_block line 4 at RAISE' }) };
  assert.deepEqual(parseChk(err), { to_accountant: 'accountant', confirm_locale: 'en' });
  assert.equal(parseChk(new Error('management API 500: timeout')), null);
});

test('journey e asks the probe BEFORE the request and no longer reads committed demo handoffs', () => {
  const src = readFileSync(new URL('./journeys.mjs', import.meta.url), 'utf8');
  const body = src.slice(src.indexOf('async function refundEndToEnd'));
  assert.ok(body.indexOf('handoffProbeSql(tx.id)') > 0 && body.indexOf('handoffProbeSql(tx.id)') < body.indexOf("action: 'request_refund'"));
  assert.ok(body.includes('ladderSql(tx.id, rid)'));
  assert.ok(!body.includes("msg_type' = 'refund_request_received'"), 'the committed-handoff read is gone');
});
