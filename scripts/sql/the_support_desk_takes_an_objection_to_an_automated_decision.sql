-- AN OBJECTION TO AN AUTOMATED DECISION GOES THROUGH SUPPORT, THEN THE CEO, AND IS NEVER AUTO-CLOSED
-- (legal finding 1; PDPL Art. 18; ledger 1152).
--
-- Assigned: ceo; customer_support handles first. 19 Oct 2026.
--
-- WHAT THIS ADDS
--   The classifier output that already exists decides, never word matching: email_triage files an email under
--   ai_category 'automated_decision_objection' (an objection to a refund, dispute or verification decision made
--   automatically), and fn_support_classify_email maps it onto the case through support_signal_category.
--   The category is owned by customer_support. A case in it that is still open after
--   decision_policy.decision_objection_escalate_days (default 2) is handed to the ceo seat
--   (support.decision_objection) by the duty customer_support.decision_objection_escalate.
--   The ceo handler keeps the handoff waiting until the CEO replies; fn_support_case_idle_close no longer closes a case
--   in this category, so no seat closes it by silence.
--   The acknowledgement (management replies within 10 working days) is the triage draft reply for this category.
--
-- CHANGED: fn_support_case_idle_close, from its live definition (canonical: demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql)
--   plus one condition.
--
-- Pending: scripts/sql/pending/the_support_desk_takes_an_objection_to_an_automated_decision.txt.

insert into public.support_category (category, owner_seat, support_fixes, meaning) values
  ('automated_decision_objection', 'customer_support', true,
   'an objection to a decision the platform made automatically (refund, dispute, verification); escalated to the ceo if unresolved')
on conflict (category) do update set owner_seat = excluded.owner_seat, support_fixes = excluded.support_fixes, meaning = excluded.meaning;

insert into public.support_signal_category (source, value, category) values
  ('email_category', 'automated_decision_objection', 'automated_decision_objection')
on conflict (source, value) do update set category = excluded.category;

insert into public.decision_policy (key, value, description) values
  ('decision_objection_escalate_days', '2'::jsonb,
   'Days an objection to an automated decision stays with customer_support before it is handed to the ceo seat.')
on conflict (key) do nothing;

create or replace function public.fn_support_case_idle_close()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days)
     and category is distinct from 'automated_decision_objection'   -- legal finding 1: closed only by a reply
     and not public.fn_party_is_demo(party_kind, party_id);
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $function$;
revoke execute on function public.fn_support_case_idle_close() from public, anon, authenticated;

create or replace function public.fn_customer_support_escalates_decision_objections()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_days numeric := coalesce((select (value #>> '{}')::numeric from public.decision_policy
                                     where key = 'decision_objection_escalate_days'), 2);
        c record; v_ids bigint[] := '{}';
begin
  for c in select case_id, case_ref, party_kind, party_id, subject, opened_at from public.support_case
            where category = 'automated_decision_objection' and state <> 'closed'
              and opened_at < now() - make_interval(secs => v_days * 86400)
              and not public.fn_party_is_demo(party_kind, party_id)
  loop
    v_ids := v_ids || public.fn_seat_handoff('customer_support', 'ceo', 'support.decision_objection', 'support_case',
      c.case_id::text, jsonb_build_object('case_ref', c.case_ref, 'party_kind', c.party_kind, 'subject', c.subject,
        'opened_at', c.opened_at, 'reply_due', 'within 10 working days of the objection'));
  end loop;
  return jsonb_build_object('escalated', coalesce(array_length(v_ids, 1), 0), 'handoffs', to_jsonb(v_ids));
end $fn$;
revoke execute on function public.fn_customer_support_escalates_decision_objections() from public, anon, authenticated;

create or replace function public.fn_ceo_takes_decision_objection(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'case_ref', a.detail->>'case_ref',
    'waiting', 'the CEO reviews the automated decision and replies to the requester; closed only by that reply');
end $fn$;
revoke execute on function public.fn_ceo_takes_decision_objection(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('support.decision_objection', 'customer_support', 'ceo',
        'An objection to an automated decision (refund, dispute, verification) that customer_support did not resolve. The CEO reviews the decision and replies within 10 working days.',
        'fn_ceo_takes_decision_objection', interval '14 days', false,
        'scripts/sql/the_support_desk_takes_an_objection_to_an_automated_decision.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, owner_file = excluded.owner_file;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.decision_objection_escalate', 'customer_support', interval '6 hours', 'fn_customer_support_escalates_decision_objections',
   'An objection to an automated decision still open after decision_objection_escalate_days is handed to the ceo seat.',
   'scripts/sql/the_support_desk_takes_an_objection_to_an_automated_decision.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- PROBE: reads only; no row is written.
select case
  when not exists (select 1 from public.support_signal_category where source = 'email_category' and value = 'automated_decision_objection'
                    and category = 'automated_decision_objection') then 'PROBE FAILED: classifier output not mapped'
  when position('automated_decision_objection' in pg_get_functiondef('public.fn_support_case_idle_close()'::regprocedure)) = 0
    then 'PROBE FAILED: idle close can still close an objection'
  when not exists (select 1 from public.seat_handoff_kind where type = 'support.decision_objection' and from_seat = 'customer_support'
                    and to_seat = 'ceo' and not originator_closes) then 'PROBE FAILED: handoff kind not registered'
  when not public.fn_seat_duty_routine_exists('fn_customer_support_escalates_decision_objections') then 'PROBE FAILED: duty routine missing'
  else 'PROBE OK' end as verdict;
