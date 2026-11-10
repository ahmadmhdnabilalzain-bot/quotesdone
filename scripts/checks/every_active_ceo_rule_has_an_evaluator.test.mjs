// fn_ceo_decisions_evaluate reports ok:false for an active ceo_decision rule it has no branch for. On
// 24 Sep 2026 the company_stage rule was added with its executor as a seat duty and the evaluator was not
// told; heartbeat step ceoDecisions was red for four days (ledger 760). On 29 Sep 2026 the same happened to
// directive_escalation (the_ceo_issues_directives_and_closes_them_on_their_own_condition.sql). Every rule
// whose decision is made by a routine of its own must be named in the evaluator.
//
// Reads the CANONICAL body -- the last definer in MANIFEST order, pending files included -- rather than the
// schema mirror, so a pull request that names a rule is checked before its apply, and one that drops a name
// fails its own CI instead of main after the release train (canonical_routine_manifest proves canonical = live).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
// 10 Nov 2026: supplier_growth and supplier_growth_effect (#1879) were added the same way and are named by
// the_supplier_growth_rules_are_decided_by_their_own_duty.sql.
const DECIDED_ELSEWHERE = ['company_stage', 'seat_directive', 'constraint_stalled', 'plan_review', 'directive_escalation',
  'supplier_growth', 'supplier_growth_effect'];

test('the evaluator names every rule that is decided by its own routine', () => {
  let body = null;
  for (const f of manifestWithPending()) {
    if (!existsSync(join(REPO, f))) continue;
    for (const d of definitions(readFileSync(join(REPO, f), 'utf8'))) if (d.name === 'fn_ceo_decisions_evaluate') body = d.stmt;
  }
  assert.ok(body, 'no scripts/sql file defines fn_ceo_decisions_evaluate');
  for (const k of DECIDED_ELSEWHERE) assert.match(body, new RegExp(`'${k}'`), `${k} has no branch`);
});
