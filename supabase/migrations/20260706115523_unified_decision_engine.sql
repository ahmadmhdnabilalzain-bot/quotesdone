-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115523   name: unified_decision_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ UNIFIED DECISION ENGINE + immutable decision_log ============
create table if not exists public.decision_log(
  id bigserial primary key,
  actor text, kind text not null, ctx jsonb,
  decision text, confidence numeric, reasons jsonb, sources jsonb, route_to text,
  created_at timestamptz default now());
create index if not exists idx_declog on public.decision_log(kind, created_at desc);
alter table public.decision_log enable row level security;
revoke all on public.decision_log from anon, authenticated;

-- append-only: block updates/deletes even for service role
create or replace function public.trg_declog_immutable() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin raise exception 'decision_log is append-only'; end $$;
drop trigger if exists declog_immutable on public.decision_log;
create trigger declog_immutable before update or delete on public.decision_log
  for each row execute function public.trg_declog_immutable();

-- central explainable decision dispatcher
create or replace function public.fn_decide(p_kind text, p_ctx jsonb, p_actor text default 'agent')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare res jsonb; conf numeric; reasons jsonb:='[]'; route text; decision text; sources jsonb:='[]';
begin
  if p_kind='escalate' then
    res := public.fn_should_escalate(p_ctx);
    decision := case when (res->>'escalate')::boolean then 'escalate' else 'proceed' end;
    reasons := res->'reasons'; route := res->>'route_to';
    conf := case when (res->>'escalate')::boolean then 0.9 else 0.8 end;
    sources := to_jsonb(array['decision_policy']);

  elsif p_kind='price' then
    res := public.fn_price_confidence(coalesce(p_ctx->>'category','default'), nullif(p_ctx->>'amount_aed','')::numeric);
    decision := 'priced'; conf := coalesce((res->>'confidence')::numeric, 0.5);
    reasons := jsonb_build_array(coalesce(res->>'band', 'price band computed')); sources := to_jsonb(array['price_confidence']);
    route := 'none';

  elsif p_kind='route_category' then
    route := public.fn_resolve_cat_agent(coalesce(p_ctx->>'category',''));
    decision := coalesce(route,'unmatched'); conf := case when route is null then 0.3 else 0.85 end;
    reasons := jsonb_build_array('mapped category "'||coalesce(p_ctx->>'category','')||'" to agent '||coalesce(route,'(none)'));
    sources := to_jsonb(array['category_agents']);

  elsif p_kind='invite' then
    -- rank approved suppliers for a category (+ optional emirate)
    with pool as (
      select id, company_name, coalesce(capability_score,0) cap, coalesce(app_rating,rating,0) rat, coalesce(rv_response_rate,0) resp
      from leads
      where coalesce(approval_status,'')='approved'
        and (coalesce(p_ctx->>'category','')='' or lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_ctx->>'category')||'%')
        and (coalesce(p_ctx->>'emirate','')='' or coalesce(p_ctx->>'emirate')= any(coalesce(service_emirates,array[emirate])))
      order by (coalesce(capability_score,0)*0.5 + coalesce(app_rating,rating,0)*8 + coalesce(rv_response_rate,0)*0.3) desc
      limit coalesce((p_ctx->>'n')::int, 5))
    select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'cap',cap,'rating',rat,'response',resp)) into res from pool;
    decision := 'invite_ranked'; conf := case when res is null then 0.2 when jsonb_array_length(res)>=3 then 0.8 else 0.5 end;
    reasons := jsonb_build_array('ranked by capability_score, rating and response rate');
    sources := to_jsonb(array['leads','supplier_capability','response_rate']);
    res := jsonb_build_object('suppliers', coalesce(res,'[]'));

  elsif p_kind='approve' then
    res := public.fn_should_escalate(p_ctx);
    if (res->>'escalate')::boolean then decision:='human_review'; conf:=0.9; reasons:=res->'reasons';
    else decision:='auto_approve'; conf:=0.85; reasons:=jsonb_build_array('within autonomous thresholds'); end if;
    route := res->>'route_to'; sources := to_jsonb(array['decision_policy']);

  else
    decision := 'unsupported_kind'; conf := 0; reasons := jsonb_build_array('no handler for kind '||p_kind); route:='Secretary';
  end if;

  insert into public.decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,p_kind,p_ctx,decision,conf,reasons,sources,route);

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,'route_to',route,'sources',sources,'detail',res);
end $$;

-- self-tests
select 'esc' t, public.fn_decide('escalate','{"amount_aed":25000,"moves_money":true}'::jsonb) r
union all select 'route', public.fn_decide('route_category','{"category":"security"}'::jsonb)
union all select 'invite', public.fn_decide('invite','{"category":"security","n":3}'::jsonb)
union all select 'approve', public.fn_decide('approve','{"confidence":0.9,"amount_aed":100}'::jsonb);
