-- THE CEO ANSWERS A DELIVERY REPORT WHOSE SUBJECT IS NOT A NOTIFICATION ID.
--
-- Assigned: ceo. 28 Sep 2026.
--
-- ══ MEASURED, production htdblwldjkcgjvmqkbeh, 28 Sep 2026 ══════════════════════════════════════════════
--   The CI gate "every alarm is quiet on a healthy day" failed on every PR (e.g. #983, run ending 14:54 UTC):
--   fn_ceo_report_answer_sweep raised ceo:report_answer_failed, "1 report(s) to the CEO raised in their decider".
--   The sweep reads support_ceo_report where status = 'sent' as PRESENT state, so the replay saw today's queue.
--   Calling fn_ceo_decide_report on each of the 4 'sent' reports inside a rolled-back block:
--     5309, 5322, 6331  -> {ok:false, reason:'undecided: no confirmed delivery on any channel'}  (by design)
--     6330              -> ERROR invalid input syntax for type bigint:
--                          "wa_templates_ready:management@quotesdone.com:4f389430-..."
--                          at fn_ceo_delivery_undelivered_decide line 16
--   Report 6330 (delivery_undelivered:102416, from it_engineer, 28 Sep 14:46 UTC) is about a
--   wa_templates_ready email to the admin that was never queued ("nothing was queued"). Its request's
--   detail.subject_id is a TEXT dedupe key, not a notifications.id, and the decider cast it to bigint
--   unguarded. So the sweep was right: a real report stayed unanswered, because its decider crashed.
--
-- ══ WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════
--   fn_ceo_delivery_undelivered_decide casts subject_id only when it is all digits. A report whose subject
--   names no notification now returns {ok:false, reason:'the report names no notification'}, and
--   fn_ceo_decide_report hands it to fn_ceo_report_default_decide, which ACCEPTS it with a receipt naming
--   the owning seat (it_engineer) and reviews it again in 24 hours. Body otherwise identical to the mirror.
--
--   prevented by: scripts/checks/no_routine_casts_a_text_subject_id_to_bigint_unguarded.test.mjs

CREATE OR REPLACE FUNCTION public.fn_ceo_delivery_undelivered_decide(p_report_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.support_ceo_report; n public.notifications; twin public.notifications; v_receipt text;
  v_req public.agent_actions; v_subject bigint;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  select * into n from public.notifications
   where id = coalesce((r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                       (r.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
  if n.id is null then
    -- The report may name the notification only through its request (18 Sep reports did: the
    -- recheck found "nothing was queued"). A subject that no longer exists cannot be re-checked.
    select * into v_req from public.agent_actions
     where id = nullif(r.verified_evidence ->> 'request_id', '')::bigint and kind = 'handoff';
    -- subject_id is a notifications.id only when it is all digits; a never-queued message carries a text dedupe key.
    v_subject := coalesce(case when v_req.detail ->> 'subject_id' ~ '^[0-9]{1,18}$' then (v_req.detail ->> 'subject_id')::bigint end,
                          (r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint);
    if v_req.id is not null and v_req.detail ->> 'subject_table' = 'notifications' and v_subject is not null
       and not exists (select 1 from public.notifications x where x.id = v_subject) then
      v_receipt := 'ceo: the founder alert this report is about (notification ' || v_subject || ', request '
                   || v_req.id || ') no longer exists in public.notifications, so its delivery can never be '
                   || 're-checked and there is nothing left to deliver. Closed on that fact rather than left open for ever.';
      update public.support_ceo_report
         set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
       where id = r.id;
      return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', v_subject, 'subject_present', false, 'receipt', v_receipt);
    end if;
    return jsonb_build_object('ok', false, 'report_id', r.id, 'reason', 'the report names no notification');
  end if;
  -- The email twin fn_notify_founder writes in the same statement as the WhatsApp fan-out.
  select * into twin from public.notifications t
   where t.channel = 'email' and t.type = n.type and t.created_at = n.created_at
     and t.to_role is not distinct from n.to_role and t.id <> n.id and t.status = 'sent'
   order by t.id limit 1;

  -- 22 Sep 2026 (every_whatsapp_says_whether_it_arrived.sql): for WhatsApp and SMS a SID is only Twilio's
  -- acceptance; "the provider confirmed" needs Twilio's delivered/read report.
  if n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
     and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
    v_receipt := 'ceo: the provider confirmed notification ' || n.id || ' (' || n.channel || ', message '
                 || n.provider_message_id || ', sent ' || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai)';
  elsif n.status = 'sent' and n.channel = 'whatsapp' and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' was handed to Twilio at '
                 || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai '
                 || case when coalesce(btrim(n.provider_message_id), '') = '' then 'without a provider id on record; '
                         else '(message ' || n.provider_message_id || ') and Twilio has not reported it delivered; ' end
                 || 'the email twin ' || twin.id || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || ').';
  elsif n.status in ('failed', 'skipped', 'suppressed') and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' (' || n.channel || ') ended ' || n.status
                 || coalesce(' — ' || left(n.last_error, 160), '') || '; the email twin ' || twin.id
                 || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || '), so the alert reached the founder.';
  else
    -- A founder alert with no delivered twin, or still in the queue: not the CEO's to wave through.
    return jsonb_build_object('ok', false, 'report_id', r.id, 'notification_id', n.id, 'status', n.status,
                              'reason', 'undecided: no confirmed delivery on any channel');
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', n.id, 'receipt', v_receipt);
end $function$;

revoke execute on function public.fn_ceo_delivery_undelivered_decide(bigint) from public, anon, authenticated;
