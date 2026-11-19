-- A MAIL HELD ONLY BECAUSE THE MODEL GATEWAY FAILED IS READ AGAIN, ONCE.
-- Seat: customer_support. Agent: customer_support held-mail retrier (19 Nov 2026; ledger 1436: no supplier goes unanswered).
--
-- WHY (production SELECTs, 19 Nov 2026):
--   * inbound_messages 2169 (support@homeboxstores.com, lead 853, a person replying to our supplier invitation, 12 Nov 06:30Z) had
--     no answer after 7 days: needs_review true, owner customer_support, replied_at null, a draft that was never sent.
--   * 12 Nov: two email_triage runs read it 20 s apart (agent_runs 4990816 and 4990827). The faster read it answerable and claimed
--     it; the slower one's reading ('unclear', ai_cost_log 104000 at 06:31:20Z) was UPSERTED over it by fn_mailbox_reply_decide,
--     so the faster run's fn_inbox_send was refused ("read as unclear") and the mail went to the CEO seat as review.requested
--     (agent_actions 393159), which the CEO model dismissed on 18 Nov for want of "the decision to review". Nothing was sent.
--   * 16 Nov 05:37Z: the support drive (fn_customer_support_unanswered_inbound_tick) asked its one second reading. That reading got
--     no model answer: ai_cost_log 106269/106270, ok=false after 48 s, 502 gateway_deadline. supplier_mailbox_reading.ts recorded it
--     as the FINAL reading (mailbox_reply_decision: reading 'unclear', method 'no_model'); the drive asks only once
--     (reread_requested_at), so nothing read it again. The triaged_at of 16 Nov on 2168-2172 is that re-stamp, not a 95 h lag: the
--     first triage of each ran on 12 Nov within 0-150 s of receipt (agent_runs 4990759-4990820).
--   * mailbox_reply_decision where method = 'no_model' and reading = 'unclear': 1 row on production (2169).
--   From the deploy of email_triage in this PR a provider failure is no longer a reading (email_triage/model_retry.ts: read again
--   with backoff, held only when the attempts are spent, the drive's 24 h SLA then tells the CEO), and a reading that finishes
--   after another run took the mail is not recorded. This file puts back, ONCE, what was held before that.
--
-- WHAT: fn_inbound_mail_held_by_model_error_requeue(p_fixture) puts each unanswered mail whose only reading was a provider failure
--   (no_model + unclear + a 5xx / deadline / timeout / network reason; never a deliberate hold: an open circuit, the founder's or the
--   model hold, no paid AI, a credential refusal, an empty completion) back in front of email_triage exactly as the drive's second
--   reading does: triaged_at, ai_category, owner_role null, needs_review true. raw.model_error_requeued_at marks it, so a second call
--   (or a second apply) re-queues nothing. It sends NOTHING: email_triage's normal pipeline reads it (a second reading, which for a
--   known sender must decide answer or close, supplier_mailbox_reading.ts SECOND_READING) and answers or closes it with its reason.
--   Within 30 days of receipt only. p_fixture true touches ZZ DEMO rows only (@example.invalid and a 'ZZ DEMO' subject); false never does.
-- prevented by: a_mail_held_by_a_model_error_is_read_again_probe.sql (LOCAL), email_triage/model_retry.test.ts
-- APPLY: node scripts/apply_sql.mjs scripts/sql/a_mail_held_by_a_model_error_is_read_again.sql --apply --ddl
--   AFTER an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql and the email_triage deploy from the same PR (so the re-read gets the retry), then delete the pending note and append this
--   file as the LAST line of scripts/sql/MANIFEST.txt. Expected result row: {"requeued": 1, "ids": [2169]}.
-- ROLLBACK: drop function public.fn_inbound_mail_held_by_model_error_requeue(boolean); a re-queued mail is read by the normal
--   pipeline within one tick and needs no undo (the row's raw keeps model_error_requeued_at as the record).
-- LOCKS: row locks on the matched inbound_messages rows only (1 on production).
set local lock_timeout = '1500ms';

create or replace function public.fn_inbound_mail_held_by_model_error_requeue(p_fixture boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ids bigint[];
begin
  with held as (
    select m.id, d.why
      from public.inbound_messages m
      join public.mailbox_reply_decision d on d.inbound_message_id = m.id
     where d.method = 'no_model' and d.reading = 'unclear'
       and m.replied_at is null and m.triaged_at is not null
       and m.created_at > now() - interval '30 days'
       and not (coalesce(m.raw, '{}'::jsonb) ? 'model_error_requeued_at')
       -- the provider failed (the strings llm.ts and model_retry.ts write) ...
       and coalesce(d.why, '') ~* '(gateway_http_5[0-9][0-9]|deadline|timed? ?out|timeout|client_error|fetch_failed|the model gateway failed)'
       -- ... and it was not a deliberate hold, a refusal or an answer
       and coalesce(d.why, '') !~* '(circuit_open|open-circuit|founder_hold|model_hold|no_paid_ai|credential|forbidden|empty_completion)'
       and ((coalesce(m.from_email, '') ilike '%@example.invalid' and coalesce(m.subject, '') like 'ZZ DEMO%') = p_fixture)
     for update of m
  ), put_back as (
    update public.inbound_messages x
       set triaged_at = null, ai_category = null, owner_role = null, needs_review = true,
           raw = coalesce(x.raw, '{}'::jsonb) || jsonb_build_object('model_error_requeued_at', now(),
                 'model_error_requeue_why', left(h.why, 300), 'model_error_requeued_by', 'a_mail_held_by_a_model_error_is_read_again.sql')
      from held h
     where x.id = h.id and x.replied_at is null
    returning x.id
  )
  select coalesce(array_agg(id order by id), '{}') into v_ids from put_back;
  return jsonb_build_object('requeued', coalesce(array_length(v_ids, 1), 0), 'ids', to_jsonb(v_ids), 'fixture', p_fixture);
end $fn$;
revoke execute on function public.fn_inbound_mail_held_by_model_error_requeue(boolean) from public, anon, authenticated;
comment on function public.fn_inbound_mail_held_by_model_error_requeue(boolean) is
  'Puts an unanswered mail whose only reading was a model-gateway failure back in front of email_triage, once (raw.model_error_requeued_at). Sends nothing. a_mail_held_by_a_model_error_is_read_again.sql, 19 Nov 2026.';

-- the one re-queue, real rows only
select public.fn_inbound_mail_held_by_model_error_requeue(false) as requeued;
