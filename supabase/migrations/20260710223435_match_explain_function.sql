-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710223435   name: match_explain_function
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_match_explain(
  query_embedding vector, match_count integer default 10,
  p_emirate text default null, p_role text default null, p_product text default null, p_min_rating numeric default null)
returns table(id bigint, company_name text, emirate text, business_role text, rating numeric,
  similarity double precision, perf_boost numeric, claimed_boost numeric, approved_boost numeric,
  final_score double precision, reason text)
language sql stable set search_path to 'public','pg_temp' as $$
  select l.id, l.company_name, l.emirate, l.business_role, l.rating,
    1-(l.embedding <=> query_embedding) as similarity,
    round((0.05*coalesce(sp.perf_score,0))::numeric,4) as perf_boost,
    (case when l.claimed then 0.03 else 0 end)::numeric as claimed_boost,
    (case when l.approval_status='approved' then 0.02 else 0 end)::numeric as approved_boost,
    ( (1-(l.embedding <=> query_embedding))
      + 0.05*coalesce(sp.perf_score,0)
      + case when l.claimed then 0.03 else 0 end
      + case when l.approval_status='approved' then 0.02 else 0 end ) as final_score,
    concat_ws('; ',
      'semantic '||round((1-(l.embedding <=> query_embedding))::numeric,3),
      case when coalesce(sp.perf_score,0)>0 then 'performance +'||round((0.05*sp.perf_score)::numeric,3) else null end,
      case when l.claimed then 'claimed +0.03' else null end,
      case when l.approval_status='approved' then 'approved +0.02' else null end
    ) as reason
  from public.leads l
  left join public.supplier_perf sp on sp.supplier_id=l.id
  where l.embedding is not null
    and coalesce(l.matching_blocked,false)=false
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role is null or l.business_role=p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating>=p_min_rating)
  order by final_score desc
  limit match_count;
$$;
revoke all on function public.fn_match_explain(vector,integer,text,text,text,numeric) from anon, authenticated;
