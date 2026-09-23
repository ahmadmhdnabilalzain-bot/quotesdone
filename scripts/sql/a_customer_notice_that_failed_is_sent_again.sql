-- A CUSTOMER NOTICE THAT FAILED IS SENT AGAIN — "WE'RE ON IT" IS OWED UNTIL IT ARRIVES.
-- Seat: customer_support. 23 Sep 2026, the seat-duties build (founder_instruction 898).
--
-- WHAT WAS MEASURED: fn_reason_held_escalate (a_held_question_never_expires_it_is_escalated_at_48_hours.sql) stamps
-- escalated_at and RETURNS the rows; resilience_ping then sends each WhatsApp customer the holding notice once
-- (_shared/reasoned_delivery.ts holdingNotice: "Your question is now with our team and a person is handling it").
-- The send's outcome was put in the step's log and nowhere else. A failed send (Twilio refused, the template queue
-- refused) was never retried: escalated_at was already set, so the row never came back. The customer who was owed
-- "we're on it" heard nothing, and nothing in the database said so. (0 escalated rows on production today.)
--
-- WHAT CHANGES
--   * reasoning_held_question gains notice_attempts / notice_last_at / notice_delivered_at / notice_detail.
--   * fn_reason_held_notice_due(p_limit): escalated rows that have a customer phone and no delivered notice, not
--     tried in the last 30 minutes, fewer than 8 attempts. resilience_ping sends these (the just-escalated ones
--     included) instead of the escalate call's return value, so a failure is picked up again on a later tick.
--   * fn_reason_held_notice_record(p_id, p_delivery): records each attempt; delivered stamps notice_delivered_at.
--   * the check: 8 failed attempts is a customer who was never told — an it_engineer finding
--     'held_notice:undelivered', owned by customer_support, closed when none remain.
-- WHAT IT DOES NOT CHANGE: the wording of the notice, the 48-hour rule, or fn_reason_held_escalate.

alter table public.reasoning_held_question add column if not exists notice_attempts integer not null default 0;
alter table public.reasoning_held_question add column if not exists notice_last_at timestamptz;
alter table public.reasoning_held_question add column if not exists notice_delivered_at timestamptz;
alter table public.reasoning_held_question add column if not exists notice_detail jsonb;

create or replace function public.fn_reason_held_notice_due(p_limit integer default 20)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; v_dead int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'seat', h.seat, 'surface', h.surface, 'question', left(h.question, 500),
                                               'subject', h.subject, 'attempts', h.notice_attempts) order by h.escalated_at), '[]'::jsonb)
    into v
    from (select * from public.reasoning_held_question
           where escalated_at is not null and notice_delivered_at is null
             and coalesce(subject->>'phone', '') <> '' and notice_attempts < 8
             and (notice_last_at is null or notice_last_at < now() - interval '30 minutes')
           order by escalated_at
           limit greatest(1, least(coalesce(p_limit, 20), 100))) h;

  select count(*) into v_dead from public.reasoning_held_question
   where escalated_at is not null and notice_delivered_at is null and coalesce(subject->>'phone', '') <> '' and notice_attempts >= 8;
  if v_dead > 0 then
    perform public.fn_it_engineer_finding_upsert('held_notice:undelivered',
      v_dead || ' WhatsApp customer(s) were never told their held question is with a person (8 failed attempts each)',
      'public.reasoning_held_question / resilience_ping reasoning_escalate', 'customer_facing', v_dead,
      jsonb_build_object('owner_seat', 'customer_support'), '{}'::text[], array['what the channel refused (notice_detail)'], 'customer_support');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'every owed holding notice was delivered'
     where issue_key = 'held_notice:undelivered' and closed_at is null;
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_reason_held_notice_due(integer) from public, anon, authenticated;
grant execute on function public.fn_reason_held_notice_due(integer) to service_role;

create or replace function public.fn_reason_held_notice_record(p_id bigint, p_delivery jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_ok boolean := coalesce((p_delivery->>'delivered')::boolean, false);
begin
  update public.reasoning_held_question
     set notice_attempts = notice_attempts + 1, notice_last_at = now(), notice_detail = p_delivery,
         notice_delivered_at = case when v_ok then now() else notice_delivered_at end
   where id = p_id and notice_delivered_at is null;
  return jsonb_build_object('id', p_id, 'delivered', v_ok, 'recorded', found);
end $fn$;
revoke execute on function public.fn_reason_held_notice_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_held_notice_record(bigint, jsonb) to service_role;
