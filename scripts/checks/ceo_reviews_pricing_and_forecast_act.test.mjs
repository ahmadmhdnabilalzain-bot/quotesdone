// THE CEO'S WEEKLY REVIEW, PRICING MONITOR AND TARGET FORECAST ACT, AND EACH CALL IS CHALLENGED (23 Sep 2026; instr. 898).
//
// WHAT FAILS IF THE CAUSE RETURNS — production, in ONE aborted transaction (the pending files replayed first; the
// founder path runs with app.qd_stub_founder_notify on and the whole block rolls back, so nothing reaches him):
//   * target_forecast: no verdict is recorded for the instrumented contracts, or an off-track revenue verdict is not
//     filed as ONE normal-stakes CEO decision, or "tell the founder" does not reach him through customer_support,
//     challenged by the accountant through a cross-family seat_deliberation;
//   * management_review: the week is not gathered per seat, is filed twice, asks the model more than the verdict and
//     the binding constraint, or an internal verdict spends a second (challenge) call - 24 Sep 2026, it_engineer:
//     routine work is code, one reasoned line per report;
//   * pricing_monitor: thin evidence (under 20 quoted requests) is reasoned instead of recorded as insufficient, or a
//     pricing proposal on 20 ZZ DEMO quoted requests is not challenged by the accountant (review of #1228);
//   * any reasoned choice outside the options is applied instead of raising.
//
//   node --test scripts/checks/ceo_reviews_pricing_and_forecast_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const CEO = 'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql';
const FILES = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql', CEO,
  'scripts/sql/routine_work_is_code_and_the_model_answers_only_real_judgement.sql',
  'scripts/sql/the_ceo_management_review_request_fits_the_reasoning_limit.sql',
  'scripts/sql/the_ceo_review_proves_its_author_on_the_class_think_bills.sql',
  'scripts/sql/a_fenced_seat_duty_keeps_its_fixture_switch.sql'];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('the reveal fee is out of the pricing review, and no price is written', () => {
  const src = read(CEO).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  assert.match(src, /3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope/, 'the pricing question no longer excludes the 3% reveal fee');
  assert.ok(!/update public\.pricing_config/.test(src), 'the CEO duty writes a price; pricing is the founder\'s');
});

test('static: revokes, pinned search_path, RLS + policy, duty prefix = owner seat, pending XOR MANIFEST', () => {
  const src = read(CEO).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  const made = [...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
  assert.ok(made.length >= 9, `expected the CEO routines, found ${made.length}`);
  for (const name of made) {
    const head = src.slice(src.indexOf(`function public.${name}(`)).split('$')[0];
    assert.match(head, /security definer\s+set search_path to 'public', 'pg_temp'/, `${name} is not security definer with a pinned search_path`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  assert.match(src, /alter table public\.ceo_review enable row level security/, 'ceo_review has no RLS');
  assert.match(src, /create policy ceo_review_service_role_only on public\.ceo_review[^;]*using \(false\) with check \(false\)/, 'ceo_review has no service-role-only policy');
  const duties = [...src.matchAll(/\('(\w+)\.(\w+)', '(\w+)', interval/g)];
  assert.equal(duties.length, 3, 'expected three ceo duties');
  for (const [, prefix, , owner] of duties) assert.equal(prefix, owner, `duty ${prefix} is registered to ${owner}`);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(CEO) !== manifest.includes(CEO), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken =!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  try { await replaySql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: the forecast, the management review and the pricing monitor act and are challenged', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; h bigint; n bigint; wk date := public.fn_ceo_review_week(); cust uuid; sup bigint; iq uuid; i int; begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  -- NOTHING IS DELETED (review of #1228). The probe drives this week's three rows; a row a real run already decided is
  -- rewound for the probe only - by its exact kind and week - and the whole block rolls back, so the real row returns.
  update public.ceo_review set held_id = null, decision = null, decided_at = null, review = null
   where period = wk and kind in ('target_forecast', 'management_review', 'pricing_monitor');
  -- the author model is proven the way fn_seat_duty_cross_review proves it: the seat's latest internal_judgement call
  -- (founder_instruction 1056, 29 Sep: think()'s decision class; CEO hard work runs on anthropic/claude-opus-5.5)
  insert into public.ai_cost_log (fn, agent_key, seat, task_class, model_used, ok) values ('probe', 'ceo', 'ceo', 'internal_judgement', 'anthropic/claude-opus-5.5', true);

  v := public.fn_ceo_target_forecast();
  o := o || jsonb_build_object('verdicts', jsonb_array_length(v->'verdicts'),
    'recorded', (select count(*) from public.target_verdict where run_at > now() - interval '1 minute'));
  select held_id into h from public.ceo_review where kind = 'target_forecast' and period = wk;
  if h is not null then
    o := o || jsonb_build_object('fc_held', (select jsonb_build_object('seat', seat, 'stakes', request->>'stakes') from public.reasoning_held_question where id = h));
    begin
      perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"x","decision":{"choice":"panic"}}');
      o := o || jsonb_build_object('bad_choice', 'applied');
    exception when others then o := o || jsonb_build_object('bad_choice', left(sqlerrm, 40)); end;
    select coalesce(max(id), 0) into n from public.agent_actions;
    perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: this needs the founder","model":"anthropic/claude-opus-5.5","decision":{"choice":"tell_founder","fields":{}}}');
    o := o || jsonb_build_object('fc', (select jsonb_build_object('decision', decision, 'founder', founder_notice->'evidence'->>'stubbed', 'challenged', (review->>'deliberation_id') is not null)
                                          from public.ceo_review where kind = 'target_forecast' and period = wk),
      'founder_via', (select jsonb_agg(distinct agent) from public.agent_actions where id > n and kind = 'handoff' and detail->>'recipient_role' = 'founder'));
  end if;

  v := public.fn_ceo_management_review();
  o := o || jsonb_build_object('mr_again', public.fn_ceo_management_review()->'already_filed',
    'mr_seats', (select count(*) from public.ceo_review r, jsonb_object_keys(r.facts->'seats') k where r.kind = 'management_review' and r.period = wk));
  select held_id into h from public.ceo_review where kind = 'management_review' and period = wk;
  o := o || jsonb_build_object('mr_fields', (select jsonb_array_length(request->'decision'->'fields') from public.reasoning_held_question where id = h));
  perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: supply is the binding constraint.","model":"anthropic/claude-opus-5.5","decision":{"choice":"off_track","fields":{"binding_constraint":{"value":"verified suppliers per trade","evidence":"0 categories open"}}}}');
  o := o || jsonb_build_object('mr', (select jsonb_build_object('decision', decision, 'binding', fields->>'binding_constraint',
            'reviewer', (select reviewer_seat from public.seat_deliberation where id = (review->>'deliberation_id')::bigint)) from public.ceo_review where kind = 'management_review' and period = wk));

  v := public.fn_ceo_pricing_monitor();
  o := o || jsonb_build_object('pm_quoted', v->'quoted_requests_90d', 'pm_filed', v->'reasoning_filed',
    'pm_decision', (select decision from public.ceo_review where kind = 'pricing_monitor' and period = wk));

  -- THE PRICING PROPOSAL, DRIVEN TO THE ACCOUNTANT'S CHALLENGE (review of #1228): 20 ZZ DEMO quoted requests make the
  -- evidence sufficient, the CEO proposes a change, and the high-stakes gate must open the cross-family review.
  insert into public.customers (full_name, email, locale) values ('ZZ DEMO pricing probe customer', 'zz-demo-pricing-probe@example.invalid', 'en') returning id into cust;
  insert into public.leads (company_name, email) values ('ZZ DEMO — pricing probe supplier', 'zz-demo-pricing-probe-sup@example.invalid') returning id into sup;
  for i in 1..20 loop
    insert into public.inquiries (customer_id, category, emirate, lang, status, summary)
      values (cust, 'zz_demo_pricing_trade', 'Dubai', 'en', 'quoted', 'ZZ DEMO pricing probe ' || i) returning id into iq;
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (iq, sup, 1000 + i, 'draft');
  end loop;
  update public.ceo_review set held_id = null, decision = null, decided_at = null, review = null where period = wk and kind = 'pricing_monitor';
  v := public.fn_ceo_pricing_monitor();
  select held_id into h from public.ceo_review where kind = 'pricing_monitor' and period = wk;
  o := o || jsonb_build_object('pp_quoted', v->'quoted_requests_90d', 'pp_filed', v->'reasoning_filed');
  if h is not null then
    perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: the evidence supports a change.","model":"anthropic/claude-opus-5.5","decision":{"choice":"propose_change","fields":{"proposal":{"value":"ZZ DEMO change"},"evidence":{"value":"ZZ DEMO 20 quoted requests"}}}}');
    o := o || jsonb_build_object('pp', (select jsonb_build_object('decision', decision,
              'challenged', (review->>'deliberation_id') is not null,
              'reviewer', (select reviewer_seat from public.seat_deliberation where id = (review->>'deliberation_id')::bigint),
              'open_error', review->>'open_error')
            from public.ceo_review where kind = 'pricing_monitor' and period = wk));
  end if;
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.ok(o.verdicts >= 1 && o.recorded >= 1, 'no feasibility verdict was recorded');
  if (o.fc_held) {
    assert.deepEqual(o.fc_held, { seat: 'ceo', stakes: 'normal' }, 'the forecast call is not one normal-stakes think() call');
    assert.match(o.bad_choice, /^CHOICE_NOT_AN_OPTION/, 'a choice outside the options was applied');
    assert.deepEqual(o.fc, { decision: 'tell_founder', founder: 'true', challenged: true }, 'tell_founder did not reach the (stubbed) founder or was not challenged');
    assert.deepEqual(o.founder_via, ['customer_support'], 'the founder was not told through customer_support');
  }
  assert.equal(o.mr_again, true, 'the management review was filed twice in one week');
  assert.ok(o.mr_seats >= 6, 'the week was not gathered for every seat');
  assert.equal(o.mr_fields, 1, 'the review asks the model more than the verdict and the binding constraint');
  assert.deepEqual(o.mr, { decision: 'off_track', binding: 'verified suppliers per trade', reviewer: null }, 'the review was not recorded, or an internal verdict spent a cross-family challenge call');
  if (o.pm_quoted < 20) {
    assert.equal(o.pm_filed, false, 'thin pricing evidence was reasoned');
    assert.equal(o.pm_decision, 'insufficient_evidence');
  } else {
    assert.equal(o.pm_filed, true, 'enough pricing evidence was not reasoned');
  }
  assert.ok(o.pp_quoted >= 20, 'the 20 ZZ DEMO quoted requests were not counted');
  assert.equal(o.pp_filed, true, 'sufficient pricing evidence was not reasoned');
  assert.deepEqual(o.pp, { decision: 'propose_change', challenged: true, reviewer: 'accountant', open_error: null },
    'a pricing proposal reached the founder path without the accountant cross-family challenge');
});
