-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725200438   name: rfq_customers_agents_boards
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- RFQ pipeline board
create or replace function public.fn_rfq_board(p_search text default '', p_limit int default 80, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb;
begin
  with base as (
    select i.id, coalesce(nullif(trim(i.category),''),'general') as category,
      coalesce(nullif(trim(i.emirate),''),'—') as emirate,
      left(coalesce(nullif(trim(i.summary),''), i.raw_input, ''),140) as summary,
      coalesce(i.expected_value, i.budget) as value, i.urgency, i.status, i.outcome, i.created_at,
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
      'cards',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'category',r.category,'emirate',r.emirate,'summary',r.summary,'value',r.value,'urgency',r.urgency,'status',r.status) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
      order by s.ord)
      from (values ('new','New',1),('matched','Matched',2),('quoted','Quoted',3),('revealed','Revealed',4),('won','Won',5)) s(key,label,ord)),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'category',b.category,'emirate',b.emirate,'summary',b.summary,'value',b.value,'urgency',b.urgency,'status',b.status,'stage',b.stage,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b)
  ) into out; return out;
end $$;

-- Customers board
create or replace function public.fn_customers_board(p_search text default '', p_limit int default 80, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb;
begin
  with base as (
    select c.id::text as id, coalesce(nullif(trim(c.full_name),''),'(unnamed)') as full_name, c.email, c.phone,
      coalesce(c.email_verified,false) as email_verified, coalesce(c.phone_verified,false) as phone_verified, c.banned, c.created_at,
      case when c.banned then 'banned' when coalesce(c.email_verified,false) or coalesce(c.phone_verified,false) then 'verified' else 'new' end as stage
    from customers c
    where coalesce(p_search,'')='' or c.full_name ilike '%'||p_search||'%' or c.email ilike '%'||p_search||'%' or c.phone ilike '%'||p_search||'%'
  ), ranked as (select *, row_number() over (partition by stage order by created_at desc) rn from base),
  sc as (select stage, count(*) c from base group by stage)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'stages',(select jsonb_agg(jsonb_build_object('key',s.key,'label',s.label,'count',coalesce((select c from sc where sc.stage=s.key),0),
      'cards',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'full_name',r.full_name,'email',r.email,'phone',r.phone,'email_verified',r.email_verified,'banned',r.banned) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
      order by s.ord)
      from (values ('new','New',1),('verified','Verified',2),('banned','Banned',3)) s(key,label,ord)),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'full_name',b.full_name,'email',b.email,'phone',b.phone,'email_verified',b.email_verified,'phone_verified',b.phone_verified,'banned',b.banned,'stage',b.stage,'created_at',b.created_at) order by b.created_at desc),'[]'::jsonb)
             from (select * from base order by created_at desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b)
  ) into out; return out;
end $$;

-- Agents board (real data): org_agents joined to 24h run stats, grouped by department
create or replace function public.fn_agents_board()
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb;
begin
  with runs as (
    select agent, count(*) filter (where started_at > now() - interval '24 hours') as runs24,
           count(*) filter (where started_at > now() - interval '24 hours' and status in ('error','failed')) as fails24,
           max(started_at) as last_run, (array_agg(status order by started_at desc))[1] as last_status
    from agent_runs group by agent
  ), base as (
    select a.agent_key, coalesce(nullif(trim(a.department),''),'General') as department, a.role, a.kind, coalesce(a.active,true) as active,
      coalesce(r.runs24,0) as runs24, coalesce(r.fails24,0) as fails24, r.last_run, r.last_status
    from org_agents a left join runs r on r.agent = a.agent_key
  ), dc as (select department, count(*) c, sum(runs24) rs from base group by department)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'runs24',(select coalesce(sum(runs24),0) from base),
    'departments',(select coalesce(jsonb_agg(jsonb_build_object('key',d.department,'label',d.department,'count',d.c,'runs',d.rs,
        'cards',(select jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key) from base b where b.department=d.department))
        order by d.rs desc nulls last, d.department),'[]'::jsonb) from dc d),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'department',b.department,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key),'[]'::jsonb) from base b)
  ) into out; return out;
end $$;
