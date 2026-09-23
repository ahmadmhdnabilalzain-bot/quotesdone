// A SEAT IS NEVER REVIEWED BY A MODEL OF ITS OWN FAMILY (23 Sep 2026, it_engineer; founder_instruction 873).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the gateway stops routing a review through fn_ai_route_review, or lets a seat_deliberation class run
//     without the author's model (static, below);
//   * production (probe, below, inside ONE aborted transaction — the file itself is replayed first when it
//     is not applied yet, so nothing survives and nothing can reach a person):
//       - the database accepts a review turn on the author's family (recorded OR held);
//       - an author on Sol is not reviewed by Opus, or an author on Opus is not reviewed by Sol;
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

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql';

test('the gateway routes a review away from its author and refuses one that names no author model', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.match(gw, /counterpart \? await admin\.rpc\('fn_ai_route_review'/, 'ai_gateway must route counterpart_model through fn_ai_route_review');
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
begin
  select count(*) into n_before from public.seat_deliberation where not demo;

  -- ROUTING, both directions
  o := o || jsonb_build_object('sol_author_reviewer', public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo')->>'model',
                               'opus_author_reviewer', public.fn_ai_route_review('seat_deliberation_blind', c_opus, 'ceo')->>'model',
                               'sol_author_fallback', coalesce(public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo')->>'fallback', 'null'));

  -- OPEN under the hold: the reviewing seat's handler runs the step at once
  v_id := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo',
            'ZZ DEMO: should this month''s marketing plan be approved?', v_ev, v_pr, c_sol, null, null, null, true);
  select jsonb_build_object('status', status, 'model', model, 'provider', provider, 'why', left(why, 60))
    into v from public.seat_deliberation_turn where deliberation_id = v_id and phase = 'blind';
  o := o || jsonb_build_object('held_turn', v,
         'step_again', public.fn_seat_deliberation_step(v_id)->>'action',
         'held_turns_after_two_steps', (select count(*) from public.seat_deliberation_turn where deliberation_id = v_id and status = 'held_not_run'),
         'handoff_status', (select status || ':' || coalesce(detail->>'awaiting', '') from public.agent_actions
                             where id = (select handoff_id from public.seat_deliberation where id = v_id)));

  -- SAME FAMILY is refused, recorded or held
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_sol, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 40); end;
  o := o || jsonb_build_object('same_family_recorded', e);
  begin
    insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model)
    values (v_id, 1, 'compare', 'ceo', 'failed', c_sol);
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 40); end;
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

  -- STEELMAN: an approval without it is malformed
  begin
    perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', '  '));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('approval_without_steelman', e);
  perform public.fn_seat_deliberation_record(v_id, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
  begin
    perform public.fn_seat_deliberation_record(v_id, 'compare', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
    e := 'ACCEPTED';
  exception when others then e := left(sqlerrm, 16); end;
  o := o || jsonb_build_object('compare_without_agreements', e);
  perform public.fn_seat_deliberation_record(v_id, 'compare', c_opus, jsonb_build_object('verdict', 'approve',
            'steelman_against', v_steel, 'agreements', 'the split', 'disagreements', 'none'));
  o := o || jsonb_build_object('reviewed', (select status from public.seat_deliberation where id = v_id),
                               'compare_provider', (select provider from public.seat_deliberation_turn where deliberation_id = v_id and phase = 'compare' and status = 'recorded'),
                               'close', public.fn_seat_deliberation_close(v_id, 'marketing', 'ZZ DEMO approved')->>'final_verdict');
  o := o || jsonb_build_object('handoff_done', (select status from public.agent_actions where id = (select handoff_id from public.seat_deliberation where id = v_id)));

  -- MONITOR: 12 of 12 approvals marketing -> ceo is a finding; 6 of 12 sales_engineer -> ceo is not
  for i in 1..12 loop
    v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO q' || i, v_ev, v_pr, c_sol, null, null, null, true);
    perform public.fn_seat_deliberation_record(v_id2, 'blind', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel));
    perform public.fn_seat_deliberation_record(v_id2, 'compare', c_opus, jsonb_build_object('verdict', 'approve', 'steelman_against', v_steel, 'agreements', 'all', 'disagreements', 'none'));
    v_id2 := public.fn_seat_deliberation_open('sales_engineer.zz_demo_share', 'sales_engineer', 'ceo', 'ZZ DEMO s' || i, v_ev, v_pr, c_opus, null, null, null, true);
    perform public.fn_seat_deliberation_record(v_id2, 'blind', c_sol, jsonb_build_object('verdict', case when i % 2 = 0 then 'approve' else 'reject' end, 'steelman_against', v_steel));
    perform public.fn_seat_deliberation_record(v_id2, 'compare', c_sol, jsonb_build_object('verdict', case when i % 2 = 0 then 'approve' else 'reject' end, 'steelman_against', v_steel, 'agreements', 'some', 'disagreements', 'some'));
  end loop;
  v := public.fn_it_deliberation_independence_items(true);
  o := o || jsonb_build_object('monitor_items', (select jsonb_agg(x->>'item') from jsonb_array_elements(v) x),
    'monitor_marketing', (select x->'evidence' from jsonb_array_elements(v) x where x->>'item' = 'rubber_stamp:ceo:marketing'));

  -- UNHEALTHY OTHER FAMILY: Opus's breaker tripped by a real failure class -> no fallback to Sol
  update public.llm_route_health set opened_class = 'provider_error' where model_id = c_opus;
  v := public.fn_ai_route_review('seat_deliberation_blind', c_sol, 'ceo');
  o := o || jsonb_build_object('tripped_route', jsonb_build_object('use_llm', v->'use_llm', 'no_independent_reviewer', v->'no_independent_reviewer', 'model', v->'model'));
  v_id2 := public.fn_seat_deliberation_open('marketing.zz_demo_plan', 'marketing', 'ceo', 'ZZ DEMO tripped', v_ev, v_pr, c_sol, null, null, null, true);
  o := o || jsonb_build_object('tripped_status', (select status from public.seat_deliberation where id = v_id2),
    'tripped_turn', (select status || ':' || coalesce(model, 'no model') from public.seat_deliberation_turn where deliberation_id = v_id2 and phase = 'blind'),
    'escalated_finding', (select count(*) from public.it_engineer_finding where issue_key = 'duty:deliberation_independence_demo:no_independent_reviewer:ceo:marketing' and closed_at is null));

  o := o || jsonb_build_object('real_deliberations_untouched', (select count(*) from public.seat_deliberation where not demo) = n_before);
  raise exception 'CHK<<%>>', o::text;
end $p$;`;

test('production, in one aborted transaction: independence, blind first, steelman, monitor, and the hold', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`select to_regprocedure('public.fn_ai_route_review(text,text,text,text,text)') is not null applied`, { readOnly: true });
  const body = (r.applied ? '' : read(FILE) + '\n') + PROBE;
  let out;
  try {
    await sql(body, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out, null, 1));

  assert.equal(out.sol_author_reviewer, 'anthropic/claude-opus-5.5', 'an author on Sol is reviewed by Opus');
  assert.equal(out.opus_author_reviewer, 'openai/gpt-5.6-sol', 'an author on Opus is reviewed by Sol');
  assert.equal(out.sol_author_fallback, 'null', 'no fallback may lie in the author\'s family');

  assert.equal(out.held_turn.status, 'held_not_run', 'under the hold the blind step records held, not run');
  assert.equal(out.held_turn.provider, 'anthropic');
  assert.match(out.held_turn.why, /^held, not run: /);
  assert.equal(out.step_again, 'held');
  assert.equal(out.held_turns_after_two_steps, 1, 'held is recorded once, not every tick');
  assert.match(out.handoff_status, /^pending:/, 'the review travels as a handoff awaiting its reply');

  assert.match(out.same_family_recorded, /^SAME_FAMILY_REVIEW/);
  assert.match(out.same_family_failed_turn, /^SAME_FAMILY_REVIEW/);

  assert.equal(out.blind_has_proposal_key, false);
  assert.equal(out.blind_contains_proposal_text, false);
  assert.equal(out.blind_has_independent_plan, 'array');
  assert.equal(out.blind_has_supply_gap, 'array');
  assert.equal(out.compare_before_blind, 'BLIND_FIRST');
  assert.equal(out.proposal_in_evidence, 'BLIND_PASS_LEAK');

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

  assert.deepEqual(out.tripped_route, { use_llm: false, no_independent_reviewer: true, model: null });
  assert.equal(out.tripped_status, 'no_independent_reviewer');
  assert.equal(out.tripped_turn, 'no_independent_reviewer:no model');
  assert.equal(out.escalated_finding, 1, 'no independent reviewer is escalated as a finding');
  assert.equal(out.real_deliberations_untouched, true);
});
