// EVERY REAL OUTCOME LANDS ON THE SEAT THAT DECIDED IT; A HIGH-STAKES DECISION WAITS FOR A SECOND SEAT.
// Seat: it_engineer. 29 Sep 2026, founder_instruction 1009 upgrades 3 and 10. Offline, over the source: it fails if
// an outcome source loses its trigger, if a wrong outcome stops becoming a lesson, if a high-stakes kind loses its
// reviewer, or if the clearance could ever clear anything but an approving comparison.
// The production proof is scripts/eval/outcomes_and_cross_seat_challenge_proof.mjs (needs a token).
//
//   node --test scripts/checks/every_real_outcome_lands_on_the_seat_that_decided_it.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const OUT = read('scripts/sql/every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason.sql');
const HS = read('scripts/sql/a_high_stakes_decision_waits_for_a_second_seat_on_another_family.sql');
const TS = read('supabase/functions/_shared/high_stakes_challenge.ts');
const QC = read('supabase/functions/quote_compare/index.ts');

test('each missing outcome source has its trigger: rating, complaint, supplier left, campaign converted or not', () => {
  for (const t of ['reviews', 'complaint_tickets', 'email_suppressions', 'marketing_first_touch', 'marketing_post_metric']) {
    assert.match(OUT, new RegExp(`create trigger z92_outcome_learning after insert on public\\.${t} `), t);
  }
  for (const k of ["'rating'", "'complaint'", "'supplier_left'", "'campaign_converted'", "'campaign_not_converted'"]) assert.ok(OUT.includes(k), k);
});

test('the outcome names the seat that decided, and a wrong outcome becomes a lesson', () => {
  assert.match(OUT, /select j\.seat into v_seat from public\.seat_judgement j[\s\S]*?order by j\.id desc limit 1;\s*v_seat := coalesce\(v_seat, p_default_seat\);/);
  assert.match(OUT, /if p_correct is false then[\s\S]*?lessons \|\| v_lesson/);
  assert.match(OUT, /an outcome names its kind and its reason/);
});

test('the four high-stakes kinds, the CEO challenging and the accountant when the CEO authors', () => {
  assert.match(HS, /p_kind in \('pricing_change', 'campaign_launch', 'supplier_choice', 'refund'\)/);
  assert.match(HS, /case when p_author_seat = 'ceo' then 'accountant' else 'ceo' end/);
  assert.match(HS, /fn_seat_deliberation_open\('high_stakes\.' \|\| p_kind/);   // the family rule lives there, reused
});

test('only an approving comparison clears; a disagreement carries its disagreements as the reason', () => {
  assert.match(HS, /'cleared', v_state = 'agreed'/);
  assert.match(HS, /when c\.verdict = 'approve' then 'agreed' else 'disagreed'/);
  assert.match(HS, /when 'disagreed' then c\.disagreements/);
  assert.match(TS, /if \(error \|\| !data\) return \{ proceed: false/);
  assert.match(TS, /proceed: data\.proceed === true/);
});

const body = (name) => {
  const i = HS.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, name);
  return HS.slice(i, HS.indexOf('$fn$;', HS.indexOf('$fn$', i) + 4));
};

test('no cap holds a review (founder_instruction 987): every pair is allowed', () => {
  const b = body('fn_seat_deliberation_budget');
  assert.match(b, /jsonb_build_object\('ok', true,/);
  assert.doesNotMatch(b, /'ok', false|cap_aed_month/);
});

test('the gate proceeds only on agreement, or with the review owed while the model hold is on', () => {
  assert.match(HS, /v_go := coalesce\(\(c->>'cleared'\)::boolean, false\) or \(v_held and coalesce\(c->>'state', ''\) <> 'disagreed'\);/);
  assert.match(HS, /set proceeded_at = coalesce\(proceeded_at, now\(\)\)/);
  assert.match(body('trg_high_stakes_review'), /'high_stakes_disagreement:' \|\| d\.id[\s\S]*'owner_seat', d\.author_seat/);
});

test('the gate is wired into the four real paths', () => {
  assert.match(body('fn_refund_decide'), /fn_high_stakes_gate\('refund', 'ceo', 'refunds'[\s\S]*?awaiting_second_seat[\s\S]*?set status = 'approved'/);
  assert.match(body('fn_ceo_review_applies'), /fn_high_stakes_gate\('pricing_change', 'ceo', 'ceo_review'/);
  assert.match(body('fn_ceo_review_applies'), /v_choice = 'propose_change' and coalesce\(\(v_gate->>'proceed'\)::boolean, false\)/);
  assert.match(body('fn_marketing_post_publish_refusal'), /fn_high_stakes_may_proceed\('campaign_launch', 'marketing_campaign'/);
  assert.match(HS, /create trigger z93_high_stakes_campaign_approved after update of approved_at on public\.marketing_campaign/);
  assert.match(QC, /kind: 'supplier_choice', seat: 'sales_engineer'/);
  assert.match(QC, /if \(!g\.proceed\) \{\s*a\.top3 = \[\]/);
  assert.equal((QC.match(/analysis: withRoster\((?!\{\})/g) || []).length, 0, 'every recommendation quote_compare returns passes the gate');
});

test('every new routine is revoked from the public roles', () => {
  for (const [src, sigs] of [[OUT, ['fn_outcome_record(text, text, text, boolean, text, text, text, text)', 'trg_outcome_learning()']],
    [HS, ['fn_high_stakes_model_held()', 'fn_high_stakes_gate(text, text, text, text, text, jsonb, jsonb, text, text, boolean)', 'fn_high_stakes_may_proceed(text, text, text)', 'trg_high_stakes_review()', 'trg_high_stakes_campaign_approved()', 'fn_high_stakes_reviewer(text, text)', 'fn_high_stakes_challenge(text, text, text, text, text, jsonb, jsonb, text, text, boolean)', 'fn_high_stakes_clearance(text, text, text)']]]) {
    for (const s of sigs) assert.ok(src.includes(`revoke execute on function public.${s} from public, anon, authenticated;`), s);
  }
});
