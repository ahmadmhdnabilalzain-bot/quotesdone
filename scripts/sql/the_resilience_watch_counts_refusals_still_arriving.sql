-- THE RESILIENCE WATCH COUNTS REFUSALS STILL ARRIVING (6 Sep 2026). Follows the_resilience_watch_pages_a_condition_once.sql.
--
-- MEASURED: fn_resilience_watch logged status=error at 19:30, 19:40 ... 20:50Z (nine rows and counting,
-- one every ten minutes) with the single issue "20 internal credential(s) REFUSED in 24h, worst
-- wa_template_setup (8)". The refusals were this afternoon's hand-wiring of the WhatsApp templates
-- presenting the wrong scoped credential — operator diagnostics, the guard doing its job — and none
-- arrived after that. The watch counted a 24-hour window, so it would have called the platform
-- unhealthy every ten minutes for a full day, and a_failed_scheduled_run_has_a_reader would have had
-- to disclose a number that moves every ten minutes.
--
-- Now: a day's refusals (>= 20) are a FINDING, carried in the run's note and counts for the IT
-- operations engineer; they are an ISSUE (status=error, the founder-page path) only while refusals
-- are still arriving — five or more in the last hour. Nothing else in the function changes.
--
--   node scripts/apply_sql.mjs scripts/sql/the_resilience_watch_counts_refusals_still_arriving.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_resilience_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint; v_owner text; v_secret text;
  v_sig text;
  v_base text := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/';
  v_email_backlog int := 0; v_prev_backlog int; v_flushed boolean := false;
  v_email_on text; v_stripe text; v_kill text;
  v_last_ops timestamptz; v_last_ai timestamptz; v_match_stuck int := 0;
  v_missing text[] := '{}'; k text; v_issues text := ''; v_heals int := 0; v_alerts int := 0;
  v_cred_denied int; v_cred_top text; v_legacy int; v_legacy_who text;
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

  -- WRONG IN BOTH DIRECTIONS UNTIL 9 Aug 2026, and it fired 65 times saying so about fixtures.
  -- (a) NO UPPER BOUND. This read `between now()-24h and now()-6h`, a BAND: an inquiry older than
  --     a day left the alert whether or not it had ever been matched. Six fixtures created
  --     2026-08-08 10:40 alarmed every ten minutes until exactly 2026-08-09 10:40 and then went
  --     quiet - not because anything was matched, but because they crossed the 24-hour edge. A
  --     watchdog that forgets is worse than one that never looked, because the silence reads as
  --     health. Real stuck inquiries now stay reported until they are matched or closed.
  -- (b) FIXTURES ARE NOT CUSTOMERS. All 7 rows in inquiries carry brief_source='qd_demo_fixture'
  --     and are seeded ZZ DEMO briefs. Paging a human every ten minutes about demo data is how a
  --     monitor gets ignored, and it is why this alert had been shouting for a day about nothing.
  -- Together these make the alert mean what its text says: a REAL inquiry has gone unmatched for
  -- more than six hours. It reads 0 today because there are no real inquiries yet - NOT because
  -- matching has been shown to work on live traffic, which it has never been given.
  select count(*) into v_match_stuck from inquiries i
    where i.created_at < now()-interval '6 hours'
      and coalesce(i.brief_source,'') <> 'qd_demo_fixture'
      and i.status not in ('completed','accepted','closed','cancelled','draft')
      and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  if v_match_stuck>0 then
    v_issues := v_issues||'- '||v_match_stuck||' inquiry(ies) unmatched for >6h — the matcher may be stuck.'||E'\n';
  end if;

  -- 1,764 CREDENTIAL DECISIONS WRITTEN AND NOBODY EVER READ ONE (13 Aug 2026).
  --
  -- internal_credential_audit records every internal-credential decision, and 1,673 of the 1,764
  -- rows on production are REFUSALS. Among them a burst of 620 kb_embed denials from fn.cos_execute
  -- inside ten minutes on 11 Aug, and 823 send_whatsapp unknown_credential rows over five days in
  -- early August. Both were fixed, and neither was fixed BECAUSE of this table: nothing in the
  -- running estate selects from it. Three edge functions write to it, src/ never mentions it, and
  -- the one view built over it — v_legacy_secret_users, which names the callers still presenting
  -- the legacy shared secret instead of a per-context credential — has ZERO readers.
  --
  -- A refusal log with no reader is a smoke alarm in an empty house. This is the reader. It says
  -- nothing while the estate is quiet, which is the state it is in as this ships.
  select count(*) into v_cred_denied from internal_credential_audit
   where not allowed and at > now() - interval '24 hours';
  if v_cred_denied >= 20 then
    select function_name||' ('||count(*)||')' into v_cred_top from internal_credential_audit
     where not allowed and at > now() - interval '24 hours'
     group by function_name order by count(*) desc limit 1;
    -- 6 SEP 2026: a day's refusals are a FINDING for the IT engineer's task; refusals still arriving
    -- are the platform ISSUE. Twenty refusals from one afternoon's hand-wiring of the WhatsApp templates
    -- kept this watch at status=error every ten minutes for the rest of the day, and would have for a
    -- full day: the 24-hour window measured history, and 'error' here means the platform is unhealthy now.
    if (select count(*) from internal_credential_audit where not allowed and at > now() - interval '60 minutes') >= 5 then
      v_issues := v_issues||'- '||v_cred_denied||' internal credential(s) REFUSED in 24h, worst '
               ||coalesce(v_cred_top,'?')||' — a caller is presenting a credential it is not scoped for, and still is this hour.'||E'\n';
    else
      v_findings := v_findings||'- '||v_cred_denied||' internal credential(s) REFUSED in 24h, worst '
               ||coalesce(v_cred_top,'?')||' — a caller presented a credential it is not scoped for; none in the last hour.'||E'\n';
    end if;
  end if;

  -- The legacy shared secret is being withdrawn per audit 9.5. This names who is still on it while
  -- there is still time to move them, rather than after it is switched off.
  select count(*) into v_legacy from v_legacy_secret_users;
  if v_legacy > 0 then
    select string_agg(x.t, ', ') into v_legacy_who from (select (v.*)::text as t from v_legacy_secret_users v limit 5) x;
    v_findings := v_findings||'- '||v_legacy||' caller(s) still using the LEGACY shared secret: '
                ||left(coalesce(v_legacy_who,'?'),240)||''||E'
';
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

  -- ONCE PER CONDITION, NOT ONCE PER THREE HOURS (6 Sep 2026). The signature is the body with every number
  -- replaced, so the same standing finding with a different count or timestamp in it is still the same
  -- condition. A signature alerted inside the last 24 hours is recorded as seen and does not page again;
  -- every open signature NOT present on this pass is resolved on merit, so a finding that comes back later
  -- is a new episode and pages again.
  v_sig := md5(regexp_replace(v_body, '[0-9]+', '#', 'g'));
  update public.alert_signature s set resolved_at = now()
   where s.watcher = 'resilience' and s.resolved_at is null
     and (v_body = '' or s.signature <> v_sig);

  if v_body<>'' then
    insert into public.alert_signature (watcher, signature) values ('resilience', v_sig)
      on conflict (watcher, signature) do update
        set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
    select exists(select 1 from public.alert_signature s
                   where s.watcher = 'resilience' and s.signature = v_sig
                     and s.last_alerted_at > now() - interval '24 hours') into v_deduped;
    if not v_deduped then
      update public.alert_signature set last_alerted_at = now()
       where watcher = 'resilience' and signature = v_sig;
      -- 6 SEP 2026: fn_notify_founder, not an HTTP hop to alert_founder. founder_mail_policy routes the
      -- resilience kind to the IT operations engineer as ONE org_task per condition; the 'digested'
      -- notifications row this used to write went with it — the task is the record now.
      perform public.fn_notify_founder('Resilience: the platform needs attention',
        'The self-healing watchdog found issues it could not auto-fix:'||E'\n'||v_body,
        case when v_issues<>'' then 'critical' else 'warn' end,
        p_kind => 'resilience', p_dedupe_key => 'resilience');
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
end $function$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_resilience_watch_counts_refusals_still_arriving.sql',
       evidence = 'refusals still arriving are the issue; a day of them is a finding (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_resilience_watch';
