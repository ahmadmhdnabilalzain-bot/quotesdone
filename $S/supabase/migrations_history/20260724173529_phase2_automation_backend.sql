-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724173529   name: phase2_automation_backend
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- B1: registry mapping cron jobs to human names + categories.
CREATE TABLE IF NOT EXISTS public.cron_registry (
  jobname     text PRIMARY KEY,
  human_name  text NOT NULL,
  category    text NOT NULL DEFAULT 'Operations',
  purpose     text NOT NULL DEFAULT ''
);
ALTER TABLE public.cron_registry ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cron_registry FROM anon, authenticated;

-- Seed from live jobs with a sensible category derived from the name (idempotent).
INSERT INTO public.cron_registry (jobname, human_name, category)
SELECT j.jobname,
  initcap(replace(replace(j.jobname,'_',' '),'-',' ')),
  CASE
    WHEN j.jobname ~* 'agent|exec|dept|cos_|secretary|orchestr' THEN 'Agents'
    WHEN j.jobname ~* 'market|content|blog|social|boost|seo|meta_' THEN 'Marketing'
    WHEN j.jobname ~* 'finance|gl_|billing|dues|subscription|cost|invoice|collections' THEN 'Finance'
    WHEN j.jobname ~* 'invite|supplier|capability|founding|category_sales' THEN 'Supplier growth'
    WHEN j.jobname ~* 'security|fraud|vt_|selfaudit' THEN 'Security'
    WHEN j.jobname ~* 'knowledge|kb_|canon|learn|curator|category_|persona|graph|embed|match' THEN 'Knowledge'
    WHEN j.jobname ~* 'health|uptime|resilience|smoke|drift|quality|silence' THEN 'Health & monitoring'
    WHEN j.jobname ~* 'backup|dr_|dropbox|retention|archive|prune|history' THEN 'Backup & retention'
    WHEN j.jobname ~* 'email|sms|wa_|whatsapp|reveal|nudge|reminder|digest' THEN 'Messaging'
    WHEN j.jobname ~* 'deploy|site|github|autodeploy' THEN 'Deploy & sync'
    WHEN j.jobname ~* 'doc|licen|kyc|legal|compliance' THEN 'Documents & compliance'
    ELSE 'Operations'
  END
FROM cron.job j
ON CONFLICT (jobname) DO NOTHING;

-- B2: list jobs with registry + latest run status.
CREATE OR REPLACE FUNCTION public.fn_os_automation_list()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  select coalesce(jsonb_agg(x order by x->>'category', x->>'human_name'), '[]'::jsonb) from (
    select jsonb_build_object(
      'jobid', j.jobid, 'jobname', j.jobname,
      'human_name', coalesce(r.human_name, initcap(replace(replace(j.jobname,'_',' '),'-',' '))),
      'category', coalesce(r.category,'Operations'), 'purpose', coalesce(r.purpose,''),
      'schedule', j.schedule, 'active', j.active,
      'last_status', lr.status, 'last_start', lr.start_time, 'last_end', lr.end_time,
      'last_message', left(coalesce(lr.return_message,''), 240)
    ) as x
    from cron.job j
    left join public.cron_registry r on r.jobname = j.jobname
    left join lateral (
      select status, start_time, end_time, return_message
      from cron.job_run_details d where d.jobid = j.jobid
      order by d.start_time desc nulls last limit 1
    ) lr on true
  ) q;
$$;
REVOKE ALL ON FUNCTION public.fn_os_automation_list() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_automation_list() TO service_role;

-- B3a: pause / resume.
CREATE OR REPLACE FUNCTION public.fn_os_automation_set_active(p_jobid bigint, p_active boolean, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nm text;
BEGIN
  SELECT jobname INTO nm FROM cron.job WHERE jobid = p_jobid;
  IF nm IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  PERFORM cron.alter_job(job_id := p_jobid, active := p_active);
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_active','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'active',p_active),true);
  RETURN jsonb_build_object('ok',true,'active',p_active);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_automation_set_active(bigint,boolean,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_automation_set_active(bigint,boolean,text) TO service_role;

-- B3b: reschedule (validate 5-field cron, let pg_cron reject anything invalid).
CREATE OR REPLACE FUNCTION public.fn_os_automation_reschedule(p_jobid bigint, p_schedule text, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE nm text; oldsched text;
BEGIN
  SELECT jobname, schedule INTO nm, oldsched FROM cron.job WHERE jobid = p_jobid;
  IF nm IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  IF coalesce(array_length(regexp_split_to_array(btrim(p_schedule), '\s+'),1),0) <> 5 THEN
    RETURN jsonb_build_object('ok',false,'error','schedule_must_have_5_fields'); END IF;
  BEGIN PERFORM cron.alter_job(job_id := p_jobid, schedule := p_schedule);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error',SQLERRM); END;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_reschedule','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'old',oldsched,'new',p_schedule),true);
  RETURN jsonb_build_object('ok',true,'schedule',p_schedule);
END $$;
REVOKE ALL ON FUNCTION public.fn_os_automation_reschedule(bigint,text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_automation_reschedule(bigint,text,text) TO service_role;

-- B3c: run now (executes the job's own command; commands are ours; audited).
CREATE OR REPLACE FUNCTION public.fn_os_automation_run(p_jobid bigint, p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cmd text; nm text; ok boolean := true; msg text := '';
BEGIN
  SELECT command, jobname INTO cmd, nm FROM cron.job WHERE jobid = p_jobid;
  IF cmd IS NULL THEN RETURN jsonb_build_object('ok',false,'error','job_not_found'); END IF;
  BEGIN EXECUTE cmd; EXCEPTION WHEN others THEN ok := false; msg := SQLERRM; END;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'automation_run','cron_job',p_jobid::text,jsonb_build_object('jobname',nm,'error',msg),ok);
  RETURN jsonb_build_object('ok',ok,'error',nullif(msg,''));
END $$;
REVOKE ALL ON FUNCTION public.fn_os_automation_run(bigint,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_automation_run(bigint,text) TO service_role;

