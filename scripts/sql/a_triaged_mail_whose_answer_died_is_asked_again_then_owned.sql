-- A TRIAGED MAIL WHOSE ANSWER DIED IS ASKED AGAIN, THEN OWNED BY A SEAT THAT ACTS.
-- Seat: customer_support with sales_engineer. 2 Nov 2026, founder ledger 1436, 1446.
--
-- MEASURED 1-2 Nov 2026 (production, read-only): inbound 1615 (a known supplier asking to register a subsidiary, to
-- management@) has triaged_at 21:02:51Z, a draft, replied_at null, owner_role null, no notification. Its email_triage run
-- 4602652 (started 21:02:29Z) has finished_at null and counts {}: the worker stopped between marking the row and finishing
-- answer(). A stopped worker runs no catch, so #1741's handoff to the ceo seat never fired, and email_triage selects only
-- triaged_at null, so nothing reads the row again. It is the only such row in 60 days. Why the worker stopped was not
-- measured: the logs did not name it (an edge-function CPU or wall limit is an inference).
--
-- THE ROUTE. A row in that state for 10 minutes has triaged_at cleared, once, so the normal email_triage tick answers it
-- with its normal facts and gate. If it dies again:
--   a known supplier (lead_id): the sales engineer answers it deterministically (mailbox.supplier_reply,
--     fn_sales_engineer_acts_on_supplier_reply, a_supplier_reply_gets_the_action_it_asked_for.sql);
--   anyone else: the ceo seat holds it (review.requested, owner_role ceo), exactly the handoff #1741 files on a failed answer.
-- A row answered, owned, spam or declined is never touched. No model is called and no mail is written from here except by
-- the seat's own handler.
--
-- Prevented by: scripts/checks/nothing_a_person_sends_us_waits.test.mjs and the verdict below.
-- Needs a_supplier_reply_gets_the_action_it_asked_for.sql applied first.

create or replace function public.fn_customer_support_rescues_dead_answers()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m record; v_retried int := 0; v_seat int := 0; v_ceo int := 0; v_err jsonb := '[]'::jsonb; v_from text; v_hid bigint;
begin
  for m in select i.* from public.inbound_messages i
            where i.needs_review and i.replied_at is null and i.owner_role is null and i.triaged_at is not null
              and i.triaged_at < now() - interval '10 minutes' and i.created_at > now() - interval '30 days'
              and coalesce(i.ai_category, '') not in ('no_auto_reply', 'spam', 'routine_queued', 'test_reply')
            order by i.id limit 20 for update of i skip locked loop
    begin
      if coalesce(m.raw->>'answer_retried_at', '') = '' then
        update public.inbound_messages
           set triaged_at = null, ai_category = null,
               raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('answer_retried_at', now())
         where id = m.id;
        v_retried := v_retried + 1;
      elsif m.lead_id is not null then
        v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
        update public.inbound_messages set owner_role = 'sales_engineer' where id = m.id;
        v_hid := public.fn_seat_handoff('marketing', 'sales_engineer', 'mailbox.supplier_reply', 'inbound_messages', m.id::text,
          jsonb_build_object('inbound_message_id', m.id, 'lead_id', m.lead_id, 'from_email', v_from, 'subject', left(coalesce(m.subject, ''), 200),
                             'reply_text', left(btrim(regexp_replace(replace(coalesce(m.body, ''), E'\r', ''), E'(\\n|^)\\s*(>|On [^\\n]{0,200}wrote:|-{2,}\\s*Original Message|_{8,}|From:\\s).*$', '')), 4000),
                             'ask', 'email_triage died twice answering this supplier: answer it in its thread.'));
        v_seat := v_seat + 1;
      else
        v_hid := public.fn_seat_handoff('customer_support', 'ceo', 'review.requested', 'inbound_messages', m.id::text,
          jsonb_build_object('inbound_message_id', m.id, 'from_email', m.from_email, 'to_email', m.to_email, 'subject', left(coalesce(m.subject, ''), 200),
                             'ask', 'customer_support could not write an answer, so the sender has heard nothing. Decide the answer and have it sent in the thread.',
                             'error', 'email_triage stopped twice before it finished the answer'));
        update public.inbound_messages set owner_role = 'ceo' where id = m.id;
        v_ceo := v_ceo + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('inbound', m.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('retried', v_retried, 'to_sales_engineer', v_seat, 'to_ceo', v_ceo, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_customer_support_rescues_dead_answers() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.dead_answer_rescue', 'customer_support', interval '5 minutes', 'fn_customer_support_rescues_dead_answers',
   'A triaged mail whose answer never finished is asked again once, then owned: a known supplier by the sales engineer, anyone else by the CEO seat.',
   'scripts/sql/a_triaged_mail_whose_answer_died_is_asked_again_then_owned.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case
  when not exists (select 1 from public.seat_duty where duty = 'customer_support.dead_answer_rescue') then 'PROBE FAILED: the duty is missing'
  when not exists (select 1 from public.seat_handoff_kind where type = 'mailbox.supplier_reply' and to_seat = 'sales_engineer') then 'PROBE FAILED: the supplier handoff is not registered'
  else 'PROBE OK' end as verdict;
