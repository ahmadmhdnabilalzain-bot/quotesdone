-- A HANDOFF CLOSES ONLY WHEN ITS RECEIVER CITES THE HANDOVER NOTE, OR SAYS WHY NOT.
-- apply-window: off-hours (the trigger takes a brief lock on public.agent_actions)
--
-- Assigned: ceo (founder ledger 1013, the handover-note rule) and customer_support (the adoption routine below is that
-- seat's). 27 Oct 2026.
-- Founder ledger 1013: "seat handover notes: when work passes between seats, a structured note (context, decision,
-- open asks, deadline) is written and read by the receiver."
--
-- ══ MEASURED, 27 Oct 2026 08:50 UTC, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════════════════════════
--   every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql (applied 19 Oct)
--   made the two citing close paths (fn_seat_handoff_act, fn_seat_handoff_complete) put evidence.cites_note on the
--   receiver's answer. It did not make citing a CONDITION of closing. Handoffs closed in the last 30 days whose note
--   has the four fields, grouped by type and path:
--     it.finding 505, ceo.improvement 7, ceo.decision_closed 7, marketing.report 8, report.five_numbers 8,
--     ceo.directive 2, reveal.paid 1                                   -> all cited
--     delivery.request 199 (customer_support 91, sales_engineer 84, it_engineer 12, ceo 11, accountant 1)
--                                                                      -> 0 cited, 0 with a reason
--   All 199 carry evidence {queued, adopted, channel, notification_id}: they are written ALREADY 'done' by
--   fn_customer_support_adopts_untracked_send, the trigger that files a delivery.request for every notification a
--   routine writes directly (every_send_comes_back_to_whoever_asked.sql). No receiver read anything before that
--   send: the note is built in the same INSERT that closes the row, after the routine queued the message.
--   Every routine whose body closes a handoff was listed from pg_proc (the update-to-done and the insert-as-done
--   shapes): fn_seat_handoff_complete (cites), fn_customer_support_adopts_untracked_send (does not). The others
--   that set status 'done' on agent_actions close other kinds (held_question, support_question_handover).
--   No edge function sets a handoff to 'done' (grep of supabase/functions, 27 Oct).
--
-- ══ WHAT THIS CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════
--   1. Trigger a02_handoff_close_cites_its_note (BEFORE INSERT OR UPDATE OF status, evidence; after a01, which
--      builds the note) REFUSES a handoff reaching 'done' unless its evidence either
--        cites the note:      evidence.cites_note.handoff_id = the row's own id, or
--        says why it cannot:  evidence.not_cited.reason is a non-blank sentence (and not_cited.by names the routine).
--      A row that was already 'done' and never cited (the 18,349 closed before this file) may still be updated, so
--      the delivery watch can keep writing its loop verdict onto old requests. A row that WAS cited, or carried a
--      reason, cannot have it removed.
--   2. fn_customer_support_adopts_untracked_send records why it cannot cite: the routine queued the send before any
--      handoff existed. Its body is production's (read back 27 Oct, identical to every_send_comes_back_to_whoever_
--      asked.sql) with only that line added. It is not a citation and does not pretend to be one.
--   3. fn_handoff_citation_gaps(p_since) now splits closures into cited / reason recorded (by reason) / neither.
--      'neither' is the number the trigger holds at 0 from this file's apply onward.
--
-- WHAT IT DOES NOT DO. It does not touch the 18,349 closed rows, the note builder, any reply window, or who closes a
-- handoff (z61_handoff_only_originator_closes still decides that). It does not make the adoption a citation.
--
-- Prevented by: scripts/checks/a_handoff_closes_only_when_its_receiver_cites_the_note.test.mjs (every canonical
-- routine that closes a handoff cites the note or records why not; this trigger exists and refuses).
-- Pending: scripts/sql/pending/a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.txt

set local lock_timeout = '5s';

create or replace function public.trg_handoff_close_cites_its_note()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cited  boolean := (new.evidence->'cites_note'->>'handoff_id') = new.id::text;
  v_reason boolean := nullif(btrim(coalesce(new.evidence->'not_cited'->>'reason', '')), '') is not null;
begin
  if v_cited or v_reason then return new; end if;
  -- A row closed before this rule, with neither, may still be written to (the delivery watch records its loop
  -- verdict on old requests). One that had a citation or a reason may not lose it.
  if tg_op = 'UPDATE' and old.status = 'done'
     and (old.evidence->'cites_note'->>'handoff_id') is distinct from old.id::text
     and nullif(btrim(coalesce(old.evidence->'not_cited'->>'reason', '')), '') is null then
    return new;
  end if;
  raise exception using
    errcode = 'check_violation',
    message = format('handoff %s (%s, %s -> %s) closed without its receiver citing the handover note and without a reason why not - refused (founder ledger 1013)',
                     new.id, coalesce(new.detail->>'type', '?'), coalesce(new.detail->>'from', '?'), new.agent),
    hint = 'Close it through fn_seat_handoff_complete, which cites the note, or set evidence.not_cited = {"reason": "...", "by": "<routine>"}.';
end $fn$;

revoke execute on function public.trg_handoff_close_cites_its_note() from public, anon, authenticated;

drop trigger if exists a02_handoff_close_cites_its_note on public.agent_actions;
create trigger a02_handoff_close_cites_its_note
  before insert or update of status, evidence on public.agent_actions
  for each row
  when (new.kind = 'handoff' and new.status = 'done')
  execute function public.trg_handoff_close_cites_its_note();

-- Production's body (every_send_comes_back_to_whoever_asked.sql, read back 27 Oct 2026) with ONE change: the evidence
-- says why this closure cannot cite a note.
create or replace function public.fn_customer_support_adopts_untracked_send()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_from text; v_id bigint;
begin
  if coalesce(current_setting('app.qd_delivery_tracked', true), '') = 'on' then return null; end if;
  if coalesce(NEW.requested_by, '') = 'platform' then return null; end if;
  v_from := coalesce(nullif(btrim(NEW.requested_by), ''), 'customer_support');
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail, evidence, target_table, target_id, decided_at, decided_by)
    values ('customer_support', 'handoff', 'done', 'low',
            left('delivery.request from ' || v_from || ' about notifications ' || NEW.id, 200),
            jsonb_build_object('type', 'delivery.request', 'from', v_from, 'from_name', v_from, 'to', 'customer_support',
                               'subject_table', 'notifications', 'subject_id', NEW.id::text, 'adopted', true,
                               'msg_type', NEW.type, 'recipient_role', NEW.to_role, 'to_email', NEW.to_email,
                               'supplier_id', NEW.lead_id, 'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id),
            jsonb_build_object('queued', true, 'adopted', true, 'notification_id', NEW.id, 'channel', NEW.channel,
                               -- 1013, 27 Oct 2026: this closure cannot cite a note, and says so.
                               'not_cited', jsonb_build_object(
                                 'reason', v_from || ' queued this send itself before any handoff existed; the request is filed after the fact, so no receiver read a note before acting',
                                 'by', 'fn_customer_support_adopts_untracked_send')),
            'notifications', 'delivery.request:notification:' || NEW.id, now(), 'customer_support')
    returning id into v_id;
    perform public.fn_seat_handoff_event(v_id, 'sent');
    perform public.fn_seat_handoff_event(v_id, 'done');
  exception when others then
    begin
      perform public.fn_support_report_to_ceo('adoption_failed:' || NEW.id, 'serious',
        'A ' || coalesce(NEW.type, 'notice') || ' left the outbox without a loop: adopting it failed',
        jsonb_build_object('notification_id', NEW.id, 'requested_by', NEW.requested_by, 'error', left(sqlerrm, 500)),
        jsonb_build_array('the send itself was kept'),
        'Find why fn_customer_support_adopts_untracked_send failed and track this notification by hand.',
        'notifications#' || NEW.id);
    exception when others then
      raise warning 'fn_customer_support_adopts_untracked_send: notification % not adopted and not reported: %', NEW.id, sqlerrm;
    end;
    return null;
  end;
  -- a seat the register does not list: filed under its own name above, and the gap raised once
  if v_from <> 'customer_support' and not exists (select 1 from public.fn_seat_handoff_types() t
       where t.type = 'delivery.request' and t.from_seat = v_from and t.to_seat = 'customer_support') then
    perform public.fn_support_report_to_ceo('unregistered_sender:' || v_from, 'elevated',
      v_from || ' sends notices but has no delivery conversation with customer_support',
      jsonb_build_object('seat', v_from, 'first_notification_id', NEW.id, 'request_id', v_id),
      jsonb_build_array('the request was filed under ' || v_from || ', not reassigned'),
      'Add delivery.request (' || v_from || ' -> customer_support) and delivery.result (customer_support -> ' || v_from || ') to fn_seat_handoff_types.',
      'agent_actions#' || v_id);
  end if;
  return null;
end $fn$;

-- CREATE OR REPLACE keeps the ACL every_send_comes_back_to_whoever_asked.sql revoked; repeated so the file stands alone.
revoke execute on function public.fn_customer_support_adopts_untracked_send() from public, anon, authenticated;

-- THE MEASUREMENT, split three ways. 'neither' must be 0 for every closure after this file's apply.
create or replace function public.fn_handoff_citation_gaps(p_since timestamptz default now() - interval '1 day')
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with c as (
    select a.id,
           (a.evidence->'cites_note'->>'handoff_id') = a.id::text as cited,
           nullif(btrim(coalesce(a.evidence->'not_cited'->>'reason', '')), '') is not null as reasoned,
           coalesce(a.evidence->'not_cited'->>'by', 'unnamed') as reason_by
      from public.agent_actions a
     where a.kind = 'handoff' and a.status = 'done' and a.decided_at >= p_since
       and a.detail->'summary' ?& array['context','decision','open_asks','deadline'])
  select jsonb_build_object(
    'since', p_since,
    'closed_with_note', count(*),
    'cited', count(*) filter (where cited),
    'reason_recorded', count(*) filter (where not coalesce(cited, false) and reasoned),
    'reason_by', coalesce((select jsonb_object_agg(reason_by, n) from (select reason_by, count(*) n from c
                             where not coalesce(cited, false) and reasoned group by 1) r), '{}'::jsonb),
    'neither', count(*) filter (where not coalesce(cited, false) and not reasoned),
    'uncited_ids', coalesce(jsonb_agg(id order by id) filter (where not coalesce(cited, false) and not reasoned), '[]'::jsonb))
    from c;
$fn$;

revoke execute on function public.fn_handoff_citation_gaps(timestamptz) from public, anon, authenticated;
