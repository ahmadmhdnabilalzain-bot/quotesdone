-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724083940   name: policy_lint_covers_agent_knowledge
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Audit follow-up (2026-07-24): extend the weekly policy-consistency linter to scan
-- agent_knowledge and dept_library — the stores that feed the AI departments' minds.
-- Gap this closes: the "2% commission" contradiction lived in agent_knowledge for weeks
-- because this linter only checked the site, FAQ, and invite emails.
CREATE OR REPLACE FUNCTION public.fn_policy_consistency_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; f jsonb := '[]'::jsonb; n int := 0; v_admin text; v_crit int := 0;
begin
  for r in select * from policy_rules where active loop
    -- live site source (skip archived files)
    if r.scope in ('all','site') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','site','location',path))
             from qd_deploy_src where path not like '\_archive/%' and data ~* r.forbid_regex), '[]'::jsonb);
    end if;
    -- knowledge base (feeds both agents)
    if r.scope in ('all','faq') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','company_faq','location','#'||id||' '||question))
             from company_faq where status='approved' and answer ~* r.forbid_regex), '[]'::jsonb);
    end if;
    -- outbound email copy
    if r.scope in ('all','email') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','email','location',key))
             from app_secrets where key in ('invite_body','invite_subject') and value ~* r.forbid_regex), '[]'::jsonb);
    end if;
    -- NEW: agent knowledge — the rows injected into every department agent's context
    if r.scope in ('all','kb') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_knowledge','location',agent_key||' / '||topic||' (#'||id||')'))
             from agent_knowledge where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','dept_library','location',department||' / '||title||' (#'||id||')'))
             from dept_library where content ~* r.forbid_regex), '[]'::jsonb);
    end if;
  end loop;
  n := jsonb_array_length(f);
  select count(*) into v_crit from jsonb_array_elements(f) e where e->>'severity'='critical';
  if n > 0 then
    v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');
    if not exists (select 1 from founder_alerts where event='policy_inconsistency' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values(case when v_crit>0 then 'crit' else 'warn' end,'policy_inconsistency',
          n||' policy contradiction(s) found across the live site, FAQ, outbound email, agent knowledge and department library: '||left(f::text,600),'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('policy_inconsistency', v_admin,'admin','email','Policy contradiction detected',
          n||' place(s) now contradict current QuotesDone policy (e.g. a phantom supplier fee or an outdated subscription term). This scan covers the live site, approved FAQ, invite emails, agent_knowledge and dept_library. Details: '||left(f::text,1500),'queued');
    end if;
  end if;
  return json_build_object('findings', n, 'critical', v_crit, 'detail', f, 'checked_at', now());
end $function$;
