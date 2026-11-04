-- A HOLDING NOTICE IS CLAIMED BY ONE SENDER. Seat: it_engineer, 2 Nov 2026 (review of #1786).
-- fn_reason_held_notice_due only READ the owed notices, so the two senders - sales_engineer reask_turns
-- (_shared/reask.ts) and resilience_ping's reasoning_escalate step - could both pick the same row and both send
-- the customer a WhatsApp holding notice. It now CLAIMS what it returns: notice_last_at = now() under
-- FOR UPDATE SKIP LOCKED, so a second caller, concurrent or a moment later, gets other rows. The existing
-- 30-minute window is the lease: a sender that crashed before fn_reason_held_notice_record sees its row
-- offered again after 30 minutes. Attempts are still counted by the record only (the 8-attempt cap is unchanged).
-- CREATE OR REPLACE keeps the ACL (service_role only, measured 2 Nov); the probe is
-- a_holding_notice_is_claimed_by_one_sender_probe.sql.
create or replace function public.fn_reason_held_notice_due(p_limit integer default 20)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_dead int;
begin
  with due as (
    select h.id from public.reasoning_held_question h
     where h.escalated_at is not null and h.notice_delivered_at is null
       and coalesce(h.subject->>'phone', '') <> '' and h.notice_attempts < 8
       and (h.notice_last_at is null or h.notice_last_at < now() - interval '30 minutes')
     order by h.escalated_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set notice_last_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.question, h.subject, h.notice_attempts, h.escalated_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'seat', c.seat, 'surface', c.surface, 'question', left(c.question, 500),
                                               'subject', c.subject, 'attempts', c.notice_attempts) order by c.escalated_at), '[]'::jsonb)
    into v from claimed c;

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
end $function$;
