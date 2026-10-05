// A CEO REJECTION LOOPS BACK TO THE SEAT, WITH REASONS, AND NEVER TO THE FOUNDER (ceo, 29 Sep 2026).
//
// The founder, founder_instruction 1059: a rejection never ends the cycle; the CEO gives reasons for every
// rejection and a logic for every approval; the originating seat revises and resubmits until approved; the
// founder is never part of it. scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql
// built it on public.ceo_decision_round. This fails when:
//   1. (static, canonical bodies: the last definer in MANIFEST order, pending files included) a wired path stops
//      writing its decision to the ledger, a CEO rejection of a deliberation can no longer be revised, the refund
//      loop pages the founder again, the ledger loses its loop guard or its reasons rule, or the ledger falls out
//      of the daily export (another file redefining fn_table_export_list from an older list would drop it);
//   2. (production, with a management token) the two files and the probe, replayed in ONE transaction that the
//      probe always rolls back, do not answer PROBE OK.
//
//   node --test scripts/checks/a_ceo_rejection_loops_back_to_the_seat.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';
import { exportedTables } from '../lib/table_export_registry.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql';
const EVAL = 'scripts/sql/the_directive_escalation_rule_is_decided_by_its_own_duty.sql';
const PROBE = 'scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises_probe.sql';

// The canonical CREATE FUNCTION statement of each routine, SQL comments removed (a check that greps source
// must not match its own comment).
function canonical() {
  const out = new Map();
  for (const f of manifestWithPending()) {
    if (!existsSync(join(REPO, f))) continue;
    for (const d of definitions(readFileSync(join(REPO, f), 'utf8'))) {
      out.set(d.name, d.stmt.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n'));
    }
  }
  return out;
}

test('every wired path writes its CEO decision to the ledger, and a rejection is revised', () => {
  const c = canonical();
  for (const fn of ['fn_seat_deliberation_record', 'fn_ceo_refund_review', 'fn_reason_apply_ceo__experiment_approval',
                    'fn_ceo_review_one_answered_improvement']) {
    assert.ok(c.has(fn), `${fn} is defined nowhere`);
    assert.match(c.get(fn), /public\.fn_ceo_decide\(/, `${fn} no longer records the CEO's decision in ceo_decision_round`);
  }
  assert.match(c.get('fn_seat_deliberation_revise'), /v_last = 'reject' and d\.reviewer_seat = 'ceo'/, 'a CEO reject can no longer be revised by the author');
  assert.match(c.get('fn_reason_apply_ceo__sales_escalation'), /fn_ceo_reasons_problem\(/, 'the sales escalation answer no longer needs reasons');
  assert.match(c.get('fn_ceo_reviews_answered_improvements'), /fn_ceo_review_one_answered_improvement\(/, 'the improvement sweep bypasses the ledger');
});

test('the refund loop never pages the founder', () => {
  const c = canonical();
  for (const fn of ['fn_ceo_refund_review', 'fn_ceo_refund_loop_sweep']) {
    assert.doesNotMatch(c.get(fn), /fn_ceo_founder_summary|fn_notify_founder|recipient_role'\s*,\s*'founder/, `${fn} pages the founder again`);
    assert.match(c.get(fn), /fn_ceo_decide\(|fn_ceo_decision_owe\(/, `${fn} no longer owes the CEO the decision`);
  }
});

test('the ledger keeps its loop guard and its reasons rule, and is exported every day', () => {
  const c = canonical();
  const rules = c.get('trg_ceo_decision_round_rules');
  assert.ok(rules, 'the ledger rules trigger is defined nowhere');
  assert.match(rules, /'rejections'\)::int\s*>=\s*4/, 'the loop guard is no longer 4 rejections');
  assert.match(c.get('fn_ceo_decide'), /fn_ceo_decision_next\(p_item_key\)/, 'the CEO entry counts rounds somewhere other than the one place');
  assert.match(rules, /ROUND_LIMIT/);
  assert.match(rules, /fn_ceo_reasons_problem\(new\.reasons\)/, 'the ledger accepts a reasonless decision');
  assert.match(c.get('trg_ceo_approval_carries_its_reasons'), /fn_ceo_reasons_problem\(new\.rationale\)/);
  assert.equal(exportedTables(REPO).has('ceo_decision_round'), true, 'ceo_decision_round dropped out of the daily export (public.table_export_registry)');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, aborted: the probe answers PROBE OK', { skip: hasToken ? false : 'no Supabase management token in this environment', timeout: 600000 }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const text = [FILE, EVAL, PROBE].map((f) => readFileSync(join(REPO, f), 'utf8')).join('\n;\n');
  let msg = '';
  for (let attempt = 0; attempt < 2; attempt++) {
    try { await replaySql(text, { retry: false }); msg = 'the probe did not raise'; break; }
    catch (e) { msg = String(e.message); if (!/deadlock detected|55P03|57014/.test(msg)) break; }   // serial re-issue of a rolled-back replay is safe
  }
  const i = msg.indexOf('CHK<<');
  assert.ok(i >= 0, msg.slice(0, 1500));
  const out = msg.slice(i + 5, msg.indexOf('>>', i));
  assert.match(out, /PROBE OK/, out.slice(0, 3000));
});
