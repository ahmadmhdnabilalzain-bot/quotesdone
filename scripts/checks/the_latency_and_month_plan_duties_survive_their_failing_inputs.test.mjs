// THE LATENCY AND MONTH-PLAN DUTIES SURVIVE THE INPUTS THAT STOPPED THEM (it_engineer, 27 Oct 2026).
//
// Measured 26 Oct 2026 21:00Z by the local gate: it_engineer.latency_slo had failed 115 runs in a row and
// marketing.month_plan 7 days running.
//   * latency_slo: a function past its 30-day error budget with no counted run in the last 24 h (customer_api: all
//     118 runs were HTTP 204) has burn_rate_24h = null; the finding title concatenated it, came out null, and
//     fn_it_duty_settle refused the whole batch every hour.
//   * month_plan: the November plan's round-2 revision question failed three model attempts on 13 Oct and nothing
//     asked it again, and the revision path never changed the idea list the CEO reviews (round 2 was rejected for
//     being word for word round 1).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the canonical latency routine concatenates burn_rate_24h without a fallback; the revision question for
//     a month plan stops asking for the idea list; the tick stops re-asking a revision whose question died;
//   * production, in ONE rolled-back transaction (pending files replayed first, ZZ DEMO rows and the year 2099 only):
//       - a ZZ DEMO function with a 30-day breach and no counted runs today: the duty settles and titles the finding;
//       - a 2099 plan whose revision question failed: the tick asks again under a fresh key, a prose-only 'revised'
//         answer is refused, and a revision with its idea list replaces the ideas (weekend and other-month lines
//         dropped) and goes back to the CEO as the next round.
//   Against production before the two files, both production tests fail.
//
//   node --test scripts/checks/the_latency_and_month_plan_duties_survive_their_failing_inputs.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const LATENCY = 'scripts/sql/the_latency_duty_titles_an_error_budget_breach_on_a_day_with_no_counted_runs.sql';
const PLAN = 'scripts/sql/a_month_plan_revision_carries_its_ideas_and_a_failed_one_is_asked_again.sql';

function canonical() {
  const out = new Map();
  for (const f of manifestWithPending()) {
    if (!existsSync(join(REPO, f))) continue;
    for (const d of definitions(readFileSync(join(REPO, f), 'utf8'))) out.set(d.name, d.stmt.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n'));
  }
  return out;
}

test('static: the canonical routines carry the three fixes', () => {
  const c = canonical();
  assert.match(c.get('fn_it_engineer_latency_slo'), /coalesce\(' is burning its error budget at ' \|\| \(j->>'burn_rate_24h'\)/,
    'the error-budget title concatenates burn_rate_24h with no fallback (null on a day with no counted runs)');
  assert.match(c.get('fn_seat_revises_for_the_ceo'), /'marketing_month_plan' then[\s\S]*'key', 'ideas'/, 'a month-plan revision is not asked for its idea list');
  assert.match(c.get('fn_seat_revises_for_the_ceo'), /':retry' \|\| v_n/, 'a failed revision question is never asked again under a fresh key');
  assert.match(c.get('fn_ceo_revision_applies'), /fn_marketing_month_plan_parse_ideas\(/, 'the revision does not replace the idea list');
  assert.match(c.get('fn_marketing_month_plan_tick'), /fn_seat_revises_for_the_ceo\(v_owed\.id\)/, 'the tick does not re-ask a revision whose question died');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  const text = [LATENCY, PLAN].map((f) => readFileSync(join(REPO, f), 'utf8')).join('\n;\n') + '\n;\n' + block;
  try { await replaySql(text, { retry: false, label: 'duty failing-input probe' }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1200));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, rolled back: a 30-day breach with no counted runs today settles and is titled', { skip: SKIP, timeout: 300000 }, async () => {
  const o = await probe(String.raw`
do $p$ declare o jsonb; v jsonb; begin
  insert into public.agent_runs (agent, started_at, status, counts)
  select 'fn:zz_demo_slo', now() - interval '2 days' - g * interval '1 minute', 'ok', '{"ms": 900, "budget_ms": 100, "http": 200, "method": "GET"}'::jsonb
    from generate_series(1, 6) g;
  v := public.fn_it_engineer_latency_slo();
  o := jsonb_build_object(
    'row', (select e from jsonb_array_elements(v->'functions') e where e->>'fn' = 'zz_demo_slo'),
    'title', (select title from public.it_engineer_finding where issue_key = 'duty:latency_slo:zz_demo_slo:error_budget' and closed_at is null));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  assert.equal(o.row?.runs_30d, 6, 'the ZZ DEMO runs were not counted');
  assert.equal(o.row?.burn_rate_24h, null, 'the probe did not reproduce the null 24-hour burn rate');
  assert.match(String(o.title), /^zz_demo_slo has spent its error budget \(no counted runs in the last 24 h\); 30-day availability 0\.00 %/,
    'the breach was not filed with a title: ' + JSON.stringify(o));
});

test('production, rolled back: a dead revision question is asked again and a revision replaces the ideas', { skip: SKIP, timeout: 300000 }, async () => {
  const o = await probe(String.raw`
do $p$ declare o jsonb := '{}'; v jsonb; h1 bigint; rh bigint; rq bigint; rq2 bigint;
  c_reasons constant text := 'Re-weight the list towards suppliers and restate every claim we cannot yet stand behind, then resubmit the list.';
begin
  if exists (select 1 from public.marketing_month_plan where month = date '2099-11-01') then
    raise exception 'CHK<<{"refused":"a plan exists for November 2099; the probe will not touch it"}>>';
  end if;
  v := public.fn_marketing_month_plan_tick(date '2099-10-20');
  h1 := (v->'filed'->>'held_id')::bigint;
  v := public.fn_reason_apply_ceo__marketing_month_plan(h1, jsonb_build_object('decision', jsonb_build_object('choice', 'reject'), 'answer', c_reasons));
  select a.id into rh from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise'
     and a.detail->>'item_key' = 'marketing_month_plan:2099-11-01';
  -- the dispatcher asked once (as on 12 Oct); that question then failed every model attempt more than 7 days ago
  rq := (public.fn_seat_revises_for_the_ceo(rh)->>'held_id')::bigint;
  update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('held_id', rq) where id = rh;
  update public.reasoning_held_question set status = 'failed', attempts = 3, last_attempt_at = now() - interval '8 days' where id = rq;
  o := o || jsonb_build_object('asks_for_ideas', (select request->'decision'->'fields' @> '[{"key":"ideas"}]' from public.reasoning_held_question where id = rq));
  v := public.fn_marketing_month_plan_tick(date '2099-10-21');
  rq2 := (v->'revision_asked_again'->>'held_id')::bigint;
  o := o || jsonb_build_object('asked_again', rq2 is not null and rq2 <> rq,
    'q2', (select jsonb_build_object('status', status, 'key', dedupe_key) from public.reasoning_held_question where id = rq2),
    'evidence_points_at_it', (select (evidence->>'held_id')::bigint = rq2 from public.agent_actions where id = rh));
  begin
    perform public.fn_ceo_revision_applies(rq2, jsonb_build_object('decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
      'revision', 'All five directives are met in the plan.', 'answers', 'Every one of the CEO reasons is now answered in the resubmitted plan.')),
      'answer', 'Revised as the CEO asked.'));
    o := o || '{"prose_only":"accepted"}';
  exception when check_violation then o := o || jsonb_build_object('prose_only', split_part(sqlerrm, ':', 1)); end;
  v := public.fn_ceo_revision_applies(rq2, jsonb_build_object('decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
      'revision', 'Supplier-weighted list.', 'answers', 'Re-weighted to suppliers and every claim restated as the CEO asked in round one.',
      'ideas', E'1. 2099-11-02 | supplier | ZZ DEMO one | ZZ DEMO hook | ZZ DEMO cta | ZZ DEMO film\n'
            || E'2099-11-04 | Supplier | ZZ DEMO two | ZZ DEMO hook | ZZ DEMO cta\n'
            || E'2099-11-07 | supplier | ZZ DEMO a Saturday | hook | cta\n'
            || E'2099-12-01 | supplier | ZZ DEMO next month | hook | cta\n'
            || E'not an idea line at all')),
      'answer', 'Revised: a supplier-weighted idea list.'));
  o := o || jsonb_build_object('resubmitted', v->'resubmission'->'filed', 'round', v->'resubmission'->'round',
    'ideas', (select jsonb_agg(e->>'date' || ':' || (e->>'n') || ':' || (e->>'audience')) from public.marketing_month_plan m, jsonb_array_elements(m.plan->'ideas') e where month = '2099-11-01'),
    'brief_count', (select content_brief->'videos'->'count' from public.marketing_month_plan where month = '2099-11-01'));
  raise exception 'CHK<<%>>', o::text;
end $p$;`);
  assert.equal(o.refused, undefined, o.refused);
  assert.equal(o.asks_for_ideas, true, 'the revision question does not ask for the idea list');
  assert.equal(o.asked_again, true, 'the tick did not ask the dead revision again: ' + JSON.stringify(o));
  assert.deepEqual(o.q2, { status: 'held', key: 'ceo_revision:marketing_month_plan:2099-11-01:g1:r1:retry1' });
  assert.equal(o.evidence_points_at_it, true, 'the handoff does not point at the new question');
  assert.equal(o.prose_only, 'UNANSWERED_REVISION', 'a prose-only revised answer was accepted again');
  assert.equal(o.resubmitted, true, 'the revision did not go back to the CEO');
  assert.equal(o.round, 2);
  assert.deepEqual(o.ideas, ['2099-11-02:1:supplier', '2099-11-04:2:supplier'], 'the idea list was not replaced by the parsed revision');
  assert.equal(o.brief_count, 2);
});
