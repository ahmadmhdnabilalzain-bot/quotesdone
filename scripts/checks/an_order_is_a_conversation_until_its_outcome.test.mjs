// AN ORDER IS A CONVERSATION UNTIL ITS OUTCOME (ceo, 16 Nov 2026).
// Founder, 16 Nov 2026: "So he gave him an order. What will the IT do? What if he can't? How do they talk to each other? How do
// the CEO conclude what to do next? ... every agent is working on his own ... that's not how real companies work."
// Offline, from the text, this fails when:
//   1. a turn kind loses its effect for a seat (the replay would answer it and nothing would happen), or a turn stops being a
//      held question of the seat that speaks (a parallel system, a code-written turn);
//   2. a plan can name a tool its seat lacks, a need can ask the engineer session for what the register does not give it, or
//      money in a need skips the company limits;
//   3. a CEO turn skips a check a plan bet passes: the founder ask, refused acts, the company limits, the message gates, a seat
//      that takes an order, a measure code can read, the date window; or "close met" stops reading the measure;
//   4. the lesson stops reaching the seat's case memory, the shared pool or the next order's turns;
//   5. the founder's summary or the CEO's planning pack stops reading the conversations;
//   6. the register stops telling the it_engineer's truth (it reads verdicts; it cannot run GlockApps, write DNS or warm up alone);
//   7. a routine is not revoked and pinned, a table has no policy, or the file enters MANIFEST.txt unapplied.
// LOCAL (QD_LOCAL_DB_URL = a psql URL of a LOCAL Postgres 16 built from the mirror; never production): the four plan-branch
// files and this one apply to a copy of that database, the probe (the founder's example) answers PROBE OK, and a second
// conversation walks the other transitions: a turn deferred over the day's cap, a lapsed question asked again, an on-track
// check-in, a re-plan, a seat that cannot, a reassignment, a withdrawal, and an engineer build that flips the register.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=postgresql://postgres@%2Fdev%2Fshm%2Fpg:55617/base node --test scripts/checks/an_order_is_a_conversation_until_its_outcome.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/an_order_is_a_conversation_until_its_outcome.sql';
const PROBE = 'scripts/sql/an_order_is_a_conversation_until_its_outcome_probe.sql';
const PLAN_FILE = 'scripts/sql/the_ceo_thinks_plans_and_orders_every_week.sql';
const BEFORE = ['scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql',
  'scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql', 'scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql', PLAN_FILE];
const SQL = read(FILE);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const C = code(SQL);
const fnBody = (name, text = C) => {
  const at = text.indexOf(`create or replace function public.${name}(`);
  return at < 0 ? '' : text.slice(at, text.indexOf('$fn$;', at));
};
const SEATS = ['it_engineer', 'sales_engineer', 'customer_support', 'marketing', 'accountant'];

test('1. every turn is a held question of the seat that speaks, and every surface has its effect', () => {
  for (const s of SEATS) for (const k of ['order_plan', 'order_status', 'order_retro']) {
    assert.match(C, new RegExp(`create or replace function public\\.fn_reason_apply_${s}__${k}\\(p_id bigint, p_result jsonb\\)[^\\n]*fn_order_turn_applies`), `${s}.${k} has its effect`);
  }
  for (const k of ['order_answer', 'order_response', 'order_next']) assert.match(C, new RegExp(`fn_reason_apply_ceo__${k}\\(p_id bigint, p_result jsonb\\)[^\\n]*fn_order_turn_applies`));
  const ask = fnBody('fn_order_ask');
  assert.match(ask, /insert into public\.reasoning_held_question/, 'a turn is a held question (the one replay answers it)');
  assert.match(ask, /'stakes', 'normal'/); assert.match(ask, /'plan', jsonb_build_object\('steps', '\[\]'::jsonb\)/, 'one call: a fixed plan, normal stakes');
  assert.match(ask, /'authored', true/, 'the fields are the seat\'s own writing');
  assert.match(ask, /fn_order_turn_room\(\)/, 'every turn is inside the day\'s cap');
  assert.match(ask, /v_seat \|\| '\.order_'/, 'the surface belongs to the seat that speaks');
  const applies = fnBody('fn_order_turn_applies');
  assert.doesNotMatch(applies, /raise exception/, 'a refused turn is recorded and asked again with its reasons, never raised');
  assert.match(applies, /u\.round < v_max/, 'a refusal goes back once (max_rounds)');
  assert.match(applies, /risk = 'blocked'/, 'a second refusal blocks the conversation on its reason');
  assert.match(applies, /'ceo_answer'[\s\S]{0,200}NO ACCEPTED PLAN/, 'a seat with no accepted plan leaves the decision to the CEO');
});

test('2. a plan names only its seat\'s tools; needs are checked', () => {
  const plan = fnBody('fn_order_plan_refusals');
  assert.match(plan, /from public\.seat_capability x where x\.seat = t\.seat and x\.tool = e->>'tool'/, 'every step\'s tool is read in the register for its seat');
  assert.match(plan, /not c\.available/, 'a tool the seat lacks is refused as a step');
  assert.match(plan, /p_choice in \('partly', 'cannot'\) and jsonb_array_length\(v_needs\) = 0/, 'partly and cannot say what they need');
  assert.match(plan, /v_at > coalesce\(v_due/, 'milestones fall before the due date');
  assert.match(plan, /fn_order_text_refusals\(/);
  const needs = fnBody('fn_order_needs_refusals');
  assert.match(needs, /x\.who_can = 'engineer_session'/, 'the engineer session is asked only for what the register gives it');
  assert.match(needs, /fn_company_spend_fits\(v_aed\)/, 'money in a need fits the company limits');
  assert.match(needs, /fn_order_seat_orderable\(e->>'seat'\)/, 'another seat\'s help names a seat the CEO can order');
});

test('3. every CEO turn passes the plan bet\'s checks', () => {
  const ceo = fnBody('fn_order_ceo_refusals');
  for (const [what, re] of [['the company limits', /fn_company_spend_fits\(v_n\)/], ['the message gates per lead', /fn_company_message_gates\('email', null, v_lead\)/],
    ['a seat that takes an order, never the founder', /a->>'seat' in \('ceo', 'founder'\) or not public\.fn_order_seat_orderable/], ['a measure code can read', /fn_ceo_plan_measures\(\) \? \(a->>'measure'\)/],
    ['the date window', /v_due < now\(\) \+ interval '12 hours'/], ['every amount in the words', /fn_ceo_plan_text_aed\(/], ['the words', /fn_order_text_refusals\(/],
    ['the volume ceiling', /least\(coalesce\(\(pol->>'m365_warmup_max_per_day'\)::int, 40\), 150\)/]]) assert.match(ceo, re, what);
  const words = fnBody('fn_order_text_refusals');
  assert.match(words, /fn_ceo_plan_text_asks_founder\(/, 'the founder is never asked (ledger 1696)');
  assert.match(words, /verdict = 'refused' and act_terms is not null/, 'no refused act in the words');
  const next = fnBody('fn_order_next_refusals');
  assert.match(next, /fn_ceo_plan_bet_reading\(t\.bet_id\)/, 'close met reads the measure');
  assert.match(next, /t\.extensions >= /, 'an order is extended a bounded number of times');
});

test('4. the lesson reaches the seat, the shared pool and the next order', () => {
  const l = fnBody('fn_order_lesson_write');
  assert.match(l, /insert into public\.seat_case_memory/, 'the seat\'s case memory (its playbook learns)');
  assert.match(l, /fn_lesson_scrub\(/, 'a lesson carries no id, amount or contact');
  assert.match(l, /fn_emit\('order\.lesson'/, 'the shared pool');
  assert.match(C, /'order\.lesson', k, k = 'ceo', 'digest'/, 'every seat hears it');
  assert.match(fnBody('fn_order_case'), /'lessons_from_recent_orders', public\.fn_order_lessons\(/, 'every later turn reads the recent lessons');
});

test('5. the founder\'s summary and the CEO\'s pack read the conversations', () => {
  const plan = code(read(PLAN_FILE));
  assert.match(fnBody('fn_ceo_plan_summary_text', plan), /fn_order_threads_summary_text\(\)/, 'one line per open order in the daily summary');
  assert.match(fnBody('fn_ceo_planning_pack', plan), /'order_threads', public\.fn_order_threads_pack\(\)/, 'the weekly pack reads open threads and retros');
  assert.match(fnBody('fn_ceo_plan_bet_reading', plan), /to_regclass\('public\.engineer_session_request'\) is null/, 'the plan file stands alone before this one');
  const line = fnBody('fn_order_threads_summary_text');
  assert.match(line, /fn_order_thread_status\(t\.handoff_id\)/); assert.match(line, /' - next: '/);
  assert.match(fnBody('fn_order_thread_status'), /'blocked on ' \|\| t\.blocked_on/);
});

test('6. the register tells the it_engineer\'s truth', () => {
  for (const t of ['placement_verdict_read', 'sender_readings', 'seed_placement_check', 'exo_transport_rule', 'm365_lane_watch']) {
    assert.match(SQL, new RegExp(`\\('it_engineer', '${t}', true,`), `it_engineer can ${t}`);
  }
  assert.match(SQL, /\('it_engineer', 'glockapps_test', false,[^\n]*ledger 1344[^\n]*'engineer_session'/, 'GlockApps is the engineer session\'s (ruling 1344)');
  assert.match(SQL, /\('it_engineer', 'dns_write', false,/); assert.match(SQL, /\('it_engineer', 'warmup_volume', false,[^\n]*'sales_engineer'/);
  assert.match(SQL, /\('sales_engineer', 'm365_reply_lane', false,/, 'the M365 lane carries no replies yet');
  assert.match(fnBody('fn_engineer_session_request_done'), /t\.created_at < r\.created_at/, 'a re-test is done only with a test recorded after the request');
  assert.match(fnBody('fn_engineer_session_request_open'), /to_regprocedure\('public\.fn_it_code_defect_open\(/, 'a build also reaches it_code_defect when that queue exists, never required');
});

test('7. routines revoked and pinned, tables with a policy, the file pending until applied', () => {
  const fns = [...C.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)].map((m) => m[1]);
  assert.ok(fns.length > 30);
  for (const f of new Set(fns)) {
    assert.match(C, new RegExp(`revoke execute on function [^;]*public\\.${f}\\(`), `${f} is revoked`);
    const body = fnBody(f);
    assert.match(body, /set search_path to 'public', 'pg_temp'/, `${f} pins its search_path`);
  }
  for (const t of ['seat_capability', 'engineer_session_request', 'seat_order_thread', 'seat_order_turn']) assert.match(C, new RegExp(`'${t}'`), `${t} gets its policy`);
  assert.match(C, /create policy %I on public\.%I as permissive for all to public using \(false\) with check \(false\)/);
  const manifest = read('scripts/sql/MANIFEST.txt');
  assert.ok(!manifest.split('\n').some((l) => l.trim() === 'an_order_is_a_conversation_until_its_outcome.sql'), 'not in MANIFEST until applied');
  assert.ok(existsSync(join(REPO, 'scripts/sql/pending/an_order_is_a_conversation_until_its_outcome.txt')), 'its pending note says why');
});

// ── LOCAL ───────────────────────────────────────────────────────────────────────────────────────────────────────────
const URL_ = process.env.QD_LOCAL_DB_URL ?? '';
const isLocal = /^postgres(ql)?:\/\/[^@]*@(%2F|localhost|127\.0\.0\.1)/i.test(URL_);
const LOCAL_SKIP = !URL_ ? 'QD_LOCAL_DB_URL not set (a local Postgres 16 built from the mirror)' : !isLocal ? 'QD_LOCAL_DB_URL is not a local database: refused' : false;

const SCENARIO = String.raw`
do $s$
declare v_fail text := ''; v_plan bigint; v_r jsonb; v_h bigint; v_q bigint; v_t public.seat_order_thread; v_sub bigint; v_req bigint; v_n int;
  d3 text := to_char(now() + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SSOF'); d10 text := to_char(now() + interval '10 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
  d20 text := to_char(now() + interval '20 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
  ans constant text := '{"status": "answered", "answer": "ZZ DEMO stub", "model": "zz-demo/stub"}';
begin
  perform set_config('qd.duty_fixtures', 'on', true); perform set_config('qd.probe_files_demo_handoff', 'on', true);
  update public.decision_policy set value = value || '{"turns_per_day": 1000, "aed_per_day": 1000, "max_rounds": 2}'::jsonb where key = 'order_threads';
  insert into public.ceo_plan_week (kind, period, status, task_class, output, pack) values ('daily', current_date + 1001, 'asked', 'routine_employee_reasoning', '{}', '{}') returning id into v_plan;
  v_r := public.fn_ceo_plan_file(v_plan, jsonb_build_object('decision', jsonb_build_object('bets', jsonb_build_array(jsonb_build_object('channel', 'registration_unblock', 'seat', 'sales_engineer',
    'what', 'ZZ DEMO every submitted registration decided within two days', 'how', 'the registration review', 'why', 'the founder''s people arrive in a burst',
    'measure', 'held_registrations', 'measure_args', '{}'::jsonb, 'target', 0, 'direction', 'at_most', 'due_at', d10, 'cost_aed', 0, 'legal', 'safe', 'kill_criterion', 'never')))), 'zz-demo/stub', null);
  select handoff_id into v_h from public.ceo_plan_bet where plan_id = v_plan and ord = 1;
  perform public.fn_order_threads_tick(now());
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and status = 'asked');
  -- DEFERRED: the day's cap is full when the CEO is to answer
  update public.decision_policy set value = value || jsonb_build_object('turns_per_day', (public.fn_order_turn_room()->>'asked_today')::int) where key = 'order_threads';
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO the registration review is mine and the queue is empty today', 'steps', '[{"tool": "registration_review", "action": "decide each submitted registration the day it lands", "by": "' || d3 || '"}]',
    'needs', '[]', 'risks', 'a burst of the founder''s people', 'milestones', '[{"at": "' || d3 || '", "expect": 0}]'))));
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and status = 'deferred') then v_fail := v_fail || 'no deferral over the cap; '; end if;
  update public.decision_policy set value = value || '{"turns_per_day": 1000}'::jsonb where key = 'order_threads';
  perform public.fn_order_threads_tick(now() + interval '30 hours');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 1 and status = 'asked');
  if v_q is null then v_fail := v_fail || 'the deferred turn was not asked on its day; '; end if;
  -- LAPSED: the replay gave up; the next tick asks again, one round up
  update public.reasoning_held_question set status = 'failed' where id = v_q;
  perform public.fn_order_threads_tick(now() + interval '30 hours');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 2 and status = 'asked');
  if v_q is null or not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 1 and status = 'lapsed') then v_fail := v_fail || 'a failed question was not asked again; '; end if;
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object('reason', 'ZZ DEMO the plan is the job itself; go.', 'actions', '[]'))));
  -- ON TRACK at the milestone: no status is asked
  perform public.fn_order_threads_tick(now() + interval '4 days');
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'checkin' and choice = 'on_track')
     or exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'status') then v_fail := v_fail || 'an on-track milestone asked a status; '; end if;
  -- RE-PLAN after the retro
  perform public.fn_order_threads_tick(now() + interval '11 days');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'retro' and status = 'asked');
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'met', 'fields', jsonb_build_object(
    'done', 'ZZ DEMO decided each registration the day it landed', 'result', 'no registration held two days', 'why', 'the queue stayed small', 'next', 'keep the same-day review'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_next' and status = 'asked');
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'replan', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO the burst has not come yet; plan the review for the burst', 'lesson', 'An empty queue proves nothing about a burst: plan for the peak, not the average day.',
    'new_due', d20, 'new_target', '', 'new_seat', ''))));
  if (select due_at from public.ceo_plan_bet b join public.agent_actions a on a.id = b.handoff_id where a.id = v_h) <> d20::timestamptz
     or (select question from public.reasoning_held_question where id = (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and round = 2 and status = 'asked')) !~ 'THE CEO ASKS FOR A NEW PLAN'
  then v_fail := v_fail || 'the re-plan did not move the date and ask a new plan; '; end if;
  -- CANNOT: blocked on what it cannot do alone, the CEO decides
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and round = 2 and status = 'asked');
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'cannot', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO a burst needs someone to chase missing documents on WhatsApp, which only support can do inside the window', 'steps', '[]',
    'needs', '[{"kind": "seat_help", "seat": "customer_support", "what": "ask each stuck supplier for the missing document inside his window"}]', 'risks', 'none', 'milestones', '[]'))));
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.risk <> 'blocked' or v_t.blocked_on !~ '^what sales_engineer cannot do alone' or v_t.state <> 'awaiting_ceo' then v_fail := v_fail || 'a seat that cannot was not blocked and handed to the CEO; '; end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and status = 'asked' order by round desc limit 1);
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object('reason', 'ZZ DEMO noted; the retro will decide who carries it.', 'actions', '[]'))));
  -- REASSIGN at the end
  perform public.fn_order_threads_tick(now() + interval '21 days');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'retro' and status = 'asked' order by round desc limit 1);
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'missed', 'fields', jsonb_build_object(
    'done', 'ZZ DEMO reviewed what came in', 'result', 'two registrations waited three days for a document', 'why', 'nobody chased the document inside the window', 'next', 'support chases the documents'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_next' and status = 'asked' order by round desc limit 1);
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'reassign', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO the missing piece is a chase inside the WhatsApp window: support carries it', 'lesson', 'The seat that can reach the person inside his window owns the chase.',
    'new_due', d20, 'new_target', '', 'new_seat', 'customer_support'))));
  select handoff_id into v_sub from public.seat_order_thread where parent_handoff_id = v_h and seat = 'customer_support';
  if v_sub is null or (select outcome from public.seat_order_thread where handoff_id = v_h) <> 'reassigned' then v_fail := v_fail || 'the reassignment did not file the new seat''s order; '; end if;
  -- WITHDRAW
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'plan' and status = 'asked');
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO the consent question and the reply inside the window are mine', 'steps', '[{"tool": "support_reply", "action": "ask each stuck supplier for the missing document", "by": "' || d10 || '"}]',
    'needs', '[]', 'risks', 'none', 'milestones', '[{"at": "' || d10 || '", "expect": 0}]'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'ceo_answer' and status = 'asked');
  perform public.fn_reason_held_resolve(v_q, ans::jsonb || jsonb_build_object('decision', jsonb_build_object('choice', 'withdraw', 'fields', jsonb_build_object('reason', 'ZZ DEMO the burst was handled before the plan landed.', 'actions', '[]'))));
  if (select state from public.seat_order_thread where handoff_id = v_sub) <> 'closed' or (select status from public.agent_actions where id = v_sub) <> 'done'
     or (select status from public.ceo_plan_bet where handoff_id = v_sub) <> 'withdrawn' then v_fail := v_fail || 'the withdrawal did not close the order and its bet; '; end if;
  if public.fn_order_threads_summary_text() ~ ('#' || v_h || ' ') or public.fn_order_threads_summary_text() ~ ('#' || v_sub || ' ') then v_fail := v_fail || 'a closed order is still in the summary; '; end if;
  -- AN ENGINEER BUILD FLIPS THE REGISTER; WONT_DO SAYS WHY
  v_req := public.fn_engineer_session_request_open('capability', 'marketing', 'zz_demo_tool', 'ZZ DEMO build a demo tool for the probe', 'ZZ DEMO the demo tool answers its own check', null, null, null, null);
  if public.fn_engineer_session_request_open('capability', 'marketing', 'zz_demo_tool', 'ZZ DEMO the same build asked twice', 'ZZ DEMO the same acceptance twice over', null, null, null, null) <> v_req then v_fail := v_fail || 'one open request per tool; '; end if;
  v_r := public.fn_engineer_session_request_claim('zz-demo-session', v_req);
  v_r := public.fn_engineer_session_request_done(v_req, 'zz-demo-session', 'ZZ DEMO built and deployed', 'PR #99999');
  if not coalesce((v_r->>'ok')::boolean, false) or not exists (select 1 from public.seat_capability where seat = 'marketing' and tool = 'zz_demo_tool' and available) then v_fail := v_fail || 'a done build did not flip the register: ' || v_r::text || '; '; end if;
  v_req := public.fn_engineer_session_request_open('glockapps_retest', 'it_engineer', 'glockapps_test', 'ZZ DEMO a GlockApps re-test for the scenario', 'ZZ DEMO a decided test recorded after the request', null, null, 'microsoft', null);
  if not coalesce((public.fn_engineer_session_request_wont_do(v_req, 'zz-demo-session', 'ZZ DEMO no credit left this month')->>'ok')::boolean, false) then v_fail := v_fail || 'wont_do failed; '; end if;
  select count(*) into v_n from public.seat_order_turn where thread_id = v_h;
  if v_fail <> '' then raise exception 'CHK<<SCENARIO FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<SCENARIO OK: % turns>>', v_n;
end $s$;`;

test('8. (local Postgres) the files apply twice, the probe plays the founder\'s example, the other transitions hold', { skip: LOCAL_SKIP, timeout: 600000 }, () => {
  const db = 'order_check_' + process.pid;
  const admin = (args) => spawnSync('psql', [URL_, '-v', 'ON_ERROR_STOP=1', '-q', ...args], { encoding: 'utf8' });
  const at = (args, input) => spawnSync('psql', [URL_.replace(/\/[^/?]+(\?|$)/, `/${db}$1`), '-q', ...args], { encoding: 'utf8', input });
  const tpl = URL_.match(/\/([^/?]+)(\?|$)/)[1];
  assert.equal(admin(['-c', `create database ${db} template ${tpl}`]).status, 0, 'the copy of the local database');
  try {
    for (const f of [...BEFORE, FILE, FILE]) {
      const r = at(['-v', 'ON_ERROR_STOP=1', '-1', '-f', join(REPO, f)]);
      assert.equal(r.status, 0, `${f} does not apply: ${r.stderr.slice(0, 600)}`);
    }
    for (let i = 0; i < 2; i++) assert.match(at(['-f', join(REPO, PROBE)]).stderr, /CHK<<PROBE OK/, 'the probe');
    assert.match(at([], SCENARIO).stderr, /CHK<<SCENARIO OK/, 'the other transitions');
  } finally { admin(['-c', `drop database if exists ${db}`]); }
});
