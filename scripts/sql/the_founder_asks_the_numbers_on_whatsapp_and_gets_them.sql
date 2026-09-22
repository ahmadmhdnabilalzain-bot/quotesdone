-- THE FOUNDER ASKS THE NUMBERS ON WHATSAPP AND GETS THEM — without a model.
--
-- SEAT: customer_support (the WhatsApp channel). One routine; no table.
--
-- MEASURED 22 Sep 2026: every free-text question from the founder's number that was not a settings
-- change went to agent_brain with fn_wa_context's figures pasted into the prompt. agent_brain was
-- deleted on 7 Sep 2026 (config.toml has no entry; the URL answers 404), so "how many suppliers do we
-- have", "any requests today", "revenue this month" had no answer for fifteen days, and on
-- wa_messages 271 the reply was the 404 itself. With the model held, the answer has to be read, not
-- composed: this routine gathers the readings; supabase/functions/wa_inbound/founder_queries.ts
-- recognises the question and says the numbers.
--
-- REUSE, NOT A SECOND COPY OF ANY RULE. Every figure comes from the routine that already owns it, so
-- the WhatsApp answer and the daily brief can never disagree:
--   suppliers registered / verified, requests, reveals and fees  -> fn_ceo_plan_measure (the CEO plan's
--       own measures, demo-excluded the same way the brief is)
--   quotes                                                       -> fn_wa_context('founder', ...)
--   marketing                                                    -> fn_marketing_report_figures
--   the brief's time                                             -> app_secrets.ceo_digest_local_time,
--       the key fn_ceo_daily_digest_tick reads (20:00 Asia/Dubai when unset)
-- Only three counts are read directly, because no routine owns them as a number: open support cases
-- (support_case.closed_at is null), people waiting for a person (the pending support.human_requested
-- handoffs fn_wa_human_request files), and open IT findings (it_engineer_finding.closed_at is null,
-- the same count fn_founder_brief_figures states in its plan).
--
-- THE FOUNDER ONLY. The routine refuses any number fn_identify_contact does not resolve to the founder
-- (app_secrets.admin_mfa_phone), so a caller that passed another number gets {ok:false}, never a
-- figure. wa_inbound calls it only inside its founder branch; both locks are tested.
--
-- NOT CHANGED: fn_wa_context, fn_ceo_plan_measure, fn_marketing_report_figures, the daily brief.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_asks_the_numbers_on_whatsapp_and_gets_them.sql --apply
--   probe after apply: scripts/sql/the_founder_asks_the_numbers_on_whatsapp_and_gets_them_probe.sql

create or replace function public.fn_founder_whatsapp_figures(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_now   timestamptz := now();
  v_day   timestamptz := date_trunc('day', v_now at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_month timestamptz := date_trunc('month', v_now at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_ever  timestamptz := timestamptz '2000-01-01 00:00+00';
  v_ctx jsonb; v_mkt jsonb; v_at text; v_sent boolean;
begin
  if (public.fn_identify_contact(p_phone)->>'audience') is distinct from 'founder' then
    return jsonb_build_object('ok', false, 'reason', 'not_the_founder');
  end if;

  v_ctx := public.fn_wa_context('founder', p_phone);
  v_mkt := public.fn_marketing_report_figures(v_now - interval '7 days', v_now)->'measured';
  select coalesce(nullif(btrim(value), ''), '20:00') into v_at from public.app_secrets where key = 'ceo_digest_local_time';
  v_sent := exists (select 1 from public.ceo_daily_digest
                     where report_key = 'quotesdone:' || to_char((v_now at time zone 'Asia/Dubai')::date, 'YYYY-MM-DD')
                       and submitted_at is not null);

  return jsonb_build_object(
    'ok', true,
    'read_at', v_now,
    'read_at_local', to_char(v_now at time zone 'Asia/Dubai', 'HH24:MI "on" Dy DD Mon'),
    'suppliers', jsonb_build_object(
      'registered',      public.fn_ceo_plan_measure('registrations_submitted', v_ever, v_now),
      'registered_7d',   public.fn_ceo_plan_measure('registrations_submitted', v_now - interval '7 days', v_now),
      'verified',        public.fn_ceo_plan_measure('registrations_verified', v_ever, v_now)),
    'requests', jsonb_build_object(
      'today',           public.fn_ceo_plan_measure('inquiries_posted', v_day, v_now),
      'last_7d',         public.fn_ceo_plan_measure('inquiries_posted', v_now - interval '7 days', v_now)),
    'quotes', jsonb_build_object(
      'total',           (v_ctx->'demand'->>'quotes_total')::numeric,
      'last_7d',         (v_ctx->'demand'->>'quotes_7d')::numeric),
    'reveals_month', jsonb_build_object(
      'paid',            public.fn_ceo_plan_measure('reveals_paid', v_month, v_now),
      'fee_aed',         public.fn_ceo_plan_measure('fee_aed', v_month, v_now)),
    'support', jsonb_build_object(
      'open_cases',      (select count(*) from public.support_case where closed_at is null),
      'waiting_for_person', (select count(*) from public.agent_actions
                              where kind = 'handoff' and status = 'pending'
                                and detail ->> 'type' = 'support.human_requested')),
    'it', jsonb_build_object(
      'open_findings',   (select count(*) from public.it_engineer_finding where closed_at is null)),
    'marketing_7d', jsonb_build_object(
      'posts_published', (v_mkt->>'posts_published')::numeric,
      'posts_scheduled', (v_mkt->>'posts_scheduled_next_7_days')::numeric,
      'ad_spend_aed',    (v_mkt->>'ad_spend_reported_aed')::numeric),
    'brief', jsonb_build_object('local_time', v_at, 'sent_today', v_sent));
end;
$fn$;

revoke execute on function public.fn_founder_whatsapp_figures(text) from public, anon, authenticated;

comment on function public.fn_founder_whatsapp_figures(text) is
  'The founder''s WhatsApp readings (suppliers, requests, quotes, reveals this month, support, IT, marketing 7d, brief time), each from the routine that owns it. Refuses any number that is not the founder''s. Read by wa_inbound founder_queries.ts; no model.';
