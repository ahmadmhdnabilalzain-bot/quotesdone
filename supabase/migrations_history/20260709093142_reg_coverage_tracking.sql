-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709093142   name: reg_coverage_tracking
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.reg_coverage as
select
  count(*) filter (where copyright='free') as free_codes,
  count(*) filter (where copyright='free' and status='indexed') as indexed,
  count(*) filter (where copyright='free' and status<>'indexed') as missing,
  count(*) filter (where priority=1 and copyright='free') as critical_total,
  count(*) filter (where priority=1 and copyright='free' and status='indexed') as critical_indexed,
  count(*) filter (where copyright='copyrighted') as reference_only,
  round(100.0*count(*) filter (where copyright='free' and status='indexed')/nullif(count(*) filter (where copyright='free'),0),1) as coverage_pct
from reg_catalog;
revoke all on public.reg_coverage from anon, authenticated;

-- add regulatory-coverage tasks to the Curator
create or replace function public.fn_knowledge_curator()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_health numeric; n_task int; n_appr int:=0; rec record; rc record;
begin
  select * into k from knowledge_kpis;
  select * into rc from reg_coverage;
  v_health := round(coalesce(k.coverage_pct,0)*0.30 + coalesce(k.accuracy_pct,0)*0.25 + coalesce(k.freshness_pct,0)*0.25 + coalesce(k.usage_reach_pct,0)*0.20,1);
  insert into knowledge_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health,'reg_coverage',to_jsonb(rc)))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform kn_task('playbook_gap', (k.categories_total - k.cat_with_playbook) > 0, 'medium', 'Qualification playbook gaps',
    (k.categories_total - k.cat_with_playbook)||' of '||k.categories_total||' categories lack a qualification playbook. Generating them sharpens RFQ qualification quality.');
  perform kn_task('stale_compliance', (k.compliance_active - k.compliance_fresh) > 0, 'low', 'Stale compliance sources',
    (k.compliance_active - k.compliance_fresh)||' compliance sources have not been re-checked in 45 days.');
  perform kn_task('low_accuracy', coalesce(k.flagged_revisions,0) > 0, 'medium', 'Knowledge flagged by validation',
    k.flagged_revisions||' knowledge revisions failed or were flagged by AI validation. Review before they can mislead the agents.');
  perform kn_task('reg_coverage', rc.missing > 0, 'high', 'UAE codes not yet indexed as full documents',
    'Regulatory library is '||rc.coverage_pct||'% complete ('||rc.indexed||'/'||rc.free_codes||' free-published codes fully indexed; '||rc.critical_indexed||'/'||rc.critical_total||' critical). Still missing (critical first): '
    ||coalesce((select string_agg(authority||' — '||code_name, '; ') from (select authority,code_name from reg_catalog where copyright='free' and status<>'indexed' order by priority, authority limit 10) g),'none')
    ||'. Many are portal/viewer-gated or scanned — supply official full PDFs (or a licensed copy) to index them.');

  for rec in select id::text as rid, title, authority from regulations where approved_at is null loop
    if not exists (select 1 from agent_actions where kind='knowledge_approval' and detail->>'ref'=rec.rid and detail->>'kind'='regulation' and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('knowledge_curator','knowledge_approval','pending','high',
        'Approve regulation: '||coalesce(rec.title,'#'||rec.rid),
        'A new/updated high-stakes regulation ('||coalesce(rec.authority,'')||') is awaiting your approval before it publishes to the knowledge base.',
        jsonb_build_object('kind','regulation','ref',rec.rid,'authority',rec.authority),'regulations', rec.rid);
      n_appr := n_appr + 1;
    end if;
  end loop;

  select count(*) into n_task from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'reg_coverage',to_jsonb(rc),'open_items',n_task,'new_approvals',n_appr);
end $fn$;
revoke all on function public.fn_knowledge_curator() from anon, authenticated, public;
