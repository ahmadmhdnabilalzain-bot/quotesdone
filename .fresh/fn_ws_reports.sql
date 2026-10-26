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
      from public.exec_reports r where r.officer='ceo' order by r.created_at desc limit 1),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry order by report_type, created_at desc
        ) x order by report_type) t),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$
