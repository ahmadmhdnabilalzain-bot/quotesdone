-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727014358   name: connect_event_emitters_to_subscriptions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- The backbone was disconnected at BOTH ends: nothing emitted the 16
-- subscribed types, and nothing subscribed to the 2 emitted types.
-- ================================================================

-- ---- 1. subscribe to what is actually emitted ----
insert into public.event_subscription (agent_key, event_type, reason, active) values
('marketing','content.published','Owns published output and is accountable for what went out.', true),
('brief','content.published','Chief of Staff keeps a running picture of what the company has said publicly.', true)
on conflict do nothing;

-- review.step is deliberately NOT subscribed: it is an audit stream, one row per hop.
-- Subscribing to it would generate a task per approval hop. Rejections are what matter,
-- and those are covered by the department head who issues them.

-- ---- 2. emit the subscribed types that a trigger can produce deterministically ----

-- supplier.applied: a supplier submits a registration.
create or replace function public.fn_emit_supplier_applied() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.registration_submitted_at is not null
     and coalesce(old.registration_submitted_at, '-infinity'::timestamptz) is distinct from new.registration_submitted_at then
    insert into company_event (event_type, entity_type, entity_id, actor, payload)
    values ('supplier.applied','lead', new.id::text, coalesce(new.claimed_by,'supplier'),
            jsonb_build_object('company', new.company_name, 'emirate', new.emirate,
                               'trade_licence', new.trade_license_no, 'trades', new.invite_trades));
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_emit_supplier_applied on public.leads;
create trigger trg_emit_supplier_applied after update on public.leads
for each row execute function public.fn_emit_supplier_applied();

-- invoice.received: a supplier bill is booked.
create or replace function public.fn_emit_invoice_received() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('invoice.received','ap_bill', new.bill_no, coalesce(new.created_by,'system'),
          jsonb_build_object('vendor_id', new.vendor_id, 'total', new.total,
                             'bill_date', new.bill_date, 'due_date', new.due_date));
  return new;
end; $fn$;

drop trigger if exists trg_emit_invoice_received on public.ap_bills;
create trigger trg_emit_invoice_received after insert on public.ap_bills
for each row execute function public.fn_emit_invoice_received();

-- test.failed: a scheduled run errors. Deduped to one event per agent per day so a
-- persistent failure does not generate 40 identical tasks.
create or replace function public.fn_emit_test_failed() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.status = 'error' and coalesce(old.status,'') <> 'error' then
    if not exists (
      select 1 from company_event e
      where e.event_type = 'test.failed' and e.entity_id = new.agent
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('test.failed','scheduled_run', new.agent, 'system',
              jsonb_build_object('run_id', new.id, 'note', left(coalesce(new.note,''), 500),
                                 'started_at', new.started_at));
    end if;
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_emit_test_failed_ins on public.agent_runs;
drop trigger if exists trg_emit_test_failed_upd on public.agent_runs;
create trigger trg_emit_test_failed_upd after update on public.agent_runs
for each row execute function public.fn_emit_test_failed();

create or replace function public.fn_emit_test_failed_ins() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.status = 'error' then
    if not exists (
      select 1 from company_event e
      where e.event_type = 'test.failed' and e.entity_id = new.agent
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('test.failed','scheduled_run', new.agent, 'system',
              jsonb_build_object('run_id', new.id, 'note', left(coalesce(new.note,''), 500),
                                 'started_at', new.started_at));
    end if;
  end if;
  return new;
end; $fn$;

create trigger trg_emit_test_failed_ins after insert on public.agent_runs
for each row execute function public.fn_emit_test_failed_ins();

-- kpi.missed and goal.at_risk: emitted from the metric snapshot, once per metric per day.
create or replace function public.fn_emit_metric_alerts() returns integer
language plpgsql security definer set search_path = public as $fn$
declare n integer := 0; r record;
begin
  for r in
    select metric_key, label, value, target, owner_dept, state from v_bi_scorecard
    where state = 'OFF_TARGET'
  loop
    if not exists (
      select 1 from company_event e
      where e.event_type = 'kpi.missed' and e.entity_id = r.metric_key
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('kpi.missed','metric', r.metric_key, coalesce(r.owner_dept,'exec'),
              jsonb_build_object('label', r.label, 'value', r.value, 'target', r.target, 'state', r.state));
      n := n + 1;
    end if;
  end loop;

  -- A company goal whose owning department has an off-target metric is a goal at risk.
  for r in
    select distinct g.key, g.goal, g.owner_dept
    from company_goals g
    join v_bi_scorecard s on s.owner_dept = g.owner_dept and s.state = 'OFF_TARGET'
    where g.active
  loop
    if not exists (
      select 1 from company_event e
      where e.event_type = 'goal.at_risk' and e.entity_id = r.key
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('goal.at_risk','company_goal', r.key, coalesce(r.owner_dept,'exec'),
              jsonb_build_object('goal', r.goal, 'owner_dept', r.owner_dept));
      n := n + 1;
    end if;
  end loop;

  return n;
end; $fn$;

revoke execute on function public.fn_emit_supplier_applied() from anon, authenticated, public;
revoke execute on function public.fn_emit_invoice_received() from anon, authenticated, public;
revoke execute on function public.fn_emit_test_failed() from anon, authenticated, public;
revoke execute on function public.fn_emit_test_failed_ins() from anon, authenticated, public;
revoke execute on function public.fn_emit_metric_alerts() from anon, authenticated, public;

insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department)
values ('metric_alerts','rpc','fn_emit_metric_alerts','{}'::jsonb, true,
        'Turns off-target metrics into kpi.missed and goal.at_risk events, deduped to one per metric per day.', false, 'exec')
on conflict do nothing;
