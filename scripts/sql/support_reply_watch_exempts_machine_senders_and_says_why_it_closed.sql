-- THE FIRST-REPLY WATCH EXEMPTS MACHINE SENDERS, AND ITS CLOSE NOTE SAYS WHY IT CLOSED (27 Oct 2026).
-- Assigned: customer_support — the first-reply watch over inbound email, WhatsApp and chat.
--
-- Built on the LIVE body of fn_support_reply_watch_tick() (pg_get_functiondef, read 27 Oct 2026 20:08 UTC),
-- which was identical to its canonical file, detectors_stop_escalating_what_is_not_a_fault.sql. Two
-- defects, both measured on production:
--
-- 1. THE MACHINE-SENDER RULE WAS ANCHORED AT THE START OF THE LOCAL PART. inbound_messages 159 and 160,
--    from security-noreply@ (LinkedIn), 23 Sep 2026 17:23 and 17:26 UTC, replied_at NULL, were counted as
--    a customer waiting for a first reply for the whole 30-day window (support_reply_sla:email, opened
--    24 Sep 17:30, affected 2). The rule only exempted a local part BEGINNING with no-reply / do-not-reply.
--    Now the machine word is exempt anywhere in the local part, as a whole token: at the start (the old
--    rule, unchanged), or after a hyphen or underscore and followed by a hyphen, underscore, plus or the
--    end. The words: noreply, donotreply, mailerdaemon, each with an optional hyphen or underscore
--    between its parts. A DOT does not bound the word, because a dot is how a person's name is written:
--    alice.noreply.fan@ stays a counted customer (guarded since 19 Oct, check 6b). A plus does not open
--    it either, because alice+tag@ is a person's own sub-address. Under-exempting is the safe direction:
--    an extra finding is a record, a missed customer is a customer nobody answers.
--    Measured over all 44 inbound_messages (8 distinct senders): security-noreply is the only local part
--    the new rule exempts that the old rule did not, and no other sender matches either rule.
--
-- 2. THE CLOSE NOTE CLAIMED REPLIES THAT NEVER HAPPENED. support_reply_sla:email closed 23 Oct 17:46 UTC
--    with "every email message older than 24 h has a first reply". Neither 159 nor 160 was ever replied
--    to: they had passed the 30-day window (23 Sep 17:23 + 30 d) and the count fell to zero. The finding
--    is closed by the channel being clear; the NOTE now says what cleared it, per message it last listed:
--    answered, aged out of the window unanswered, no longer counted (now exempt or excluded), or gone.
--    It claims "every one got a first reply" only when every message it listed was answered AND it listed
--    every message that was waiting. The founder reads this note: fn_it_engineer_alert_tick sends it as
--    the RESOLVED line when he was alerted about the finding.
--
-- New routine fn_support_reply_watch_close_note: CREATE grants EXECUTE to PUBLIC, so it is revoked below.
-- fn_support_reply_watch_tick is CREATE OR REPLACE, which keeps its ACL (service_role only, read
-- 27 Oct 2026), so it is not revoked again.
--
-- Probe: support_reply_watch_exempts_machine_senders_and_says_why_it_closed_probe.sql (writes only inside a
-- block it rolls back). Prevented by: scripts/checks/detectors_stop_escalating_what_is_not_a_fault.test.mjs
-- 6c-6e, which replay this routine's machine-sender pattern over named addresses and read the close note.

create or replace function public.fn_support_reply_watch_close_note(p_channel text, p_evidence jsonb, p_sla numeric)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_ids bigint[] := array(select x::bigint from jsonb_array_elements_text(coalesce(p_evidence->'ids', '[]'::jsonb)) x);
  v_listed int; v_waiting int; v_found int := 0;
  v_replied int := 0; v_aged int := 0; v_other int := 0; v_gone int;
  v_window timestamptz := now() - interval '30 days';
  v_parts text[] := '{}'; v_head text; v_tail text := '';
begin
  v_listed := coalesce(cardinality(v_ids), 0);
  v_waiting := greatest(coalesce((p_evidence->>'waiting')::int, v_listed), v_listed);

  if p_channel = 'email' then
    select count(*), count(*) filter (where m.replied_at is not null),
           count(*) filter (where m.replied_at is null and m.created_at <= v_window)
      into v_found, v_replied, v_aged
      from public.inbound_messages m where m.id = any (v_ids);
  elsif p_channel = 'whatsapp' then
    select count(*), count(*) filter (where w.reply is not null and coalesce(w.sent, false)),
           count(*) filter (where not (w.reply is not null and coalesce(w.sent, false)) and w.created_at <= v_window)
      into v_found, v_replied, v_aged
      from public.wa_messages w where w.id = any (v_ids);
  else
    select count(*), count(*) filter (where coalesce(g.answered, false) or coalesce(t.status, '') = 'done'),
           count(*) filter (where not (coalesce(g.answered, false) or coalesce(t.status, '') = 'done') and g.created_at <= v_window)
      into v_found, v_replied, v_aged
      from public.assistant_logs g left join public.org_tasks t on t.id = g.gap_task_id
     where g.id = any (v_ids);
  end if;
  v_other := v_found - v_replied - v_aged;     -- unanswered, inside the window, and no longer counted by the watch
  v_gone := v_listed - v_found;

  if v_replied > 0 then v_parts := v_parts || (v_replied || ' got a first reply'); end if;
  if v_aged > 0 then v_parts := v_parts || (v_aged || ' aged out of the 30-day window with no reply'); end if;
  if v_other > 0 then v_parts := v_parts || (v_other || ' are no longer counted (now exempt or excluded) and have no reply'); end if;
  if v_gone > 0 then v_parts := v_parts || (v_gone || ' are no longer on record'); end if;

  if v_listed = 0 then
    v_head := 'cleared: the earlier list of waiting messages was not recorded, so whether they were answered is not known';
  elsif v_replied = v_listed and v_waiting = v_listed then
    v_head := 'cleared by replies: every one of the ' || v_listed || ' waiting message(s) got a first reply';
  elsif v_replied = 0 and v_aged > 0 and v_aged = v_listed then
    v_head := 'cleared because the ' || v_listed || ' waiting message(s) aged out of the 30-day window, NOT because they were answered: none got a first reply';
  elsif v_replied = 0 then
    v_head := 'cleared without a reply: of the ' || v_listed || ' message(s) listed, ' || array_to_string(v_parts, ', ');
  else
    v_head := 'cleared: of the ' || v_listed || ' message(s) listed, ' || array_to_string(v_parts, ', ');
  end if;
  if v_waiting > v_listed then
    v_tail := '. The other ' || (v_waiting - v_listed) || ' that were waiting were not listed, so how they cleared is not recorded';
  end if;

  return 'no ' || p_channel || ' message older than ' || p_sla || ' h is waiting inside the 30-day window; '
      || v_head || v_tail;
end
$function$;

revoke execute on function public.fn_support_reply_watch_close_note(text, jsonb, numeric) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_support_reply_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_cut timestamptz; v_founder text[]; c text; v_n int; v_oldest timestamptz; v_ids jsonb; v_median numeric;
  v_out jsonb := '{}'::jsonb;
begin
  v_cut := now() - make_interval(secs => (v_sla * 3600)::double precision);
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  foreach c in array array['email', 'whatsapp', 'chat'] loop
    if c = 'email' then
      select count(*), min(m.created_at), coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.inbound_messages m
       where m.created_at > now() - interval '30 days' and m.created_at < v_cut and m.replied_at is null
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
         -- 19 Oct 2026: a machine sender cannot be answered, and calendar+ is the founder's own approval inbox.
         -- 27 Oct 2026: the machine word is matched anywhere in the sender's LOCAL PART as a whole token (start,
         -- or bounded by hyphen/underscore), not only at its start: security-noreply@ waited 30 days as a customer.
         -- A dot does not bound it, so a person whose name merely contains the word stays counted.
         and coalesce(m.to_email, '') !~* '^calendar\+'
         and coalesce(substring(m.from_email from '([^<>\s"]+)@'), '') !~* '^(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)|[-_](no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)([-_+]|$)'
         and not public.fn_is_demo_email(m.from_email);
      select percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60) into v_median
        from public.inbound_messages m
       where m.replied_at is not null and m.created_at > now() - interval '7 days'
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant';
    elsif c = 'whatsapp' then
      select count(*), min(w.created_at), coalesce(jsonb_agg(w.id order by w.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.wa_messages w
       where w.created_at > now() - interval '30 days' and w.created_at < v_cut
         and coalesce(btrim(w.inbound), '') <> '' and (w.reply is null or not coalesce(w.sent, false))
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder));
      v_median := null;   -- the WhatsApp reply is written in the same row as the inbound: minutes are not recorded
    else
      select count(*), min(g.created_at), coalesce(jsonb_agg(g.id order by g.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.assistant_logs g
        left join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and g.created_at > now() - interval '30 days' and g.created_at < v_cut
         and coalesce(t.status, 'open') not in ('done', 'cancelled');
      select percentile_cont(0.5) within group (order by extract(epoch from t.updated_at - g.created_at) / 60) into v_median
        from public.assistant_logs g join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and t.status = 'done' and t.updated_at > g.created_at and g.created_at > now() - interval '7 days';
    end if;

    if v_n > 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:' || c,
        v_n || ' ' || c || ' message(s) have waited more than ' || v_sla || ' h for a first reply (oldest '
          || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> ' || c, 'customer_facing', v_n,
        jsonb_build_object('channel', c, 'sla_hours', v_sla, 'waiting', v_n, 'oldest', v_oldest,
                           'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                           'median_first_reply_minutes_7d', round(v_median), 'owner_seat', 'customer_support', 'duty', 'reply_time'),
        '{}'::text[], array['whether the customer was answered on another channel'], 'customer_support');
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:' || c and closed_at is null) then
      -- 27 Oct 2026: the note says what cleared each message it last listed (answered, aged out, no longer
      -- counted, gone), never a reply that did not happen.
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        public.fn_support_reply_watch_close_note(c,
          (select f.evidence from public.it_engineer_finding f where f.issue_key = 'support_reply_sla:' || c and f.closed_at is null),
          v_sla));
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end
$function$;
