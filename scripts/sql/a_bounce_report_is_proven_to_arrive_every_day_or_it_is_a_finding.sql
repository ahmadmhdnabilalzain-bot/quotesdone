-- A BOUNCE REPORT IS PROVEN TO ARRIVE EVERY DAY, OR IT IS A FINDING (21 Sep 2026, customer_support).
--
-- MEASURED, 21 Sep 2026, before the supplier campaign (PR #787 stops itself at a 5% bounce rate):
--   * resend_webhook's last agent_runs row was 9 Sep (a query-key refusal); the last bounce it recorded
--     was 15 Aug. Nothing distinguished "no bounces" from "the reports stopped arriving".
--   * The Resend webhook 91890b68… is registered, enabled, events [email.bounced, email.complained], its
--     ?key= equals app_secrets.resend_webhook_key and its signing secret equals
--     app_secrets.resend_webhook_signing_secret (compared by script, never printed).
--   * End to end, live: three mails through the real outbox to Resend's documented test sinks
--     (bounced+…@resend.dev, complained+…@resend.dev) came back as Svix-verified events 3-4 s after sending
--     and were suppressed (hard_bounce:permanent, spam_complaint); a lead whose address carried a capital
--     letter was marked bounced; the next outbox pass marked all three 'suppressed' and sent nothing; and a
--     rolled-back run of enqueue_supplier_invites with 14 filler leads plus that one webhook-bounced lead
--     auto-paused the campaign (1/15 = 6.7% > 5%). A forged event with the right ?key= and no signature
--     was refused 401.
--
-- WHAT WAS WRONG: the only signals about delivery feedback -- the IT sender duty's 7-day bounce rate and
-- the campaign brake -- both read ZERO when the webhook is dead, and zero is also what a clean list reads.
-- A guard that cannot tell a dead feed from a healthy one is not watching it.
--
-- WHAT THIS CHANGES: fn_delivery_feedback_canary_tick(), on the resilience_ping heartbeat (step
-- deliveryCanary, every 15 min):
--   1. while real email has been sent in the last 24 hours, once a day it queues ONE mail to
--      bounced+canary-<utc minute>@resend.dev -- Resend's documented bounce sink, which reaches no person --
--      through the real outbox (the same tick's drain sends it);
--   2. when the webhook has suppressed that address, the canary is stamped arrived, its suppression and
--      error_events row are removed (so it never counts toward the sender duty's bounce rate or the brake:
--      it has no lead) and the finding is closed;
--   3. if 30 minutes after sending nothing has arrived, it raises the IT finding
--      delivery_feedback:bounce_reports_silent (customer_facing: the campaign brake is blind while it lasts).
--
-- WHAT IT DOES NOT CHANGE: resend_webhook, the brake (enqueue_supplier_invites), the sender duty. A canary
-- that Resend refuses or the outbox holds is stamped with that status and not judged -- the outbox has its
-- own detectors, and this one answers one question only. Known ceiling: between the webhook's write and the
-- next tick (at most 15 min) the canary's suppression row exists; the sender duty counts it only if it runs
-- inside that window.
--
-- ORDER: deploy resilience_ping (STEP_RUN gains deliveryCanary) BEFORE applying this file. A schedule row
-- for a step the deployed code lacks fails every tick (every_tick_step_is_scheduled.mjs).

create or replace function public.fn_delivery_feedback_canary_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c public.notifications;
  v_new bigint;
  v_arrived timestamptz;
  v_sends int;
  v_out jsonb := '{}'::jsonb;
  v_key constant text := 'delivery_feedback:bounce_reports_silent';
begin
  select * into c from public.notifications
   where type = 'delivery_feedback_canary' order by id desc limit 1;

  -- ── judge the last canary, once ──
  if c.id is not null and c.last_error is null then
    if c.status = 'sent' then
      select s.created_at into v_arrived from public.email_suppressions s
       where s.email = lower(c.to_email) and s.source = 'resend_webhook';
      if v_arrived is not null then
        update public.notifications
           set last_error = 'canary verdict: bounce report arrived ' || round(extract(epoch from v_arrived - c.sent_at)) || ' s after sending'
         where id = c.id;
        delete from public.email_suppressions where email = lower(c.to_email) and source = 'resend_webhook';
        delete from public.error_events where source = 'resend_webhook' and detail -> 'emails' ? lower(c.to_email);
        perform public.fn_it_engineer_finding_close(v_key, 'the daily canary bounce came back through resend_webhook (notification ' || c.id || ')');
        v_out := jsonb_build_object('judged', c.id, 'arrived', true, 'seconds', round(extract(epoch from v_arrived - c.sent_at)));
      elsif c.sent_at < now() - interval '30 minutes' then
        update public.notifications set last_error = 'canary verdict: NO bounce report within 30 minutes' where id = c.id;
        perform public.fn_it_engineer_finding_upsert(v_key,
          'Bounce and complaint reports have stopped arriving: the daily test bounce sent at '
            || to_char(c.sent_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z never reached resend_webhook',
          'Resend webhook -> resend_webhook -> email_suppressions', 'customer_facing', 1,
          jsonb_build_object('notification_id', c.id, 'to_email', c.to_email, 'provider_message_id', c.provider_message_id,
                             'sent_at', c.sent_at,
                             'last_verified_webhook_run', (select max(started_at) from public.agent_runs
                                                            where agent = 'resend_webhook' and status = 'ok')),
          array['the canary was accepted by Resend (status sent, provider id recorded)'],
          array['whether Resend emitted the event (read GET /emails/<provider_message_id> last_event)',
                'whether the webhook is still registered and enabled, with the key and signing secret app_secrets holds'],
          'customer_support');
        v_out := jsonb_build_object('judged', c.id, 'arrived', false);
      else
        v_out := jsonb_build_object('waiting', c.id);
      end if;
    elsif c.status not in ('queued', 'pending') then
      update public.notifications set last_error = 'canary not judged: the outbox left it ' || coalesce(c.status, 'null') where id = c.id;
      v_out := jsonb_build_object('not_sent', c.id, 'status', c.status);
    end if;
  end if;

  -- ── one canary a day, only while real mail is going out ──
  if c.id is null or c.created_at < now() - interval '23 hours 50 minutes' then
    select count(*) into v_sends from public.notifications
     where status = 'sent' and sent_at > now() - interval '24 hours' and type <> 'delivery_feedback_canary';
    if v_sends > 0 then
      -- to_role 'system': not a customer, supplier or founder, so no WhatsApp twin, no language rewrite,
      -- no founder-mail policy and no digest applies; requested_by 'platform' keeps it out of the seats' loop.
      insert into public.notifications (type, to_email, to_role, channel, subject, body, lang, status, requested_by)
      values ('delivery_feedback_canary',
              'bounced+canary-' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MI') || '@resend.dev',
              'system', 'email', 'Delivery feedback canary',
              'Daily check that bounce reports still reach resend_webhook. Sent to Resend''s bounce test sink; reaches no person.',
              'en', 'queued', 'platform')
      returning id into v_new;
      v_out := v_out || jsonb_build_object('queued', v_new, 'real_sends_24h', v_sends);
    end if;
  end if;
  return jsonb_build_object('ok', true) || v_out;
end
$fn$;

revoke execute on function public.fn_delivery_feedback_canary_tick() from public, anon, authenticated;

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('deliveryCanary', interval '15 min', 800, 'plan', 0,
   'customer_support: once a day a test bounce to Resend''s sink proves resend_webhook still receives reports; 30 min of silence is the finding delivery_feedback:bounce_reports_silent (fn_delivery_feedback_canary_tick). Must run before the outbox drain, which it does: the drain is place=last')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank, note = excluded.note;
