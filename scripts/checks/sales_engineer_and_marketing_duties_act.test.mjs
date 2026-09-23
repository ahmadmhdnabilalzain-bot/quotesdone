// THE SALES ENGINEER'S AND MARKETING'S DUTIES ACT (23 Sep 2026; founder_instruction 898).
//
// WHAT FAILS IF THE CAUSE RETURNS — production, in ONE aborted transaction (the pending files replayed first; ZZ DEMO
// and example.invalid only; every message is a queued row that rolls back, so nothing reaches a person):
//   * supplier_onboarding: the matched ZZ DEMO supplier is not at stage 'matched', is not nudged after 3 days, or is
//     nudged twice in one week;
//   * supplier_performance: nothing is scored, or fn_match_capability stops reading supplier_performance;
//   * supply_gap: a waiting customer's trade is not recruited for by rule, a gap nobody waits on is not filed as a
//     high-stakes reasoned decision of the sales engineer, a reasoned 'recruit' does not reach marketing through a
//     cross-family review, or a choice outside the options is applied;
//   * recruitment_funnel: a recruiting gap has no funnel row, or its leads do not go first in the invitation queue;
//   * reputation: a missing review link is not a finding, the ask does not go through customer_support once the link
//     exists, or it goes twice.
//
//   node --test scripts/checks/sales_engineer_and_marketing_duties_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SALES = 'scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql';
const MKT = 'scripts/sql/marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql';
const FILES = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql', SALES, MKT];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('matching reads the measured score and the invitation queue reads the recruit targets', () => {
  const s = read(SALES), m = read(MKT);
  assert.match(s, /left join public\.supplier_performance pf on pf\.lead_id = sc\.supplier_id/, 'fn_match_capability does not join supplier_performance');
  assert.match(s, /coalesce\(pf\.score, sp\.quote_rate, sp\.perf_score, 0\)/, 'the measured score is not the first track-record input');
  assert.match(m, /order by r\.target_rank, r\.is_none/, 'recruit targets do not go first in the invitation queue');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  try { await sql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: onboarding, performance, supply gaps, the funnel and reputation all act', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; lid bigint; inq uuid; h bigint; n bigint; c uuid; tr text; em text; begin
  -- ONBOARDING: the ZZ DEMO approved supplier is matched to an open request 4 days ago and has not quoted.
  -- a ZZ DEMO supplier on a reserved example domain who has never quoted
  select id into lid from public.leads l where l.company_name like 'ZZ DEMO%' and split_part(l.email, '@', 2) in ('example.invalid', 'example.com')
     and l.approval_status = 'approved' and not exists (select 1 from public.quotes q where q.supplier_id = l.id) order by id limit 1;
  select i.id into inq from public.inquiries i where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
     and not exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = lid) limit 1;
  delete from public.inquiry_matches where supplier_id = lid;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason) values (inq, lid, 0.9, now() - interval '4 days', 'ZZ DEMO probe');
  v := public.fn_sales_engineer_supplier_onboarding();
  o := o || jsonb_build_object('stage', (select stage from public.supplier_onboarding where lead_id = lid),
    'nudges1', (select nudges from public.supplier_onboarding where lead_id = lid));
  perform public.fn_sales_engineer_supplier_onboarding();
  o := o || jsonb_build_object('nudges2', (select nudges from public.supplier_onboarding where lead_id = lid));

  -- PERFORMANCE
  v := public.fn_sales_engineer_supplier_performance();
  o := o || jsonb_build_object('scored', (v->>'scored')::int > 0);

  -- SUPPLY GAPS: a trade with demand is recruited by rule; others are filed for reasoning
  v := public.fn_sales_engineer_supply_gap(1);
  o := o || jsonb_build_object('rule', (select count(*) from public.supply_gap where decided_by = 'rule:customer_waiting' and status = 'recruit' and demand_90d > 0),
    'filed', v->'filed_for_reasoning');
  select held_id, trade, emirate into h, tr, em from public.supply_gap where status = 'deciding' limit 1;
  o := o || jsonb_build_object('held', (select jsonb_build_object('seat', seat, 'stakes', request->>'stakes') from public.reasoning_held_question where id = h));
  begin
    perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"x","model":"openai/gpt-5.6-sol","decision":{"choice":"maybe"}}');
    o := o || jsonb_build_object('bad_choice', 'applied');
  exception when others then
    o := o || jsonb_build_object('bad_choice', left(sqlerrm, 40), 'still_deciding', (select status from public.supply_gap where trade = tr and emirate = em));
  end;
  -- the author's model is proven the way think() proves it: its latest agent_reasoning call by the seat
  insert into public.ai_cost_log (fn, agent_key, seat, task_class, model_used, ok) values ('probe', 'sales_engineer', 'sales_engineer', 'agent_reasoning', 'openai/gpt-5.6-sol', true);
  update public.reasoning_held_question set status = 'held' where id = h;
  perform public.fn_reason_held_resolve(h, '{"status":"answered","answer":"ZZ DEMO: thin supply and a deep uninvited pool make this worth recruiting now.","model":"openai/gpt-5.6-sol","decision":{"choice":"recruit"}}');
  o := o || jsonb_build_object('reasoned', (select jsonb_build_object('status', status, 'by', decided_by, 'deliberation', (review->>'deliberation_id') is not null)
                                             from public.supply_gap where trade = tr and emirate = em),
    'reviewer', (select reviewer_seat from public.seat_deliberation where id = (select (review->>'deliberation_id')::bigint from public.supply_gap where trade = tr and emirate = em)));

  -- THE FUNNEL: a recruiting gap gets its row; its leads go first
  v := public.fn_marketing_recruitment_funnel();
  o := o || jsonb_build_object('funnel_rows', (select count(*) from public.supplier_recruitment_funnel f join public.supply_gap s using (trade, emirate)
                                                where s.status = 'recruit' and f.day = (now() at time zone 'Asia/Dubai')::date)
                                            = (select count(*) from public.supply_gap where status = 'recruit'),
    'first_is_target', (select exists (select 1 from public.leads l join public.supply_gap g on g.status = 'recruit' and g.trade = any(l.invite_trades)
                                        and (g.emirate = 'UAE' or g.emirate = l.emirate)
                                        where l.id = (select lead_id from public.fn_supplier_invite_candidates(1) limit 1))));

  -- REPUTATION: no link -> a finding and nothing sent; a link -> one ask through customer_support, never two
  c := (select id from public.customers where email like '%@example.invalid' order by email limit 1);
  delete from public.app_secrets where key = 'public_review_url';
  insert into public.company_review_ask (customer_id, rating, status) values (c, 5, 'waiting_link') on conflict (customer_id) do update set status = 'waiting_link';
  v := public.fn_marketing_reputation();
  o := o || jsonb_build_object('no_link_asked', v->'asked', 'no_link_finding', (select count(*) from public.it_engineer_finding where issue_key = 'reputation:no_public_review_link' and closed_at is null));
  insert into public.app_secrets (key, value) values ('public_review_url', 'https://example.invalid/review');
  select coalesce(max(id), 0) into n from public.agent_actions;
  v := public.fn_marketing_reputation();
  o := o || jsonb_build_object('asked', v->'asked', 'asked_again', public.fn_marketing_reputation()->'asked',
    'sender', (select jsonb_agg(distinct detail->>'from') from public.agent_actions where id > n and kind = 'handoff' and detail->>'msg_type' = 'public_review_ask'));
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.equal(o.stage, 'matched', 'the matched ZZ DEMO supplier is not at stage matched');
  assert.equal(o.nudges1, 1, 'a matched supplier who has not quoted in 3 days was not told');
  assert.equal(o.nudges2, 1, 'the supplier was nudged twice in one week');
  assert.equal(o.scored, true, 'no supplier was scored');
  assert.ok(o.rule >= 1, 'a trade with demand was not recruited for by rule');
  assert.equal(o.filed, 1, 'a gap nobody waits on was not filed for reasoning');
  assert.deepEqual(o.held, { seat: 'sales_engineer', stakes: 'high' });
  assert.match(o.bad_choice, /^CHOICE_NOT_AN_OPTION/, 'a choice outside the options was applied');
  assert.equal(o.still_deciding, 'deciding');
  assert.deepEqual(o.reasoned, { status: 'recruit', by: 'reasoning', deliberation: true }, 'a reasoned recruit did not open a cross-family review');
  assert.equal(o.reviewer, 'marketing', 'the review is not marketing\'s');
  assert.equal(o.funnel_rows, true, 'a recruiting gap has no funnel row');
  assert.equal(o.first_is_target, true, 'the first lead in the invitation queue is not in a recruiting trade');
  assert.equal(o.no_link_asked, 0, 'an ask went out with no link');
  assert.equal(o.no_link_finding, 1, 'a missing review link is not a finding');
  assert.equal(o.asked, 1, 'the ask did not go once the link existed');
  assert.equal(o.asked_again, 0, 'the ask went twice');
  assert.deepEqual(o.sender, ['customer_support'], 'the ask did not go through customer_support');
});
