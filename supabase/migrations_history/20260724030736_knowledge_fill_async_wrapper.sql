-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724030736   name: knowledge_fill_async_wrapper
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- knowledge_fill executor wrapper: fast + honest. Reconciles the taxonomy inline (self-heal on every
-- run), then triggers the slow gap-generator in the BACKGROUND (net.http_post, its own 280s timeout,
-- logs to agent_runs) so the coordinator never blocks. Returns immediately.
create or replace function public.fn_org_exec_knowledge_fill(p_limit int default 5)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_gaps int; v_req bigint; v_recon jsonb;
begin
  -- self-heal the taxonomy every run (fast, synchronous)
  v_recon := public.fn_kb_reconcile();
  -- how many service categories still have zero knowledge chunks
  select count(*) into v_gaps from public.category_specs s
    where not exists (select 1 from public.kb_chunks k where k.category = s.category);
  -- trigger the (slow) generator in the background
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

-- point knowledge_fill at the fast rpc wrapper instead of the slow edge fn directly
update public.org_action_executor
  set kind='rpc', target='fn_org_exec_knowledge_fill', params='{}',
      note='Reconcile taxonomy + trigger background gap-fill (kb_autofill_gaps). Fast/non-blocking.'
  where action_class='knowledge_fill';
