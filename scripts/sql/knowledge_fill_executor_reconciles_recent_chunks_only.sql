-- THE knowledge_fill EXECUTOR RAN A FULL-TABLE RECONCILE ON EVERY WORKFLOW STEP (4 Sep 2026).
--
-- fn_org_exec_knowledge_fill is the rpc executor behind incident_response steps 6 and 7 ("write the
-- lesson", "update the runbook"). Its first line called fn_kb_reconcile(), whose prefix-strip UPDATE
-- (`category like 'cat:%'`) and its `count(distinct category) ... not in (...)` scan the whole of
-- kb_chunks — 2,649,590 rows, 8.4 GB, and no index a LIKE prefix can use. MEASURED: cron job 266
-- (fn_action_invoke_rpc) failed "canceling statement due to statement timeout" on every 5-minute tick
-- from 06:15 UTC, and because the invoker orders queued rows by created_at the slow row at the head
-- blocked every rpc executor behind it (knowledge_fill, self_review, metric_alerts, bi_snapshot).
-- Seven incident_response runs sat at step 6/7 for this reason alone.
--
-- Reconciling the taxonomy of chunks created in the last 24 hours is the executor's honest scope
-- (older chunks were reconciled by the runs that saw them), and it is index-backed: measured in an
-- aborted transaction, the bounded update + the category-gap count take 4 ms + 5 ms + 2 ms. The
-- whole-table counts are reported as not measured on this path rather than estimated. fn_kb_reconcile
-- itself is untouched (it is the knowledge lane's maintenance routine, not this executor's).
--
--   node scripts/apply_sql.mjs scripts/sql/knowledge_fill_executor_reconciles_recent_chunks_only.sql --apply --ddl

begin;

create or replace function public.fn_org_exec_knowledge_fill(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_gaps int; v_req bigint; v_recon jsonb; v_stripped int := 0; v_aliased int := 0;
begin
  -- self-heal the taxonomy of RECENT chunks every run (index-backed; the whole table is not this
  -- executor's job — see the header)
  with upd as (
    update public.kb_chunks c set category = substring(c.category from 5)
    where c.created_at > now() - interval '24 hours'
      and c.category like 'cat:%'
      and ( substring(c.category from 5) in (select slug from public.category_agents where active)
         or substring(c.category from 5) in (select category from public.category_specs) )
    returning 1
  ) select count(*) into v_stripped from upd;

  with oneone as (
    select category, min(maps_to) as target
    from public.kb_category_aliases group by category having count(distinct maps_to)=1
  ), upd2 as (
    update public.kb_chunks c set category = o.target
    from oneone o
    where c.created_at > now() - interval '24 hours'
      and c.category = o.category and c.category <> o.target
    returning 1
  ) select count(*) into v_aliased from upd2;

  v_recon := jsonb_build_object('cat_prefix_stripped', v_stripped, 'alias_remapped', v_aliased,
               'scope', 'chunks created in the last 24 hours',
               'note', 'whole-table uncategorised/non-canonical counts are not measured on the executor path; run fn_kb_reconcile() for those');

  -- how many service categories still have zero knowledge chunks (kb_chunks_cat_id_idx)
  select count(*) into v_gaps from public.category_specs s
    where not exists (select 1 from public.kb_chunks k where k.category = s.category);
  -- trigger the (slow) generator in the background
  select net.http_post(
    url:='https://' || public.qd_project_ref() || '.supabase.co/functions/v1/kb_autofill_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from public.app_secrets where key='cred_db_internal'),'limit',greatest(1,least(coalesce(p_limit,5),5))),
    timeout_milliseconds:=280000
  ) into v_req;
  return jsonb_build_object('empty_categories', v_gaps, 'autofill_triggered', true, 'reconcile', v_recon,
    'used_llm', false,
    'note', case when v_gaps=0 then 'Knowledge base complete: 0 empty categories. Recent-chunk taxonomy reconciled ('||v_stripped||' prefixes stripped, '||v_aliased||' aliased).'
                 else 'Triggered background gap-fill for '||v_gaps||' empty category(ies); recent-chunk taxonomy reconciled. Generation runs in the background and logs to agent_runs.' end);
end $function$;

commit;
