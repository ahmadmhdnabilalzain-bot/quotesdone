-- DEPARTMENT / SUPPLIER / CUSTOMER / AI REPORTS RESUME; "DAILY" MEASURES THE BRIEF THAT ACTUALLY RUNS.
--
-- Measured 6 Sep 2026: report_registry's last department, supplier, customer and ai rows are dated 16 Aug —
-- the day cron 83 (reporting_ai_daily -> fn_reporting_ai -> fn_report_generate) was switched off in the
-- stand-down, after 29 clean runs. fn_report_generate builds every one of the four from KPI views with
-- fn_kv_block — no model call, no outbound message (fn_report_flag writes an agent_actions row) — so it is
-- re-enabled under the kernel wrapper the way red_view_alerter.sql does it, owned by the data intelligence
-- director (W25, data_reporting_and_forecasting) in data_intel.
--
-- "Daily" was red for a different reason: report_kpis.daily_at reads agent_actions kind = 'exec_briefing',
-- which nothing has written since 23 Jul 2026. The daily brief that DOES run every morning (cron 14,
-- founder_brief_daily -> fn_founder_brief, succeeded 3, 4 and 5 Sep) writes notifications type =
-- 'founder_brief'. The view now takes the later of the two, so the tile reports the brief that exists.
--
-- fn_ws_reports gains 'producers' (per report_type: cron job, active, last run, paused_reason) so the
-- Reports page can say "paused" on a tile instead of showing a stale date as if it were live.
--
--   node scripts/apply_sql.mjs scripts/sql/report_types_resume_under_the_kernel.sql --apply --ddl
begin;

create or replace view public.report_kpis as
 WITH reg AS (
         SELECT report_registry.source, report_registry.report_type, report_registry.title,
                report_registry.period, report_registry.created_at, report_registry.id
           FROM public.report_registry
        ), lt AS (
         SELECT max(reg.created_at) FILTER (WHERE reg.report_type = 'weekly'::text) AS weekly_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'monthly'::text) AS monthly_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'quarterly'::text) AS quarterly_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'department'::text) AS department_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'supplier'::text) AS supplier_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'customer'::text) AS customer_at,
            max(reg.created_at) FILTER (WHERE reg.report_type = 'ai'::text) AS ai_at,
            max(reg.created_at) FILTER (WHERE reg.source = 'exec'::text) AS exec_at,
            max(reg.created_at) FILTER (WHERE reg.source = 'finance'::text) AS finance_at
           FROM reg
        ), daily AS (
         -- The morning brief is founder_brief (cron 14, every day); exec_briefing stopped on 23 Jul 2026.
         SELECT greatest(
                  (SELECT max(a.created_at) FROM public.agent_actions a WHERE a.kind = 'exec_briefing'::text),
                  (SELECT max(n.created_at) FROM public.notifications n WHERE n.type = 'founder_brief'::text)) AS daily_at
        )
 SELECT ( SELECT count(*) AS count FROM reg) AS total_reports,
    ( SELECT count(*) AS count FROM reg WHERE reg.created_at > (now() - '30 days'::interval)) AS reports_30d,
    ( SELECT count(DISTINCT reg.report_type) AS count FROM reg) AS report_types,
    d.daily_at, lt.weekly_at, lt.monthly_at, lt.quarterly_at, lt.department_at, lt.supplier_at, lt.customer_at, lt.ai_at, lt.exec_at, lt.finance_at,
    d.daily_at > (now() - '36:00:00'::interval) AS daily_fresh,
    lt.weekly_at > (now() - '8 days'::interval) AS weekly_fresh,
    lt.monthly_at > date_trunc('month'::text, now()) AS monthly_fresh,
    lt.quarterly_at > (now() - '95 days'::interval) AS quarterly_fresh,
    lt.department_at > (now() - '2 days'::interval) AS department_fresh,
    lt.supplier_at > (now() - '2 days'::interval) AS supplier_fresh,
    lt.customer_at > (now() - '2 days'::interval) AS customer_fresh,
    lt.ai_at > (now() - '2 days'::interval) AS ai_fresh,
        CASE WHEN COALESCE(d.daily_at > (now() - '36:00:00'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.weekly_at > (now() - '8 days'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.monthly_at > date_trunc('month'::text, now()), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.quarterly_at > (now() - '95 days'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.department_at > (now() - '2 days'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.supplier_at > (now() - '2 days'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.customer_at > (now() - '2 days'::interval), false) THEN 0 ELSE 1 END +
        CASE WHEN COALESCE(lt.ai_at > (now() - '2 days'::interval), false) THEN 0 ELSE 1 END AS stale_count
   FROM lt, daily d;

CREATE OR REPLACE FUNCTION public.fn_ws_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    -- THE LATEST EXECUTIVE MEETING, IN SEQUENCE. exec_reports.findings is the ordered transcript of
    -- what each of the ten officers said; report_registry projects only title/period/id, so until
    -- now the body reached nothing the browser could run. `contributions` keeps the array order
    -- the meeting wrote it in — that order IS the replay.
    'meeting', (select jsonb_build_object(
        'id', r.id, 'period', r.period, 'officer', r.officer, 'summary', r.summary,
        'at', to_char(r.created_at,'YYYY-MM-DD HH24:MI'),
        'contributions', coalesce(r.findings, '[]'::jsonb),
        'priorities', coalesce(r.recommendations, '[]'::jsonb),
        'challenges', (select coalesce(jsonb_agg(jsonb_build_object(
              'proposal', c.proposal, 'by', c.challenged_by, 'of', c.proposed_by,
              'stance', c.stance, 'confidence', c.confidence, 'reasoning', c.reasoning,
              'alternatives', c.alternatives) order by c.id), '[]'::jsonb)
            from public.challenge_record c
           where c.created_at between r.created_at - interval '30 minutes'
                                  and r.created_at + interval '6 hours'))
      from public.exec_reports r where r.officer='ceo' and r.created_at >= public.fn_os_fresh_start_at() order by r.created_at desc limit 1),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by report_type, created_at desc
        ) x order by report_type) t),
    -- WHO PRODUCES EACH TYPE, AND WHETHER IT IS RUNNING. A tile that shows only a last date reads
    -- as live; this says "paused" out loud when the cron behind a type is off. Keyed by report_type.
    'producers', (select coalesce(jsonb_object_agg(p.report_type, jsonb_build_object(
        'job', p.jobname, 'active', coalesce(j.active, false),
        'last_run', (select to_char(max(d.start_time),'YYYY-MM-DD HH24:MI') from cron.job_run_details d where d.jobid = j.jobid),
        'paused_reason', case when coalesce(j.active, false) then null
                              when j.jobid is null then 'no cron job named ' || p.jobname
                              else 'cron ' || p.jobname || ' is paused' end)), '{}'::jsonb)
      from (values ('daily','founder_brief_daily'), ('department','reporting_ai_daily'), ('supplier','reporting_ai_daily'),
                   ('customer','reporting_ai_daily'), ('ai','reporting_ai_daily'), ('weekly','board_report_weekly'),
                   ('monthly','monthly_report'), ('quarterly','quarterly_report'), ('finance','finance_ai_daily')) as p(report_type, jobname)
      left join cron.job j on j.jobname = p.jobname),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$
;

do $$
declare v_job bigint; v_r jsonb;
begin
  select jobid into v_job from cron.job where jobname = 'reporting_ai_daily';
  if v_job is null then
    raise exception 'reporting_ai_daily is not scheduled; nothing to re-enable';
  end if;
  -- Data intelligence owns the report producers (W25). data_intelligence_director sits in data_intel.
  v_r := public.fn_kernel_wrap_and_enable_cron(v_job, 'data_intelligence_director', 'data_intel', 'routine_operational_decision');
  if coalesce((v_r->>'ok')::boolean, false) is not true then
    raise exception 'fn_kernel_wrap_and_enable_cron refused: %', v_r;
  end if;
  update public.cron_registry
     set purpose = 'Every day 04:20 UTC: fn_reporting_ai regenerates the department, supplier, customer and AI reports '
                || '(fn_report_generate, KPI views only, no model call) and flags any scheduled report that is stale. '
                || 'Paused in the 16 Aug 2026 stand-down after 29 clean runs; resumed under the kernel wrapper 6 Sep 2026.'
   where jobname = 'reporting_ai_daily';
end $$;

commit;
