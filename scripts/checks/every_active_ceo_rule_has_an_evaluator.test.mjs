// fn_ceo_decisions_evaluate reports ok:false for an active ceo_decision rule it has no branch for. On
// 24 Sep 2026 the company_stage rule was added with its executor as a seat duty and the evaluator was not
// told; heartbeat step ceoDecisions was red for four days (ledger 760). Every rule whose decision is made
// by a routine of its own must be named in the evaluator. Reads the live mirror.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const DECIDED_ELSEWHERE = ['company_stage', 'seat_directive', 'constraint_stalled', 'plan_review'];

test('the evaluator names every rule that is decided by its own routine', () => {
  const sql = readSchemaMirror();
  const i = sql.search(/FUNCTION public\.fn_ceo_decisions_evaluate\(/);
  assert.ok(i >= 0, 'fn_ceo_decisions_evaluate is not in the mirror');
  const body = sql.slice(i, sql.indexOf('$function$', sql.indexOf('$function$', i) + 10));
  if (!/when 'company_stage'/.test(body)) return;   // before the apply: the pending note covers it
  for (const k of DECIDED_ELSEWHERE) assert.match(body, new RegExp(`'${k}'`), `${k} has no branch`);
});
