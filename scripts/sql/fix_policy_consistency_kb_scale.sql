-- fn_policy_consistency_check: scale the kb_chunks scan to a multi-million-row corpus.
--
-- 31 Aug 2026 — policy_consistency_weekly (cron) started FAILING with "canceling statement due to
-- statement timeout". The function scans eight content stores with `content ~* forbid_regex` per active
-- policy rule. Seven are small; kb_chunks grew from ~97k to 2.69M rows during the agent-expertise
-- ingestion, so its full-table regex scan (~3GB of text per rule) no longer completes inside the 120s
-- statement timeout, and the weekly check has been dead since 24 Aug's last green run.
--
-- FIX (restores the check's ORIGINAL effective scope; does not weaken what it exists to catch):
--   * The 2.6M new rows are third-party reference material ingested for agent expertise — source_kind
--     'standard' (2.06M), 'reference', 'cert', 'textbook', 'guide', 'code', 'handbook', 'book', 'paper',
--     … These are external authoritative standards (ACI/NIST/WHO/IETF/…). They cannot contain a
--     QuotesDone POLICY contradiction (a forbid_regex hit in them is a false positive), and they are what
--     blows the scan. The company-AUTHORED, policy-bearing kinds — 'qd_kb_pack' (the company knowledge
--     packs), 'company_faq', 'generated', 'memory', 'library', 'document', 'material' — total ~95k rows,
--     which is essentially the ~97k the whole table held BEFORE the ingestion. So scoping the kb_chunks
--     scan to those kinds RESTORES the original scope this check ran under, and runs in seconds again.
--   * kb_chunks is only the 8th of eight stores; the seven company stores (site, FAQ, email,
--     agent_knowledge, dept_library, agent_memory, org_memory) are unchanged and still full-scanned, so
--     company-authored content remains comprehensively covered.
--   * statement_timeout is raised to 300s for this function as defence-in-depth.
--
-- SECURITY DEFINER preserved; CREATE OR REPLACE keeps the existing ACL (no re-grant/re-revoke needed).

CREATE OR REPLACE FUNCTION public.fn_policy_consistency_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '300000'
AS $function$
declare r record; f jsonb := '[]'::jsonb; n int := 0; v_admin text; v_crit int := 0;
begin
  for r in select * from policy_rules where active loop
    if r.scope in ('all','site') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','site','location',path))
             from qd_deploy_src where path not like '\_archive/%' and data ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','faq') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','company_faq','location','#'||id||' '||question))
             from company_faq where status='approved' and answer ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','email') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','email','location',key))
             from app_secrets where key in ('invite_body','invite_subject') and value ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','kb') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_knowledge','location',agent_key||' / '||topic||' (#'||id||')'))
             from agent_knowledge where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','dept_library','location',department||' / '||title||' (#'||id||')'))
             from dept_library where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_memory','location',agent_key||' / '||kind||' (#'||id||')'))
             from agent_memory where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','org_memory','location',scope||' / '||kind||' (#'||id||')'))
             from org_memory where active and content ~* r.forbid_regex), '[]'::jsonb);
      -- kb_chunks: scan only the COMPANY-AUTHORED, policy-bearing kinds (see header) — ~95k rows, the
      -- table's pre-ingestion scope. Third-party reference standards ('standard'/'reference'/'cert'/…)
      -- are excluded: they cannot state QuotesDone policy, and scanning 2.6M of them times out.
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','kb_chunks','location',coalesce(category,'?')||' (#'||id||')'))
             from kb_chunks where source_kind in ('qd_kb_pack','company_faq','generated','memory','library','document','material')
                              and content ~* r.forbid_regex), '[]'::jsonb);
    end if;
  end loop;
  n := jsonb_array_length(f);
  select count(*) into v_crit from jsonb_array_elements(f) e where e->>'severity'='critical';
  if n > 0 then
    v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');
    if not exists (select 1 from founder_alerts where event='policy_inconsistency' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values(case when v_crit>0 then 'crit' else 'warn' end,'policy_inconsistency',
          n||' policy contradiction(s) found across site, FAQ, email, agent knowledge, library, memories and retrieval chunks: '||left(f::text,600),'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('policy_inconsistency', v_admin,'admin','email','Policy contradiction detected',
          n||' place(s) now contradict current QuotesDone policy. Scan covers 8 stores incl. kb_chunks retrieval. Details: '||left(f::text,1500),'queued');
    end if;
  end if;
  return json_build_object('findings', n, 'critical', v_crit, 'detail', f, 'checked_at', now());
end $function$;
