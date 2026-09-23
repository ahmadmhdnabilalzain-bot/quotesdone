// THE IT ENGINEER'S DUTIES ACT, AND AN OWED CUSTOMER NOTICE IS SENT UNTIL IT ARRIVES (23 Sep 2026; founder_instruction 898).
//
// WHAT FAILS IF THE CAUSE RETURNS — production, in ONE aborted transaction (pending files replayed, ZZ DEMO only,
// nothing commits, nothing is sent: every message here is a queued row that rolls back):
//   * licence_expiry_watch: a ZZ DEMO approved supplier whose licence expired stays matchable;
//   * knowledge_exam: no seat is asked, a seat's answer is not graded as a high-stakes reasoned decision, or the
//     grade is not recorded;
//   * knowledge_pass_rate: a seat at 20 % is not raised (finding + it.finding handoff) or its missed items are not
//     re-filed for research in its own queue;
//   * knowledge_refresh: a quarter is not opened for all six seats, is opened twice, is not research, or a reasoned
//     item is not stamped done;
//   * held notices: a failed notice is not offered again after 30 minutes, a delivered one is, or eight failures are
//     not a finding. The TypeScript half (a failed send is recorded and retried) is reasoned_delivery.test.ts.
//
//   node --test scripts/checks/it_engineer_duties_and_owed_notices_act.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILES = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql',
  'scripts/sql/the_it_engineer_watches_licences_and_every_seats_knowledge.sql',
  'scripts/sql/a_customer_notice_that_failed_is_sent_again.sql'];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const PING = read('supabase/functions/resilience_ping/index.ts');

test('resilience_ping sends owed notices from the queue and records each attempt', () => {
  assert.match(PING, /rpc\('fn_reason_held_notice_due'/, 'the owed notices do not come from fn_reason_held_notice_due');
  assert.match(PING, /sendHeldNotices\(/, 'resilience_ping does not use sendHeldNotices');
  assert.match(PING, /rpc\('fn_reason_held_notice_record'/, 'an attempt is not recorded');
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

test('production, aborted: the licence watch, the exam, the pass rate, the refresh and the owed notice all act', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; lid bigint; e_id bigint; ah bigint; g bigint; hid bigint; n bigint; i int; begin
  -- the ZZ DEMO supplier (example.invalid) is made expired inside this transaction only
  select id into lid from public.leads where company_name like 'ZZ DEMO%' and email like '%@example.invalid' and approval_status = 'approved' order by id limit 1;
  update public.leads set license_expiry = current_date - 3, matching_blocked = false, matching_block_reason = null where id = lid;
  v := public.fn_it_engineer_licence_expiry_watch();
  o := o || jsonb_build_object('lic_after', v->'expired_matchable_after', 'lic_blocked', (select matching_blocked from public.leads where id = lid));

  v := public.fn_it_engineer_knowledge_exam(1);
  o := o || jsonb_build_object('asked', v->'asked', 'asked_seats', (select count(distinct seat) from public.seat_knowledge_exam where asked_at >= now()));
  select id, asked_held_id into e_id, ah from public.seat_knowledge_exam where seat = 'ceo' and asked_at >= now() order by id limit 1;
  perform public.fn_reason_held_resolve(ah, '{"status":"answered","answer":"ZZ DEMO answer","model":"zz/model"}');
  select grade_held_id into g from public.seat_knowledge_exam where id = e_id;
  o := o || jsonb_build_object('grade', (select jsonb_build_object('seat', seat, 'stakes', request->>'stakes', 'n', jsonb_array_length(request->'decision'->'options')) from public.reasoning_held_question where id = g));
  begin
    perform public.fn_reason_held_resolve(g, '{"status":"answered","answer":"x","decision":{"choice":"maybe"}}');
    o := o || jsonb_build_object('bad_grade', 'applied');
  exception when others then o := o || jsonb_build_object('bad_grade', left(sqlerrm, 40)); end;
  perform public.fn_reason_held_resolve(g, '{"status":"answered","answer":"contradicts the reference","decision":{"choice":"wrong"}}');
  o := o || jsonb_build_object('verdict', (select verdict from public.seat_knowledge_exam where id = e_id));

  for i in 1..5 loop
    insert into public.seat_knowledge_exam (seat, item_key, question, reference, verdict, graded_at)
    values ('ceo', 'zz:' || i, 'ZZ DEMO q' || i, 'ZZ DEMO reference', case when i = 1 then 'correct' else 'wrong' end, now());
  end loop;
  v := public.fn_it_engineer_knowledge_pass_rate();
  o := o || jsonb_build_object('raised', v->'raised', 'refiled', v->'refiled',
    'finding', (select count(*) from public.it_engineer_finding where issue_key = 'knowledge_pass_rate:ceo' and closed_at is null),
    'handoff', (select count(*) from public.agent_actions where kind = 'handoff' and agent = 'ceo' and target_id like 'it.finding:knowledge_pass_rate:ceo:%'),
    'refile_queue', (select count(*) from public.reasoning_held_question where seat = 'ceo' and surface = 'ceo.knowledge_refresh' and dedupe_key like 'krefile:%' and created_at >= now()));

  delete from public.seat_knowledge_refresh where true;
  v := public.fn_it_engineer_knowledge_refresh();
  o := o || jsonb_build_object('opened', v->'opened', 'again', public.fn_it_engineer_knowledge_refresh()->'opened');
  select (items->0->>'held_id')::bigint into hid from public.seat_knowledge_refresh where seat = 'accountant';
  o := o || jsonb_build_object('research', (select request->>'research' from public.reasoning_held_question where id = hid));
  perform public.fn_reason_held_resolve(hid, '{"status":"answered","answer":"unchanged","sources":[]}');
  o := o || jsonb_build_object('done', (select items->0->>'done_at' is not null from public.seat_knowledge_refresh where seat = 'accountant'));

  insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, dedupe_key, escalated_at)
  values ('customer_support', 'wa_inbound.needs_a_person', 'ZZ DEMO where is my quote?', '{}', '{"phone":"+971500000000"}', 'zz', 'zz-notice-probe', now())
  returning id into n;
  o := o || jsonb_build_object('due1', (select count(*) from jsonb_array_elements(public.fn_reason_held_notice_due(100)) x where (x->>'id')::bigint = n));
  perform public.fn_reason_held_notice_record(n, '{"delivered":false,"detail":"twilio 63016"}');
  o := o || jsonb_build_object('due_after_fail', (select count(*) from jsonb_array_elements(public.fn_reason_held_notice_due(100)) x where (x->>'id')::bigint = n));
  update public.reasoning_held_question set notice_last_at = now() - interval '31 minutes' where id = n;
  o := o || jsonb_build_object('due_retry', (select count(*) from jsonb_array_elements(public.fn_reason_held_notice_due(100)) x where (x->>'id')::bigint = n));
  update public.reasoning_held_question set notice_attempts = 8 where id = n;
  perform public.fn_reason_held_notice_due(100);
  o := o || jsonb_build_object('dead_finding', (select count(*) from public.it_engineer_finding where issue_key = 'held_notice:undelivered' and closed_at is null));
  update public.reasoning_held_question set notice_attempts = 0, notice_last_at = null where id = n;
  perform public.fn_reason_held_notice_record(n, '{"delivered":true}');
  o := o || jsonb_build_object('due_delivered', (select count(*) from jsonb_array_elements(public.fn_reason_held_notice_due(100)) x where (x->>'id')::bigint = n));
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.equal(o.lic_after, 0, 'an expired supplier is still matchable after the watch');
  assert.equal(o.lic_blocked, true, 'the ZZ DEMO expired supplier was not paused');
  assert.equal(o.asked, 6, 'the exam did not ask one item of each of the six seats');
  assert.equal(o.asked_seats, 6);
  assert.deepEqual(o.grade, { seat: 'it_engineer', stakes: 'high', n: 4 }, 'the grade is not a high-stakes reasoned decision of the it_engineer');
  assert.match(o.bad_grade, /^CHOICE_NOT_AN_OPTION/, 'a grade outside the options was applied (and the question lost)');
  assert.equal(o.verdict, 'wrong', 'the reasoned grade was not recorded');
  assert.equal(o.raised, 1, 'a seat at 20 % was not raised');
  assert.equal(o.finding, 1);
  assert.equal(o.handoff, 1, 'the seat was not handed the finding');
  assert.ok(o.refiled >= 4 && o.refile_queue >= 4, 'the missed items were not re-filed for research in the seat queue');
  assert.equal(o.opened, 6, 'the quarter was not opened for all six seats');
  assert.equal(o.again, 0, 'a quarter was opened twice');
  assert.equal(o.research, 'true', 'a refresh question is not research');
  assert.equal(o.done, true, 'a reasoned refresh item was not stamped done');
  assert.equal(o.due1, 1, 'an escalated question with a phone is not owed a notice');
  assert.equal(o.due_after_fail, 0, 'a failed notice is retried inside 30 minutes');
  assert.equal(o.due_retry, 1, 'a failed notice is never retried');
  assert.equal(o.dead_finding, 1, 'eight failed notices are not a finding');
  assert.equal(o.due_delivered, 0, 'a delivered notice is sent again');
});
