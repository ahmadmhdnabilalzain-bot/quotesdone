-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725193552   name: fn_suppliers_board
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_suppliers_board(p_search text default '', p_sector text default '', p_limit int default 60, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb;
begin
  with base as (
    select l.id, l.company_name,
      coalesce(nullif(trim(l.sector),''),'general') as sector,
      coalesce(nullif(trim(l.emirate),''),'—') as emirate,
      coalesce(l.rating, l.app_rating) as rating,
      l.verified, (l.approved_at is not null) as approved, l.banned,
      (l.invited_at is not null) as invited, l.claimed, (l.registration_submitted_at is not null) as registered,
      coalesce(l.capability_score,0) as capability_score, l.created_at,
      case when l.approved_at is not null then 'approved' when l.verified then 'verified'
           when l.registration_submitted_at is not null then 'registered' when l.invited_at is not null then 'invited'
           when l.contacted then 'contacted' else 'sourced' end as stage
    from leads l
    where (coalesce(p_search,'') = '' or l.company_name ilike '%'||p_search||'%' or l.sector ilike '%'||p_search||'%' or l.emirate ilike '%'||p_search||'%')
      and (coalesce(p_sector,'') = '' or l.sector = p_sector)
  ),
  ranked as (select *, row_number() over (partition by stage order by created_at desc, id desc) as rn from base),
  stagecounts as (select stage, count(*) as c from base group by stage)
  select jsonb_build_object(
    'total', (select count(*) from base),
    'stages', (
      select jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label,
        'count', coalesce((select c from stagecounts sc where sc.stage=s.key),0),
        'cards', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'company_name',r.company_name,'sector',r.sector,'emirate',r.emirate,'rating',r.rating,'verified',r.verified,'approved',r.approved,'banned',r.banned,'capability_score',r.capability_score) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
        order by s.ord)
      from (values ('sourced','Sourced',1),('contacted','Contacted',2),('invited','Invited',3),('registered','Registered',4),('verified','Verified',5),('approved','Approved',6)) s(key,label,ord)
    ),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'company_name',b.company_name,'sector',b.sector,'emirate',b.emirate,'rating',b.rating,'verified',b.verified,'approved',b.approved,'banned',b.banned,'invited',b.invited,'registered',b.registered,'stage',b.stage,'capability_score',b.capability_score,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b),
    'sectors', (select coalesce(jsonb_agg(jsonb_build_object('label',x.sector,'n',x.n) order by x.n desc),'[]'::jsonb) from (select sector, count(*) n from base group by sector order by count(*) desc limit 12) x)
  ) into out;
  return out;
end $$;
