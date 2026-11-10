-- A PARKED MODEL QUESTION HAS AN OWNER AND A DEADLINE, AND IT CLOSES WHEN WHAT IT WAS ABOUT IS SETTLED.
-- Seat: it_engineer (the queue of held questions is the platform's; each question stays its own seat's). 10 Nov 2026,
-- founder ruling 1574. fn_held_questions_settle is one of the IT engineer's safe-fix playbooks
-- (the_it_engineer_runs_the_safe_fix_playbooks_itself.sql); the overdue ones are the session's daily list
-- (the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql).
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   822 agent_actions of kind held_question are pending ("A question held after N failed reasonings on <surface> needs
--   you"), oldest 25 Sep, none with an owner field or a deadline. What the reasoning_held_question row behind each says:
--   expired 390, failed 352, applied 48, reasoned 32. So 438 of them are about a question that was already applied or
--   has expired; nothing ever closes the "needs you" row. By surface the failed ones are it_engineer.postmortem 190,
--   sales_engineer.knowledge_refresh 23, ceo.knowledge_refresh 18, marketing.knowledge_refresh 17, inquiry_intake.exact_spec 16,
--   marketing_social.comment_classify 13, the ceo_revision surfaces 26, and others. Three are wa_inbound.unwritten_reply:
--   a person's WhatsApp turn.
--
-- WHAT THIS FILE DOES:
--   1. fn_held_questions_settle(p_limit) first stamps every pending held_question that has none with detail.owner_seat
--      (its seat) and detail.due_at (created + seat clock policy held_question_days, default 7), so the 822 rows and every
--      later one carry an owner and their true deadline (most of the 822 have passed theirs). No trigger on agent_actions:
--      no DDL takes a lock on that table. Then it closes a pending held_question on the record only:
--        applied            -> done       ("answered and applied on <date>")
--        superseded         -> dismissed  (a later question of the same seat, surface and subject exists)
--        row gone           -> dismissed  (the question no longer exists)
--        expired            -> dismissed  (it expired unanswered; nothing will apply it), EXCEPT a person-facing surface
--      and marks the rest that are past their deadline (detail.overdue_at). A PERSON-FACING question (a WhatsApp turn,
--      a supplier or portal reply, the request chat, a comment that needs a person) is never dismissed by age or
--      expiry: it stays open and overdue, so the session's daily list carries it.
--   Nothing is sent and no model is called. CREATE of each routine is followed by its revoke.
--
-- Prevented by: scripts/checks/a_parked_model_question_has_an_owner_and_a_deadline.test.mjs (static rules plus a
-- rolled-back replay over the 822 rows: what closes, what stays, and that no person-facing question is dismissed).
--   node scripts/apply_sql.mjs scripts/sql/a_parked_model_question_has_an_owner_and_a_deadline.sql --apply --ddl --seat it_engineer

-- a question a person is waiting on: its answer goes to a customer, a supplier or a visitor
create or replace function public.fn_held_question_is_person_facing(p_surface text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_surface, '') in ('wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten', 'sales_engineer.portal_unwritten',
                                     'inquiry_intake.unwritten_reply')
      or coalesce(p_surface, '') like '%needs_a_person%'
$fn$;
revoke execute on function public.fn_held_question_is_person_facing(text) from public, anon, authenticated;

create or replace function public.fn_held_questions_settle(p_limit integer default 1000)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a record; v_status text; v_verdict text; v_later bigint; n_done int := 0; n_dismissed int := 0; n_overdue int := 0; n_open int := 0;
  v_by jsonb := '{}'::jsonb;
begin
  -- EVERY PARKED QUESTION HAS AN OWNER AND A DEADLINE: its seat, and created + the seat clock policy held_question_days
  -- (default 7). Stamped here rather than by a trigger on agent_actions, so no DDL ever takes a lock on that table.
  update public.agent_actions x
     set detail = coalesce(x.detail, '{}'::jsonb) || jsonb_build_object('owner_seat', x.agent,
                    'due_at', (x.created_at + make_interval(days => greatest(1, public.fn_seat_clock_policy('held_question_days', 7)::int)))::text)
   where x.id in (select y.id from public.agent_actions y
                   where y.kind = 'held_question' and y.status = 'pending' and not (coalesce(y.detail, '{}'::jsonb) ? 'due_at')
                   for update skip locked);
  for a in select x.*, r.id rid, r.status rstatus, r.surface rsurface, r.subject rsubject, r.applied_at, r.expires_at, r.created_at rcreated
             from public.agent_actions x left join public.reasoning_held_question r on r.id = (x.detail->>'held_id')::bigint
            where x.kind = 'held_question' and x.status = 'pending'
            order by x.id limit greatest(1, least(coalesce(p_limit, 1000), 5000))
            for update of x skip locked loop
    v_status := null; v_verdict := null; v_later := null;
    if a.rid is null then
      v_status := 'dismissed'; v_verdict := 'the held question no longer exists (reasoning_held_question ' || coalesce(a.detail->>'held_id', '?') || ')';
    elsif a.rstatus = 'applied' then
      v_status := 'done'; v_verdict := 'answered and applied' || coalesce(' on ' || to_char(a.applied_at, 'YYYY-MM-DD'), '');
    else
      select r2.id into v_later from public.reasoning_held_question r2
       where r2.seat = a.agent and r2.surface = a.rsurface and r2.subject is not distinct from a.rsubject
         and r2.created_at > a.rcreated and r2.id <> a.rid
       order by r2.created_at desc limit 1;
      if v_later is not null and not public.fn_held_question_is_person_facing(a.rsurface) then
        v_status := 'dismissed'; v_verdict := 'superseded: the same question was asked again as held question ' || v_later;
      elsif a.rstatus = 'expired' and not public.fn_held_question_is_person_facing(a.rsurface) then
        v_status := 'dismissed'; v_verdict := 'the question expired unanswered' || coalesce(' on ' || to_char(a.expires_at, 'YYYY-MM-DD'), '') || '; nothing will apply it';
      end if;
    end if;
    if v_status is not null then
      update public.agent_actions
         set status = v_status, decided_at = now(), decided_by = 'it_engineer:fn_held_questions_settle',
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('verdict', v_verdict, 'held_status', a.rstatus, 'settled_at', now())
       where id = a.id;
      if v_status = 'done' then n_done := n_done + 1; else n_dismissed := n_dismissed + 1; end if;
      v_by := jsonb_set(v_by, array[coalesce(a.rstatus, 'gone')], to_jsonb(coalesce((v_by->>coalesce(a.rstatus, 'gone'))::int, 0) + 1));
    elsif coalesce(a.detail->>'due_at', '') <> '' and (a.detail->>'due_at')::timestamptz < now() then
      if not (a.detail ? 'overdue_at') then
        update public.agent_actions set detail = detail || jsonb_build_object('overdue_at', now()) where id = a.id;
      end if;
      n_overdue := n_overdue + 1;
    else
      n_open := n_open + 1;
    end if;
  end loop;
  return jsonb_build_object('done', n_done, 'dismissed', n_dismissed, 'settled_by_held_status', v_by, 'overdue', n_overdue, 'open_in_time', n_open);
end $fn$;
revoke execute on function public.fn_held_questions_settle(integer) from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_held_questions_settle(integer)'::regprocedure, 'public.fn_held_question_is_person_facing(text)'::regprocedure)
       and (not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  ) z) y;
