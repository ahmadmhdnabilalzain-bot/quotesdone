-- Blueprint 6: each OS holds INDEPENDENT knowledge; Leadership does not duplicate Finance,
-- it queries it. When I staffed the three new systems I copied strategy_director's bindings
-- to all ten new hires, which is exactly the duplication the blueprint forbids. Correcting it.

create table if not exists public.os_knowledge_domain (
  os_key     text not null references operating_system(os_key),
  domain_key text not null,
  ownership  text not null default 'owns' check (ownership in ('owns','queries')),
  primary key (os_key, domain_key)
);
alter table public.os_knowledge_domain enable row level security;
comment on table public.os_knowledge_domain is
  'Which OS OWNS a knowledge domain and which merely QUERY it. Prevents ten systems each keeping their own copy of UAE VAT.';

-- each OS owns the domains that match its responsibilities; everything else it queries
insert into os_knowledge_domain (os_key, domain_key, ownership)
select r.os_key, d.domain_key, 'owns'
from knowledge_domain d
join os_responsibility r on d.domain_key ilike '%'||replace(r.responsibility,'_','%')||'%'
on conflict do nothing;

-- Leadership and Evolution query everything they do not own, rather than duplicating it
insert into os_knowledge_domain (os_key, domain_key, ownership)
select o.os_key, d.domain_key, 'queries'
from operating_system o cross join knowledge_domain d
where o.os_key in ('leadership','evolution','intelligence')
  and not exists (select 1 from os_knowledge_domain k where k.os_key=o.os_key and k.domain_key=d.domain_key)
on conflict do nothing;

-- Blueprint 17: every OS asks the same five questions, weekly, about itself.
create or replace function public.fn_os_improve()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n int := 0; q text; qs text[];
  v_failed int; v_slow int; v_cost numeric; v_manual int; v_dead int;
begin
  for r in select o.os_key, o.name, o.owner_agent,
                  coalesce((select department from org_agents a where a.agent_key=o.owner_agent),'exec') as dept
           from operating_system o where o.active
  loop
    qs := array[]::text[];

    select count(*) into v_failed from agent_runs ar
      join os_department od on od.os_key = r.os_key
      join org_agents a on a.department = od.dept_key and a.agent_key = ar.agent
     where ar.status='error' and ar.started_at > now()-interval '7 days';

    select count(*) into v_slow from org_tasks t join os_department od on od.dept_key=t.dept_key
     where od.os_key=r.os_key and t.status<>'done' and t.created_at < now()-interval '14 days';

    select coalesce(sum(c.cost_aed),0) into v_cost from ai_cost_log c
      join os_department od on od.dept_key = c.dept_key
     where od.os_key = r.os_key and c.occurred_at > now()-interval '7 days';

    select count(*) into v_manual from org_tasks t join os_department od on od.dept_key=t.dept_key
     where od.os_key=r.os_key and t.needs_founder;

    select count(*) into v_dead from workflow w where w.os_key=r.os_key and not w.active;

    if v_failed > 0 then qs := array_append(qs,'What failed? '||v_failed||' agent run(s) errored this week in '||r.name||'. Root cause each one.'); end if;
    if v_slow   > 0 then qs := array_append(qs,'What slowed us? '||v_slow||' task(s) have been open over 14 days in '||r.name||'. Why has none closed?'); end if;
    if v_cost   > 0 then qs := array_append(qs,'What cost too much? '||r.name||' spent '||round(v_cost,2)||' AED on AI this week. Which calls could a cheaper model have served?'); end if;
    if v_manual > 0 then qs := array_append(qs,'What can be automated? '||v_manual||' task(s) in '||r.name||' still need the founder. Which of those is a rule rather than a judgement?'); end if;
    if v_dead   > 0 then qs := array_append(qs,'What should be deleted? '||v_dead||' inactive workflow(s) remain in '||r.name||'. Retire or revive them.'); end if;

    foreach q in array qs loop
      insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
      select r.dept, left(r.name||' improvement: '||q, 120),
             q||E'\n\nOwner: '||coalesce(r.owner_agent,'unassigned')||'. Answer with evidence. If the answer implies a change, open it through fn_outcome_open so it is graded against a baseline.',
             'proposed','advisory',false,'recommend'
      where not exists (select 1 from org_tasks t where t.title = left(r.name||' improvement: '||q,120) and t.status<>'done');
      if found then n := n+1; end if;
    end loop;
  end loop;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('os_improve',now(),now(),'ok',jsonb_build_object('questions',n),
    'Continuous improvement: '||n||' question(s) raised across the ten operating systems.');
  return jsonb_build_object('questions',n);
end $fn$;

revoke execute on function public.fn_os_improve() from public, anon, authenticated;