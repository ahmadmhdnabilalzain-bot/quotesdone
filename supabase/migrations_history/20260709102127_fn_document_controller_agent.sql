-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709102127   name: fn_document_controller_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.doc_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='doc_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('document_controller','doc_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'documents',p_sig);
  end if;
end $$;
revoke all on function public.doc_rec(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_document_controller()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_health numeric; v_ret numeric; v_backup numeric; n int;
begin
  select * into k from document_kpis;
  v_ret := round(100.0*(k.total_documents - coalesce(k.past_retention,0))/nullif(k.total_documents,0),1);
  v_backup := case when coalesce(k.days_since_backup,999) <= 10 then 100 when coalesce(k.days_since_backup,999) <= 20 then 60 else 20 end;
  v_health := round(coalesce(k.ocr_coverage_pct,100)*0.30 + coalesce(v_ret,100)*0.35 + v_backup*0.20 + greatest(0,100-coalesce(k.oversized,0)*5)*0.15,1);

  insert into document_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('doc_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- recommendations (founder-visible; the Controller NEVER deletes a document on its own)
  perform doc_rec('past_retention', coalesce(k.past_retention,0) > 0, 'medium', 'Documents past retention period',
    k.past_retention||' document(s) are older than their retention class. Review for archival or deletion — the Controller flags only and never deletes on its own.');
  perform doc_rec('ocr_backlog', coalesce(k.ocr_backlog,0) > 0, 'low', 'Documents pending OCR/processing',
    k.ocr_backlog||' registered document(s) are not fully processed/extracted. Re-run the doc processing pipeline.');
  perform doc_rec('backup_stale', coalesce(k.days_since_backup,999) > 10, 'high', 'Backup may be stale',
    'The last backup to the backups bucket was '||coalesce(k.days_since_backup::text,'never')||' day(s) ago. Confirm the weekly Dropbox backup job is running.');
  perform doc_rec('oversized', coalesce(k.oversized,0) > 0, 'low', 'Oversized files',
    k.oversized||' file(s) exceed 30MB. Consider compressing or archiving to control storage cost.');

  select count(*) into n from agent_actions where agent='document_controller' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'doc_health',v_health,'kpis',to_jsonb(k),'open_tasks',n);
end $fn$;
revoke all on function public.fn_document_controller() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('document_controller','Document Controller','📁',true,
  'Manages every company document across all storage buckets and Dropbox. Maintains the inventory and metadata, enforces naming and versioning, tracks approvals, OCR/extraction and retention classes (tax 7y, compliance, legal permanent, operational), monitors backups and archives, and flags documents past retention, OCR backlogs, oversized files and stale backups. It organises, indexes and recommends — it NEVER deletes a document or moves it out of retention on its own; disposal is founder-approved.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('document_controller_daily','25 4 * * *', $$select public.fn_document_controller();$$);
