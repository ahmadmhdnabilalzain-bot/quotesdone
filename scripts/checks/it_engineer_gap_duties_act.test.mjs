// THE IT ENGINEER'S GAP DUTIES ACT (24 Sep 2026; seat audit GAPS.md IT gaps 2-9, founder_instruction 704/705, ledger 983).
//
// WHAT FAILS IF THE CAUSE RETURNS — production, in ONE aborted transaction (the pending files replayed first, ZZ DEMO
// rows only, nothing commits, nothing is sent):
//   * provider_status: a provider at 'major' is not a finding, the firewall found off is not a security finding, an
//     unreadable page is raised as more than configuration, or a cleared page does not close its finding;
//   * latency_slo: a portal function over its 2.5 s budget at p95 is not raised;
//   * data_quality: a ZZ DEMO customer's quote joined to a real supplier is not raised;
//   * model_spend: an unlisted consumer or a loop is not raised; the inventory does not list the consumer;
//   * postmortem: a closed high-severity fault of a known class gets no incident, or no cause and check from the playbook;
//   * ownership: the licence watch still sits on the IT seat, or a knowledge pass-rate drop is not handed to the CEO.
//
//   node --test scripts/checks/it_engineer_gap_duties_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILES = [
  'scripts/sql/the_it_engineer_reads_provider_status_pages_and_the_firewall.sql',
  'scripts/sql/the_it_engineer_holds_the_portals_to_their_latency_budget.sql',
  'scripts/sql/the_it_engineer_checks_the_data_is_whole_and_demo_never_touches_real.sql',
  'scripts/sql/every_model_credit_consumer_is_listed_and_a_runaway_is_flagged.sql',
  'scripts/sql/the_it_playbook_knows_its_recurring_failure_classes.sql',
  'scripts/sql/every_serious_incident_gets_a_postmortem.sql',
  'scripts/sql/each_seat_owns_the_duty_the_founder_gave_it_and_it_measures.sql',
];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: every new duty file has a header, a revoke per routine and a verdict row', () => {
  for (const f of FILES) {
    const s = read(f);
    assert.match(s, /^-- [A-Z]/, f + ' does not open with its subject');
    assert.match(s, /as verdict;\s*$/, f + ' does not end with a verdict row');
    for (const m of s.matchAll(/create or replace function public\.(fn_[a-z0-9_]+)\(/g)) {
      assert.match(s, new RegExp('revoke execute on function public\\.' + m[1] + '\\('), f + ': ' + m[1] + ' is never revoked');
    }
    assert.ok(!/raise notice/i.test(s), f + ' reports through NOTICE, which nobody reads');
  }
});

test('static: resilience_ping runs the provider reading on the IT heartbeat', () => {
  const ping = read('supabase/functions/resilience_ping/index.ts');
  assert.match(ping, /step\('provider_status'/);
  assert.match(ping, /rpc\('fn_it_provider_watch', \{ p_r: await takeProviderReadings\(sec\) \}\)/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  // A file's trailing verdict SELECT is harmless inside the DO-less batch; the probe block raises at the end.
  try { await replaySql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1200));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: the gap duties raise, act and close', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; qid uuid; hid bigint; inc public.it_incident; i int; begin
  -- provider status and firewall
  v := public.fn_it_provider_watch('{"providers":[{"provider":"twilio","basis":"measured","indicator":"major","description":"ZZ DEMO outage"},
      {"provider":"stripe","basis":"unavailable","reason":"ZZ DEMO 404"},{"provider":"vercel","basis":"measured","indicator":"minor"}],
      "firewall":{"config":{"basis":"measured","enabled":false},"attack":{"basis":"measured","under_attack":false}}}');
  o := o || jsonb_build_object(
    'p_twilio', (select blast from public.it_engineer_finding where issue_key = 'duty:provider_status:twilio' and closed_at is null),
    'p_vercel', (select count(*) from public.it_engineer_finding where issue_key = 'duty:provider_status:vercel' and closed_at is null),
    'p_fw', (select blast from public.it_engineer_finding where issue_key = 'duty:provider_status:firewall:off' and closed_at is null),
    'p_stripe', (select count(*) from public.it_engineer_finding where issue_key = 'duty:provider_status:unreadable:stripe' and closed_at is null));
  perform public.fn_it_provider_watch('{"providers":[{"provider":"twilio","basis":"measured","indicator":"none"}],
      "firewall":{"config":{"basis":"measured","enabled":true},"attack":{"basis":"measured","under_attack":false}}}');
  o := o || jsonb_build_object('p_closed', (select count(*) from public.it_engineer_finding
    where issue_key in ('duty:provider_status:twilio', 'duty:provider_status:firewall:off') and closed_at is null));

  -- latency
  for i in 1..40 loop
    insert into public.agent_runs (agent, status, started_at, finished_at, counts)
    values ('fn:zz_demo_portal', 'ok', now() - interval '1 hour', now() - interval '1 hour',
            jsonb_build_object('ms', 4000 + i, 'http', 200, 'method', 'POST', 'budget_ms', 2500, 'region', 'ap-south-1'));
  end loop;
  v := public.fn_it_engineer_latency_slo();
  o := o || jsonb_build_object('lat', (select count(*) from public.it_engineer_finding where issue_key = 'duty:latency_slo:zz_demo_portal' and closed_at is null));

  -- data quality: a ZZ DEMO customer's quote re-pointed at a real supplier (inside this transaction only)
  select q.id into qid from public.quotes q join public.inquiries i on i.id = q.inquiry_id join public.customers cu on cu.id = i.customer_id
   where cu.is_demo order by q.id limit 1;
  alter table public.quotes disable trigger user;
  update public.quotes set supplier_id = (select id from public.leads where not is_demo order by id limit 1) where id = qid;
  alter table public.quotes enable trigger user;
  v := public.fn_it_engineer_data_quality();
  o := o || jsonb_build_object('dq_quote', qid is not null, 'dq_cross', (select count(*) from public.it_engineer_finding
    where issue_key = 'duty:data_quality:demo_quote_crosses_real' and closed_at is null and evidence->'ids' @> to_jsonb(qid)));

  -- model spend
  for i in 1..40 loop
    insert into public.ai_cost_log (fn, task_class, model_used, occurred_at, cached, cache_hit_key)
    values ('zz_demo_fn', 'zz_loop', 'zz/model', now() - interval '5 minutes', false, 'zz-same-call');
  end loop;
  insert into public.ai_cost_log (fn, task_class, model_used, occurred_at) values ('sales_engineer', 'agent_reasoning', 'zz/model', now());
  v := public.fn_it_engineer_model_spend();
  o := o || jsonb_build_object(
    'm_unlisted', (select evidence->>'owner_seat' from public.it_engineer_finding where issue_key = 'duty:model_spend:unlisted:zz_demo_fn:zz_loop' and closed_at is null),
    'm_runaway', (select count(*) from public.it_engineer_finding where issue_key = 'duty:model_spend:runaway:zz_demo_fn:zz_loop' and closed_at is null),
    'm_repeat', (select count(*) from public.it_engineer_finding where issue_key like 'duty:model_spend:repeat:zz_demo_fn:zz_loop:%' and closed_at is null),
    'm_think_unlisted', (select count(*) from public.it_engineer_finding where issue_key = 'duty:model_spend:unlisted:sales_engineer:agent_reasoning' and closed_at is null),
    'm_inventory', (select calls_30d from public.fn_it_model_consumer_inventory() where consumer = 'zz_demo_fn:zz_loop'));

  -- postmortem: a high-severity fault of a known class, closed after the duty went live
  insert into public.agent_actions (agent, kind, status, detail, decided_at, evidence)
  values ('sales_engineer', 'handoff', 'done', jsonb_build_object('type', 'it.finding', 'severity', 'high',
          'issue_key', 'duty:latency_slo:zz_demo_portal', 'title', 'ZZ DEMO slow', 'occurrence_started_at', now() - interval '2 hours'),
          now(), '{"answer":"ZZ DEMO bounded"}')
  returning id into hid;
  insert into public.agent_actions (agent, kind, status, detail, decided_at)
  select 'ceo', 'handoff', 'done', jsonb_build_object('type', 'it.finding', 'severity', 'critical',
          'issue_key', 'zz_demo_new_class:' || g, 'title', 'ZZ DEMO new class ' || g, 'occurrence_started_at', now() - interval '2 hours'), now()
    from generate_series(1, 4) g;
  v := public.fn_it_engineer_postmortem();
  perform public.fn_it_engineer_postmortem();
  select * into inc from public.it_incident where handoff_id = hid;
  o := o || jsonb_build_object('pm_opened', inc.id is not null, 'pm_class', inc.playbook_class,
    'pm_cause', coalesce(btrim(inc.cause), '') <> '', 'pm_check', inc.regression_check,
    'pm_asked', (select count(*) from public.reasoning_held_question q join public.it_incident i on q.dedupe_key = 'postmortem:' || i.id
                  where i.issue_key like 'zz_demo_new_class:%'));

  -- ownership
  o := o || jsonb_build_object(
    'own_lic', (select owner_seat from public.seat_duty where duty = 'sales_engineer.licence_expiry_watch'),
    'own_lic_it', (select count(*) from public.seat_duty where duty = 'it_engineer.licence_expiry_watch'),
    'own_wa', (select owner_seat from public.it_duty_schedule where duty = 'whatsapp_delivery'));
  for i in 1..5 loop
    insert into public.seat_knowledge_exam (seat, item_key, question, reference, verdict, graded_at)
    values ('marketing', 'zz:' || i, 'ZZ DEMO q' || i, 'ZZ DEMO reference', case when i = 1 then 'correct' else 'wrong' end, now());
  end loop;
  perform public.fn_it_engineer_knowledge_pass_rate();
  o := o || jsonb_build_object('kp_ceo', (select count(*) from public.agent_actions where kind = 'handoff' and agent = 'ceo'
                                            and target_id like 'it.finding:knowledge_pass_rate:marketing:%'));
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.equal(o.p_twilio, 'customer_facing', 'a provider at major is not a customer-facing finding');
  assert.equal(o.p_vercel, 0, 'a provider at minor was raised: that is the noise instruction 642 forbids');
  assert.equal(o.p_fw, 'security', 'the firewall found off is not a security finding');
  assert.equal(o.p_stripe, 1, 'an unreadable status page is not recorded');
  assert.equal(o.p_closed, 0, 'a cleared status page did not close its finding');
  assert.equal(o.lat, 1, 'a portal function over its budget at p95 was not raised');
  assert.equal(o.dq_quote, true, 'no ZZ DEMO quote to test with');
  assert.equal(o.dq_cross, 1, 'a demo quote joined to a real supplier is not raised');
  assert.equal(o.m_unlisted, 'ceo', 'an unlisted model consumer is not raised to the CEO');
  assert.equal(o.m_runaway, 1, 'a loop of 40 calls in an hour is not raised');
  assert.equal(o.m_repeat, 1, 'the same uncached call paid 40 times is not raised');
  assert.equal(o.m_think_unlisted, 0, 'a think() call from a listed host is raised as unlisted');
  assert.equal(o.pm_asked, 4, 'an incident past one run cap of three is never asked for its root cause');
  assert.equal(o.m_inventory, 40, 'the inventory does not list an observed consumer');
  assert.equal(o.pm_opened, true, 'a closed high-severity fault got no incident record');
  assert.equal(o.pm_class, 'latency_over_budget');
  assert.equal(o.pm_cause, true, 'the postmortem has no cause from the playbook');
  assert.equal(o.pm_check, 'supabase/functions/_shared/observe.test.ts');
  assert.equal(o.own_lic, 'sales_engineer');
  assert.equal(o.own_lic_it, 0, 'the licence watch still sits on the IT seat');
  assert.equal(o.own_wa, 'customer_support');
  assert.equal(o.kp_ceo, 1, 'a knowledge pass-rate drop is not handed to the CEO');
});
