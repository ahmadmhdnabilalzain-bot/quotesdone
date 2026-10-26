-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709090909   name: fn_knowledge_curator_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- de-dupe helper: one open knowledge task per signal
create or replace function public.kn_task(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('knowledge_curator','knowledge_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'knowledge',p_sig);
  end if;
end $$;
revoke all on function public.kn_task(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_knowledge_curator()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_health numeric; n_task int; n_appr int:=0; rec record;
begin
  select * into k from knowledge_kpis;
  v_health := round(coalesce(k.coverage_pct,0)*0.30 + coalesce(k.accuracy_pct,0)*0.25 + coalesce(k.freshness_pct,0)*0.25 + coalesce(k.usage_reach_pct,0)*0.20,1);
  insert into knowledge_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform kn_task('playbook_gap', (k.categories_total - k.cat_with_playbook) > 0, 'medium', 'Qualification playbook gaps',
    (k.categories_total - k.cat_with_playbook)||' of '||k.categories_total||' categories lack a qualification playbook. Generating them sharpens RFQ qualification quality.');
  perform kn_task('reg_gap', (k.categories_total - k.cat_with_regs) > 0, 'low', 'Regulation coverage gaps',
    (k.categories_total - k.cat_with_regs)||' categories have no mapped regulation. Add the governing UAE authority reference where one applies.');
  perform kn_task('stale_compliance', (k.compliance_active - k.compliance_fresh) > 0, 'low', 'Stale compliance sources',
    (k.compliance_active - k.compliance_fresh)||' compliance sources have not been re-checked in 45 days. A refresh keeps references current.');
  perform kn_task('low_accuracy', coalesce(k.flagged_revisions,0) > 0, 'medium', 'Knowledge flagged by validation',
    k.flagged_revisions||' knowledge revisions failed or were flagged by AI validation. Review before they can mislead the agents.');

  -- HIGH-STAKES APPROVAL QUEUE: pending regulations must be approved before publishing (hybrid gate)
  for rec in select id::text as rid, title, authority from regulations where approved_at is null loop
    if not exists (select 1 from agent_actions where kind='knowledge_approval' and detail->>'ref'=rec.rid and detail->>'kind'='regulation' and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('knowledge_curator','knowledge_approval','pending','high',
        'Approve regulation: '||coalesce(rec.title,'#'||rec.rid),
        'A new/updated high-stakes regulation ('||coalesce(rec.authority,'')||') is awaiting your approval before it publishes to the knowledge base. Approve to publish, or edit it first.',
        jsonb_build_object('kind','regulation','ref',rec.rid,'authority',rec.authority),
        'regulations', rec.rid);
      n_appr := n_appr + 1;
    end if;
  end loop;

  select count(*) into n_task from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'open_items',n_task,'new_approvals',n_appr);
end $fn$;
revoke all on function public.fn_knowledge_curator() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('knowledge_curator','Knowledge Curator','📚',true,
  'Maintains the company knowledge platform that powers every other agent. Collects and curates government regulations, engineering standards, manufacturers, datasheets, materials, brands, methods, playbooks and lessons learned; runs the validate → version → review → approve → publish lifecycle; and tracks coverage, accuracy, freshness and usage. High-stakes content (regulations, standards, compliance) is HELD for the founder''s approval before it publishes; low-stakes knowledge auto-publishes after AI validation. Flags coverage gaps, stale sources and validation failures — it never publishes high-stakes knowledge on its own.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('knowledge_curator_daily','10 3 * * *', $$select public.fn_knowledge_curator();$$);
