-- Phase A (agent network): one read-only window onto the whole company for AI employees.
-- Routes a topic to the existing fn_ws_* workspace layer (extend/connect, no replacement).
-- Consumed by secretary_act's query_platform tool and available to any agent via service_role.
create or replace function public.fn_query_platform(p_topic text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v jsonb;
begin
  case lower(coalesce(p_topic,''))
    when 'topics' then
      v := jsonb_build_object('topics', jsonb_build_array(
        'knowledge','agents','agent_ops','ai','analytics','company','customers','documents',
        'ea','exec','finance','fraud','governance','marketing','marketplace','operations',
        'refunds','reports','strategy','suppliers','supplier_360','customer_360','rfq_360','funnel'));
    when 'knowledge'   then v := to_jsonb(fn_ws_knowledge());
    when 'agents'      then v := to_jsonb(fn_ws_agents());
    when 'agent_ops'   then v := to_jsonb(fn_ws_agent_ops(coalesce(p_args->>'agent','')));
    when 'ai'          then v := to_jsonb(fn_ws_ai());
    when 'analytics'   then v := to_jsonb(fn_ws_analytics());
    when 'company'     then v := to_jsonb(fn_ws_company());
    when 'customers'   then v := to_jsonb(fn_ws_customers());
    when 'documents'   then v := to_jsonb(fn_ws_documents());
    when 'ea'          then v := to_jsonb(fn_ws_ea());
    when 'exec'        then v := to_jsonb(fn_ws_exec());
    when 'finance'     then v := to_jsonb(fn_ws_finance());
    when 'fraud'       then v := to_jsonb(fn_ws_fraud());
    when 'governance'  then v := to_jsonb(fn_ws_governance());
    when 'marketing'   then v := to_jsonb(fn_ws_marketing());
    when 'marketplace' then v := to_jsonb(fn_ws_marketplace());
    when 'operations'  then v := to_jsonb(fn_ws_operations());
    when 'refunds'     then v := to_jsonb(fn_ws_refunds());
    when 'reports'     then v := to_jsonb(fn_ws_reports());
    when 'strategy'    then v := to_jsonb(fn_ws_strategy());
    when 'suppliers'   then v := to_jsonb(fn_ws_suppliers(coalesce(p_args,'{}'::jsonb)));
    when 'supplier_360' then v := to_jsonb(fn_ws_supplier_360((p_args->>'id')::bigint));
    when 'customer_360' then v := to_jsonb(fn_ws_customer_360((p_args->>'id')::uuid));
    when 'rfq_360'      then v := to_jsonb(fn_ws_rfq_360((p_args->>'id')::uuid));
    when 'funnel'       then v := to_jsonb(funnel_metrics(coalesce((p_args->>'days')::int,30)));
    else v := jsonb_build_object('error','unknown_topic','hint','call with topic=topics to list valid topics');
  end case;
  return coalesce(v,'{}'::jsonb);
exception when others then
  return jsonb_build_object('error','query_failed','topic',p_topic,'detail',sqlerrm);
end $$;

revoke execute on function public.fn_query_platform(text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_query_platform(text, jsonb) to service_role;
