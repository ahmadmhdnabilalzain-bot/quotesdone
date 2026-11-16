-- EVERY HAND-OVER HAS AN OWNER AND A CLOCK, AND CLOSES OR ESCALATES ONCE TO THE CEO, WHOSE DECISION CLOSES IT.
-- Seat: ceo. Agent: L4_LOOPS (ledger build wave 1, item 6). 16 Nov 2026. Founder ledger 1535 ("Not a single thing in our app is
-- one-way communication. Everything runs in loops"), 1688 (a real office: "It's a loop. It's never like this agent is done with
-- this task, he just sends an output and he doesn't know what happens after that"), 1685; rulings 1696 and 1710 (the CEO decides,
-- nothing waits on the founder).
--
-- MEASURED (production, read-only SELECTs on tables, views and the catalogue, 16 Nov 2026 ~14:20 UTC):
--   * 697 agent_actions pending (the ledger's "704 open hand-overs"): 399 held_question, 285 handoff, 10 held_question_expired,
--     1 backup_coverage, 1 doc_trades_held, 1 service_alias_review. 0 demo rows, 0 duplicates by subject.
--   * Every handoff kind (150 rows of seat_handoff_kind) names a handler that exists in public; the release this builds on retires
--     none of the 56 handlers. So there are NO dead letters among the handoffs today: what is open is answered work that nobody
--     closes. All 285 carry replied_at. 197 are it.finding waiting for the it_engineer to re-verify a fault that is still there
--     (82 to the CEO, 115 to the other seats); 24 delivery.request wait for the next IT digest; the rest are orders, revisions,
--     deliberations, knowledge requests and month directives.
--   * The overdue escalation (fn_handoff_overdue_escalate) skips any row escalated to a support_ceo_report (199), any row older
--     than 60 days, and every non-handoff row. 9 open rows carry its mark. The CEO's case for them (surface ceo.overdue_handoff,
--     fn_ceo_files_judgements) shares one room of 30 a day with ceo.it_finding and ceo.authority, and the IT findings take all
--     of it: asked_today 30, room 0; production holds NO ceo.overdue_handoff question, ever. Its 'wait' choice re-asks every
--     7 days for ever, so even a decided row would not close.
--   * held_question: 352 past their due_at, 44 offered to a seat's daily backlog review; the CEO's own "raise" marks
--     needs_founder (a wait on the founder, against 1696/1710). held_question_expired: 10 person-facing questions from 6 Oct
--     with no routine that works them for a seat other than the CEO.
--   * ceo_directive: 114 missed against 22 met, but 103 chains: fn_ceo_directive_review re-issues a missed directive up to 4
--     times, and a miss after the re-issue only opens a ceo_task nobody decides. 68 of the misses are per-source compliance
--     re-checks owned by the CEO, which fn_ceo_register_review itself (15 Nov) found "could never be met" and replaced by one
--     batch to the it_engineer; 34 such chains were still open. The seat_audit check ("no handoff to the seat is open past its
--     reply window") counts a hand-over the seat ANSWERED that waits on the sender (memory: a-handoff-is-answered-at-replied-at),
--     so 14 seat_audit directives missed for the it_engineer's lag. Every directive has a live seat and a check that ran
--     without error (0 errored).
--
-- WHAT IS NOW TRUE:
--   1. A REGISTER FOR EVERY KIND. Handoff kinds stay in public.seat_handoff_kind; every other kind of pending work is in the new
--      public.agent_action_kind (owner rule, handler, clock, or the reason it is retired). public.v_handover_open shows every open
--      hand-over with its owner seat (the seat that owes the next move: the receiver, or the sender once it was answered and the
--      sender closes), whether its kind is registered, whether its handler exists, its due time and its escalation.
--   2. THE CLOCK (duty ceo.handover_clock, hourly, fn_handover_clock_tick):
--      a. fn_handover_sweep closes, with the reason on the row, only what can never complete: a row whose kind has no handler
--         ("no handler: ..."), a test row older than a day ("test row: ..."), and a later copy of the same subject ("duplicate of
--         #<kept>", the first one stays open). Every other open row gets detail.clock {owner_seat, due_at, kind, handler}.
--         A row of an UNREGISTERED kind is never closed: it is counted and goes to the CEO at its due time like any other.
--      b. fn_handoff_overdue_escalate (redefined) escalates EVERY open hand-over past its due time, of any kind and any age, ONCE
--         (detail.silence.escalated_at; never again) to the owner seat's manager: the CEO, including for the CEO's own. Never the
--         founder. Rows the CEO already judges on their own surface (an it.finding or ceo.authority hand-over to the CEO) and a
--         parked question in its seat's review today are left to that decision and counted.
--   3. THE CEO'S DECISION CLOSES IT. fn_ceo_files_judgements files each escalated row as a ceo.overdue_handoff question on its OWN
--      daily room (decision_policy 'ceo_daily_overdue_cases', 40 a day, AED 0.60, 10 a tick; the routine route, AED 0.0106) so the
--      IT findings can no longer starve it. The choices all close the row: close (with the reason), chase / reorder (the row
--      closes and a ceo.order to the owing seat carries the work, with its own clock), withdraw (a late order), answer (the
--      CEO's own), reissue (a missed directive, once more, due in 7 days). There is no 'wait'. fn_reason_apply_ceo__overdue_handoff
--      carries the choice out through fn_handover_close: 'done' when the CEO may close it (he sent it, or its kind does not wait
--      for its sender), otherwise 'dismissed' with the CEO's decision on the row, so a dismissal is never shown as finished work.
--   4. DIRECTIVES: each has a live owner (fn_ceo_directive_issue already refuses another) and a check of the result it asked for:
--      the issuer now also refuses a check that errors (it could never be met); the seat_audit check counts only hand-overs the
--      seat itself owes (fn_ceo_directive_run, and the 3 open ones are corrected); a directive missed after its one re-issue
--      becomes a directive_missed item in the CEO's queue (fn_directive_missed_to_the_ceo) that the clock escalates and the CEO
--      decides, instead of a ceo_task nobody decides and up to 4 automatic re-issues (fn_ceo_directive_review). The open
--      per-source compliance directives to the CEO are withdrawn with that reason (new status 'withdrawn'), each one counted.
--
-- WHAT IT DOES NOT CHANGE: fn_seat_handoff, fn_seat_handoff_act, the IT loop (fn_it_loop_reverify still closes an it.finding when
-- its fault clears), the CEO's it.finding and authority judgements, the seats' backlog reviews (fn_seat_backlog_review), the
-- IT digest to the founder for a new bug (fn_ceo_it_escalation_decide).
--
-- Every routine redefined here was diffed against production's pg_get_functiondef on 16 Nov 2026 (md5 equal to the local copy
-- built from main): fn_handoff_overdue_escalate 9ebbc05e..., fn_ceo_files_judgements 4a932d34..., fn_ceo_judgement_room
-- c76e95ca..., fn_reason_apply_ceo__overdue_handoff 08817655..., fn_ceo_directive_run ad5d09a5..., fn_ceo_directive_review
-- 2b671f6d..., fn_ceo_directive_issue 55c98364... (md5 of the definition text as saved).
--
-- LOCKS: one CHECK on public.ceo_directive (a few hundred rows) is replaced; nothing alters agent_actions. lock_timeout 3 s: a
-- busy minute fails the apply fast, and it is re-run.
-- Probe: scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates_probe.sql (local PG16, twice).
-- Pending: scripts/sql/pending/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.txt
-- prevented by: scripts/checks/every_hand_over_has_an_owner_and_a_clock.test.mjs and the probe.
--   node scripts/apply_sql.mjs scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql --apply --ddl

set local lock_timeout = '3s';

-- ── 1. the register of the non-handoff kinds ────────────────────────────────────────────────────────────────────────────
create table if not exists public.agent_action_kind (
  kind text primary key,
  owner_rule text not null check (owner_rule in ('agent', 'detail_owner_seat')),
  handler text not null check (handler ~ '^(fn_[a-z0-9_]+|edge:supabase/functions/[A-Za-z0-9_./-]+#[a-z_]+)$'),
  close_within interval,
  retired_reason text,
  what text not null check (length(btrim(what)) >= 20),
  owner_file text not null,
  check ((retired_reason is null) = (close_within is not null))
);
comment on table public.agent_action_kind is
  'Every kind of pending agent_actions work that is not a seat hand-over (those are in seat_handoff_kind): who owns it, what works it, how long it may stay open, or why it is retired. Read by v_handover_open and the hand-over clock.';
alter table public.agent_action_kind enable row level security;
drop policy if exists agent_action_kind_service_role_only on public.agent_action_kind;
create policy agent_action_kind_service_role_only on public.agent_action_kind
  as permissive for all to public using (false) with check (false);
revoke all on public.agent_action_kind from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('agent_action_kind', true, 'company', 'The register of pending-work kinds that are not seat hand-overs: owner, handler and clock; small configuration.', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

insert into public.agent_action_kind (kind, owner_rule, handler, close_within, retired_reason, what, owner_file) values
  ('held_question', 'detail_owner_seat', 'fn_seat_backlog_review', interval '14 days', null,
   'A seat''s model question parked after its tries: the seat''s daily backlog review answers, retries, closes or raises it.',
   'scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.sql'),
  ('held_question_expired', 'agent', 'fn_ceo_files_judgements', interval '1 day', null,
   'A person''s question that expired unanswered; no seat routine works it, so at its due time the CEO decides it (order a seat to answer, or close with the reason).',
   'scripts/sql/a_held_question_lives_fourteen_days_once_the_model_is_open_and_the_newest_is_answered_first.sql'),
  ('backup_coverage', 'agent', 'fn_it_backup_alerts_settle', interval '2 days', null,
   'A Dropbox backup coverage alert; the it_engineer''s settle duty closes it against the coverage measured today.',
   'scripts/sql/a_backup_alert_closes_against_the_coverage_measured_today.sql'),
  ('doc_trades_held', 'agent', 'fn_ceo_files_judgements', interval '3 days', null,
   'A supplier document whose trades the readings did not agree on; no seat action reads it, so at its due time the CEO decides it.',
   'supabase/functions/_shared/supplier_doc_trades.ts'),
  ('service_alias_review', 'agent', 'edge:supabase/functions/sales_engineer/actions/operator.ts#alias_decide', interval '3 days', null,
   'A supplier''s own names for services, for the sales_engineer to approve or reject as aliases (action alias_decide).',
   'supabase/functions/_shared/supplier_services.ts'),
  ('directive_missed', 'agent', 'fn_ceo_files_judgements', interval '1 hour', null,
   'A CEO directive missed after its one re-issue: the CEO decides it at once (issue it once more, or close it with the reason).',
   'scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql')
on conflict (kind) do update set owner_rule = excluded.owner_rule, handler = excluded.handler, close_within = excluded.close_within,
  retired_reason = excluded.retired_reason, what = excluded.what, owner_file = excluded.owner_file;

-- ── 2. every open hand-over with its owner, handler and clock ──────────────────────────────────────────────────────────
create or replace function public.fn_handover_ts(p text)
returns timestamptz
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  return p::timestamptz;
exception when others then return null;
end $fn$;
revoke execute on function public.fn_handover_ts(text) from public, anon, authenticated;

create or replace function public.fn_handover_ts_id(p text)
returns bigint
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$ select case when p ~ '^[0-9]{1,18}$' then p::bigint end $fn$;
revoke execute on function public.fn_handover_ts_id(text) from public, anon, authenticated;

create or replace view public.v_handover_open with (security_invoker = true) as
select a.id, a.agent, a.kind, a.status, a.title, a.created_at, a.detail, a.evidence, a.target_table, a.target_id,
       case when a.kind = 'handoff' then 'handoff:' || coalesce(a.detail->>'type', '?') else a.kind end as kind_key,
       case when a.kind = 'handoff' then k.type is not null else ak.kind is not null end as registered,
       coalesce(k.handler, ak.handler) as handler,
       coalesce(k.handler, ak.handler) like 'edge:%'
         or exists (select 1 from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = coalesce(k.handler, ak.handler)) as handler_live,
       ak.retired_reason,
       coalesce(k.reply_within, interval '1 day') as reply_window,
       coalesce(k.originator_closes, false) as originator_closes,
       o.owner_seat,
       exists (select 1 from public.org_role r where r.role_id = o.owner_seat and r.status = 'active') as owner_live,
       c.due_at,
       c.due_at < now() as overdue,
       public.fn_handover_ts(a.detail->'silence'->>'escalated_at') as escalated_at,
       a.detail->'silence'->>'escalated_to' as escalated_to,
       coalesce(a.detail->'silence' ? 'ceo_decision', false) as ceo_decided,
       case when coalesce(a.detail->>'demo', '') = 'true' then 'detail.demo is true'
            when coalesce(a.title, '') ilike '%ZZ DEMO%' then 'the title says ZZ DEMO'
            when a.detail ? 'e2e_run_tag' then 'a test run tagged it (' || (a.detail->>'e2e_run_tag') || ')' end as test_reason,
       case when a.kind = 'handoff' and a.agent = 'ceo' and a.detail->>'type' in ('it.finding', 'ceo.authority')
              then 'the CEO judges it on its own surface (ceo.' || replace(a.detail->>'type', 'ceo.', '') || ')'
            when a.kind = 'held_question' and a.detail ? 'backlog_held_id'
                 and exists (select 1 from public.reasoning_held_question q
                              where q.id = public.fn_handover_ts_id(a.detail->>'backlog_held_id') and q.status = 'held')
              then 'its seat''s backlog review has it today' end as in_review
  from public.agent_actions a
  left join public.seat_handoff_kind k
    on a.kind = 'handoff' and k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
  left join public.agent_action_kind ak on a.kind <> 'handoff' and ak.kind = a.kind
  cross join lateral (select case when a.kind = 'handoff' then public.fn_handoff_owing_seat(a.detail->>'awaiting', a.agent)
                                  when ak.owner_rule = 'detail_owner_seat' then coalesce(nullif(a.detail->>'owner_seat', ''), a.agent)
                                  else a.agent end as owner_seat) o
  -- a handoff is due as fn_handoff_is_late reads it (an answered one honours its due_at); any other kind at its own clock,
  -- never earlier than a due_at its filer set
  cross join lateral (select case when a.kind = 'handoff'
                                  then case when a.detail ? 'replied_at'
                                            then coalesce(public.fn_handover_ts(a.detail->>'due_at'), a.created_at + coalesce(k.reply_within, interval '1 day'))
                                            else a.created_at + coalesce(k.reply_within, interval '1 day') end
                                  else greatest(coalesce(public.fn_handover_ts(a.detail->>'due_at'), '-infinity'::timestamptz),
                                                a.created_at + coalesce(ak.close_within, interval '1 day')) end as due_at) c
 where a.status in ('pending', 'open');
comment on view public.v_handover_open is
  'Every open hand-over (agent_actions pending/open): its owner seat (who owes the next move), registered kind, handler and whether it exists, due time, escalation and decision. The clock (fn_handover_clock_tick) and the CEO''s directives read it.';
revoke all on public.v_handover_open from anon, authenticated;

-- ── 3. one way to close a hand-over that is not finished by its own handler ────────────────────────────────────────────
create or replace function public.fn_handover_close(p_id bigint, p_by text, p_verdict text, p_extra jsonb default '{}'::jsonb, p_dismiss boolean default false)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; k public.seat_handoff_kind; v_ev jsonb;
begin
  if coalesce(btrim(p_verdict), '') = '' then raise exception 'a hand-over is never closed without its reason (%)', p_id; end if;
  select * into a from public.agent_actions where id = p_id for update;
  if not found or a.status not in ('pending', 'open') then return null; end if;
  v_ev := coalesce(a.evidence, '{}'::jsonb) || coalesce(p_extra, '{}'::jsonb)
          || jsonb_build_object('verdict', left(p_verdict, 1000), 'closed_by', p_by, 'closed_at', now(),
                                'not_cited', jsonb_build_object('reason', left(p_verdict, 300), 'by', p_by));
  if a.kind = 'handoff' and not p_dismiss then
    select * into k from public.seat_handoff_kind where type = a.detail->>'type' and from_seat = a.detail->>'from' and to_seat = a.agent;
    -- 'done' only where this closer may close it: the kind does not wait for its sender, or the closer IS the sender. A fault
    -- (it.finding) or a backup hand-over is finished only by the it_engineer's own re-verification, never by a decision.
    if found and (not k.originator_closes or a.detail->>'from' = p_by)
       and a.detail->>'type' not in ('it.finding', 'backup.refile', 'backup.remediate') then
      perform set_config('qd.handoff_closer', p_by, true);
      perform public.fn_seat_handoff_complete(p_id, v_ev);
      perform set_config('qd.handoff_closer', '', true);
      return 'done';
    end if;
  end if;
  if a.kind = 'held_question' and exists (select 1 from public.reasoning_held_question q
                                           where q.id = public.fn_handover_ts_id(a.detail->>'held_id') and q.status = 'held') then
    perform public.fn_reason_held_expire(array[public.fn_handover_ts_id(a.detail->>'held_id')], p_by, left(p_verdict, 500));
  end if;
  update public.agent_actions
     set status = 'dismissed', decided_at = now(), decided_by = p_by, evidence = v_ev
   where id = p_id;
  if a.kind = 'handoff' then perform public.fn_seat_handoff_event(p_id, 'dismissed'); end if;
  return 'dismissed';
end $fn$;
revoke execute on function public.fn_handover_close(bigint, text, text, jsonb, boolean) from public, anon, authenticated;

-- ── 4. the sweep: close only what can never complete, with the reason; stamp the clock on the rest ──────────────────────
create or replace function public.fn_handover_sweep(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_reason text; v_kept bigint; v_clock jsonb;
  n_dead int := 0; n_test int := 0; n_dup int := 0; n_stamped int := 0; v_by_reason jsonb := '{}'::jsonb; v_unreg jsonb;
begin
  -- every open row is read (a few hundred); WRITES stop at p_limit a run, so a backlog is worked down over the hourly runs
  for r in select v.* from public.v_handover_open v order by v.id loop
    exit when n_dead + n_test + n_dup + n_stamped >= greatest(coalesce(p_limit, 500), 1);
    v_reason := null; v_kept := null;
    -- (a) DEAD LETTERS: nothing can ever act on it. An unregistered NON-handoff kind is not one (it may be new work):
    --     it stays open and goes to the CEO at its due time.
    if r.kind = 'handoff' and not r.registered then
      v_reason := 'no handler: the conversation ' || coalesce(r.detail->>'type', '?') || ' from ' || coalesce(r.detail->>'from', '?')
                  || ' to ' || r.agent || ' is not in seat_handoff_kind, so fn_seat_handoff_act can never act on it';
    elsif r.retired_reason is not null then
      v_reason := 'no handler: the kind ' || r.kind || ' is retired (' || r.retired_reason || ')';
    elsif r.registered and not r.handler_live then
      v_reason := 'no handler: ' || r.handler || ' does not exist';
    elsif r.registered and not r.owner_live and not exists (select 1 from public.org_role o where o.role_id = r.agent and o.status = 'active') then
      v_reason := 'no handler: neither ' || coalesce(r.owner_seat, '?') || ' nor ' || r.agent || ' is a live seat';
    -- (b) TEST ROWS a day old: a rehearsal's leftovers never wait on a seat
    elsif r.test_reason is not null and r.created_at < now() - interval '1 day' then
      v_reason := 'test row: ' || r.test_reason;
    else
      -- (c) A LATER COPY OF THE SAME SUBJECT: the first one stays open and carries the work
      select x.id into v_kept from public.agent_actions x
       where x.status in ('pending', 'open') and x.kind = r.kind and x.agent = r.agent and x.id < r.id
         -- (a pending row is unique by agent, kind and target_id, so a copy differs there and names the same subject)
         and ((r.kind = 'handoff' and r.detail ? 'subject_id' and x.detail->>'type' = r.detail->>'type' and x.detail->>'from' = r.detail->>'from'
               and x.detail->>'subject_id' = r.detail->>'subject_id'
               and coalesce(x.detail->>'subject_table', '') = coalesce(r.detail->>'subject_table', ''))
           or (r.kind like 'held_question%' and x.detail->>'held_id' = r.detail->>'held_id' and r.detail ? 'held_id')
           or (r.kind = 'directive_missed' and x.target_id = r.target_id))
       order by x.id limit 1;
      if v_kept is not null then v_reason := 'duplicate of #' || v_kept || ' (the same subject; #' || v_kept || ' stays open)'; end if;
    end if;

    if v_reason is not null then
      perform public.fn_handover_close(r.id, 'ceo.handover_clock', v_reason,
        jsonb_build_object('closed_by_the_clock', jsonb_build_object('rule', split_part(v_reason, ':', 1), 'reason', v_reason,
                                                                     'kept_open', v_kept, 'handler', r.handler, 'at', now())), true);
      if v_reason like 'no handler%' then n_dead := n_dead + 1; elsif v_reason like 'test row%' then n_test := n_test + 1; else n_dup := n_dup + 1; end if;
      v_by_reason := v_by_reason || jsonb_build_object(r.kind_key, coalesce((v_by_reason->>r.kind_key)::int, 0) + 1);
      continue;
    end if;

    -- (d) THE CLOCK ON THE ROW: written only when it changed, so an hourly run rewrites nothing that is current
    v_clock := jsonb_build_object('owner_seat', r.owner_seat, 'due_at', r.due_at, 'kind', r.kind_key, 'handler', r.handler,
                                  'registered', r.registered);
    if (r.detail->'clock') - 'stamped_at' is distinct from v_clock then
      update public.agent_actions set detail = detail || jsonb_build_object('clock', v_clock || jsonb_build_object('stamped_at', now()))
       where id = r.id;
      n_stamped := n_stamped + 1;
    end if;
  end loop;
  select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) into v_unreg
    from (select v.kind, count(*) n from public.v_handover_open v where not v.registered and v.kind <> 'handoff' group by v.kind) u;
  return jsonb_build_object('closed_no_handler', n_dead, 'closed_test_rows', n_test, 'closed_duplicates', n_dup,
                            'closed_by_kind', v_by_reason, 'clock_stamped', n_stamped, 'unregistered_kinds_open', v_unreg);
end $fn$;
revoke execute on function public.fn_handover_sweep(integer) from public, anon, authenticated;

-- ── 5. past its due time: escalated ONCE to the owner seat's manager, the CEO ──────────────────────────────────────────
create or replace function public.fn_handoff_overdue_escalate()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; v_since timestamptz; n_seat int := 0; n_own int := 0; v_ids bigint[] := '{}';
begin
  for h in select v.* from public.v_handover_open v
            where v.overdue and v.escalated_at is null and v.in_review is null and v.test_reason is null
              and (v.registered and v.handler_live or (not v.registered and v.kind <> 'handoff'))
              and v.retired_reason is null
            order by v.due_at limit 200 loop
    v_since := case when h.kind = 'handoff' and h.detail ? 'replied_at' then coalesce(public.fn_handover_ts(h.detail->>'replied_at'), h.created_at)
                    else h.created_at end;
    -- THE MANAGER IS THE CEO: every live seat reports to the CEO, and the CEO's own late work is the CEO's to decide (1696).
    -- The founder is never a manager here (1696, 1710).
    update public.agent_actions
       set escalated = true,
           escalation_reason = left('Past its due time (' || to_char(h.due_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai): '
             || h.owner_seat || ' owes the next move since ' || to_char(v_since at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             || '; escalated once to the ceo, whose decision closes it (fn_handoff_overdue_escalate)', 500),
           detail = detail || jsonb_build_object('silence', jsonb_build_object(
             'silent_seat', h.owner_seat, 'since', v_since, 'due', h.due_at, 'escalated_to', 'ceo', 'escalated_at', now(),
             'kind', h.kind_key, 'registered', h.registered,
             'owes', case when h.kind <> 'handoff' then coalesce(h.detail->>'waiting_for', h.detail->>'needed', 'its decision')
                          when h.owner_seat = h.agent and not (h.detail ? 'replied_at') then 'an answer'
                          when h.owner_seat = h.detail->>'from' then 'the close of an answered hand-over'
                          else coalesce(h.detail->>'awaiting', 'the next step') end))
     where id = h.id and status in ('pending', 'open') and not coalesce(detail->'silence' ? 'escalated_at', false);
    continue when not found;
    insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
    values ('handoff.overdue.escalated', 'agent_actions', h.id::text, coalesce(h.detail->>'from', h.agent),
            jsonb_build_object('handoff_id', h.id, 'kind', h.kind_key, 'type', h.detail->>'type', 'from', h.detail->>'from', 'to', h.agent,
                               'silent_seat', h.owner_seat, 'since', v_since, 'escalated_to', 'ceo',
                               'subject_table', h.detail->>'subject_table', 'subject_id', h.detail->>'subject_id'),
            'handoff.overdue.escalated:' || h.id)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
    if h.owner_seat = 'ceo' then n_own := n_own + 1; else n_seat := n_seat + 1; end if;
    v_ids := v_ids || h.id;
  end loop;
  return jsonb_build_object('escalated_to_a_seat', n_seat, 'the_ceos_own', n_own, 'ids', to_jsonb(v_ids));
end $fn$;
revoke execute on function public.fn_handoff_overdue_escalate() from public, anon, authenticated;

-- ── 6. the CEO's room for late hand-overs is its own ───────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('ceo_daily_overdue_cases', '{"items": 40, "aed": 0.6, "per_tick": 10}'::jsonb,
   'How many late hand-overs the CEO''s model decides a day (ceo.overdue_handoff, routine route). Its own room, so the IT findings cannot starve it. The CEO may change it.')
on conflict (key) do nothing;

create or replace function public.fn_ceo_overdue_room()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p jsonb := coalesce((select value from public.decision_policy where key = 'ceo_daily_overdue_cases'), '{}'::jsonb);
        v_items int := coalesce((p->>'items')::int, 40); v_aed numeric := coalesce((p->>'aed')::numeric, 0.6);
        v_tick int := coalesce((p->>'per_tick')::int, 10); v_unit numeric; v_today int;
        v_day timestamptz := (date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai');
begin
  select avg(cost_aed) into v_unit from public.ai_cost_log
   where coalesce(seat, agent_key) = 'ceo' and task_class = 'routine_employee_reasoning' and occurred_at > now() - interval '7 days';
  v_unit := greatest(coalesce(v_unit, 0.0106), 0.0001);
  select count(*) into v_today from public.reasoning_held_question
   where surface = 'ceo.overdue_handoff'
     and greatest(created_at, coalesce(case when plan->>'rearmed_at' ~ '^\d{4}' then (plan->>'rearmed_at')::timestamptz end, created_at)) >= v_day;
  return jsonb_build_object('room', greatest(0, least(v_items - v_today, floor((v_aed - v_today * v_unit) / v_unit)::int, v_tick)),
    'asked_today', v_today, 'items_cap', v_items, 'aed_cap', v_aed, 'unit_aed', round(v_unit, 4), 'per_tick', v_tick);
end $fn$;
revoke execute on function public.fn_ceo_overdue_room() from public, anon, authenticated;

-- The shared room now holds the IT findings and the authority questions only; the late hand-overs have their own.
create or replace function public.fn_ceo_judgement_room()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare p jsonb := coalesce((select value from public.decision_policy where key = 'ceo_daily_judgements'), '{}'::jsonb);
        v_items int := coalesce((p->>'items')::int, 30); v_aed numeric := coalesce((p->>'aed')::numeric, 0.5);
        v_tick int := coalesce((p->>'per_tick')::int, 5); v_unit numeric; v_today int;
        v_day timestamptz := (date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai');
begin
  select avg(cost_aed) into v_unit from public.ai_cost_log
   where coalesce(seat, agent_key) = 'ceo' and task_class = 'routine_employee_reasoning' and occurred_at > now() - interval '7 days';
  v_unit := greatest(coalesce(v_unit, (p->>'unit_aed_default')::numeric, 0.0106), 0.0001);
  select count(*) into v_today from public.reasoning_held_question
   where surface in ('ceo.it_finding', 'ceo.authority')   -- ceo.overdue_handoff has its own room (fn_ceo_overdue_room)
     and greatest(created_at, coalesce(case when plan->>'rearmed_at' ~ '^\d{4}' then (plan->>'rearmed_at')::timestamptz end, created_at)) >= v_day;
  return jsonb_build_object('room', greatest(0, least(v_items - v_today, floor((v_aed - v_today * v_unit) / v_unit)::int, v_tick)),
    'asked_today', v_today, 'items_cap', v_items, 'aed_cap', v_aed, 'unit_aed', round(v_unit, 4), 'per_tick', v_tick);
end $fn$;
revoke execute on function public.fn_ceo_judgement_room() from public, anon, authenticated;


-- fn_ceo_files_judgements: the authority and IT-finding loops are production's text unchanged; the late hand-overs loop is new.
create or replace function public.fn_ceo_files_judgements()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare v_room jsonb := public.fn_ceo_judgement_room(); n int := (v_room->>'room')::int; r record; v_opts jsonb; v_case jsonb;
        n_a int := 0; n_f int := 0; n_o int := 0; v_round int; v_id bigint; v_seats text[]; v_guard text; v_text text; v_limits jsonb;
        v_auth_room int; v_ov jsonb; n_ov int; v_owner text;
begin
  -- the late hand-overs keep their own room, so an empty shared room no longer stops them (16 Nov 2026)
  if n < 0 then n := 0; end if;
  -- half of the room (one when the room is one): the IT findings and the late hand-overs keep the other half
  v_auth_room := case when n <= 1 then n else n / 2 end;
  v_limits := public.fn_company_limits();
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'ceo' and a.status = 'pending' and a.detail->>'type' = 'ceo.authority'
              and not (a.evidence ? 'ceo_decision') and not coalesce((a.detail->>'demo')::boolean, false)
              and not exists (select 1 from public.reasoning_held_question q
                               where q.dedupe_key = 'ceo.authority:' || a.id || ':1'
                                 and (q.status = 'held' or coalesce(q.last_attempt_at, q.created_at) > now() - interval '24 hours'))
            order by a.created_at limit v_auth_room loop
    v_id := public.fn_ceo_ask('ceo.authority', r.id, 1,
      'The ' || (r.detail->>'from') || ' asks: ' || (r.detail->>'what') || ' (' || (r.detail->>'action_class') || ' on ' || (r.detail->>'subject')
        || coalesce(', AED ' || (r.detail->>'amount_aed'), '') || '). Why: ' || coalesce(r.detail->>'why', 'not given') || '. The standing rule refused it: '
        || coalesce(r.detail->>'refusal', '?') || ' The company limits allow it (per action AED ' || coalesce(v_limits->>'per_action_aed', '?')
        || ', AED ' || coalesce(v_limits->>'spent_today_aed', '?') || ' of AED ' || coalesce(v_limits->>'daily_spend_aed', '?')
        || ' committed today), and every message still passes the consent, suppression, opt-out and inbox-placement gates. As CEO you decide alone (founder ledger 1696): decide and give the reason in one or two sentences.',
      jsonb_build_object('handoff_id', r.id, 'asked_by', r.detail->>'from', 'action_class', r.detail->>'action_class', 'subject', r.detail->>'subject',
                         'amount_aed', r.detail->'amount_aed', 'what', r.detail->>'what', 'why', r.detail->>'why', 'facts', r.detail->'facts',
                         'refusal', r.detail->>'refusal', 'limits', v_limits),
      jsonb_build_array(
        jsonb_build_object('id', 'allow_once', 'meaning', 'let ' || (r.detail->>'from') || ' do exactly this, once, within 24 hours; your answer is the reason it may'),
        jsonb_build_object('id', 'refuse', 'meaning', 'refuse it; your answer is the reason ' || (r.detail->>'from') || ' reads')));
    if v_id is not null then n_a := n_a + 1; end if;
  end loop;
  n := n - n_a;
  for r in select a.*, f.title ftitle, f.where_it_is, f.affected, f.seen_count, f.started_at fstart, f.last_seen_at, f.closed_at fclosed, f.evidence fev, f.blast fblast
             from public.agent_actions a
             left join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
            where n > 0 and a.kind = 'handoff' and a.agent = 'ceo' and a.status = 'pending' and a.detail->>'type' = 'it.finding'
              and f.closed_at is null
              and not coalesce((a.detail->>'demo')::boolean, false) and coalesce(a.title, '') not ilike '%ZZ DEMO%'
              and not public.fn_seat_work_is_demo(a.detail::text, a.detail, a.target_table, a.detail->>'subject_id')
              and (not (a.evidence ? 'ceo_decision')
                   or (a.evidence->'ceo_decision'->>'review_at')::timestamptz < now())
              and not exists (select 1 from public.reasoning_held_question q
                               where q.dedupe_key = 'ceo.it_finding:' || a.id || ':' || (coalesce((a.evidence->'ceo_decision'->>'round')::int, 0) + 1)
                                 and (q.status = 'held' or coalesce(q.last_attempt_at, q.created_at) > now() - interval '24 hours'))
            order by case lower(coalesce(a.detail->>'severity', '')) when 'critical' then 0 when 'high' then 1 when 'serious' then 2 when 'moderate' then 3 else 4 end,
                     a.created_at
            limit greatest(n, 0) loop
    v_round := coalesce((r.evidence->'ceo_decision'->>'round')::int, 0) + 1;
    v_text := concat_ws(' ', r.detail->>'issue_key', coalesce(r.ftitle, r.detail->>'title'), coalesce(r.where_it_is, r.detail->>'where_it_is'));
    v_seats := public.fn_ceo_fix_seats(v_text, coalesce(r.fblast, r.detail->>'blast'), r.detail->>'duty');
    v_guard := public.fn_ceo_finding_guard(r.detail->>'severity', coalesce(r.fblast, r.detail->>'blast'), v_text);
    v_opts := coalesce((select jsonb_agg(jsonb_build_object('id', 'fix_now:' || s, 'meaning',
                          case when s = 'it_engineer' then 'the IT engineer prepares the code or configuration change within 7 days (a deploy keeps its release path)'
                               else replace(s, '_', ' ') || ' fixes it within 7 days (its duties cover this subject)' end) order by s)
                          from unnest(v_seats) s), '[]'::jsonb)
      || case when v_guard is null
              then jsonb_build_array(jsonb_build_object('id', 'accept_risk', 'meaning', 'accept the risk for 14 days; your answer is the reason; it comes back to you on the review date'))
              else '[]'::jsonb end
      || coalesce((select jsonb_agg(jsonb_build_object('id', 'duplicate_of:' || d.id, 'meaning', 'the same fault as open finding #' || d.id || ': ' || left(coalesce(d.detail->>'title', d.detail->>'issue_key'), 80)))
                     from (select x.id, x.detail from public.agent_actions x
                            where x.kind = 'handoff' and x.detail->>'type' = 'it.finding' and x.status = 'pending' and x.id <> r.id
                              and (split_part(x.detail->>'issue_key', ':', 1) || ':' || split_part(x.detail->>'issue_key', ':', 2)
                                     = split_part(r.detail->>'issue_key', ':', 1) || ':' || split_part(r.detail->>'issue_key', ':', 2)
                                   or (nullif(x.detail->>'title', '') is not null and x.detail->>'title' = r.detail->>'title'))
                            order by x.id limit 3) d), '[]'::jsonb);
    v_case := jsonb_build_object('handoff_id', r.id, 'issue_key', r.detail->>'issue_key', 'title', coalesce(r.ftitle, r.detail->>'title'),
      'severity', r.detail->>'severity', 'blast', coalesce(r.fblast, r.detail->>'blast'), 'where', coalesce(r.where_it_is, r.detail->>'where_it_is'), 'duty', r.detail->>'duty',
      'open_since', r.fstart, 'last_seen', r.last_seen_at, 'seen_count', r.seen_count, 'affected', r.affected,
      'still_open', r.fclosed is null, 'evidence', left(coalesce(r.fev::text, (r.detail->'finding_evidence')::text, ''), 1200),
      'accept_risk_not_offered_because', v_guard, 'previous_decision', r.evidence->'ceo_decision');
    v_id := public.fn_ceo_ask('ceo.it_finding', r.id, v_round,
      'IT finding #' || r.id || ': "' || left(coalesce(r.ftitle, r.detail->>'title', r.detail->>'issue_key'), 200) || '" ('
        || coalesce(r.detail->>'severity', 'severity not recorded') || ', open since ' || coalesce(to_char(r.fstart at time zone 'Asia/Dubai', 'DD Mon'), '?')
        || ', seen ' || coalesce(r.seen_count::text, '?') || ' times). As CEO, decide what happens next and give the reason in one or two sentences.',
      v_case, v_opts);
    if v_id is not null then n_f := n_f + 1; end if;
  end loop;
  n := n - n_f;
  -- THE LATE HAND-OVERS (16 Nov 2026, L4_LOOPS): every row the clock escalated, of any kind, on its OWN room so the IT
  -- findings above can no longer take all of it (production 16 Nov: room 0, no ceo.overdue_handoff question ever filed).
  -- Each choice CLOSES the row (fn_reason_apply_ceo__overdue_handoff); there is no 'wait' that re-asks for ever.
  v_ov := public.fn_ceo_overdue_room();
  n_ov := (v_ov->>'room')::int;
  for r in select a.*, v.owner_seat as v_owner, v.kind_key as v_key, v.due_at as v_due
             from public.agent_actions a
             join public.v_handover_open v on v.id = a.id
            where n_ov > 0 and a.detail->'silence'->>'escalated_to' = 'ceo' and a.detail->'silence' ? 'escalated_at'
              and not (a.detail->'silence' ? 'ceo_decision')
              and not exists (select 1 from public.reasoning_held_question q
                               where q.dedupe_key = 'ceo.overdue_handoff:' || a.id || ':1'
                                 and (q.status = 'held' or coalesce(q.last_attempt_at, q.created_at) > now() - interval '24 hours'))
            order by case when a.kind = 'directive_missed' then 0 when a.kind = 'handoff' then 1
                          when public.fn_held_question_is_person_facing(a.detail->>'surface') then 2 else 3 end,
                     (a.detail->'silence'->>'escalated_at')::timestamptz, a.id
            limit greatest(n_ov, 0) loop
    v_owner := coalesce(r.detail->'silence'->>'silent_seat', r.v_owner);
    v_opts := case
      when r.kind = 'handoff' and r.detail->>'type' = 'ceo.order'
        then jsonb_build_array(jsonb_build_object('id', 'withdraw', 'meaning', 'withdraw the order: it is no longer needed or cannot be done; your answer is the reason ' || r.agent || ' reads'),
                               jsonb_build_object('id', 'reorder', 'meaning', 'close this late order and give ' || r.agent || ' a new one due in 7 days; your answer is the new order, in your words'))
      when r.kind = 'directive_missed'
        then jsonb_build_array(jsonb_build_object('id', 'reissue', 'meaning', 'issue the directive to ' || coalesce(r.detail->>'seat', 'its seat') || ' once more, due in 7 days; your answer says what must change'),
                               jsonb_build_object('id', 'close', 'meaning', 'close it: the result is no longer wanted, out of the seat''s reach, or covered by other work; your answer is the reason'))
      when v_owner = 'ceo'
        then jsonb_build_array(jsonb_build_object('id', 'answer', 'meaning', 'answer it now: your answer is the reply, and the hand-over closes'),
                               jsonb_build_object('id', 'close', 'meaning', 'close it without an answer: your answer says why nothing more is owed'))
      else jsonb_build_array(jsonb_build_object('id', 'chase', 'meaning', 'order ' || v_owner || ' to finish it within 2 days: this hand-over closes and the order carries the work; your answer says what is owed'),
                             jsonb_build_object('id', 'close', 'meaning', 'close it: the work is done, moot or will not be done; your answer is the reason ' || v_owner || ' reads'))
    end;
    v_id := public.fn_ceo_ask('ceo.overdue_handoff', r.id, 1,
      'Late ' || r.v_key || ' #' || r.id || ' (' || left(coalesce(r.title, ''), 160) || '): ' || v_owner || ' owes '
        || coalesce(r.detail->'silence'->>'owes', 'the next step') || ', due ' || to_char(r.v_due at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
        || ' Dubai. It was escalated to you once and your decision closes it. Decide and give the reason in one or two sentences.',
      jsonb_build_object('handoff_id', r.id, 'kind', r.v_key, 'type', r.detail->>'type', 'from', r.detail->>'from', 'to', r.agent,
                         'owner', v_owner, 'silence', r.detail->'silence', 'awaiting', r.detail->>'awaiting', 'summary', r.detail->'summary',
                         'what', coalesce(r.detail->>'what', r.detail->>'waiting_for', r.detail->>'needed'),
                         'question', left(coalesce(r.detail->>'question', ''), 700), 'surface', r.detail->>'surface',
                         'directive', case when r.kind = 'directive_missed' then jsonb_build_object('seat', r.detail->>'seat', 'instruction', r.detail->>'instruction',
                                         'done_when', r.detail->>'done_when', 'deadline', r.detail->>'deadline') end,
                         'reply', left(coalesce(r.evidence::text, ''), 600)),
      v_opts);
    if v_id is not null then n_o := n_o + 1; end if;
  end loop;
  return v_room || jsonb_build_object('authority_room', v_auth_room, 'filed_authority', n_a, 'filed_it_findings', n_f, 'filed_overdue', n_o, 'overdue_room', v_ov);
end $fn$;
revoke execute on function public.fn_ceo_files_judgements() from public, anon, authenticated;


-- ── 7. the CEO's decision closes the late hand-over ────────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_apply_ceo__overdue_handoff(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare q public.reasoning_held_question; h public.agent_actions; d public.ceo_directive; v_choice text := p_result->'decision'->>'choice';
        v_reason text := btrim(coalesce(p_result->>'answer', '')); v_dec jsonb; v_owner text; v_to text; v_h bigint; v_new bigint;
        v_status text; v_what text;
begin
  select * into q from public.reasoning_held_question where id = p_id;
  select * into h from public.agent_actions where id = (q.subject->>'handoff_id')::bigint for update;
  if not found or h.status not in ('pending', 'open') then return jsonb_build_object('skipped', 'the hand-over is no longer open'); end if;
  if not public.fn_ceo_answer_is_offered(q, p_result) then
    -- an answer that is not one of the choices, or has no reason, decides nothing; the question is offered again after 24 hours
    update public.agent_actions set detail = detail || jsonb_build_object('ceo_judgement_refused',
      jsonb_build_object('held_id', p_id, 'choice', v_choice, 'at', now(), 'why', 'not one of the offered choices, or no reason')) where id = h.id;
    return null;
  end if;
  v_owner := coalesce(h.detail->'silence'->>'silent_seat', h.agent);
  v_dec := jsonb_build_object('choice', v_choice, 'reason', left(v_reason, 600), 'model', p_result->>'model', 'held_id', p_id,
                              'decided_at', now(), 'by', 'ceo (model, surface ceo.overdue_handoff)');
  v_what := coalesce(h.detail->'silence'->>'owes', 'the next step') || ' on ' || coalesce(h.detail->'silence'->>'kind', h.kind) || ' #' || h.id
            || ' (' || left(coalesce(h.title, ''), 160) || ')';

  if v_choice in ('chase', 'reorder') then
    -- THE WORK GOES ON AS AN ORDER WITH ITS OWN CLOCK, and the late hand-over closes: never an order about an open order
    v_to := case when v_choice = 'reorder' then h.agent else v_owner end;
    if not exists (select 1 from public.org_role where role_id = v_to and status = 'active') or v_to = 'ceo' then
      raise exception 'fn_reason_apply_ceo__overdue_handoff: % is not a live seat the CEO can order (hand-over %)', v_to, h.id;
    end if;
    v_h := public.fn_seat_handoff('ceo', v_to, 'ceo.order', 'agent_actions', h.id || ':' || v_choice,
      jsonb_build_object('decision', v_choice, 'reasons', left(v_reason, 600), 'overdue_handoff_id', h.id, 'path', 'overdue_handoff',
                         'what', left(v_reason, 600) || ' (late: ' || v_what || ')',
                         'due_at', now() + case when v_choice = 'chase' then interval '2 days' else interval '7 days' end));
    if v_h is null then
      raise exception 'fn_reason_apply_ceo__overdue_handoff: the order for hand-over % was not filed', h.id;
    end if;
    v_dec := v_dec || jsonb_build_object('order_handoff_id', v_h, 'ordered', v_to);
  elsif v_choice = 'reissue' and h.kind = 'directive_missed' then
    select * into d from public.ceo_directive where id = (h.detail->>'directive_id')::bigint;
    if found then
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref,
              'RE-ISSUED by the CEO after #' || d.id || ' was missed: ' || left(v_reason, 600) || ' ' || regexp_replace(d.instruction, '^RE-ISSUED[^:]*: ', ''),
              d.done_when, d.done_sql, now() + interval '7 days', d.id,
              (d.evidence - 'missed' - 'escalated' - 'closed' - 'measured' - 'review' - 'ceo_case') || jsonb_build_object('reissued_by_the_ceo', v_dec))
      returning id into v_new;
      v_dec := v_dec || jsonb_build_object('reissue_id', v_new);
    end if;
  elsif v_choice = 'answer' then
    v_dec := v_dec || jsonb_build_object('reply', 'The CEO answers: ' || left(v_reason, 500));
  end if;

  if h.kind = 'directive_missed' then
    update public.ceo_directive set evidence = evidence || jsonb_build_object('ceo_case', v_dec || jsonb_build_object('action_id', h.id))
     where id = (h.detail->>'directive_id')::bigint;
  end if;
  update public.agent_actions set detail = jsonb_set(detail, '{silence}', coalesce(detail->'silence', '{}'::jsonb) || jsonb_build_object('ceo_decision', v_dec))
   where id = h.id;
  v_status := public.fn_handover_close(h.id, 'ceo',
    case v_choice when 'chase' then 'The CEO ordered ' || v_to || ' to finish it (order #' || v_h || '): ' || left(v_reason, 400)
                  when 'reorder' then 'The CEO replaced this late order with order #' || v_h || ': ' || left(v_reason, 400)
                  when 'withdraw' then 'The CEO withdrew this order: ' || left(v_reason, 400)
                  when 'answer' then 'The CEO answered it: ' || left(v_reason, 400)
                  when 'reissue' then 'The CEO issued the directive once more' || coalesce(' as #' || v_new, '') || ': ' || left(v_reason, 400)
                  else 'The CEO closed it: ' || left(v_reason, 400) end,
    jsonb_build_object('ceo_decision', v_dec) || case when v_choice = 'answer' then jsonb_build_object('reply', 'The CEO answers: ' || left(v_reason, 500)) else '{}'::jsonb end,
    -- the CEO's own decision on a hand-over another seat sends and closes is recorded as dismissed-with-reason, never as finished
    false);
  return jsonb_build_object('decided', v_choice, 'handoff_id', h.id, 'closed_as', v_status, 'order_handoff', v_h, 'reissue_id', v_new);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__overdue_handoff(bigint, jsonb) from public, anon, authenticated;

-- ── 8. directives: an owner, a check that can run, and a miss the CEO decides ──────────────────────────────────────────
alter table public.ceo_directive drop constraint if exists ceo_directive_status_check;
alter table public.ceo_directive add constraint ceo_directive_status_check
  check (status = any (array['open', 'met', 'escalated', 'missed', 'paused', 'withdrawn']));

create or replace function public.fn_directive_missed_to_the_ceo(p_directive_id bigint, p_error text default null)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  select 'ceo', 'directive_missed', 'pending', 'low',
         left('Directive #' || d.id || ' to ' || d.seat || ' missed after its re-issue: ' || d.done_when, 200),
         jsonb_build_object('directive_id', d.id, 'seat', d.seat, 'source_kind', d.source_kind, 'source_ref', d.source_ref,
                            'instruction', left(d.instruction, 1500), 'done_when', d.done_when, 'deadline', d.deadline,
                            'first_issued_as', d.escalated_from, 'check_error', p_error, 'owner_seat', 'ceo',
                            'waiting_for', 'the CEO decides: issue it once more, or close it with the reason'),
         'ceo_directive', d.id::text
    from public.ceo_directive d
   where d.id = p_directive_id
     and not exists (select 1 from public.agent_actions x where x.kind = 'directive_missed' and x.target_table = 'ceo_directive' and x.target_id = d.id::text)
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_directive_missed_to_the_ceo(bigint, text) from public, anon, authenticated;

-- fn_ceo_directive_issue: production's text; a check that errors refuses the directive instead of issuing one that can never be met.
create or replace function public.fn_ceo_directive_issue(p_seat text, p_kind text, p_ref text, p_instruction text, p_done_when text, p_done_sql text, p_deadline timestamp with time zone, p_evidence jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare v_id bigint; v_done boolean;
begin
  if exists (select 1 from public.ceo_directive where seat = p_seat and source_kind = p_kind and source_ref = p_ref and status <> 'met')
     or not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return null;
  end if;
  begin
    execute 'select coalesce((' || p_done_sql || ')::boolean, false)' into v_done;
  exception when others then
    -- 16 Nov 2026 (L4_LOOPS): a check that cannot run could never be met; no directive is issued without a check of its result
    return null;
  end;
  if v_done then
    return null;   -- nothing to direct: the condition is already met
  end if;
  insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, evidence)
  values (p_seat, p_kind, p_ref, p_instruction, p_done_when, p_done_sql, p_deadline, coalesce(p_evidence, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_directive_issue(text, text, text, text, text, text, timestamp with time zone, jsonb) from public, anon, authenticated;


-- fn_ceo_directive_run: production's text with two changes (the seat_audit check, and where a miss goes).
create or replace function public.fn_ceo_directive_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare r record; d public.ceo_directive; v bigint; v_ok boolean; v_err text; v_new bigint; v_dec bigint; v_task bigint;
  n_issued int := 0; n_met int := 0; n_esc int := 0; n_missed int := 0; n_paused int := 0; v_q date; v_hold text;
  -- 16 Nov 2026 (L4_LOOPS): the seat's OWN late hand-overs (v_handover_open.owner_seat): a hand-over it answered that waits on
  -- its sender is the sender's, not its own (memory: a-handoff-is-answered-at-replied-at); any other kind of open work counts too
  v_late text := $q$exists (select 1 from public.v_handover_open h
     where h.owner_seat = %1$L and case when h.kind = 'handoff' then public.fn_handoff_is_late(h.detail, h.created_at, h.reply_window) else h.overdue end)$q$;
begin
  -- 1. target misses on the year-one plan (a target the founder has held reads 'paused', never 'miss')
  for r in select e->>'metric' as metric, e->>'owner_seat' as seat, e->>'actual' as actual, e->>'expected' as expected
             from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(p_at)->'metrics', '[]'::jsonb)) e
            where e->>'status' = 'miss' and e->>'owner_seat' is not null loop
    v := public.fn_ceo_directive_issue(r.seat, 'target_miss', r.metric || ':' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM'),
      format('Bring %s back to its path: it reads %s against %s. Name the step that is not converting and change that step.', r.metric, coalesce(r.actual, '?'), r.expected),
      format('%s is no longer a miss on the year-one plan.', r.metric),
      format($q$not exists (select 1 from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb)) e where e->>'metric' = %L and e->>'status' = 'miss')$q$, r.metric),
      p_at + interval '7 days', jsonb_build_object('metric', r.metric, 'actual', r.actual, 'expected', r.expected));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 2. late deliverables: the month marketing plan
  for r in select i.id, (i.evidence->>'plan_month')::date as m, (i.evidence->>'deadline')::date as due_was, (i.evidence->>'due_on')::date as due_on
             from public.ceo_improvement i where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    v := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'marketing_month_plan:' || r.m,
      format('Send the CEO the marketing plan for %s. It was due on %s; the month does not start unplanned.', to_char(r.m, 'FMMonth YYYY'), to_char(r.due_was, 'DD Mon')),
      format('marketing_month_plan for %s exists and has left draft, or improvement #%s is closed.', r.m, r.id),
      format($q$exists (select 1 from public.marketing_month_plan p where p.month = %L::date and p.status <> 'draft') or exists (select 1 from public.ceo_improvement i where i.id = %s and i.status = 'done')$q$, r.m, r.id),
      greatest(coalesce(r.due_on::timestamp at time zone 'Asia/Dubai', p_at), p_at) + interval '1 day',
      jsonb_build_object('improvement_id', r.id, 'plan_month', r.m, 'due_was', r.due_was));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 3. stuck handoffs
  for r in select a.id, a.agent as seat, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v := public.fn_ceo_directive_issue(r.seat, 'stuck_handoff', 'agent_actions:' || r.id,
      format('Answer handoff #%s (%s from %s), waiting since %s.', r.id, r.type, r.from_seat, to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('handoff #%s is answered (replied_at set) or no longer pending.', r.id),
      format($q$exists (select 1 from public.agent_actions a where a.id = %s and (a.status <> 'pending' or a.detail ? 'replied_at'))$q$, r.id),
      p_at + interval '1 day', jsonb_build_object('handoff_id', r.id, 'type', r.type, 'from', r.from_seat, 'since', r.created_at));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 4. the latest seat audit's below-bar seats
  select max(quarter) into v_q from public.ceo_seat_audit;
  for r in select a.seat, a.shortfalls, a.improvement_id from public.ceo_seat_audit a where a.quarter = v_q and a.below_bar loop
    v := public.fn_ceo_directive_issue(r.seat, 'seat_audit', v_q || ':' || r.seat,
      format('Get back to the senior bar found short in the audit of the quarter starting %s: %s.', to_char(v_q, 'DD Mon YYYY'), array_to_string(r.shortfalls, '; ')),
      'the seat owes no hand-over past its due time (as receiver, or as the sender who closes it), and none of its duties is failing or overdue.',
      format('not ' || v_late || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, r.seat),
      p_at + interval '14 days', jsonb_build_object('quarter', v_q, 'improvement_id', r.improvement_id, 'shortfalls', r.shortfalls));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- the close loop: each open directive is re-checked on its own predicate
  for d in select * from public.ceo_directive where status = 'open' order by id loop
    -- 19 Oct 2026: a target directive on work the founder has held is paused - not met, not re-issued.
    v_hold := null;
    if d.source_kind = 'target_miss' then
      select h.hold_key into v_hold from public.fn_held_targets() h where h.target_key = d.evidence->>'metric' limit 1;
    end if;
    if v_hold is not null then
      update public.ceo_directive set status = 'paused', closed_at = p_at,
             evidence = evidence || jsonb_build_object('paused', jsonb_build_object('checked_at', p_at, 'founder_hold', v_hold))
       where id = d.id;
      n_paused := n_paused + 1; continue;
    end if;
    v_err := null;
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false; v_err := left(sqlerrm, 300);
    end;
    if v_ok then
      update public.ceo_directive set status = 'met', closed_at = p_at,
             evidence = evidence || jsonb_build_object('closed', jsonb_build_object('checked_at', p_at, 'predicate', d.done_sql, 'result', true))
       where id = d.id;
      n_met := n_met + 1;
    elsif p_at > d.deadline and d.escalated_from is null then
      update public.ceo_directive set status = 'escalated', closed_at = p_at,
             evidence = evidence || jsonb_build_object('escalated', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref, 'RE-ISSUED after the deadline of ' || to_char(d.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' passed: ' || d.instruction,
              d.done_when, d.done_sql, p_at + (d.deadline - d.issued_at), d.id, d.evidence)
      returning id into v_new;
      insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, outcome, dedupe_key)
      values ('directive_escalation',
              format('Directive #%s to %s passed its deadline unmet; re-issued once as #%s, due %s.', d.id, d.seat, v_new,
                     to_char((p_at + (d.deadline - d.issued_at)) at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('directive_id', d.id, 'reissue_id', v_new, 'seat', d.seat, 'done_when', d.done_when, 'deadline', d.deadline, 'predicate_error', v_err),
              'done-condition false at ' || p_at, 'decided', 'ceo_directive_escalation:' || d.id)
      on conflict do nothing returning id into v_dec;
      update public.ceo_directive set evidence = evidence || jsonb_build_object('decision_log_id', v_dec) where id = d.id;
      n_esc := n_esc + 1;
    elsif p_at > d.deadline then
      update public.ceo_directive set status = 'missed', closed_at = p_at,
             evidence = evidence || jsonb_build_object('missed', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      -- 16 Nov 2026 (L4_LOOPS): the miss is a case in the CEO's queue that the clock escalates and the CEO's model decides
      -- (issue it once more, or close it with the reason), not a ceo_task nobody decides
      v_task := public.fn_directive_missed_to_the_ceo(d.id, v_err);
      update public.ceo_directive set evidence = jsonb_set(evidence, '{missed,case_action_id}', coalesce(to_jsonb(v_task), 'null'::jsonb))
       where id = d.id;
      n_missed := n_missed + 1;
    end if;
  end loop;

  return jsonb_build_object('issued', n_issued, 'met', n_met, 'escalated', n_esc, 'missed', n_missed, 'paused', n_paused,
    'open', (select count(*) from public.ceo_directive where status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_directive_run(timestamp with time zone) from public, anon, authenticated;


-- fn_ceo_directive_review: production's text; a miss goes to the CEO's case instead of an automatic re-issue.
create or replace function public.fn_ceo_directive_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare d public.ceo_directive; v_metrics jsonb := coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb);
  v_ok boolean; v_m jsonb; v_reason text; v_new bigint; v_n int; n_measured int := 0; n_reissued int := 0; n_decided int := 0;
begin
  -- every open directive carries the reading it was measured at today
  for d in select * from public.ceo_directive where status = 'open' loop
    select e into v_m from jsonb_array_elements(v_metrics) e where e->>'metric' = split_part(d.source_ref, ':', 1) and d.source_kind = 'target_miss';
    update public.ceo_directive set evidence = evidence || jsonb_build_object('measured', jsonb_build_object('at', now(),
             'actual', v_m->'actual', 'expected', v_m->'expected', 'status', v_m->'status', 'deadline_in_days', round(extract(epoch from deadline - now()) / 86400, 1)))
     where id = d.id;
    n_measured := n_measured + 1;
  end loop;

  -- every missed directive gets the CEO's decision, once
  for d in select * from public.ceo_directive where status = 'missed' and not evidence ? 'review' order by id loop
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false;
    end;
    select e into v_m from jsonb_array_elements(v_metrics) e where e->>'metric' = split_part(d.source_ref, ':', 1) and d.source_kind = 'target_miss';
    v_reason := case when v_m is not null
      then format('%s reads %s against %s (gap %s%%) on %s.', v_m->>'metric', coalesce(v_m->>'actual', 'nothing measurable'), v_m->>'expected',
                  coalesce(v_m->>'gap_pct', '?'), to_char(now() at time zone 'Asia/Dubai', 'DD Mon'))
      else format('Still not true on %s: %s', to_char(now() at time zone 'Asia/Dubai', 'DD Mon'), d.done_when) end;
    select count(*) into v_n from public.ceo_directive where seat = d.seat and source_kind = d.source_kind and source_ref = d.source_ref;
    v_new := null;
    -- 16 Nov 2026 (L4_LOOPS): no automatic re-issue (it made chains of up to 4 misses, 114 missed rows from 103 chains). A
    -- miss still open goes to the CEO's queue once as a directive_missed case; the CEO's model decides reissue or close.
    if not v_ok then
      v_new := public.fn_directive_missed_to_the_ceo(d.id, null);
      n_reissued := n_reissued + (v_new is not null)::int;
    end if;
    update public.ceo_directive set evidence = evidence || jsonb_build_object('review', jsonb_build_object('at', now(), 'reason', v_reason,
             'decision', case when v_ok then 'met_since' when v_new is not null then 'to_the_ceo' else 'already_with_the_ceo' end,
             'case_action_id', v_new))
     where id = d.id;
    n_decided := n_decided + 1;
  end loop;
  return jsonb_build_object('measured', n_measured, 'missed_decided', n_decided, 'to_the_ceo', n_reissued,
    'open', (select count(*) from public.ceo_directive where status = 'open'),
    'met_7d', (select count(*) from public.ceo_directive where status = 'met' and closed_at > now() - interval '7 days'));
end $fn$;
revoke execute on function public.fn_ceo_directive_review() from public, anon, authenticated;


-- the per-source compliance re-checks the CEO could never meet (fn_ceo_register_review, 15 Nov: one monthly batch to the
-- it_engineer replaced them); each open one is withdrawn with that reason, and counted in the apply output below
update public.ceo_directive
   set status = 'withdrawn', closed_at = now(),
       evidence = evidence || jsonb_build_object('withdrawn', jsonb_build_object('at', now(), 'by', 'ceo',
         'reason', 'superseded: since 15 Nov 2026 the compliance sources are re-checked by the it_engineer in one monthly batch '
                   || '(fn_ceo_register_review, source compliance_sources:batch); a per-source re-check owned by the CEO could never be met'))
 where seat = 'ceo' and source_kind = 'register_review' and status = 'open' and source_ref ~ '^compliance_sources:[0-9]+:';

-- the open seat_audit directives get the corrected check: the seat owes no late hand-over (whichever side of it the seat is on)
update public.ceo_directive
   set done_when = 'the seat owes no hand-over past its due time (as receiver, or as the sender who closes it), and none of its duties is failing or overdue.',
       done_sql = format('not ' || $q$exists (select 1 from public.v_handover_open h
     where h.owner_seat = %1$L and case when h.kind = 'handoff' then public.fn_handoff_is_late(h.detail, h.created_at, h.reply_window) else h.overdue end)$q$
         || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, seat),
       evidence = evidence || jsonb_build_object('check_corrected', jsonb_build_object('at', now(), 'by', 'ceo',
         'why', 'the old check counted a hand-over the seat had answered that waits on its sender (memory: a-handoff-is-answered-at-replied-at)'))
 where source_kind = 'seat_audit' and status = 'open';

-- ── 9. the clock duty ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_handover_clock_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_sweep jsonb; v_esc jsonb; v_late int; v jsonb;
begin
  v_sweep := public.fn_handover_sweep(500);
  v_esc := public.fn_handoff_overdue_escalate();
  select jsonb_build_object(
           'open', count(*),
           'overdue', count(*) filter (where overdue),
           'overdue_not_escalated', count(*) filter (where overdue and escalated_at is null and in_review is null),
           'escalated_waiting_for_the_ceo', count(*) filter (where escalated_at is not null and not ceo_decided),
           'in_review', count(*) filter (where in_review is not null),
           'unregistered', count(*) filter (where not registered),
           'by_owner', (select coalesce(jsonb_object_agg(owner_seat, n), '{}'::jsonb)
                          from (select owner_seat, count(*) n from public.v_handover_open group by owner_seat) o)),
         count(*) filter (where overdue and escalated_at is null and in_review is null)
    into v, v_late
    from public.v_handover_open;
  perform public.fn_seat_duty_result_record('ceo.handover_clock',
    'open hand-overs past their due time that are neither escalated to the CEO nor in a seat''s or the CEO''s own review',
    'at_most', 0, v_late, v);
  return jsonb_build_object('sweep', v_sweep, 'escalated', v_esc, 'now', v);
end $fn$;
revoke execute on function public.fn_handover_clock_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('ceo.handover_clock', 'ceo', interval '1 hour', 'fn_handover_clock_tick',
        'Every open hand-over carries its owner and due time; what can never complete is closed with its reason; a late one is escalated once to the CEO, whose decision closes it.',
        'scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- what the apply did, in one row (counts only)
select jsonb_build_object(
  'directives_withdrawn', (select count(*) from public.ceo_directive where status = 'withdrawn'),
  'seat_audit_checks_corrected', (select count(*) from public.ceo_directive where evidence ? 'check_corrected'),
  'open_hand_overs', (select count(*) from public.v_handover_open),
  'unregistered_open', (select count(*) from public.v_handover_open where not registered)) as applied;
