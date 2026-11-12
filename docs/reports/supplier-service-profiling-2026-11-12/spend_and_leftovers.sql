with mine as (select replace(run_tag,'qd_run:','') tag, note, cap_usd, models_allowed, ended_at from rehearsal_window where opened_by like 'sales_engineer services analysis%')
select json_build_object(
 'windows', (select json_agg(json_build_object('tag',m.tag,'stage',replace(m.note,'supplier service profiling: hard-profile set, ',''),'cap',m.cap_usd,'models_allowed',m.models_allowed,'closed',m.ended_at is not null,
     'calls',(select count(*) from ai_cost_log c where c.e2e_run_tag=m.tag),'failed',(select count(*) from ai_cost_log c where c.e2e_run_tag=m.tag and not c.ok),
     'usd',(select round(coalesce(sum(cost_aed),0)::numeric/3.6725,4) from ai_cost_log c where c.e2e_run_tag=m.tag))) from mine m),
 'total_usd', (select round(coalesce(sum(c.cost_aed),0)::numeric/3.6725,4) from ai_cost_log c where c.e2e_run_tag in (select tag from mine)),
 'total_calls', (select count(*) from ai_cost_log c where c.e2e_run_tag in (select tag from mine)),
 'open_windows_mine', (select count(*) from mine where ended_at is null or models_allowed),
 'leftover_leads', (select count(*) from leads where company_name like 'ZZ DEMO services analysis subject%'),
 'leftover_leads_by_tag_email', (select count(*) from leads l where exists (select 1 from mine m where l.claimed_by like 'qd-'||m.tag||'-%' or l.email like 'qd-'||m.tag||'-%')),
 'leftover_caps', (select count(*) from supplier_capabilities sc join leads l on l.id=sc.supplier_id where l.company_name like 'ZZ DEMO services analysis subject%'),
 'leftover_actions', (select count(*) from agent_actions a where a.detail::text like '%zz-demo-hard/%'),
 'leftover_storage', (select count(*) from storage.objects o where o.name like '%zz-demo-hard%')
) j;
