-- ============================================================================
-- KNOWLEDGE department: self-healing taxonomy reconciliation + real gap-fill executor.
-- Wires knowledge_fill (supervised) onto the action-executor registry.
-- ============================================================================

-- fn_kb_reconcile: idempotent, safe normalizer of kb_chunks.category so knowledge stays visible to
-- category-filtered retrieval. Runs daily (cron kb_reconcile_daily @ 03:05) AND inline on every
-- knowledge_fill, so the taxonomy never drifts. Only provably-safe moves:
--   1. strip 'cat:' prefix where the bare slug is a real category (0 orphans created)
--   2. apply ONLY 1:1 curated aliases (skips 1:many composites like combined-mep)
-- Deliberately leaves truly-uncategorized chunks as global knowledge (still semantically retrievable).
create or replace function public.fn_kb_reconcile()
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_stripped int:=0; v_aliased int:=0; v_uncat int; v_noncanon int;
begin
  with upd as (
    update public.kb_chunks c set category = substring(c.category from 5)
    where c.category like 'cat:%'
      and ( substring(c.category from 5) in (select slug from public.category_agents where active)
         or substring(c.category from 5) in (select category from public.category_specs) )
    returning 1
  ) select count(*) into v_stripped from upd;

  with oneone as (
    select category, min(maps_to) as target
    from public.kb_category_aliases group by category having count(distinct maps_to)=1
  ), upd2 as (
    update public.kb_chunks c set category = o.target
    from oneone o where c.category = o.category and c.category <> o.target
    returning 1
  ) select count(*) into v_aliased from upd2;

  select count(*) into v_uncat from public.kb_chunks where category is null or category='';
  select count(distinct category) into v_noncanon from public.kb_chunks
    where category is not null and category<>'' and category not like 'cat:%'
      and category not in (select slug from public.category_agents where active)
      and category not in (select category from public.category_specs);

  return jsonb_build_object('cat_prefix_stripped',v_stripped,'alias_remapped',v_aliased,
    'uncategorized_left',v_uncat,'noncanonical_categories_left',v_noncanon,
    'note','Normalized kb_chunks categories: stripped '||v_stripped||' cat: prefix(es), remapped '||v_aliased||' via curated 1:1 aliases. '||v_uncat||' chunk(s) remain uncategorized (global knowledge — still semantically retrievable).');
end $function$;
revoke execute on function public.fn_kb_reconcile() from public, anon, authenticated;
grant execute on function public.fn_kb_reconcile() to service_role;

-- knowledge_fill executor wrapper: fast + honest. Reconciles the taxonomy inline (self-heal on every
-- run), then triggers the slow gap-generator in the BACKGROUND (kb_autofill_gaps via net.http_post, its
-- own 280s timeout, logs to agent_runs) so the coordinator never blocks. Returns immediately.
create or replace function public.fn_org_exec_knowledge_fill(p_limit int default 5)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_gaps int; v_req bigint; v_recon jsonb;
begin
  v_recon := public.fn_kb_reconcile();
  select count(*) into v_gaps from public.category_specs s
    where not exists (select 1 from public.kb_chunks k where k.category = s.category);
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_autofill_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from public.app_secrets where key='inbound_secret'),'limit',greatest(1,least(coalesce(p_limit,5),5))),
    timeout_milliseconds:=280000
  ) into v_req;
  return jsonb_build_object('empty_categories', v_gaps, 'autofill_triggered', true, 'reconcile', v_recon,
    'note', case when v_gaps=0 then 'Knowledge base complete: 0 empty categories. Taxonomy reconciled ('||coalesce(v_recon->>'cat_prefix_stripped','0')||' prefixes stripped, '||coalesce(v_recon->>'alias_remapped','0')||' aliased).'
                 else 'Triggered background gap-fill for '||v_gaps||' empty category(ies); taxonomy reconciled. Generation runs in the background and logs to agent_runs.' end);
end $function$;
revoke execute on function public.fn_org_exec_knowledge_fill(int) from public, anon, authenticated;
grant execute on function public.fn_org_exec_knowledge_fill(int) to service_role;

-- Register the Knowledge executor.
insert into public.org_action_executor(action_class, kind, target, params, note) values
('knowledge_fill','rpc','fn_org_exec_knowledge_fill','{}','Reconcile taxonomy + trigger background gap-fill (kb_autofill_gaps). Fast/non-blocking.')
on conflict (action_class) do update set kind=excluded.kind, target=excluded.target, params=excluded.params, note=excluded.note, active=true;

insert into public.org_memory(scope,kind,content,source) values
('knowledge','policy','Knowledge executes real work: knowledge_fill (supervised) reconciles the taxonomy then triggers background generation for categories with zero chunks (kb_autofill_gaps). fn_kb_reconcile also runs daily to self-heal the taxonomy (strip cat: prefixes, apply 1:1 aliases). Truly-uncategorized chunks are kept as global knowledge, still semantically retrievable.','founder_directive')
on conflict do nothing;

-- Cron: daily self-healing reconciliation.
-- select cron.schedule('kb_reconcile_daily', '5 3 * * *', 'select public.fn_kb_reconcile();');