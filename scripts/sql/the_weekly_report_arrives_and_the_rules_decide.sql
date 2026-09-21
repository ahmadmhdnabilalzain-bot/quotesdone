-- THE CEO'S WEEKLY REPORT ARRIVES, AND THE CEO'S DECISION RULES ACTUALLY DECIDE.
-- Seat: ceo. 21 Sep 2026. Apply with --apply --ddl. Pure-probe partner: the_weekly_report_arrives_and_the_rules_decide_probe.sql
--
-- MEASURED (production, 21 Sep 2026, read-only):
--   1. public.ceo_weekly_report: W36 never sent (status generated, 0 attempts); W37 delivery_failed after
--      69 attempts on 14 Sep; W38 delivery_failed after 7 attempts today. Both failures carry the SAME
--      error: invalid input syntax for type bigint: "{"kind": "board_report", "mode": "email", "emailed": true}".
--      CAUSE: fn_ceo_weekly_report_deliver stored the result of fn_notify_founder in `v_notif bigint`.
--      fn_notify_founder returns JSONB since the founder-mail-policy rewrite of 6 Sep, so the
--      assignment raised, the exception block rolled the queued email back with it, and the founder
--      received nothing. The same text sat in last_delivery_error on both Mondays.
--   2. It stayed invisible because the tick returned {fired:true, delivery:{ok:false}} with no top-level
--      ok/error, and resilience_ping's failureOf only reads the top level: resilience_step.ceoWeekly shows
--      last_ok_at 21 Sep 18:31Z across all 76 failed attempts.
--   3. It was never retried after its Monday: the tick gated on "today IS the configured day" (<>), so a
--      failed Monday report was abandoned until the next week generated a new key.
--   4. There was no PDF at all. fn_notify_founder writes a bare "[Attention] " alert (and a WhatsApp
--      copy at level 'high'): the wrong vehicle for a report the founder reads.
--   5. public.ceo_decision: 10 active rules; public.ceo_decision_log: 0 rows ever. CAUSE: NO ROUTINE IN
--      THE DATABASE WRITES ceo_decision_log (pg_proc searched for an INSERT into it: none). The rules'
--      trigger_condition is prose, measure_sql only MEASURES (fn_ceo_standing reads it), and nothing on
--      the heartbeat evaluates a condition. Not a false condition and not a wrong table name: no caller.
--
-- WHAT THIS CHANGES:
--   * ceo_weekly_report gains the PDF columns the accountant's weekly report already has. The report is
--     rendered on the company template (pdf_native, letterhead) and delivered as an ATTACHMENT through a
--     notifications row of kind board_report -- which a10_notifications_founder_mail_policy (the
--     founder_mail_policy gate) admits, because board_report is allowed and owned by the ceo. No alert,
--     no "[Attention]" prefix, no WhatsApp.
--   * fn_ceo_weekly_report_deliver takes the notification id from INSERT ... RETURNING id (a bigint),
--     and returns {ok:false, error} at the TOP level when it fails, so the heartbeat raises it to IT.
--   * fn_ceo_weekly_report_tick: a report already generated for the week is finished on ANY tick (PDF,
--     then delivery), exactly as fn_accountant_weekly_report_tick does. A new week starts on or after the
--     configured day/hour (app_secrets.ceo_weekly_report_local_dow / _local_time, unchanged: Mon 08:00
--     Asia/Dubai). W38's existing row is therefore delivered on the first tick after apply + deploy.
--   * ceo_decision_log gains outcome ('decided' | 'needs_judgement') and a unique dedupe_key.
--   * fn_ceo_decisions_evaluate(p_dry_run) evaluates every active rule deterministically, one branch per
--     decision_key, and writes a row with evidence for each firing. An active rule with no branch is
--     returned as no_evaluator with ok:false, so a rule added later without an evaluator is flagged
--     by the heartbeat instead of sitting silent the way these ten did.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE:
--   * The configured day. The founder has not ruled on a day; Mon 08:00 Dubai is the value seeded 9 Sep.
--   * fn_notify_founder, founder_mail_policy, the a10 gate. Nothing new emails the founder: the evaluator
--     writes ceo_decision_log only, escalated_to_founder is always false, and it opens no alert.
--   * W36 and W37: they stay as recorded (a two-week-old report is noise, not news).
--   * spend_against_constraint and risk_owner have no instrument (measure_sql is null); they are
--     returned as not_instrumented, never as a fabricated decision. structure is founder_specified.
--   * The model: nothing here calls ai_gateway. A rule that needs judgement records 'needs_judgement'.

-- ── 1. THE REPORT CARRIES ITS DOCUMENT ───────────────────────────────────────────────────────────
alter table public.ceo_weekly_report
  add column if not exists pdf_blocks       jsonb,
  add column if not exists pdf_bucket       text,
  add column if not exists pdf_path         text,
  add column if not exists pdf_url          text,
  add column if not exists pdf_bytes        int,
  add column if not exists pdf_error        text,
  add column if not exists pdf_generated_at timestamptz;

-- ceo_weekly_report had RLS on and no policy. Deliberately service-role only, said in the schema.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='ceo_weekly_report') then
    create policy ceo_weekly_report_service_role_only on public.ceo_weekly_report
      as permissive for all to public using (false) with check (false);
  end if;
end $$;

-- The document, built from the row's own body so the PDF and the email text cannot disagree.
-- A line of capitals is a section heading, an indented line is an item, a rule of dashes is a gap.
create or replace function public.fn_ceo_weekly_report_pdf_blocks(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_array(
           jsonb_build_object('t','h2','text','Weekly company report'),
           jsonb_build_object('t','p','text', to_char(r.week_start,'Dy DD Mon YYYY')||' to '||to_char(r.week_end,'Dy DD Mon YYYY')
                                              ||'  (Asia/Dubai)   ISO '||to_char(r.week_start,'IYYY-"W"IW')||'   Revision '||r.revision),
           jsonb_build_object('t','note','text','Prepared by the CEO seat for the founder. Informational: nothing in this document asks for an approval.'),
           jsonb_build_object('t','space','h',6))
      || coalesce((
           select jsonb_agg(case
                    when l.line ~ '^-{5,}$'              then jsonb_build_object('t','space','h',8)
                    when l.line ~ '^\s{2}'               then jsonb_build_object('t','li','text', btrim(l.line))
                    when l.line ~ '^[A-Z][A-Z ]+[A-Z]$'  then jsonb_build_object('t','h3','text', initcap(l.line))
                    else jsonb_build_object('t','p','text', l.line) end order by l.n)
             from regexp_split_to_table(coalesce(r.body,''), E'\n') with ordinality as l(line, n)
            where btrim(l.line) <> ''), '[]'::jsonb)
    from public.ceo_weekly_report r where r.id = p_id
$fn$;
revoke execute on function public.fn_ceo_weekly_report_pdf_blocks(bigint) from public, anon, authenticated;

-- ── 2. DELIVERY: ONE NOTIFICATION, WITH THE PDF, THROUGH THE FOUNDER-MAIL GATE ───────────────────
create or replace function public.fn_ceo_weekly_report_deliver(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r        public.ceo_weekly_report;
  v_owner  text;
  v_notif  bigint;          -- the notifications.id from RETURNING, never a routine's jsonb answer
  v_file   text;
  v_err    text;
begin
  select * into r from public.ceo_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_report '||p_id); end if;
  if r.founder_submitted_at is not null then
    return jsonb_build_object('ok', true, 'report_key', r.report_key, 'status', r.status, 'already', true);
  end if;

  -- THE PDF IS THE DELIVERABLE. Mailing text and closing the week would close it on the wrong thing.
  if r.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; the report is retained and the next tick retries';
  else
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_err := 'no recipient configured in app_secrets.admin_emails';
    else
      v_file := 'QuotesDone_Weekly_Company_Report_'
             || regexp_replace(replace(r.report_key, 'quotesdone:', ''), '[^A-Za-z0-9_-]', '_', 'g')
             || case when r.revision > 1 then '_revision_'||r.revision else '' end || '.pdf';
      begin
        -- kind board_report: allowed by founder_mail_policy and owned by the ceo. The a10 gate decides;
        -- if it refuses, RETURNING yields no row and v_notif stays null, named below.
        insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
        values ('board_report', 'board_report', v_owner, 'admin', 'email', r.subject,
                coalesce(r.body,'') || E'\n\nThe report is attached as ' || v_file || '.',
                jsonb_build_array(jsonb_build_object('bucket', coalesce(r.pdf_bucket,'agent-docs'),
                                                     'path', r.pdf_path, 'filename', v_file)))
        returning id into v_notif;
        if v_notif is null then
          v_err := 'the founder-mail gate did not accept the row (kind board_report)';
        end if;
      exception when others then
        v_err := 'founder submission raised: ' || sqlerrm;
      end;
    end if;
  end if;

  update public.ceo_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = v_err,
         status               = case when v_notif is not null then 'delivered' else 'delivery_failed' end,
         updated_at           = now()
   where id = p_id returning * into r;

  -- ok/error at the TOP LEVEL: resilience_ping's failureOf reads nothing deeper, which is how 76 failed
  -- attempts were recorded as a healthy step.
  return jsonb_build_object('ok', v_notif is not null, 'report_key', r.report_key,
    'notification_id', r.notification_id, 'status', r.status, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_deliver(bigint) from public, anon, authenticated;

-- The heartbeat renders the PDF (Postgres cannot) and hands the result back here. A render failure is
-- recorded and the report retained: the next tick re-renders from the stored blocks.
create or replace function public.fn_ceo_weekly_report_attach_pdf(
  p_id bigint, p_bucket text default null, p_path text default null, p_url text default null,
  p_bytes int default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.ceo_weekly_report;
begin
  select * into r from public.ceo_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_report '||p_id); end if;

  if p_path is null or coalesce(p_error,'') <> '' then
    update public.ceo_weekly_report
       set pdf_error = coalesce(nullif(p_error,''), 'pdf_native returned no path'),
           delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'the PDF could not be rendered: '||coalesce(nullif(p_error,''),'no path returned'),
           status = case when founder_submitted_at is null then 'delivery_failed' else status end,
           updated_at = now()
     where id = p_id returning * into r;
    return jsonb_build_object('ok', false, 'report_key', r.report_key, 'retained', true, 'error', r.last_delivery_error);
  end if;

  update public.ceo_weekly_report
     set pdf_bucket = coalesce(p_bucket,'agent-docs'), pdf_path = p_path, pdf_url = p_url, pdf_bytes = p_bytes,
         pdf_generated_at = now(), pdf_error = null, updated_at = now()
   where id = p_id;
  return public.fn_ceo_weekly_report_deliver(p_id);
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_attach_pdf(bigint, text, text, text, int, text) from public, anon, authenticated;

-- ── 3. THE TICK: FINISH WHAT IS IN FLIGHT ON ANY TICK; START A WEEK ON OR AFTER ITS SLOT ──────────
create or replace function public.fn_ceo_weekly_report_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_dow int; v_at time; v_ws date; v_key text; v_gen jsonb;
  r public.ceo_weekly_report;
begin
  begin
    select coalesce(nullif(btrim(value),''),'1')::int into v_dow from public.app_secrets where key = 'ceo_weekly_report_local_dow';
  exception when others then v_dow := 1; end;
  begin
    select coalesce(nullif(btrim(value),''),'08:00')::time into v_at from public.app_secrets where key = 'ceo_weekly_report_local_time';
  exception when others then v_at := time '08:00'; end;
  v_dow := coalesce(v_dow, 1); v_at := coalesce(v_at, time '08:00');

  v_ws  := (date_trunc('week', v_local::date) - interval '7 days')::date;   -- the week that closed
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  select * into r from public.ceo_weekly_report where report_key = v_key order by revision desc limit 1;

  if not found then
    if extract(isodow from v_local)::int < v_dow
       or (extract(isodow from v_local)::int = v_dow and v_local::time < v_at) then
      return jsonb_build_object('fired', false, 'reason', 'before the configured local day/time',
        'report_key', v_key, 'configured_dow', v_dow, 'configured_at', v_at::text);
    end if;
    v_gen := public.fn_ceo_weekly_report(v_ws);
    select * into r from public.ceo_weekly_report where id = (v_gen->>'id')::bigint;
  end if;

  if r.founder_submitted_at is not null then
    return jsonb_build_object('fired', false, 'reason', 'already delivered', 'report_key', v_key, 'id', r.id);
  end if;

  -- A REPORT IN FLIGHT IS FINISHED WHATEVER DAY IT IS (the Monday-only gate abandoned W37).
  if r.pdf_path is null then
    if r.pdf_blocks is null then
      update public.ceo_weekly_report set pdf_blocks = public.fn_ceo_weekly_report_pdf_blocks(r.id), updated_at = now()
       where id = r.id returning * into r;
    end if;
    return jsonb_build_object('fired', true, 'pdf_pending', true, 'id', r.id, 'report_key', r.report_key,
      'revision', r.revision, 'subject', r.subject, 'pdf_blocks', r.pdf_blocks);
  end if;

  return public.fn_ceo_weekly_report_deliver(r.id) || jsonb_build_object('fired', true);
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_tick() from public, anon, authenticated;

-- ── 4. THE DECISION LOG CAN RECORD AN HONEST "NEEDS JUDGEMENT", AND FIRES ONCE PER EVENT ─────────
alter table public.ceo_decision_log
  add column if not exists outcome    text not null default 'decided',
  add column if not exists dedupe_key text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ceo_decision_log_outcome_ck') then
    alter table public.ceo_decision_log add constraint ceo_decision_log_outcome_ck
      check (outcome in ('decided','needs_judgement'));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='ceo_decision_log') then
    create policy ceo_decision_log_service_role_only on public.ceo_decision_log
      as permissive for all to public using (false) with check (false);
  end if;
end $$;
create unique index if not exists ceo_decision_log_dedupe_uidx on public.ceo_decision_log (dedupe_key) where dedupe_key is not null;
revoke all on public.ceo_decision_log from anon, authenticated;

-- ── 5. THE EVALUATOR, ON THE HEARTBEAT ───────────────────────────────────────────────────────────
-- One branch per decision_key; each branch reads its rule's trigger_condition as code. A firing writes
-- one row (dedupe_key makes a second tick a no-op). p_dry_run evaluates and writes nothing -- the CI
-- check uses it. Returns ok:false with error when an ACTIVE rule has no branch: that is precisely the
-- state that left ten rules silent for two weeks, and the heartbeat raises it to the IT engineer.
create or replace function public.fn_ceo_decisions_evaluate(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d record; x record;
  v_out jsonb := '[]'::jsonb; v_fired int := 0; v_written int := 0; v_missing text[] := '{}';
  v_state text; v_detail text; v_reading text;
  v_day date := ((now() at time zone 'Asia/Dubai')::date - 1);   -- the last COMPLETE Dubai day
  v_hold timestamptz := timestamptz '2026-08-15 02:51:33.108565+00';
  v_n bigint; v_m numeric; v_rate numeric; v_prev text; v_ev jsonb;
  v_rows jsonb;   -- [{key, decision, outcome, evidence}] this rule wants written
begin
  for d in select * from public.ceo_decision where active order by decision_key loop
    v_rows := '[]'::jsonb; v_state := 'quiet'; v_detail := null; v_reading := null;
    if d.measure_sql is not null then
      begin execute d.measure_sql into v_reading;
      exception when others then v_reading := 'INSTRUMENT FAILED -- '||sqlerrm; end;
    end if;

    case d.decision_key
    when 'target_is_reachable' then
      -- "Any weekly feasibility run whose verdict is not REACHABLE, or any week the required run rate
      -- rises above twice the highest ever measured." One firing per feasibility run.
      for x in select v.*, c.contract_key,
                      (select max(v2.current_run_rate) from public.target_verdict v2 where v2.contract_id = c.id) as best_rate
                 from public.target_contract c
                 join lateral (select * from public.target_verdict v where v.contract_id = c.id order by v.run_at desc limit 1) v on true
                where c.status = 'active' and c.metric_unit = 'AED'
      loop
        if x.verdict <> 'REACHABLE' or (x.best_rate > 0 and x.required_run_rate > 2 * x.best_rate) then
          v_rows := v_rows || jsonb_build_object('key', 'target_is_reachable:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('The AED 1,000,000 target is NOT reachable on the evidence (verdict %s of %s). What must change: %s',
                               x.verdict, to_char(x.run_at at time zone 'Asia/Dubai','DD Mon YYYY'),
                               coalesce(array_to_string(x.what_must_change, ' '), x.verdict_reason)),
            'evidence', jsonb_build_object('contract', x.contract_key, 'verdict_id', x.id, 'verdict', x.verdict,
              'run_at', x.run_at, 'verdict_reason', x.verdict_reason, 'binding_stage', x.binding_stage,
              'required_run_rate', x.required_run_rate, 'highest_measured_run_rate', x.best_rate,
              'measured_rate_count', x.measured_rate_count, 'assumed_rate_count', x.assumed_rate_count));
        end if;
      end loop;

    when 'binding_constraint' then
      -- "Any week the binding stage named by the feasibility run differs from the one currently being
      -- worked." The one being worked is the stage of the last logged binding_constraint decision.
      select v.* into x from public.target_verdict v join public.target_contract c on c.id = v.contract_id
       where c.status = 'active' and v.binding_stage is not null order by v.run_at desc limit 1;
      if not found then
        v_detail := 'no feasibility run has named a binding stage (target_verdict.binding_stage is null on every run)';
      else
        select l.evidence->>'binding_stage' into v_prev from public.ceo_decision_log l
         where l.decision_key = 'binding_constraint' order by l.decided_at desc limit 1;
        if v_prev is distinct from x.binding_stage then
          v_rows := jsonb_build_array(jsonb_build_object('key', 'binding_constraint:verdict:'||x.id, 'outcome', 'decided',
            'decision', format('Work the %s stage next: the feasibility run names it as the binding constraint%s.',
                               x.binding_stage, case when v_prev is null then '' else ' (previously '||v_prev||')' end),
            'evidence', jsonb_build_object('verdict_id', x.id, 'run_at', x.run_at, 'binding_stage', x.binding_stage,
              'binding_reason', x.binding_reason, 'previous_stage', v_prev)));
        end if;
      end if;

    when 'supplier_admission' then
      -- "A registration arrives with all six present." Fixtures never produce a company decision.
      for x in select l.id, l.company_name, l.verified, l.owner_email_verified, l.owner_phone_verified
                 from public.leads l
                where l.claimed and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
                  and coalesce(l.email,'') !~* '@example[.]invalid$'
                  and cardinality(public.fn_supplier_mandatory_six_for(l.id)) = 0
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'supplier_admission:lead:'||x.id||':'||case when x.owner_email_verified and x.owner_phone_verified then 'admit' else 'hold' end,
          'outcome', 'decided',
          'decision', case when x.owner_email_verified and x.owner_phone_verified
                           then format('Admit %s: all six mandatory fields present, email and UAE mobile confirmed by OTP.', x.company_name)
                           else format('Hold %s: the six are present but the %s is not OTP-confirmed.', x.company_name,
                                       case when not coalesce(x.owner_email_verified,false) then 'email' else 'UAE mobile' end) end,
          'evidence', jsonb_build_object('lead_id', x.id, 'mandatory_missing', '[]'::jsonb,
            'owner_email_verified', x.owner_email_verified, 'owner_phone_verified', x.owner_phone_verified,
            'verified_flag_now', x.verified));
      end loop;

    when 'report_to_founder' then
      -- "Every reporting cadence." Fires once per weekly report the founder actually received.
      for x in select * from public.ceo_weekly_report where founder_submitted_at is not null
                  and report_key like 'quotesdone:%'
                order by week_start desc limit 4
      loop
        select count(*) into v_n from public.ceo_decision_log l
         where l.decided_at > x.founder_submitted_at - interval '7 days' and l.decided_at <= x.founder_submitted_at;
        v_rows := v_rows || jsonb_build_object('key', 'report_to_founder:'||x.report_key||':r'||x.revision, 'outcome', 'decided',
          'decision', format('Reported to the founder: "%s". %s decision(s) taken alone in the week before it; none escalated.', x.subject, v_n),
          'evidence', jsonb_build_object('report_id', x.id, 'report_key', x.report_key, 'notification_id', x.notification_id,
            'delivered_at', x.founder_submitted_at, 'pdf', x.pdf_bucket||'/'||x.pdf_path, 'decisions_alone', v_n, 'escalated', 0));
      end loop;

    when 'channel_volume' then
      -- "Any bounce rate above 5 per cent." Bounces = email_suppressions added for a bounce in the last 7
      -- days, over emails sent in the same window. The "proposal to send more" half has no instrument.
      select count(*) into v_n from public.notifications
       where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
      select count(*) into v_m from public.email_suppressions
       where reason ilike '%bounce%' and created_at > now() - interval '7 days';
      v_rate := case when v_n > 0 then round(100.0 * v_m / v_n, 2) end;
      v_detail := format('bounce %s%% (%s bounced / %s sent, 7 days); proposals to raise volume are not instrumented',
                         coalesce(v_rate::text,'n/a'), v_m, v_n);
      if v_rate > 5 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'channel_volume:'||v_day, 'outcome', 'decided',
          'decision', format('No outreach channel is raised above its standing ceiling: the 7-day bounce rate is %s%%, above the 5%% limit.', v_rate),
          'evidence', jsonb_build_object('bounced_7d', v_m, 'sent_7d', v_n, 'bounce_pct', v_rate, 'ceilings', v_reading)));
      end if;

    when 'refund' then
      -- "A buyer asks for a refund, or a reveal is disputed." Weighing a buyer's stated reason is
      -- judgement; the CEO's refund review decides it. Until that review has an outcome, say so.
      for x in select t.id, t.refund_status,
                      (select rv.outcome from public.refund_ceo_review rv where rv.transaction_id = t.id
                        order by rv.created_at desc limit 1) as review_outcome
                 from public.transactions t where coalesce(t.refund_status,'') <> ''
      loop
        v_rows := v_rows || jsonb_build_object(
          'key', 'refund:tx:'||x.id||':'||coalesce(x.review_outcome,'open'),
          'outcome', case when x.review_outcome is null then 'needs_judgement' else 'decided' end,
          'decision', case when x.review_outcome is null
                           then format('Refund on transaction %s needs judgement: no CEO refund review has reached an outcome.', x.id)
                           else format('Refund on transaction %s: %s (the CEO refund review).', x.id, x.review_outcome) end,
          'evidence', jsonb_build_object('transaction_id', x.id, 'refund_status', x.refund_status, 'review_outcome', x.review_outcome));
      end loop;

    when 'paid_inference' then
      -- "Any request that needs a paid model while the hold is on." ai_gateway marks those rows HELD.
      -- One firing per complete Dubai day. A charge during the hold is not a rule's to excuse.
      select coalesce(sum(n), 0), coalesce(jsonb_object_agg(fn, n), '{}'::jsonb) into v_n, v_ev from (
        select coalesce(fn, '(unnamed)') fn, count(*) n from public.ai_cost_log
         where model_selected_because like '%HELD:%'
           and occurred_at >= (v_day::timestamp at time zone 'Asia/Dubai')
           and occurred_at <  ((v_day + 1)::timestamp at time zone 'Asia/Dubai')
         group by fn) s;
      select coalesce(sum(cost_aed),0) into v_m from public.ai_cost_log where occurred_at > v_hold;
      if v_n > 0 or v_m > 0 then
        v_rows := jsonb_build_array(jsonb_build_object('key', 'paid_inference:'||v_day,
          'outcome', case when v_m > 0 then 'needs_judgement' else 'decided' end,
          'decision', case when v_m > 0
            then format('Paid inference was charged during the hold (AED %s since 15 Aug). The hold is the founder''s constraint; this is not excused by a rule.', v_m)
            else format('Paid inference refused on %s for %s request(s) that asked for a model; each was held and answered without one. Cost since the hold: AED 0.', v_day, v_n) end,
          'evidence', jsonb_build_object('day', v_day, 'held_requests', v_n, 'held_by_function', v_ev, 'cost_since_hold_aed', v_m)));
      end if;

    when 'spend_against_constraint', 'risk_owner' then
      v_state := 'not_instrumented'; v_detail := d.measure;

    when 'structure' then
      v_state := 'founder_specified'; v_detail := 'the founder specifies the seats; the CEO decides nothing here';

    else
      v_state := 'no_evaluator'; v_missing := v_missing || d.decision_key;
    end case;

    if jsonb_array_length(v_rows) > 0 then
      v_state := 'fired'; v_fired := v_fired + jsonb_array_length(v_rows);
      if not p_dry_run then
        with ins as (
          insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, escalated_to_founder, outcome, dedupe_key)
          select d.decision_key, e->>'decision', (e->'evidence') || jsonb_build_object('rule', d.trigger_condition),
                 v_reading, false, e->>'outcome', e->>'key'
            from jsonb_array_elements(v_rows) e
          on conflict (dedupe_key) where dedupe_key is not null do nothing
          returning 1)
        select v_written + count(*) into v_written from ins;
      end if;
    end if;

    v_out := v_out || jsonb_build_object('rule', d.decision_key, 'state', v_state, 'firings', jsonb_array_length(v_rows),
                                         'detail', v_detail, 'keys', (select jsonb_agg(e->'key') from jsonb_array_elements(v_rows) e));
  end loop;

  return jsonb_build_object('ok', cardinality(v_missing) = 0, 'dry_run', p_dry_run,
           'fired', v_fired, 'written', v_written, 'rules', v_out)
      || case when cardinality(v_missing) = 0 then '{}'::jsonb
              else jsonb_build_object('error', 'active ceo_decision rule(s) with no evaluator: '||array_to_string(v_missing, ', ')) end;
end $fn$;
revoke execute on function public.fn_ceo_decisions_evaluate(boolean) from public, anon, authenticated;

comment on function public.fn_ceo_decisions_evaluate(boolean) is
  'Evaluates every active public.ceo_decision rule deterministically and writes one ceo_decision_log row with evidence per firing (dedupe_key). Called by resilience_ping step ceoDecisions. ok:false names any active rule with no evaluator. Writes nothing to the founder. 21 Sep 2026, ceo.';

-- ── 6. ON THE HEARTBEAT ──────────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('ceoDecisions', interval '1 hour', 1000, 'plan', 0,
   'fn_ceo_decisions_evaluate: the CEO''s ten decision rules, evaluated deterministically; each firing is one ceo_decision_log row')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note;
