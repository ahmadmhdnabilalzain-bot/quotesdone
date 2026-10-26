-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725200515   name: fn_rfq_board_fix
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_rfq_board(p_search text default '', p_limit int default 80, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb;
begin
  with base as (
    select i.id, coalesce(nullif(trim(i.category),''),'general') as category,
      coalesce(nullif(trim(i.emirate),''),'—') as emirate,
      left(coalesce(nullif(trim(i.summary),''), i.raw_input, ''),140) as summary,
      i.expected_value as value, nullif(btrim(i.budget),'') as budget, i.urgency, i.status, i.outcome, i.created_at,
      case lower(coalesce(i.pipeline_stage, i.status, ''))
        when 'won' then 'won' when 'revealed' then 'revealed' when 'quoted' then 'quoted' when 'matched' then 'matched'
        else (case when i.outcome='won' then 'won' else 'new' end) end as stage
    from inquiries i
    where coalesce(p_search,'')='' or i.category ilike '%'||p_search||'%' or i.summary ilike '%'||p_search||'%' or i.emirate ilike '%'||p_search||'%'
  ), ranked as (select *, row_number() over (partition by stage order by created_at desc, id desc) rn from base),
  sc as (select stage, count(*) c from base group by stage)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'stages',(select jsonb_agg(jsonb_build_object('key',s.key,'label',s.label,'count',coalesce((select c from sc where sc.stage=s.key),0),
      'cards',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'category',r.category,'emirate',r.emirate,'summary',r.summary,'value',r.value,'budget',r.budget,'urgency',r.urgency,'status',r.status) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
      order by s.ord)
      from (values ('new','New',1),('matched','Matched',2),('quoted','Quoted',3),('revealed','Revealed',4),('won','Won',5)) s(key,label,ord)),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'category',b.category,'emirate',b.emirate,'summary',b.summary,'value',b.value,'budget',b.budget,'urgency',b.urgency,'status',b.status,'stage',b.stage,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b)
  ) into out; return out;
end $$;
