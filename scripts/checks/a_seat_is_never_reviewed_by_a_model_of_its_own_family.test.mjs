// A SEAT IS NEVER REVIEWED BY A MODEL OF ITS OWN FAMILY (23 Sep 2026, it_engineer; founder_instruction 873).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the gateway stops routing a review through fn_ai_route_review, or lets a seat_deliberation class run
//     without the author's model (static, below);
//   * production (probe, below, inside ONE aborted transaction — the file itself is replayed first when it
//     is not applied yet, so nothing survives and nothing can reach a person):
//       - the database accepts a review turn on the author's family (recorded OR held);
//       - an author on Sol is not reviewed by Opus, or an author on Opus is not reviewed by the class's own fallback
//         (gpt-6-luna since founder_instruction 1056), or a fallback lies in the author's family;
//       - with the other family's breaker tripped, the review falls back instead of "no independent reviewer";
//       - the blind payload carries the proposal, or the comparison is built before a blind verdict;
//       - an approval without its steelman is accepted;
//       - the monitor stays silent on a 12-of-12 approval history, or raises on a 6-of-12 one;
//       - under the founder's hold a review step does anything but record "held, not run".
//
//   node --test scripts/checks/a_seat_is_never_reviewed_by_a_model_of_its_own_family.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql';
// The founder's model matrix (founder_instruction 1056) moves the review classes and the pool. Replayed first when it is
// not applied yet, like FILE, so the assertions below read the routes the matrix sets.
const MATRIX = 'scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql';
// Matrix v2 (5 Oct 2026): replayed while its pending note exists, so the assertions read the routes it sets.
const V2 = 'every_seat_runs_luna_with_gemini_behind_and_the_two_retired_models_leave_routing';
const V2_REPLAY = existsSync(join(REPO, 'scripts/sql/pending', `${V2}.txt`)) ? read(`scripts/sql/${V2}.sql`) + '\n' : '';

test('the gateway routes a review away from its author and refuses one that names no author model', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.match(gw, /counterpart \? await admin\.rpc\('fn_ai_route_review(_for)?'/, 'ai_gateway must route counterpart_model through fn_ai_route_review');
  assert.match(gw, /!counterpart && \/\^seat_deliberation_\//, 'a seat_deliberation class without counterpart_model must be refused');
  assert.match(read('supabase/functions/_shared/llm.ts'), /counterpart_model: opts\.counterpartModel/);
  const rp = read('supabase/functions/resilience_ping/index.ts');
  assert.match(rp, /advanceOpenDeliberations\(admin, 3\)/);
  assert.match(rp, /rpc\('fn_it_deliberation_independence_watch'\)/);
});

test('the file replays safely and closes every routine it defines', () => {
  const sql = read(FILE);
  assert.doesNotMatch(sql.replace(/--[^\n]*/g, ''), /^\s*(begin|commit)\s*;/im, 'no begin/commit: the check replays it inside an aborted transaction');
  const defined = [...sql.matchAll(/create or replace function public\.([a-z0-9_]+)\(/g)].map((m) => m[1]);
  for (const f of defined) assert.match(sql, new RegExp(`revoke execute on function public\\.${f}\\(`), `${f} has no revoke`);
  const blind = sql.slice(sql.indexOf('function public.fn_seat_deliberation_blind_payload'), sql.indexOf('function public.fn_seat_deliberation_compare_payload'));
  assert.doesNotMatch(blind, /'proposal',/, 'the blind payload must not carry a proposal key');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const PROBE = String.raw`
do $p$
declare
  o jsonb := '{}'::jsonb; v jsonb; v_id bigint; v_id2 bigint; e text; i int; n_before int;
  v_ev jsonb := '{"channel_spend_aed": 1200, "leads_last_30d": 40}'::jsonb;
  v_pr jsonb := '{"plan": "ZZ DEMO spend AED 900 on search, 300 on social"}'::jsonb;
  c_sol constant text := 'openai/gpt-5.6-sol'; c_opus constant text := 'anthropic/claude-opus-5.5';
  v_steel constant text := 'The strongest case against: forty leads a month cannot show that search outperforms social.';
  v_steel2 constant text := 'Against the revealed plan: a nine hundred dirham search budget is untested against any supplier gap.';
begin
  select count(*) into n_before from public.seat_deliberation where not demo;
  -- the file registers no pair; both exist only inside this rolled-back transaction unless production already has
  -- them (marketing -> ceo is #876's; sales_engineer -> ceo since the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql)
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('deliberation.review', 'marketing', 'ceo', 'ZZ DEMO probe pair', 'fn_seat_deliberation_acts_on_handoff', interval '2 days', true,
          'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.seat_deliberation_ceiling values ('marketing', 'ceo', 'marketing', 50, 'ZZ DEMO probe pair') on conflict do nothing;
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('deliberation.review', 'sales_engineer', 'ceo', 'ZZ DEMO probe pair', 'fn_seat_deliberation_acts_on_handoff', interval '2 days', true,
          'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.seat_deliberation_ceiling values ('sales_engineer', 'ceo', 'marketplace', 50, 'ZZ DEMO probe pair');

  -- ROUTING, both directions
  o := o || jsonb_build_object('sol_rev', public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo')->>'model',
                               'opus_rev', public.fn_ai_route_review('seat_deliberation_blind', c_opus, 'ceo')->>'model',
                               'sol_author_fallback', coalesce(public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo')->>'fallback', 'null'));

  -- OPEN under the hold: the reviewing seat's handler runs the step at once
  v_id := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo',
            'ZZ DEMO: should this month''s marketing plan be approved?', v_ev, v_pr, c_sol, null, null, null, true);
  select jsonb_build_object('status', status, 'provider', provider, 'why', left(why, 26))
    into v from public.seat_deliberation_turn where deliberation_id = v_id and phase = 'blind';
  o := o || jsonb_build_object('held_turn', v,
         'step_again', public.fn_seat_deliberation_step(v_id)->>'action',
         'held_turns_after_two_steps', (select count(*) from public.seat_deliberation_turn where deliberation_id = v_id and status = 'held_not_run'),
         'handoff_status', (select status || ':' || (detail ? 'awaiting') from public.agent_actions
                             where id = (select handoff_id from public.seat_deliberation where id = v_id)));

  -- SAME FAMILY is refused, recorded or held
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_sol, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 18); end;
  o := o || jsonb_build_object('same_family_recorded', e);
  begin
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model)
    values (v_id, 1, 'compare', 'ceo', 'failed', c_sol);
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 18); end;
  o := o || jsonb_build_object('same_family_failed_turn', e);

  -- BLIND: the proposal is not in the payload; the comparison cannot be built first
  v := public.fn_seat_deliberation_blind_payload(v_id);
  o := o || jsonb_build_object('blind_has_proposal_key', v ? 'proposal',
                               'blind_contains_proposal_text', strpos(v::text, v_pr::text) > 0,
                               'blind_has_independent_plan', jsonb_typeof(v->'independent_context'->'plan_targets'),
                               'blind_has_supply_gap', jsonb_typeof(v->'independent_context'->'supplier_gap_by_trade'));
  begin perform public.fn_seat_deliberation_compare_payload(v_id); e := 'BUILT';
  exception when others then e := left(sqlerrm, 11); end;
  o := o || jsonb_build_object('compare_before_blind', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO leak?',
              v_ev || jsonb_build_object('pasted', v_pr), v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('proposal_in_evidence', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO multi-line',
              v_ev || jsonb_build_object('note', 'ZZ DEMO spend AED 900' || chr(10) || 'on search,' || chr(9) || '300 on social'), v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('multi_line', e);
  insert into public.ai_cost_log (fn, agent_key, task_class, model_used, cost_aed, ok, occurred_at) values
    ('marketing', 'marketing', 'marketing_copy', c_sol, 0, true, now() - interval '2 hours'),
    ('marketing', 'marketing', 'marketing_copy', c_opus, 0, true, now() - interval '1 hour');
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'Real plan?', v_ev, v_pr, c_sol, 'marketing_copy', null, null, false);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 21); end;
  o := o || jsonb_build_object('author_not_latest', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO copied field', v_ev || jsonb_build_object('notes', jsonb_build_array('ok', jsonb_build_object('line', upper('zz demo spend aed 900 on search,   300 on social!')))), v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('one_copied_field', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO string-encoded', v_ev || jsonb_build_object('blob', v_pr::text), v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('string_encoded_proposal', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO should we: ZZ DEMO spend AED 900 on search, 300 on social?', v_ev, v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('proposal_in_question', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO wrapped', v_ev || jsonb_build_object('copied', 'ZZ DEMO spend AED 900 on search, 300 on social'), jsonb_build_object('doc', v_pr::text), c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 15); end;
  o := o || jsonb_build_object('proposal_string_encoded_in_proposal', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'Not a demo question', v_ev, v_pr, c_sol, null, null, null, true);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 21); end;
  o := o || jsonb_build_object('author_unproven_demo_flag_only', e);
  begin
    perform public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO real?', v_ev, v_pr, c_sol, null, null, null, false);
    e := 'OPENED';
  exception when others then e := left(sqlerrm, 21); end;
  o := o || jsonb_build_object('author_unproven_not_demo', e);

  -- STEELMAN: an approval without it is malformed
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', '  '));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('approval_without_steelman', e);
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', to_jsonb('No counter-case, this plan is fine as it stands'::text)));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('steelman_placeholder', e);
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', to_jsonb('Forty leads is thin'::text)));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('steelman_too_short', e);
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', jsonb_build_array('The strongest case against: forty leads a month cannot show that search wins.')));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('steelman_not_a_string', e);
  perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
  begin
    perform public.fn_seat_deliberation_record(v_id, 'compare', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', upper(v_steel),
              'agreements', 'the split', 'disagreements', 'none'));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('compare_repeats_blind_steelman', e);
  begin
    perform public.fn_seat_deliberation_record(v_id, 'compare', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel2));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('compare_without_agreements', e);
  -- A CEO decision carries its reasons (founder_instruction 1059, a_rejection_never_ends_the_cycle_...sql): the
  -- agreements are the approval's logic, so they are a sentence, and once that file is applied the author closes an
  -- approved deliberation the moment the CEO's decision reaches it. Both states read the same here.
  perform public.fn_seat_deliberation_record(v_id, 'compare', c_opus, jsonb_build_object('verdict', 'approve',
            'steelman_against', v_steel2, 'agreements', 'the split between search and social fits the lead volume we measured', 'disagreements', 'none'));
  o := o || jsonb_build_object('reviewed', (select case status when 'closed' then 'reviewed' else status end from public.seat_deliberation where id = v_id),
                               'compare_provider', (select provider from public.seat_deliberation_turn where deliberation_id = v_id and phase = 'compare' and status = 'recorded'));
  o := o || jsonb_build_object('close', (select case when d.status = 'closed'
                                                     then (select t.verdict from public.seat_deliberation_turn t where t.deliberation_id = d.id and t.phase = 'compare' and t.status = 'recorded' order by t.round desc limit 1)
                                                     else public.fn_seat_deliberation_close(v_id, 'marketing', 'ZZ DEMO approved')->>'final_verdict' end
                                           from public.seat_deliberation d where d.id = v_id));
  o := o || jsonb_build_object('handoff_done', (select status from public.agent_actions where id = (select handoff_id from public.seat_deliberation where id = v_id)));

  -- MONITOR: 12 of 12 approvals marketing -> ceo is a finding; 6 of 12 sales_engineer -> ceo is not
  for i in 1..12 loop
    v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO q' || i, v_ev, v_pr, c_sol, null, null, null, true);
    perform public.fn_seat_deliberation_record(v_id2, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
    perform public.fn_seat_deliberation_record(v_id2, 'compare', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel2, 'agreements', 'all of it: the split fits the lead volume we measured', 'disagreements', 'none'));
    v_id2 := public.fn_seat_deliberation_open('sales_engineer.zz_demo_share', 'sales_engineer', 'ceo', 'ZZ DEMO s' || i, v_ev, v_pr, c_opus, null, null, null, true);
    perform public.fn_seat_deliberation_record(v_id2, 'blind', c_sol, jsonb_build_object('verdict', case when i % 2 = 0 then 'approve' else 'reject' end, 'steelman_against', v_steel));
    perform public.fn_seat_deliberation_record(v_id2, 'compare', c_sol, jsonb_build_object('verdict', case when i % 2 = 0 then 'approve' else 'reject' end, 'steelman_against', v_steel2, 'agreements', 'some of the share estimate holds for this month', 'disagreements', 'the estimate leaves out two trades that have no suppliers yet'));
  end loop;
  v := public.fn_it_deliberation_independence_items(true);
  o := o || jsonb_build_object('monitor_items', (select jsonb_agg(x->>'item') from jsonb_array_elements(v) x),
    'monitor_marketing', (select jsonb_build_object('reviews', x->'evidence'->'reviews', 'approvals', x->'evidence'->'approvals') from jsonb_array_elements(v) x where x->>'item' = 'rubber_stamp:ceo:marketing'));

  -- UNHEALTHY OTHER FAMILY: Opus's breaker tripped by a real failure class -> no fallback to Sol
  update public.llm_route_health set opened_class = 'provider_error' where model_id in (c_opus, 'google/gemini-3.8-flash', 'openai/gpt-6-luna');  -- every family but the author's (third-family last resort, #880; the two retired models are inactive)
  v := public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo');
  o := o || jsonb_build_object('tripped_route', concat_ws(':', v->>'use_llm', v->>'no_independent_reviewer', coalesce(v->>'model', 'none')));
  v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO tripped', v_ev, v_pr, c_sol, null, null, null, true);
  o := o || jsonb_build_object('tripped_status', (select status from public.seat_deliberation where id = v_id2),
    'tripped_turn', (select status || ':' || coalesce(model, 'no model') from public.seat_deliberation_turn where deliberation_id = v_id2 and phase = 'blind'),
    'escalated_finding', (select count(*) from public.it_engineer_finding where issue_key = 'duty:deliberation_independence_demo:no_independent_reviewer:ceo:marketing' and closed_at is null));

  -- NO PAIR CEILING (24 Sep 2026, founder_instruction 987): marketing -> ceo has spent AED 60 this month (a rolled-back
  -- row, above the old AED 50 cap) and the review is still NOT held for spend
  update public.llm_route_health set opened_class = null where model_id in (c_opus, 'google/gemini-3.8-flash', 'openai/gpt-6-luna');
  insert into public.ai_cost_log (fn, dept_key, agent_key, task_class, model_used, cost_aed, ok)
  values ('resilience_ping', 'marketing', 'ceo', 'seat_deliberation_blind', c_opus, 60, true);
  v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO over budget', v_ev, v_pr, c_sol, null, null, null, true);
  o := o || jsonb_build_object('over_ceiling_turn', (select status || ':' || left(why, 27) from public.seat_deliberation_turn where deliberation_id = v_id2 and phase = 'blind'),
    'budget_ok', public.fn_seat_deliberation_budget('marketing', 'ceo')->'ok', 'no_ceil', public.fn_seat_deliberation_budget('accountant', 'ceo')->'ok',
    'no_ceil_dept', coalesce(public.fn_seat_deliberation_budget('accountant', 'ceo')->>'dept', 'none'),
    'no_ceil_why', public.fn_seat_deliberation_budget('accountant', 'ceo')->>'why', 'budget_dept', public.fn_seat_deliberation_budget('marketing', 'ceo')->>'dept');
  -- A DEMO NEVER REACHES call_model, even with the hold lifted (inside this rolled-back transaction only)
  delete from public.ai_cost_log where task_class = 'seat_deliberation_blind' and agent_key = 'ceo' and cost_aed = 60;
  update public.llm_route_health set open_until = null;
  v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO no hold', v_ev, v_pr, c_sol, null, null, null, true);
  o := o || jsonb_build_object('demo_unheld', (select left(why, 32) from public.seat_deliberation_turn where deliberation_id = v_id2 and phase = 'blind'));
  o := o || jsonb_build_object('real_deliberations_untouched', (select count(*) from public.seat_deliberation where not demo) = n_before);
  -- abbreviated because the management API returns only the first 2,000 characters of an error
  raise exception 'CHK<<%>>', replace(replace(replace(replace(replace(o::text, 'MALFORMED_REVIEW', '~MR'), 'BLIND_PASS_LEAK', '~BL'),
    'AUTHOR_MODEL_UNPROVEN', '~AU'), 'SAME_FAMILY_REVIEW', '~SF'), 'held, not run: ', '~H ');
end $p$;`;

test('production, in one aborted transaction: independence, blind first, steelman, monitor, and the hold', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`select to_regprocedure('public.fn_ai_route_review(text,text,text,text,text)') is not null applied,
    exists (select 1 from public.model_policy where task_class = 'internal_judgement') matrix_applied`, { readOnly: true });
  const body = (r.applied ? '' : read(FILE) + '\n') + (r.matrix_applied ? '' : read(MATRIX) + '\n') + V2_REPLAY + PROBE;
  let out;
  try {
    await replaySql(body, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    const full = { '~MR': 'MALFORMED_REVIEW', '~BL': 'BLIND_PASS_LEAK', '~AU': 'AUTHOR_MODEL_UNPROVEN', '~SF': 'SAME_FAMILY_REVIEW', '~H ': 'held, not run: ' };
    out = JSON.parse(m[1].replace(/\\"/g, '"').replace(/~MR|~BL|~AU|~SF|~H /g, (k) => full[k]));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out, null, 1));

  assert.equal(out.sol_rev, 'anthropic/claude-opus-5.5', 'an author on Sol is reviewed by Opus');
  // founder_instruction 1056: seat_deliberation is the CEO's review, Opus with gpt-6-luna as its own fallback. An Opus
  // author is therefore reviewed by luna, and a Sol author's fallback skips luna (Sol's family) for the pool's first
  // model, Gemini (matrix v2, 5 Oct 2026: DeepSeek left the pool and Gemini leads it).
  assert.equal(out.opus_rev, 'openai/gpt-6-luna', 'an author on Opus is reviewed by the class\'s own fallback, luna');
  assert.equal(out.sol_author_fallback, 'google/gemini-3.8-flash', 'no fallback may lie in the author\'s family (luna is Sol\'s)');

  assert.equal(out.held_turn.status, 'held_not_run', 'under the hold the blind step records held, not run');
  assert.equal(out.held_turn.provider, 'anthropic');
  assert.match(out.held_turn.why, /^held, not run: /);
  assert.equal(out.step_again, 'held');
  assert.equal(out.held_turns_after_two_steps, 1, 'held is recorded once, not every tick');
  assert.equal(out.handoff_status, 'pending:true', 'the review travels as a handoff awaiting its reply');

  assert.match(out.same_family_recorded, /^SAME_FAMILY_REVIEW/);
  assert.match(out.same_family_failed_turn, /^SAME_FAMILY_REVIEW/);

  assert.equal(out.blind_has_proposal_key, false);
  assert.equal(out.blind_contains_proposal_text, false);
  assert.equal(out.blind_has_independent_plan, 'array');
  assert.equal(out.blind_has_supply_gap, 'array');
  assert.equal(out.compare_before_blind, 'BLIND_FIRST');
  assert.equal(out.proposal_in_evidence, 'BLIND_PASS_LEAK');
  for (const k of ['one_copied_field', 'string_encoded_proposal', 'proposal_in_question', 'proposal_string_encoded_in_proposal'])
    assert.equal(out[k], 'BLIND_PASS_LEAK', k);
  assert.equal(out.author_unproven_demo_flag_only, 'AUTHOR_MODEL_UNPROVEN');
  assert.equal(out.author_unproven_not_demo, 'AUTHOR_MODEL_UNPROVEN');
  assert.equal(out.author_not_latest, 'AUTHOR_MODEL_UNPROVEN', 'the latest call on the class decides the author model');
  assert.equal(out.multi_line, 'BLIND_PASS_LEAK', 'a multi-line copy is caught');
  assert.equal(out.demo_unheld, 'held, not run: demo deliberation');
  for (const k of ['steelman_placeholder', 'steelman_too_short', 'steelman_not_a_string', 'compare_repeats_blind_steelman'])
    assert.equal(out[k], 'MALFORMED_REVIEW', k);
  assert.doesNotMatch(String(out.over_ceiling_turn), /pair_ceiling/, 'spend no longer holds a review (founder_instruction 987)');
  assert.equal(out.budget_ok, true);
  // A pair with no ceiling row (accountant -> ceo has none on production) is NOT held: founder_instruction 987 (24 Sep
  // 2026, #936) removed every spend cap, and fn_seat_deliberation_budget has answered ok for every pair since. This line
  // asserted the pre-987 rule ("held") and failed from then on; it now asserts the rule in force, and still fails if a
  // cap comes back (ok false), if the missing row is invented (a dept appears), or if the answer stops naming 987.
  assert.equal(out.no_ceil, true, 'a pair with no ceiling row is held for spend again (founder_instruction 987: no caps)');
  assert.equal(out.no_ceil_dept, 'none', 'accountant -> ceo gained a ceiling row; pick a pair that has none');
  assert.match(String(out.no_ceil_why), /no limit \(founder_instruction 987\)/);
  assert.equal(out.budget_dept, 'marketing');

  assert.equal(out.approval_without_steelman, 'MALFORMED_REVIEW');
  assert.equal(out.compare_without_agreements, 'MALFORMED_REVIEW');
  assert.equal(out.reviewed, 'reviewed');
  assert.equal(out.compare_provider, 'anthropic');
  assert.equal(out.close, 'approve');
  assert.equal(out.handoff_done, 'done', 'the originator closes the handoff');

  assert.ok(out.monitor_items.includes('rubber_stamp:ceo:marketing'), '12 of 12 approvals must raise the finding');
  assert.ok(!out.monitor_items.includes('rubber_stamp:ceo:sales_engineer'), '6 of 12 must not: independence, not forced conflict');
  assert.equal(out.monitor_marketing.reviews, 13);
  assert.equal(out.monitor_marketing.approvals, 13);

  assert.equal(out.tripped_route, 'false:true:none');
  assert.equal(out.tripped_status, 'no_independent_reviewer');
  assert.equal(out.tripped_turn, 'no_independent_reviewer:no model');
  assert.equal(out.escalated_finding, 1, 'no independent reviewer is escalated as a finding');
  assert.equal(out.real_deliberations_untouched, true);
});
