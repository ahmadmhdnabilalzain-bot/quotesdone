-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727014255   name: event_dispatcher
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Layer-4 remediation, part 3: the event backbone was write-only.
-- company_event received rows and event_subscription declared 20
-- subscriptions, but no function in the database read either table.
-- Every scenario that expected "X is notified" failed for this reason.
-- ================================================================

create table if not exists public.event_delivery (
  id           bigserial primary key,
  event_id     bigint not null references public.company_event(id) on delete cascade,
  agent_key    text not null,
  event_type   text not null,
  delivered_at timestamptz not null default now(),
  task_id      bigint,
  unique (event_id, agent_key)
);
create index if not exists event_delivery_agent_idx on public.event_delivery (agent_key, delivered_at desc);

create or replace function public.fn_event_dispatch(p_lookback_minutes integer default 1440)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v_delivered integer := 0; v_tasks integer := 0; r record; v_task bigint; v_dept text;
begin
  for r in
    select e.id as event_id, e.event_type, e.entity_type, e.entity_id, e.actor, e.occurred_at, s.agent_key, s.reason
    from company_event e
    join event_subscription s on s.active and s.event_type = e.event_type
    left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
    where d.id is null
      and e.occurred_at > now() - make_interval(mins => greatest(p_lookback_minutes, 1))
      and s.agent_key <> coalesce(e.actor, '')          -- do not notify the actor of their own event
    order by e.id
  loop
    select department into v_dept from org_agents where agent_key = r.agent_key;
    v_task := null;

    -- A subscription that only files a notice is theatre. Give the subscriber real work.
    if v_dept is not null then
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, decided_by)
      values (v_dept,
              left(r.event_type || ' on ' || r.entity_type || ' ' || coalesce(r.entity_id,''), 200),
              format('Event %s (%s %s) raised by %s at %s. You subscribe to this because: %s. Act on it or close it with a reason.',
                     r.event_type, r.entity_type, coalesce(r.entity_id,'-'), coalesce(r.actor,'system'), r.occurred_at, coalesce(r.reason,'subscription')),
              'assigned', 'autonomous', false, 'analysis', 'fn_event_dispatch')
      returning id into v_task;
      v_tasks := v_tasks + 1;
    end if;

    insert into event_delivery (event_id, agent_key, event_type, task_id)
    values (r.event_id, r.agent_key, r.event_type, v_task)
    on conflict do nothing;
    v_delivered := v_delivered + 1;
  end loop;

  return jsonb_build_object('delivered', v_delivered, 'tasks_created', v_tasks,
                            'lookback_minutes', p_lookback_minutes);
end; $fn$;

revoke execute on function public.fn_event_dispatch(integer) from anon, authenticated, public;

create or replace view public.v_event_backbone as
select s.event_type,
       count(distinct s.agent_key)                                   as subscribers,
       (select count(*) from company_event e where e.event_type = s.event_type) as events_ever,
       (select count(*) from company_event e where e.event_type = s.event_type
          and e.occurred_at > now() - interval '24 hours')           as events_24h,
       (select count(*) from event_delivery d where d.event_type = s.event_type) as deliveries,
       case
         when (select count(*) from company_event e where e.event_type = s.event_type) = 0 then 'NO_EVENTS_EVER'
         when (select count(*) from event_delivery d where d.event_type = s.event_type) = 0 then 'UNDELIVERED'
         else 'LIVE'
       end as state
from event_subscription s
where s.active
group by s.event_type
order by 1;

insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department)
values ('event_dispatch','rpc','fn_event_dispatch','{}'::jsonb, true,
        'Turns company_event rows into real work for the agents that subscribe to them. Without this the event backbone is write-only.', false, 'it')
on conflict do nothing;

alter table public.event_delivery enable row level security;
