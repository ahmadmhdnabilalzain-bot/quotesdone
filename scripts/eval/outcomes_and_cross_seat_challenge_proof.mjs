// DO REAL OUTCOMES REACH THE SEAT THAT DECIDED, AND DOES A HIGH-STAKES DECISION WAIT FOR A SECOND SEAT?
// Seat: it_engineer (shared platform). 29 Sep 2026, founder_instruction 1009 upgrades 3 and 10.
//
// Runs on PRODUCTION inside ONE transaction that always raises, so nothing commits. The pending SQL files are
// replayed first, inside the same transaction, while their notes say they are not applied. Every row is ZZ DEMO
// (a lead at example.invalid, subjects keyed zz_demo_1009:*). The reviewer MODEL IS STUBBED: its turns are recorded
// with fn_seat_deliberation_record exactly as advanceDeliberation records a model's reply, so no model is called.
//
//   OUTCOMES   1. fn_outcome_record names the seat that DECIDED (the judgement's), not the default, writes kind and
//                 reason, and turns a wrong outcome into a lesson on the case; a repeat does not duplicate it; an
//                 outcome with no reason is refused.
//              2. a supplier who LEFT (email_suppressions) and a customer RATING (reviews) reach the judgement about
//                 that supplier through the z92 trigger.
//   CHALLENGE  3. one deliberation per decision; the CEO challenges, the accountant when the CEO authors; an
//                 unknown kind is refused; not reviewed = pending, held = held, never cleared.
//              4. a same-family reviewer is refused; a disagreement is recorded WITH its reason and not cleared;
//                 an agreement clears.
//
//   node scripts/eval/outcomes_and_cross_seat_challenge_proof.mjs     exit 0 = proved, 1 = an assertion failed
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const { sql } = await import('../lib/db.mjs');
const TAG = 'zz_demo_1009';
const EMAIL = 'zz-demo-1009@example.invalid';

const PENDING = ['a_decision_names_the_recalled_case_it_followed',
  'every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason',
  'a_high_stakes_decision_waits_for_a_second_seat_on_another_family'];
const replayed = PENDING.filter((n) => existsSync(join(REPO, 'scripts/sql/pending', n + '.txt')));
const replay = replayed.map((n) => readFileSync(join(REPO, 'scripts/sql', n + '.sql'), 'utf8')).join('\n');

const AUTHOR = 'z-ai/glm-5.3-flash';     // the author's family
const REVIEWER = 'openai/gpt-5.6-sol';    // the stubbed reviewer, another family
const turn = (verdict, steel, extra = {}) => `'${JSON.stringify({ verdict, steelman_against: steel, recommendation: 'ZZ DEMO', ...extra }).replace(/'/g, "''")}'::jsonb`;

const probe = `
do $p$
declare
  t0 timestamptz := now();
  j bigint; jl bigint; lead_id bigint; o jsonb; o2 jsonb; c jsonb; d bigint; d2 bigint; dq bigint; st jsonb;
  r jsonb := '{}'; e text;
begin
  -- 1. fn_outcome_record: the deciding seat, kind, reason, lesson
  j := public.fn_judgement_record('ceo', '${TAG}', jsonb_build_object('table', '${TAG}', 'id', '${TAG}:a'), 'ZZ DEMO refund this customer?', '{"available":true,"cases":[],"finalised_precedent":false,"reason":null}'::jsonb);
  o := public.fn_outcome_record('${TAG}', '${TAG}:a', 'refund_reversed', false, 'ZZ DEMO the card issuer reversed the refund', 'accountant', 'refund', 'ZZ DEMO a refund decision');
  o2 := public.fn_outcome_record('${TAG}', '${TAG}:a', 'refund_reversed', false, 'ZZ DEMO the card issuer reversed the refund', 'accountant', 'refund', 'ZZ DEMO a refund decision');
  begin perform public.fn_outcome_record('${TAG}', '${TAG}:a', 'x', true, '  '); e := 'accepted'; exception when sqlstate '22023' then e := 'refused'; end;
  r := r || jsonb_build_object('o_seat', o->>'seat', 'no_reason', e,
    'j', (select jsonb_build_object('kind', outcome_kind, 'reason', outcome_reason, 'correct', outcome_correct) from public.seat_judgement where id = j),
    'case', (select jsonb_build_object('seat', seat, 'mine', (select count(*) from unnest(lessons) l where l like 'Outcome refund_reversed:%')) from public.seat_case_memory where source_table = '${TAG}' and source_id = '${TAG}:a'));

  -- 2. a supplier who left, and a customer's rating, reach the judgement about the supplier
  insert into public.leads (company_name, email) values ('ZZ DEMO 1009 supplier', '${EMAIL}') returning id into lead_id;
  jl := public.fn_judgement_record('sales_engineer', '${TAG}', jsonb_build_object('table', 'leads', 'id', lead_id::text), 'ZZ DEMO recruit this supplier?', '{"available":true,"cases":[],"finalised_precedent":false,"reason":null}'::jsonb);
  insert into public.reviews (supplier_id, rating, comment) values (lead_id, 1, 'ZZ DEMO never turned up on site');
  r := r || jsonb_build_object('rating', (select jsonb_build_object('kind', outcome_kind, 'reason', outcome_reason, 'correct', outcome_correct) from public.seat_judgement where id = jl));
  insert into public.email_suppressions (email, reason, source) values ('${EMAIL}', 'unsubscribe', '${TAG}');
  r := r || jsonb_build_object('left', (select jsonb_build_object('kind', outcome_kind, 'reason', outcome_reason, 'correct', outcome_correct) from public.seat_judgement where id = jl));

  -- 3. one deliberation per decision, the right reviewer, never cleared while unreviewed or held
  r := r || jsonb_build_object('reviewer_of_sales', public.fn_high_stakes_reviewer('pricing_change', 'sales_engineer'),
                               'reviewer_of_ceo', public.fn_high_stakes_reviewer('refund', 'ceo'));
  begin perform public.fn_high_stakes_challenge('lunch_order', 'sales_engineer', '${TAG}', '${TAG}:x', 'ZZ DEMO q', '{}', '{"a":1}', '${AUTHOR}', null, true); e := 'accepted';
  exception when sqlstate '22023' then e := 'refused'; end;
  r := r || jsonb_build_object('unknown_kind', e);
  d := public.fn_high_stakes_challenge('pricing_change', 'sales_engineer', '${TAG}', '${TAG}:p', 'ZZ DEMO should the success fee change for this trade?',
         '{"trade":"hvac"}'::jsonb, '{"new_fee_pct":"two and a half"}'::jsonb, '${AUTHOR}', null, true);
  d2 := public.fn_high_stakes_challenge('pricing_change', 'sales_engineer', '${TAG}', '${TAG}:p', 'ZZ DEMO should the success fee change for this trade?',
         '{"trade":"hvac"}'::jsonb, '{"new_fee_pct":"two and a half"}'::jsonb, '${AUTHOR}', null, true);
  r := r || jsonb_build_object('one_per_decision', d = d2, 'pending', (public.fn_high_stakes_clearance('pricing_change', '${TAG}', '${TAG}:p') - 'author_seat' - 'author_model' - 'deliberation_id' - 'verdict' - 'reviewer_seat'));
  st := public.fn_seat_deliberation_step(d);
  r := r || jsonb_build_object('held', (public.fn_high_stakes_clearance('pricing_change', '${TAG}', '${TAG}:p') - 'author_seat' - 'author_model' - 'deliberation_id' - 'verdict' - 'reviewer_seat'));

  -- 4. the stubbed reviewer: same family refused; disagreement recorded with its reason; agreement clears
  begin perform public.fn_seat_deliberation_record(d, 'blind', '${AUTHOR}', ${turn('approve', 'ZZ DEMO the fee change may push suppliers away')}); e := 'accepted';
  exception when others then e := left(sqlerrm, 60); end;
  r := r || jsonb_build_object('same_family', e);
  perform public.fn_seat_deliberation_record(d, 'blind', '${REVIEWER}', ${turn('reject', 'ZZ DEMO a higher fee could still be absorbed by margins')});
  perform public.fn_seat_deliberation_record(d, 'compare', '${REVIEWER}', ${turn('reject', 'ZZ DEMO the author may know of win rates I cannot see',
    { agreements: 'none', disagreements: 'ZZ DEMO the fee change is not backed by any win-rate data' })});
  r := r || jsonb_build_object('disagreed', (public.fn_high_stakes_clearance('pricing_change', '${TAG}', '${TAG}:p') - 'author_seat' - 'author_model' - 'deliberation_id' - 'verdict' - 'reviewer_seat'));

  dq := public.fn_high_stakes_challenge('refund', 'customer_support', '${TAG}', '${TAG}:q', 'ZZ DEMO should this customer be refunded?',
         '{"ledger":"paid"}'::jsonb, '{"refund":"in full"}'::jsonb, '${AUTHOR}', null, true);
  perform public.fn_seat_deliberation_record(dq, 'blind', '${REVIEWER}', ${turn('approve', 'ZZ DEMO a refund could invite copycat claims later')});
  perform public.fn_seat_deliberation_record(dq, 'compare', '${REVIEWER}', ${turn('approve', 'ZZ DEMO the customer may have used the service partly',
    { agreements: 'ZZ DEMO the payment and the failure are both on the ledger', disagreements: 'none' })});
  r := r || jsonb_build_object('agreed', (public.fn_high_stakes_clearance('refund', '${TAG}', '${TAG}:q') - 'author_seat' - 'author_model' - 'deliberation_id' - 'verdict' - 'reviewer_seat'),
    'refund_reviewer', (select reviewer_seat from public.seat_deliberation where id = dq));

  r := r || jsonb_build_object('notifications_queued', (select count(*) from public.notifications where created_at >= t0 and to_email = '${EMAIL}'),
    'misses', (select count(*) from public.seat_case_memory_miss where (source_id like '${TAG}%' or source_id = '${EMAIL}')));
  raise exception 'CHK<<%>>', r;
end $p$;`;

let r;
try { await sql(replay + '\n' + probe, { retry: false }); console.error('the probe COMMITTED: it must always raise'); process.exit(2); }
catch (e) {
  const m = String(e.message).match(/CHK<<(.*)>>/s);
  if (!m) throw e;
  r = JSON.parse(m[1].replace(/\\"/g, '"'));
}

const [left] = await sql(`select
  (select count(*) from public.leads where email = '${EMAIL}')::int leads,
  (select count(*) from public.email_suppressions where email = '${EMAIL}')::int suppressions,
  (select count(*) from public.seat_judgement where surface = '${TAG}' or subject_id like '${TAG}%')::int judgements,
  (select count(*) from public.seat_case_memory where source_table = '${TAG}')::int cases,
  (select count(*) from public.seat_deliberation where subject_table = '${TAG}')::int deliberations`, { readOnly: true });
const rowsLeft = Object.values(left).reduce((a, b) => a + b, 0);
console.log(JSON.stringify({ replayed_pending: replayed, ...r, rows_left_after: left }, null, 2));

const checks = [
  ['1 the outcome lands on the seat that decided (ceo), not the default (accountant)', r.o_seat === 'ceo' && r.case?.seat === 'ceo'],
  ['1 kind and reason recorded, marked wrong', r.j?.kind === 'refund_reversed' && r.j?.reason?.includes('reversed') && r.j?.correct === false],
  ['1 a wrong outcome becomes ONE lesson on the case', r.case?.mine === 1],
  ['1 an outcome without a reason is refused', r.no_reason === 'refused'],
  ['2 a 1-star rating reaches the supplier decision as wrong', r.rating?.kind === 'rating' && r.rating?.correct === false && r.rating?.reason?.startsWith('rated 1/5')],
  ['2 a supplier who left reaches the supplier decision', r.left?.kind === 'supplier_left' && r.left?.correct === false],
  ['3 the CEO challenges a seat; the accountant challenges the CEO', r.reviewer_of_sales === 'ceo' && r.reviewer_of_ceo === 'accountant' && r.refund_reviewer === 'ceo'],
  ['3 an unknown kind is refused', r.unknown_kind === 'refused'],
  ['3 one deliberation per decision', r.one_per_decision === true],
  ['3 unreviewed = pending or held, never cleared', ['pending', 'held'].includes(r.pending?.state) && r.pending?.cleared === false],
  ['3 held = held, not cleared', r.held?.state === 'held' && r.held?.cleared === false],
  ['4 a reviewer of the author\'s family is refused', /SAME_FAMILY_REVIEW/.test(String(r.same_family))],
  ['4 a disagreement is not cleared and carries its reason', r.disagreed?.state === 'disagreed' && r.disagreed?.cleared === false && /win-rate/.test(r.disagreed?.reason ?? '')],
  ['4 an agreement on another family clears', r.agreed?.state === 'agreed' && r.agreed?.cleared === true && r.agreed?.reviewer_model === REVIEWER],
  ['no trigger failure recorded, nothing sent', Number(r.misses) === 0 && Number(r.notifications_queued) === 0],
  ['zero ZZ DEMO rows left', rowsLeft === 0],
];
for (const [name, ok] of checks) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
process.exit(checks.every(([, ok]) => ok) ? 0 : 1);
