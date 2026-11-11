-- notifications_refuse_the_same_message_to_the_same_person_within_the_window.sql
-- Assigned: it_engineer. Founder ruling 1631 (11 Nov 2026, "extremely important"): every agent reads the history before it
-- sends anything, including notifications; "even an automatic notification (e.g. a new code) checks the history, in case a
-- bug is sending it again". Code decides it, not a model.
--
-- MEASURED (notifications, 30 days to 11 Nov 2026, ZZ DEMO and example.invalid excluded): 731 rows, 0 with a dedupe_key
-- (notifications_dedupe_key_uidx exists and nobody fills it). 129 rows repeated an earlier row's recipient, channel,
-- subject and body inside 10 minutes, all supplier_invite_seed, queued twice on 10 Nov 42 s apart: 123 were cancelled by
-- hand and 6 were sent a second time. Outside the seed list: 0 such repeats (and 0 sign-in codes repeated inside 2 min).
--
-- WHAT THIS CHANGES: a BEFORE INSERT trigger, a00_ so it runs before every other notifications trigger (they fire in name
-- order), marks a queued row cancelled when a row with the same channel, type, recipient (email folded, else the phone's
-- last nine digits), subject and body (whitespace folded) was queued, held, sending or sent in the last
-- app_secrets.outbox_duplicate_window_min minutes (default 10). The row is KEPT, cancelled with the earlier id in
-- last_error (ruling 1634: keep everything), and an it_engineer finding is raised. A per-recipient advisory lock makes two
-- concurrent identical inserts serialise. The send-time twin is supabase/functions/_shared/outbox_duplicate_guard.ts
-- (send_outbox, send_whatsapp), which also covers rows queued before this applies.
-- WHAT IT DOES NOT CHANGE: a row whose text differs is never touched (a new code, a new quote); a row inserted already
-- non-queued (held, captured) is left alone; dedupe_key keeps its own unique index.
-- Probe: notifications_refuse_the_same_message_to_the_same_person_within_the_window_probe.sql (pure, rolls back).
-- prevented by: scripts/checks/the_same_message_is_sent_to_a_person_once.test.mjs

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

revoke execute on function public.fn_notifications_the_same_message_is_sent_once() from public, anon, authenticated;

drop trigger if exists a00_notifications_the_same_message_is_sent_once on public.notifications;
create trigger a00_notifications_the_same_message_is_sent_once
  before insert on public.notifications
  for each row execute function public.fn_notifications_the_same_message_is_sent_once();

-- verdict (the behaviour is proved by the pure probe file; this states what was built)
select case
  when not exists (select 1 from pg_trigger where tgname = 'a00_notifications_the_same_message_is_sent_once' and tgrelid = 'public.notifications'::regclass)
    then 'PROBE FAILED: the trigger is not on public.notifications'
  when has_function_privilege('anon', 'public.fn_notifications_the_same_message_is_sent_once()', 'execute')
    then 'PROBE FAILED: anon can execute the trigger function'
  else 'PROBE OK' end as verdict;
