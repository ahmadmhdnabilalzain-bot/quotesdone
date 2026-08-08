-- AUDIT §2 (revision). The first cut of this change folded the receipt gap into v_issues, which
-- sets agent_runs.status='error'. fn_watch_failed_runs runs hourly and pages on ANY error row, so a
-- receipt gap that persists for a day would have produced 144 error rows and 24 pages saying
-- "resilience_watch: 6 failure(s)" — the watchdog reporting ITSELF as broken because it found
-- something. That is how a monitor gets muted.
--
-- The distinction that actually matters:
--   v_issues   = the platform is degraded. Sets status='error'. Correctly cascades to
--                fn_watch_failed_runs, because a failing pipeline SHOULD escalate.
--   v_findings = the run succeeded and found something a human must act on. Alerts once per
--                dedupe window, does NOT set status='error', does NOT cascade.
-- A booked expense with no archived receipt is a finding, not a run failure: the watchdog worked.
CREATE OR REPLACE FUNCTION public.fn_resilience_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint; v_owner text; v_secret text;
  v_base text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/';
  v_email_backlog int := 0; v_prev_backlog int; v_flushed boolean := false;
  v_email_on text; v_stripe text; v_kill text;
  v_last_ops timestamptz; v_last_ai timestamptz; v_match_stuck int := 0;
  v_missing text[] := '{}'; k text; v_issues text := ''; v_heals int := 0; v_alerts int := 0;
  v_deduped boolean;
  v_findings text := '';
  v_receipt_lost int := 0; v_receipt_manual int := 0; v_receipt_detail text;
  v_body text;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  v_owner := coalesce(nullif(btrim(v_owner),''),'management@quotesdone.com');
  insert into agent_runs(agent,started_at) values('resilience_watch',clock_timestamp()) returning id into v_run;

  select value into v_email_on from app_secrets where key='email_enabled';
  select count(*) into v_email_backlog from notifications
    where channel='email' and coalesce(status,'queued') in ('queued','pending') and created_at < now()-interval '15 minutes';
  if v_email_backlog>0 and coalesce(v_email_on,'')='true' and v_secret is not null then
    perform net.http_post(url:=v_base||'send_outbox',
      headers:='{"Content-Type":"application/json"}'::jsonb,
      body:=jsonb_build_object('__secret',v_secret,'limit',50), timeout_milliseconds:=20000);
    v_flushed := true; v_heals := v_heals+1;
    select (counts->>'email_backlog')::int into v_prev_backlog from agent_runs
      where agent='resilience_watch' and id<>v_run order by id desc limit 1;
    if coalesce(v_prev_backlog,0)>0 then
      v_issues := v_issues||'- Email pipeline STUCK: '||v_email_backlog||' message(s) undelivered >15min despite auto-flush.'||E'\n';
    end if;
  end if;

  -- CRITICAL credentials. inbound_secret is scheduled for withdrawal (audit 9.5, due 10 Aug); the
  -- credentials that took over its job, and the ones whose absence is silent and total, are here.
  foreach k in array array[
      'internal_credential_hmac_key',
      'cred_db_internal',
      'openrouter_api_key',
      'resend_api_key',
      'stripe_secret_key',
      'resend_inbound_signing_secret',
      'resend_webhook_signing_secret',
      'resend_inbound_token',
      'resend_webhook_key'
    ] loop
    if not exists(select 1 from app_secrets where key=k and value is not null and length(btrim(value))>0) then
      v_missing := array_append(v_missing,k);
    end if;
  end loop;
  if array_length(v_missing,1)>0 then
    v_issues := v_issues||'- CRITICAL credential(s) MISSING: '||array_to_string(v_missing,', ')||' — dependent flows are down.'||E'\n';
  end if;
  select left(value,8) into v_stripe from app_secrets where key='stripe_secret_key';
  if v_stripe is not null and v_stripe not like 'sk_live_%' then
    v_issues := v_issues||'- Stripe key is NOT live mode — payments will not settle.'||E'\n';
  end if;
  select value into v_kill from app_secrets where key='ai_kill_switch';
  if coalesce(v_kill,'')='true' then
    v_issues := v_issues||'- AI kill-switch is ON — every AI agent is paused.'||E'\n';
  end if;

  select max(started_at) into v_last_ops from agent_runs where agent='ops_watch' and started_at>now()-interval '4 hours';
  select max(started_at) into v_last_ai  from agent_runs where agent='ai_health' and started_at>now()-interval '4 hours';
  if v_last_ops is null or v_last_ops < now()-interval '90 minutes' then
    v_issues := v_issues||'- Ops-watch heartbeat stale (>90min) — the scheduler may be degraded.'||E'\n';
  end if;
  if v_last_ai is null or v_last_ai < now()-interval '45 minutes' then
    v_issues := v_issues||'- AI-health heartbeat stale (>45min) — the scheduler or AI monitor may be down.'||E'\n';
  end if;

  select count(*) into v_match_stuck from inquiries i
    where i.created_at between now()-interval '24 hours' and now()-interval '6 hours'
      and i.status not in ('completed','accepted','closed','cancelled','draft')
      and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  if v_match_stuck>0 then
    v_issues := v_issues||'- '||v_match_stuck||' inquiry(ies) unmatched for >6h — the matcher may be stuck.'||E'\n';
  end if;

  -- AUDIT §2. A booked expense whose receipt the pipeline HELD and then failed to store: the charge
  -- is in the ledger and the evidence is not. In the UAE the receipt is the deductibility.
  -- to_regclass guard: a watchdog must never be taken down by the absence of the thing it watches.
  if to_regclass('public.v_expense_receipt_gap') is not null then
    select count(*) filter (where document_was_received),
           count(*) filter (where not document_was_received)
      into v_receipt_lost, v_receipt_manual
      from public.v_expense_receipt_gap;

    if v_receipt_lost > 0 then
      select string_agg('#'||id||' '||vendor||' '||amount||' '||currency||' charged '||charged_on
                        ||' (attachment '||coalesce(doc_name,'?')||')', '; ' order by id)
        into v_receipt_detail
        from public.v_expense_receipt_gap where document_was_received;
      v_findings := v_findings||'- '||v_receipt_lost||' booked expense(s) whose receipt was RECEIVED and then lost '
                              ||'before archiving — the charge is in the ledger with no evidence behind it: '
                              ||coalesce(v_receipt_detail,'')
                              ||'. Fix: re-forward the vendor email to the inbound address; it will retry and archive.'||E'\n';
    end if;
  end if;

  v_body := v_issues||v_findings;

  if v_body<>'' then
    select exists(select 1 from notifications where type='resilience_alert' and created_at>now()-interval '3 hours') into v_deduped;
    if not v_deduped and v_secret is not null then
      perform net.http_post(url:=v_base||'alert_founder',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:=jsonb_build_object('__secret',v_secret,'event','Resilience: the platform needs attention',
          'level',case when v_issues<>'' then 'critical' else 'warn' end,'dedupe_key','resilience',
          'detail','The self-healing watchdog found issues it could not auto-fix:'||E'\n'||v_body),
        timeout_milliseconds:=20000);
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('resilience_alert',v_owner,'admin','email','QuotesDone resilience: action needed',v_body,'digested');
      v_alerts := v_alerts+1;
    end if;
  end if;

  update agent_runs set finished_at=clock_timestamp(),
    -- status reflects PLATFORM health, not whether the run found something. A finding must not make
    -- the watchdog look like a failed job to fn_watch_failed_runs.
    status=case when v_issues<>'' then 'error' else 'ok' end,
    counts=jsonb_build_object('email_backlog',v_email_backlog,'flushed',v_flushed,'heals',v_heals,'alerts',v_alerts,
                              'receipt_lost',v_receipt_lost,'receipt_manual_backlog',v_receipt_manual,
                              'has_issues',(v_issues<>''),'has_findings',(v_findings<>'')),
    note=coalesce(nullif(v_body,''),'all critical pipelines healthy')
    where id=v_run;
  return jsonb_build_object('ok',true,'email_backlog',v_email_backlog,'flushed',v_flushed,
                            'receipt_lost',v_receipt_lost,'receipt_manual_backlog',v_receipt_manual,
                            'issues',nullif(v_issues,''),'findings',nullif(v_findings,''),'alerts',v_alerts);
end $function$;;
