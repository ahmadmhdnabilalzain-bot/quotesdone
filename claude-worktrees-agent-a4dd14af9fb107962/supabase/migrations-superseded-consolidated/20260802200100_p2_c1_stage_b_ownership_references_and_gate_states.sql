-- P2-C1 STAGE B (2/6) - WHO OWNS WHAT, who merely READS it, and explicit gate states.
-- Applied as p2_c1_stage_b_ownership_references_and_gate_states, with the gate-default and legacy
-- identity corrections from p2_c1_stage_b_fix_gate_default_and_scope_rule and
-- p2_c1_stage_b_fix_legacy_identity_workstream_count folded in.
--
-- Founder decision, 2 Aug, on emergency lighting: electrical (route 10) is the primary technical
-- owner. Route 13 is a secondary REGULATORY consumer. Route 12 must not own duplicate
-- emergency-lighting answers or requirements at all.
--
-- Verified before excluding route 12: electrical's lighting subcategory already carries the
-- emergency technical fields (emergency_duration, central_battery_exact_item,
-- emergency_luminaire_exact_item, exit_sign_exact_item, lux_uniformity), so nothing is lost. The
-- route-12 and route-13 copies of emergency-lighting-and-exit-signage are byte-identical (83
-- questions each) - which is exactly the duplication this decision removes.

create table if not exists public.subcategory_trade_contribution (
  subcategory_slug       text not null,
  catalog_num            integer not null,
  trade_key              text not null references public.mep_trade(trade_key),
  contribution           text not null check (contribution in ('technical','regulatory','excluded')),
  contributed_field_keys text[],
  reason                 text not null,
  decided_by             text,
  decided_at             timestamptz not null default now(),
  primary key (subcategory_slug, catalog_num, trade_key)
);
alter table public.subcategory_trade_contribution enable row level security;

comment on table public.subcategory_trade_contribution is
  'Default is technical: a trade owns every field of every subcategory on its routes. Rows here are the exceptions, and every exception carries a reason.';

create table if not exists public.field_definition_reference (
  field_id              text not null references public.field_definition(field_id) on delete cascade,
  referencing_trade_key text not null references public.mep_trade(trade_key),
  reason                text not null,
  primary key (field_id, referencing_trade_key)
);
alter table public.field_definition_reference enable row level security;

comment on table public.field_definition_reference is
  'Read-only visibility across trades. A referenced answer is never counted toward the referencing trade''s completeness - it is one answer, owned once, visible where it is needed.';

insert into public.subcategory_trade_contribution
  (subcategory_slug, catalog_num, trade_key, contribution, contributed_field_keys, reason, decided_by) values
  ('emergency-lighting-and-exit-signage', 12, 'fire', 'excluded', null,
   'Founder decision 2 Aug 2026. Route 12 must not own duplicate emergency-lighting answers or requirements. The technical owner is electrical (route 10); route 13 carries the life-safety regulatory contribution.',
   'founder'),
  ('emergency-lighting-and-exit-signage', 13, 'fire', 'regulatory',
   array['authority_jurisdiction','product_approval','integration_matrix','testing_acceptance','monitor_test','addressable_emergency_exact_item'],
   'Founder decision 2 Aug 2026. Route 13 contributes life-safety approvals, integration and regulatory gates only. Every other field on this subcategory belongs to electrical and is referenced, not re-asked.',
   'founder')
on conflict (subcategory_slug, catalog_num, trade_key) do nothing;

insert into public.field_definition_reference (field_id, referencing_trade_key, reason)
select fd.field_id, 'fire',
       'Emergency lighting is stored once under electrical and referenced by fire alarm & life safety for its regulatory review. Fire cannot answer it.'
  from public.field_definition fd
 where fd.trade_key = 'electrical'
   and fd.field_id ~* 'emergency|exit_sign|central_battery|lux_uniformity'
on conflict (field_id, referencing_trade_key) do nothing;

alter table public.mep_trade add column if not exists is_core boolean not null default false;
update public.mep_trade set is_core = trade_key in ('hvac','electrical','plumbing');
comment on column public.mep_trade.is_core is
  'Founder decision 2 Aug 2026: route 8 core workstreams are HVAC, electrical and plumbing. Fire and ELV are added only when explicitly requested, detected in approved documents and confirmed, or required by scope.';

-- Explicit gate states. A boolean could only say yes or no, so "never looked at" and "looked at
-- and failed" were the same value - and which one it is, is exactly what a blocker message needs.
--
-- NOTE, and this cost a debugging pass: `state` deliberately has NO column default. An earlier
-- version defaulted it to 'not_evaluated', which meant an insert supplying only the older `passed`
-- column arrived at the trigger with state already non-null, so the trigger never derived state
-- from passed - and then rewrote passed to false. An explicit "this gate passed" silently became
-- "never evaluated". The trigger is the only thing that decides this column.

do $mig$ begin
  create type public.gate_state as enum
    ('not_evaluated','pending','passed','failed','blocked','not_applicable');
exception when duplicate_object then null; end $mig$;

alter table public.inquiry_gate add column if not exists state public.gate_state;
alter table public.inquiry_gate add column if not exists state_reason text;
alter table public.inquiry_gate alter column passed drop default;
alter table public.inquiry_gate alter column passed drop not null;
update public.inquiry_gate
   set state = (case when passed then 'passed' else 'failed' end)::public.gate_state
 where state is null;
alter table public.inquiry_gate alter column state set not null;

create or replace function public.fn_gate_state_satisfies(s public.gate_state)
returns boolean language sql immutable as $fn$
  select s in ('passed','not_applicable');
$fn$;

create or replace function public.trg_inquiry_gate_state_sync()
returns trigger language plpgsql as $fn$
begin
  if new.state is null then
    new.state := (case when new.passed is true then 'passed'
                       when new.passed is false then 'failed'
                       else 'not_evaluated' end)::public.gate_state;
  end if;
  new.passed := public.fn_gate_state_satisfies(new.state);
  return new;
end $fn$;

drop trigger if exists inquiry_gate_state_sync on public.inquiry_gate;
create trigger inquiry_gate_state_sync before insert or update on public.inquiry_gate
  for each row execute function public.trg_inquiry_gate_state_sync();

comment on column public.inquiry_gate.state is
  'not_evaluated | pending | passed | failed | blocked | not_applicable. Absent rows read as not_evaluated. Only passed and not_applicable satisfy; everything else is fail-closed.';

-- The view chain, rebuilt: `via` on answers, gate states on dispatch.
drop view if exists public.v_group_dispatch cascade;
drop view if exists public.v_group_completeness cascade;
drop view if exists public.v_workstream_dispatch cascade;
drop view if exists public.v_workstream_completeness cascade;
drop view if exists public.v_workstream_answer cascade;

create view public.v_workstream_answer as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       a.id as answer_id, a.field_id, a.value, a.unit, a.scope, a.precedence, a.source_kind,
       a.confirmed_at,
       case when a.scope = 'inquiry_shared' then 'shared'
            when exists (select 1 from public.inquiry_answer_scope s
                          where s.answer_id = a.id and s.workstream_id = w.id) then 'owned'
            else 'referenced' end as via,
       (a.value is not null and btrim(a.value) <> ''
        and a.precedence not in ('model_inference','unknown')
        and (a.scope = 'inquiry_shared'
             or exists (select 1 from public.inquiry_answer_scope s
                         where s.answer_id = a.id and s.workstream_id = w.id))
       ) as satisfies_mandatory
  from public.inquiry_workstream w
  join public.inquiry_answer a
    on a.group_id = w.group_id and a.superseded_by is null
 where a.scope = 'inquiry_shared'
    or exists (select 1 from public.inquiry_answer_scope s
                where s.answer_id = a.id and s.workstream_id = w.id)
    or exists (select 1 from public.field_definition_reference r
                where r.field_id = a.field_id and r.referencing_trade_key = w.trade_key);

comment on view public.v_workstream_answer is
  'Every live answer visible to every workstream, with how it got there. `shared` = one row joined by group_id. `referenced` = owned by another trade, visible here, and never satisfying this trade''s mandatory fields.';

create view public.v_workstream_completeness as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       count(*) filter (where r.mandatory) as required_mandatory,
       count(*) filter (where r.mandatory and va.satisfies_mandatory) as answered_mandatory,
       count(*) filter (where not r.mandatory) as required_optional,
       count(*) filter (where not r.mandatory and va.satisfies_mandatory) as answered_optional,
       coalesce(array_agg(r.field_id order by r.field_id)
                filter (where r.mandatory and not coalesce(va.satisfies_mandatory,false)),
                '{}'::text[]) as missing_mandatory,
       coalesce((select array_agg(distinct vc.field_id)
                   from public.v_workstream_conflict vc where vc.workstream_id = w.id),
                '{}'::text[]) as blocked_by
  from public.inquiry_workstream w
  left join public.inquiry_workstream_requirement r on r.workstream_id = w.id
  left join public.v_workstream_answer va on va.workstream_id = w.id and va.field_id = r.field_id
 group by w.id, w.group_id, w.trade_key, w.active;

create view public.v_workstream_dispatch as
select c.workstream_id, c.group_id, c.trade_key, c.active,
       c.required_mandatory, c.answered_mandatory, c.missing_mandatory, c.blocked_by,
       (cardinality(c.missing_mandatory) = 0) as mandatory_complete,
       (cardinality(c.blocked_by) = 0)        as no_unresolved_conflict,
       coalesce((select jsonb_object_agg(gr.gate_key,
                   coalesce((select g.state::text from public.inquiry_gate g
                              where g.workstream_id = c.workstream_id and g.gate_key = gr.gate_key),
                            'not_evaluated'))
                   from public.inquiry_gate_required gr where gr.level = 'workstream'),
                '{}'::jsonb) as gate_states,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'workstream'
            and not exists (select 1 from public.inquiry_gate g
                             where g.workstream_id = c.workstream_id
                               and g.gate_key = gr.gate_key
                               and public.fn_gate_state_satisfies(g.state))) as gates_passed,
       (c.active
        and cardinality(c.missing_mandatory) = 0
        and cardinality(c.blocked_by) = 0
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'workstream'
             and not exists (select 1 from public.inquiry_gate g
                              where g.workstream_id = c.workstream_id
                                and g.gate_key = gr.gate_key
                                and public.fn_gate_state_satisfies(g.state)))) as dispatch_eligible
  from public.v_workstream_completeness c;

comment on view public.v_workstream_dispatch is
  'A gate with no row reads as not_evaluated, and not_evaluated does not satisfy. Fail-closed.';

create view public.v_group_completeness as
select g.id as group_id, g.inquiry_id, g.rfq_mode,
       count(*) filter (where sr.mandatory) as shared_required_mandatory,
       count(*) filter (where sr.mandatory and a.id is not null) as shared_answered_mandatory,
       coalesce(array_agg(sr.field_id order by sr.field_id)
                filter (where sr.mandatory and a.id is null), '{}'::text[]) as shared_missing_mandatory,
       (select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active) as active_workstreams,
       (select count(*) from public.inquiry_answer_conflict c
         join public.field_definition fd on fd.field_id = c.field_id
        where c.group_id = g.id and c.resolved_at is null and fd.scope = 'shared') as open_shared_conflicts
  from public.inquiry_workstream_group g
  left join lateral (
    select r.field_id, bool_or(r.mandatory) as mandatory
      from public.inquiry_workstream_requirement r
      join public.inquiry_workstream w on w.id = r.workstream_id
      join public.field_definition fd on fd.field_id = r.field_id
     where w.group_id = g.id and w.active and fd.scope = 'shared'
     group by r.field_id
  ) sr on true
  left join public.inquiry_answer a
    on a.group_id = g.id and a.field_id = sr.field_id and a.superseded_by is null
   and a.value is not null and btrim(a.value) <> ''
   and a.precedence not in ('model_inference','unknown')
 group by g.id, g.inquiry_id, g.rfq_mode;

create view public.v_group_dispatch as
select gc.group_id, gc.inquiry_id, gc.rfq_mode, gc.active_workstreams,
       gc.shared_missing_mandatory,
       (cardinality(gc.shared_missing_mandatory) = 0) as shared_complete,
       (gc.open_shared_conflicts = 0)                 as no_unresolved_shared_conflict,
       coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active), false) as all_active_workstreams_eligible,
       coalesce((select array_agg(wd.trade_key order by wd.trade_key) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active and not wd.dispatch_eligible),
                '{}'::text[]) as blocking_trades,
       coalesce((select jsonb_object_agg(gr.gate_key,
                   coalesce((select g.state::text from public.inquiry_gate g
                              where g.group_id = gc.group_id and g.workstream_id is null
                                and g.gate_key = gr.gate_key), 'not_evaluated'))
                   from public.inquiry_gate_required gr where gr.level = 'group'),
                '{}'::jsonb) as gate_states,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'group'
            and not exists (select 1 from public.inquiry_gate g
                             where g.group_id = gc.group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key
                               and public.fn_gate_state_satisfies(g.state))) as group_gates_passed,
       (gc.active_workstreams > 0
        and cardinality(gc.shared_missing_mandatory) = 0
        and gc.open_shared_conflicts = 0
        and coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                       where wd.group_id = gc.group_id and wd.active), false)
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'group'
             and not exists (select 1 from public.inquiry_gate g
                              where g.group_id = gc.group_id and g.workstream_id is null
                                and g.gate_key = gr.gate_key
                                and public.fn_gate_state_satisfies(g.state)))) as overall_dispatch_eligible
  from public.v_group_completeness gc;

-- Legacy compatibility, corrected. count(*) over zero rows returns 0, not NULL, so the original
-- coalesce(..., 1) never fired and every existing single-route inquiry reported
-- effective_workstreams = 0. Found by Stage B test 13.
create or replace view public.v_inquiry_workstream_identity as
select i.id as inquiry_id, g.id as group_id,
       (g.id is not null) as has_group,
       case when g.id is null then 1
            else (select count(*) from public.inquiry_workstream w
                   where w.group_id = g.id and w.active) end as effective_workstreams,
       case when g.id is null then 'implicit_single_workstream' else 'multi_workstream' end as shape
  from public.inquiry_intake i
  left join public.inquiry_workstream_group g on g.inquiry_id = i.id;

comment on view public.v_inquiry_workstream_identity is
  'Reading this view writes nothing. An inquiry with no group reports exactly one implicit workstream, which is how the system behaves today.';

-- Activation respects ownership: excluded subcategories contribute nothing, regulatory ones
-- contribute only their named fields, and a trade never materialises a requirement it may only read.
create or replace function public.fn_inquiry_workstream_activate(
  p_group_id bigint, p_trade_key text, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ws_id bigint; v_route integer; v_reactivated boolean := false; v_reqs integer;
begin
  if not exists (select 1 from public.mep_trade where trade_key = p_trade_key) then
    return jsonb_build_object('ok', false, 'error', 'unknown_trade', 'trade_key', p_trade_key);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  select catalog_num into v_route from public.mep_trade_route
   where trade_key = p_trade_key and is_primary order by catalog_num limit 1;

  select id into v_ws_id from public.inquiry_workstream
   where group_id = p_group_id and trade_key = p_trade_key;

  if v_ws_id is null then
    insert into public.inquiry_workstream (group_id, trade_key, route_catalog_num)
    values (p_group_id, p_trade_key, v_route) returning id into v_ws_id;
  else
    update public.inquiry_workstream
       set active = true, activated_at = now(), deactivated_at = null
     where id = v_ws_id and active = false;
    v_reactivated := found;
    update public.inquiry_workstream set active = true where id = v_ws_id;
  end if;

  insert into public.inquiry_workstream_requirement (workstream_id, question_id, field_id, mandatory)
  select v_ws_id, min(q.question_id), s.field_id, bool_or(q.mandatory)
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
    join public.field_definition_source s
      on s.subcategory_slug = q.subcategory_slug and s.source_field_key = q.field_key
    left join public.subcategory_trade_contribution c
      on c.subcategory_slug = m.subcategory_slug and c.catalog_num = tr.catalog_num
     and c.trade_key = tr.trade_key
   where tr.trade_key = p_trade_key and q.field_key is not null
     and coalesce(c.contribution, 'technical') <> 'excluded'
     and (coalesce(c.contribution, 'technical') <> 'regulatory'
          or q.field_key = any(coalesce(c.contributed_field_keys, '{}'::text[])))
     and not exists (select 1 from public.field_definition_reference r
                      where r.field_id = s.field_id and r.referencing_trade_key = p_trade_key)
   group by s.field_id
  on conflict (workstream_id, field_id) do update
     set mandatory = public.inquiry_workstream_requirement.mandatory or excluded.mandatory;

  get diagnostics v_reqs = row_count;

  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id,
          case when v_reactivated then 'workstream_reactivated' else 'workstream_activated' end,
          jsonb_build_object('trade_key', p_trade_key, 'route_catalog_num', v_route,
                             'requirements', v_reqs), p_actor);

  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id, 'trade_key', p_trade_key,
                            'reactivated', v_reactivated, 'requirements', v_reqs);
end $fn$;
