-- a_notice_is_a_duplicate_only_of_the_same_event.sql
-- Assigned: sales_engineer, 12 Nov 2026 (final audit customer_journey M8 and integration_review finding 4, fix group Q5;
-- founder ledger 1642 "Proceed with fixes"). Follows notifications_refuse_the_same_message_to_the_same_person_within_the_
-- window.sql in MANIFEST and redefines its trigger function; the trigger itself is unchanged.
--
-- Ruling 1631 (11 Nov 2026): the SAME message is never sent to a person twice. It never asked for two different events
-- that read alike to be silenced.
--
-- MEASURED (final audit, run d9a04dbc, 11-12 Nov 2026): every new_quote notice on a request has one subject and body
-- (supplier_api notifyNewQuote), so by this trigger's key a second supplier's "new quote" inside 10 minutes was the same
-- message: 6 of 8 e-mails and 6 of 8 WhatsApp notices repeated one queued 85-141 s earlier and would have been cancelled
-- for a real customer (demo rows are written suppressed, which the trigger leaves alone, so none was). Production, 30 days
-- to 12 Nov 2026: 131 pairs collapse under the text-only key; 129 are the 10 Nov seed list and 2 are WhatsApp holding
-- replies, all the same event (0 pairs differ by inquiry_id or quote_id), so this change cancels nothing it cancelled before.
--
-- WHAT THIS CHANGES: the key also carries the event the row is about: inquiry_id, quote_id and dedupe_key, the three
-- columns that name it (trg_wa_fanout copies inquiry_id and quote_id to the WhatsApp twin). A retried row for the same event
-- (the same quote told again after a 502, the seed list queued twice, the holding line twice) has the same three and is
-- still cancelled. The send-time twin, _shared/outbox_duplicate_guard.ts messageKey, compares the same three: one rule.
-- supplier_api now writes quote_id on new_quote (lib/quote_acceptance.ts notifyNewQuote).
-- CREATE OR REPLACE: the ACL is preserved (EXECUTE was revoked from public, anon and authenticated). No new routine.
-- Probe: a_notice_is_a_duplicate_only_of_the_same_event_probe.sql (pure, rolls back).
-- prevented by: scripts/checks/a_notice_is_a_duplicate_only_of_the_same_event.test.mjs and _shared/outbox_duplicate_guard.test.ts

create or replace function public.fn_notifications_the_same_message_is_sent_once()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_raw text := (select value from public.app_secrets where key = 'outbox_duplicate_window_min');
  v_win int := case when v_raw ~ '^\s*[0-9]{1,4}\s*$' then greatest(1, least(1440, btrim(v_raw)::int)) else 10 end;
  v_email text := nullif(lower(btrim(coalesce(new.to_email, ''))), '');
  v_tail text := nullif(right(regexp_replace(coalesce(new.to_phone, ''), '[^0-9]', '', 'g'), 9), '');
  v_subject text := regexp_replace(btrim(coalesce(new.subject, '')), '\s+', ' ', 'g');
  v_body text := regexp_replace(btrim(coalesce(new.body, '')), '\s+', ' ', 'g');
  v_prev bigint;
begin
  if coalesce(new.status, 'queued') <> 'queued' then return new; end if;
  if v_email is null and v_tail is null then return new; end if;
  perform pg_advisory_xact_lock(hashtext('notifications_sent_once:' || coalesce(v_email, v_tail)));
  select n.id into v_prev
    from public.notifications n
   where n.created_at > now() - make_interval(mins => v_win)
     and n.status in ('queued', 'sending', 'sent', 'held', 'digest')   -- held and digest rows are still on their way
     and coalesce(n.channel, 'email') = coalesce(new.channel, 'email')
     and coalesce(n.type, '') = coalesce(new.type, '')
     and (case when v_email is not null then lower(btrim(n.to_email)) = v_email
               else n.to_email is null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail end)
     and regexp_replace(btrim(coalesce(n.subject, '')), '\s+', ' ', 'g') = v_subject
     and regexp_replace(btrim(coalesce(n.body, '')), '\s+', ' ', 'g') = v_body
     -- the same EVENT (12 Nov 2026): two quotes, two requests or two keyed events that read alike are two messages
     and n.inquiry_id is not distinct from new.inquiry_id
     and n.quote_id is not distinct from new.quote_id
     and coalesce(btrim(n.dedupe_key), '') = coalesce(btrim(new.dedupe_key), '')
   order by n.created_at desc
   limit 1;
  if v_prev is null then return new; end if;
  new.status := 'cancelled';
  new.last_error := left('duplicate: the same message to the same person as notification #' || v_prev || ' inside '
    || v_win || ' min; not sent (insert guard, founder ruling 1631)', 500);
  begin
    perform public.fn_it_engineer_finding_upsert(
      p_issue_key => 'notification_duplicate_refused_at_insert',
      p_title => 'A notification repeated one already queued or sent to the same person, and was cancelled',
      p_where => 'public.fn_notifications_the_same_message_is_sent_once (a00 trigger on notifications)',
      p_blast => 'A caller queued the same message to the same person twice inside the window; the repeat is kept, cancelled, not sent.',
      p_affected => 1,
      p_evidence => jsonb_build_object('earlier_id', v_prev, 'type', new.type, 'channel', coalesce(new.channel, 'email'), 'window_min', v_win));
  exception when others then null;   -- the refusal stands even when the finding cannot be written
  end;
  return new;
end
$fn$;

select case
  when (select prosrc from pg_proc where oid = 'public.fn_notifications_the_same_message_is_sent_once()'::regprocedure) not like '%n.quote_id is not distinct from new.quote_id%'
    then 'PROBE FAILED: the duplicate trigger does not compare the event'
  when not exists (select 1 from pg_trigger where tgname = 'a00_notifications_the_same_message_is_sent_once' and tgrelid = 'public.notifications'::regclass)
    then 'PROBE FAILED: the trigger is not on public.notifications'
  when has_function_privilege('anon', 'public.fn_notifications_the_same_message_is_sent_once()', 'execute')
    then 'PROBE FAILED: anon can execute the trigger function'
  else 'PROBE OK' end as verdict;
