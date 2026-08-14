-- V3 REMEDIATION — STAGE 5: ROLE IDENTITY AND RUNTIME ISOLATION
--
-- Result of record V3-COR-0A782DA90B10 flagged ROLE_MAPPING_ERROR on 59 of 96 certification roles.
-- Re-measured on staging (pglpqrhvozwepymcuunn) 14 Aug 2026 before writing a line of this file:
--
--   select agent_key, count(*) from org_role_identity group by 1 having count(*)>1;
--     -> 23 agents, 59 packaged roles, 13 agents serving 3 roles and 10 serving 2.
--   Every one of the 23 spans more than one archetype.  Measured breakdown:
--     director + reviewer-auditor on one agent ............... 18 agents
--     creator/reviewer conflict (producer + reviewer-auditor)  18 agents
--     manager/subordinate conflict (director + IC archetype) .. 16 agents
--     three distinct archetypes on one agent ................. 13 agents
--   And the fact that makes it consequential:
--     22 of the 23 colliding agents are the lead_agent of a department
--     (only innovation_mgr leads none) — so the packaged reviewer-auditor of a
--     department is, at runtime, the same identity as its director.
--
-- Sharing an execution SERVICE is fine.  Sharing identity, authority, KPI context and approval
-- responsibility is not.  This file separates the two.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT WAS ALREADY THERE — read before adding anything (measured, not assumed)
-- ---------------------------------------------------------------------------------------------
-- 1. fn_pick_reviewer(text,text) ALREADY refuses to return the author.  Probed live for all 27
--    (department, lead_agent) pairs the colliding agents lead:
--      26 of 27 returned a reviewer that is not the author
--         (3 routed to an in-department independent_reviewer: assurance -> ai_qa_specialist,
--          legal -> compliance_mgr, product_eng -> model_evaluator; 23 escalated one level up
--          the reporting chain)
--       1 of 27 (exec / ceo) returned available=false, i.e. escalate rather than approve.
--    So the SELECTOR is sound.  Nothing here duplicates it.
--
-- 2. review_chain already carries CHECK review_chain_no_self_approval_ck
--      (reviewer_agent is null or author_agent is null or reviewer_agent <> author_agent) NOT VALID
--    NOT VALID only exempts the rows already stored; it IS enforced on every new write.  Probed by
--    forcing it to fire — a plain insert of ('legal','legal','dept_review','approve') was rejected
--    with SQLSTATE 23514, 0 rows landed.  So runtime self-approval on review_chain is already hard-
--    blocked and this file does NOT re-add it.  (6 legacy rows predate the constraint: 2 self-
--    approvals and 4 non-approvals, newest 2026-08-12.  They are reported by
--    fn_role_isolation_status(), not silently rewritten.)
--
-- 3. fn_artifact_review_valid() blocks author = reviewer on artifact_review when verdict='pass'.
--
-- The guard that did NOT exist is one layer up: nothing stopped org_role_identity from RECORDING an
-- agent as both the producer and the independent reviewer of the same packaged department in the
-- first place.  That is what created all 18 creator/reviewer conflicts, and a future package import
-- would recreate them silently.  Section 5 closes that.
--
-- ---------------------------------------------------------------------------------------------
-- WHY THE DECISION LIVES IN ITS OWN TABLE
-- ---------------------------------------------------------------------------------------------
-- org_role_identity.readiness is NOT a durable place to record a disposition.  Probed in an
-- aborted transaction: set readiness='blocked' on 13 rows, called fn_role_readiness_recompute(),
-- counted again -> 0 of 13 survived.  mapping_type survived 1 of 1.  So:
--   * mapping_type  is written here (durable, the recompute never touches it),
--   * readiness     is made durable by teaching fn_role_readiness_recompute to honour a recorded
--                   block / restrict_to_advisory decision (section 6) — otherwise every hourly
--                   recompute would quietly reinstate the agent it was told to stop,
--   * the authority of record is role_isolation_decision, which nothing else writes.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE DECISION OF RECORD
-- ---------------------------------------------------------------------------------------------
create table if not exists public.role_isolation_decision (
  agent_key             text not null,
  packaged_role_id      text not null,
  packaged_department   text not null,
  archetype             text not null,
  -- isolate              retained as this agent's primary identity; its own output is reviewed by
  --                      someone else (fn_pick_reviewer, measured above, never returns the author)
  -- split                this identity must become its own runtime agent before it may act
  -- restrict_to_advisory may reason and recommend, may not carry authority
  -- block                may not execute this role at all
  resolution            text not null
                          check (resolution in ('isolate','split','restrict_to_advisory','block')),
  conflict_class        text[] not null default '{}',
  certification_status  text,                       -- from the sanitized RESULTS_BY_ROLE.csv
  intended_mapping_type text not null
                          check (intended_mapping_type in
                            ('one_to_one','runtime_composite','package_composite','duplicate_role',
                             'missing_runtime_agent','obsolete_runtime_agent','on_demand_specialist',
                             'requires_split','requires_merge')),
  intended_readiness    text
                          check (intended_readiness is null or intended_readiness in
                            ('knowledge_imported','runtime_mapped','tools_connected',
                             'live_data_connected','decision_trace_connected','training_passed',
                             'independent_certification_pending','certified_for_defined_role_scope',
                             'blocked','restricted_to_advisory')),
  runtime_reviewer      text,                       -- who fn_pick_reviewer actually returns
  runtime_reviewer_basis text,
  rationale             text not null,
  decided_by            text not null default 'v3_repair_06_role_isolation',
  decided_at            timestamptz not null default now(),
  primary key (agent_key, packaged_role_id)
);
alter table public.role_isolation_decision enable row level security;

comment on table public.role_isolation_decision is
  'One row per packaged role identity whose runtime mapping needed a deliberate isolation call. '
  'Written once by scripts/sql/v3_repair_06_role_isolation.sql. This is the durable record: '
  'org_role_identity.readiness is recomputed by fn_role_readiness_recompute and cannot hold it.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE COLLISION ENUMERATION
-- ---------------------------------------------------------------------------------------------
-- Seniority tiers.  NOTE, honestly: the handoff says twelve collisions cross seniority tiers.  That
-- number is NOT reproducible from org_role_identity — no seniority column exists on it, and the
-- certification tier (A/B) is uniform per agent for all 23 (checked in RESULTS_BY_ROLE.csv: every
-- shared agent has exactly one tier).  The tiering below is this file's own, stated explicitly so
-- the number it produces can be argued with:
--     1 = director               sets objectives, approves, carries budget authority
--     2 = analyst-controller /   measures and independently challenges
--         reviewer-auditor
--     3 = operations-specialist  executes
-- On that definition all 23 collisions span tiers, because all 23 include the director archetype.
create or replace function public.fn_archetype_tier(p_archetype text)
returns integer language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case p_archetype
           when 'director' then 1
           when 'analyst-controller' then 2
           when 'reviewer-auditor' then 2
           when 'operations-specialist' then 3
           else 9 end;
$$;
revoke all on function public.fn_archetype_tier(text) from public;
grant execute on function public.fn_archetype_tier(text) to service_role;

create or replace view public.v_role_identity_collision as
with agg as (
  select i.agent_key,
         count(*)                                                       as roles_served,
         array_agg(i.packaged_role_id order by i.packaged_role_id)      as roles,
         array_agg(distinct i.archetype order by i.archetype)           as archetypes,
         array_agg(distinct i.packaged_department
                   order by i.packaged_department)                      as packaged_departments,
         count(distinct fn_archetype_tier(i.archetype))                 as tiers_spanned
  from public.org_role_identity i
  group by i.agent_key
  having count(*) > 1
)
select
  a.agent_key,
  a.roles_served,
  a.roles,
  a.archetypes,
  a.packaged_departments,
  ag.department                                       as runtime_department,
  ag.seniority                                        as runtime_seniority,
  ag.active                                           as agent_active,
  (select array_agg(d.dept_key order by d.dept_key)
     from public.org_departments d
    where d.lead_agent = a.agent_key)                 as leads_departments,
  a.tiers_spanned > 1                                 as spans_seniority_tiers,
  -- self-approval: one identity is both a producer and the independent reviewer of the same work
  ('reviewer-auditor' = any(a.archetypes)
     and (   'director'              = any(a.archetypes)
          or 'operations-specialist' = any(a.archetypes)
          or 'analyst-controller'    = any(a.archetypes))) as creator_reviewer_conflict,
  -- one identity is both the manager who sets the objective and the employee measured against it
  ('director' = any(a.archetypes)
     and (   'operations-specialist' = any(a.archetypes)
          or 'analyst-controller'    = any(a.archetypes)))  as manager_subordinate_conflict,
  -- structural verdict, from the shape alone.  The recorded call may be stricter (block /
  -- restrict_to_advisory) because of what certification measured; it is never looser.
  case
    when 'reviewer-auditor' = any(a.archetypes) then 'split'
    when 'director' = any(a.archetypes)
      and (   'operations-specialist' = any(a.archetypes)
           or 'analyst-controller'    = any(a.archetypes)) then 'split'
    else 'isolate'
  end                                                 as required_verdict,
  (select array_agg(distinct d2.resolution order by d2.resolution)
     from public.role_isolation_decision d2 where d2.agent_key = a.agent_key)
                                                      as recorded_resolutions,
  (select count(*) from public.org_role_identity i2
    where i2.agent_key = a.agent_key
      and not exists (select 1 from public.role_isolation_decision d3
                       where d3.agent_key = i2.agent_key
                         and d3.packaged_role_id = i2.packaged_role_id))
                                                      as roles_without_decision
from agg a
join public.org_agents ag on ag.agent_key = a.agent_key;

comment on view public.v_role_identity_collision is
  'Every runtime agent serving more than one packaged certification role, with the conflict classes '
  'the sharing creates and the isolation verdict the shape requires. roles_without_decision > 0 '
  'means the collision has not been dispositioned in role_isolation_decision.';

revoke all on public.v_role_identity_collision from anon, authenticated;
grant select on public.v_role_identity_collision to service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. THE RESOLUTION — one decision per role identity, recorded
-- ---------------------------------------------------------------------------------------------
-- The 14 roles that certification did not merely score low but could not evaluate at all.  Taken
-- verbatim from the columns role_id / certification_status of the sanitized
-- docs/knowledge/certification/V3_CERTIFICATION_RESULTS_BY_ROLE.csv
-- (5 NOT_CONNECTED, 9 BLOCKED_CRITICAL_FAILURE — the file's own totals).  These 14 role ids resolve
-- to 18 org_role_identity rows, because marketplace-operations-operations-specialist is a
-- package_composite served by five spec_* agents.
--
-- Rule, applied to every org_role_identity row:
--   BLOCKED_CRITICAL_FAILURE                 -> block                (may not execute the role)
--   NOT_CONNECTED                            -> restrict_to_advisory (never produced a runtime
--                                               answer; it may not carry authority on the strength
--                                               of an untested mapping)
--   in a collision, archetype = director     -> isolate              (retained primary identity)
--   in a collision, any other archetype      -> split                (needs its own runtime agent)
--   not in a collision, no certification flag-> no row               (nothing to resolve)
-- 3a. Self-heal: the first version of this file stamped mapping_type='duplicate_role' on the 13
-- blocked identity rows. That was a false claim about the mapping (8 of the 13 agents serve exactly
-- one packaged role each). The values below are the mapping_types MEASURED on staging on
-- 2026-08-14 before this file first ran. Scoped to rows this file itself mis-set, so on a database
-- where that never happened this statement matches nothing.
update public.org_role_identity i
   set mapping_type = v.original, updated_at = now()
  from (values
    ('legal',              'legal-and-compliance-director',               'one_to_one'),
    ('spec_commercial',    'marketplace-operations-operations-specialist','package_composite'),
    ('spec_construction',  'marketplace-operations-operations-specialist','package_composite'),
    ('spec_fitout',        'marketplace-operations-operations-specialist','package_composite'),
    ('spec_industrial',    'marketplace-operations-operations-specialist','package_composite'),
    ('spec_mep',           'marketplace-operations-operations-specialist','package_composite'),
    ('supplier_verification','marketplace-operations-reviewer-auditor',   'one_to_one'),
    ('qa_manager',         'qa-and-testing-analyst-controller',           'runtime_composite'),
    ('qa_manager',         'qa-and-testing-director',                     'one_to_one'),
    ('qa_manager',         'qa-and-testing-operations-specialist',        'runtime_composite'),
    ('category_curator',   'supplier-knowledge-operations-specialist',    'one_to_one'),
    ('supplier_retention', 'supplier-success-operations-specialist',      'one_to_one'),
    ('trust_safety_mgr',   'trust-and-safety-operations-specialist',      'runtime_composite')
  ) as v(agent_key, packaged_role_id, original)
 where i.agent_key = v.agent_key
   and i.packaged_role_id = v.packaged_role_id
   and i.mapping_type = 'duplicate_role'
   and exists (select 1 from public.role_isolation_decision d
                where d.agent_key = i.agent_key and d.packaged_role_id = i.packaged_role_id
                  and d.intended_mapping_type = 'duplicate_role');

with cert(role_id, status) as (values
  ('customer-success-analyst-controller',        'NOT_CONNECTED'),
  ('customer-success-director',                  'NOT_CONNECTED'),
  ('customer-success-reviewer-auditor',          'NOT_CONNECTED'),
  ('marketing-director',                         'NOT_CONNECTED'),
  ('marketing-reviewer-auditor',                 'NOT_CONNECTED'),
  ('legal-and-compliance-director',              'BLOCKED_CRITICAL_FAILURE'),
  ('marketplace-operations-operations-specialist','BLOCKED_CRITICAL_FAILURE'),
  ('marketplace-operations-reviewer-auditor',    'BLOCKED_CRITICAL_FAILURE'),
  ('qa-and-testing-analyst-controller',          'BLOCKED_CRITICAL_FAILURE'),
  ('qa-and-testing-director',                    'BLOCKED_CRITICAL_FAILURE'),
  ('qa-and-testing-operations-specialist',       'BLOCKED_CRITICAL_FAILURE'),
  ('supplier-knowledge-operations-specialist',   'BLOCKED_CRITICAL_FAILURE'),
  ('supplier-success-operations-specialist',     'BLOCKED_CRITICAL_FAILURE'),
  ('trust-and-safety-operations-specialist',     'BLOCKED_CRITICAL_FAILURE')
),
coll as (
  select agent_key, array_agg(distinct archetype order by archetype) arch
  from public.org_role_identity group by agent_key having count(*) > 1
),
-- who actually reviews this agent's work today, asked of the runtime rather than assumed
pick as (
  select c.agent_key,
         (public.fn_pick_reviewer(d.dept_key, c.agent_key)->>'reviewer') as reviewer,
         (public.fn_pick_reviewer(d.dept_key, c.agent_key)->>'basis')    as basis,
         d.dept_key
  from coll c
  join public.org_departments d on d.lead_agent = c.agent_key
),
pick1 as (
  select distinct on (agent_key) agent_key, reviewer, dept_key, basis
  from pick order by agent_key, (reviewer is null) desc, dept_key
),
decided as (
  select
    i.agent_key, i.packaged_role_id, i.packaged_department, i.archetype,
    i.mapping_type as current_mapping_type,
    ct.status as certification_status,
    (c.agent_key is not null) as in_collision,
    c.arch,
    p.reviewer, p.basis, p.dept_key,
    case
      when ct.status = 'BLOCKED_CRITICAL_FAILURE' then 'block'
      when ct.status = 'NOT_CONNECTED'            then 'restrict_to_advisory'
      when c.agent_key is null                    then null
      when i.archetype = 'director'               then 'isolate'
      else 'split'
    end as resolution
  from public.org_role_identity i
  left join coll  c  on c.agent_key = i.agent_key
  left join cert  ct on ct.role_id  = i.packaged_role_id
  left join pick1 p  on p.agent_key = i.agent_key
)
insert into public.role_isolation_decision
  (agent_key, packaged_role_id, packaged_department, archetype, resolution, conflict_class,
   certification_status, intended_mapping_type, intended_readiness,
   runtime_reviewer, runtime_reviewer_basis, rationale)
select
  d.agent_key, d.packaged_role_id, d.packaged_department, d.archetype, d.resolution,
  array_remove(array[
    case when d.in_collision and 'reviewer-auditor' = any(d.arch)
              and ('director' = any(d.arch) or 'operations-specialist' = any(d.arch)
                   or 'analyst-controller' = any(d.arch))
         then 'creator_reviewer' end,
    case when d.in_collision and 'director' = any(d.arch)
              and ('operations-specialist' = any(d.arch) or 'analyst-controller' = any(d.arch))
         then 'manager_subordinate' end,
    case when d.in_collision
              and (select count(distinct public.fn_archetype_tier(x)) from unnest(d.arch) x) > 1
         then 'cross_seniority' end,
    case when d.certification_status is not null then 'certification_' || lower(d.certification_status) end
  ], null),
  d.certification_status,
  -- 'block' deliberately PRESERVES the existing mapping_type. Blocking is a statement about
  -- readiness, not about how the role maps: supplier_retention serves exactly one packaged role,
  -- and stamping it 'duplicate_role' would assert a duplication that does not exist. The first
  -- version of this file did exactly that; section 3a below undoes it.
  case d.resolution
    when 'split' then 'requires_split'
    when 'block' then d.current_mapping_type
    else 'runtime_composite'
  end,
  case d.resolution
    when 'block'                then 'blocked'
    when 'restrict_to_advisory' then 'restricted_to_advisory'
    else null
  end,
  d.reviewer, d.basis,
  case d.resolution
    when 'block' then
      'certification could not evaluate this role: ' || d.certification_status ||
      '. It may not execute until the defect that blocked it is fixed and it is re-run.'
    when 'restrict_to_advisory' then
      'certification recorded NOT_CONNECTED: the runtime produced no evaluable answer for this ' ||
      'role, so its authority rests on an untested mapping. Advisory only until re-run.'
    when 'isolate' then
      'retained as ' || d.agent_key || '''s primary identity. Its own output is reviewed by ' ||
      coalesce(d.reviewer, 'nobody - fn_pick_reviewer returns available=false, which escalates') ||
      coalesce(' for department ' || d.dept_key, '') || '.'
    else
      'agent ' || d.agent_key || ' also serves the director role for this department; this ' ||
      'identity carries different authority, KPI context and evidence expectations and must ' ||
      'become its own runtime agent before it acts.'
  end
from decided d
where d.resolution is not null
-- upsert, not do-nothing: this file is the only writer of the table, so a re-run must be able to
-- correct a call it recorded wrongly rather than silently keep the first answer.
on conflict (agent_key, packaged_role_id) do update set
  packaged_department    = excluded.packaged_department,
  archetype              = excluded.archetype,
  resolution             = excluded.resolution,
  conflict_class         = excluded.conflict_class,
  certification_status   = excluded.certification_status,
  intended_mapping_type  = excluded.intended_mapping_type,
  intended_readiness     = excluded.intended_readiness,
  runtime_reviewer       = excluded.runtime_reviewer,
  runtime_reviewer_basis = excluded.runtime_reviewer_basis,
  rationale              = excluded.rationale,
  decided_at             = now()
where public.role_isolation_decision.decided_by = 'v3_repair_06_role_isolation';

-- ---------------------------------------------------------------------------------------------
-- 4. APPLY THE DURABLE HALF OF THE DECISION
-- ---------------------------------------------------------------------------------------------
-- mapping_type only.  readiness is deliberately not written here: fn_role_readiness_recompute
-- overwrites it (probed: 0 of 13 survived) and section 6 makes it honour the decision instead.
update public.org_role_identity i
   set mapping_type = d.intended_mapping_type,
       updated_at   = now()
  from public.role_isolation_decision d
 where d.agent_key = i.agent_key
   and d.packaged_role_id = i.packaged_role_id
   and i.mapping_type is distinct from d.intended_mapping_type;

-- ---------------------------------------------------------------------------------------------
-- 5. THE HARD GUARD — a self-approving identity cannot be CREATED
-- ---------------------------------------------------------------------------------------------
-- review_chain already refuses author = reviewer at write time (measured, 23514).  What nothing
-- refused was recording the conflict in the first place: an import could map one agent to both the
-- director and the reviewer-auditor of a department, and every downstream reviewer lookup would
-- then be choosing between two masks on one face.  a00_ prefix because Postgres fires BEFORE
-- triggers in name order and this one must run before anything that normalises the row.
create or replace function public.fn_role_identity_isolation_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare v_other text;
begin
  select string_agg(o.packaged_role_id || ' (' || o.archetype || ')', ', '
                    order by o.packaged_role_id)
    into v_other
    from public.org_role_identity o
   where o.agent_key = new.agent_key
     and o.packaged_department = new.packaged_department
     and o.packaged_role_id <> new.packaged_role_id
     and ( (    new.archetype = 'reviewer-auditor'
            and o.archetype in ('director','operations-specialist','analyst-controller'))
        or (    o.archetype = 'reviewer-auditor'
            and new.archetype in ('director','operations-specialist','analyst-controller')) );

  if v_other is null then
    return new;
  end if;

  -- The conflict may exist, but only as a decision somebody signed for — and signed for THIS
  -- archetype.  Matching on (agent_key, packaged_role_id) alone was tried and probed: it let
  -- payments-and-revenue-operations-analyst-controller be redefined to reviewer-auditor on the
  -- strength of a decision that had been recorded about the analyst-controller identity.  A
  -- decision about one identity is not consent for a different one.
  if exists (select 1 from public.role_isolation_decision d
              where d.agent_key = new.agent_key
                and d.packaged_role_id = new.packaged_role_id
                and d.archetype = new.archetype) then
    return new;
  end if;

  raise exception
    'agent % would be both producer and independent reviewer of % (this row: % as %; also holds: %)',
    new.agent_key, new.packaged_department, new.packaged_role_id, new.archetype, v_other
    using errcode = '23514',
          hint = 'record the call in role_isolation_decision first: '
                 'isolate | split | restrict_to_advisory | block';
end $$;
revoke all on function public.fn_role_identity_isolation_guard() from public;

-- UPDATE OF the identity-defining columns only, deliberately.  An unqualified "before update" also
-- gates every readiness write, and fn_role_readiness_recompute runs nightly (cron job
-- v3_role_readiness_daily, 01:30).  That would mean deleting one audit row silently breaks a cron
-- job — a guard that fails the wrong thing.  Redefining who an identity IS still goes through it.
drop trigger if exists a00_role_identity_isolation_guard on public.org_role_identity;
create trigger a00_role_identity_isolation_guard
  before insert
      or update of agent_key, packaged_role_id, packaged_department, archetype
      on public.org_role_identity
  for each row execute function public.fn_role_identity_isolation_guard();

-- ---------------------------------------------------------------------------------------------
-- 6. MAKE readiness CARRY THE DECISION INSTEAD OF REVERTING IT
-- ---------------------------------------------------------------------------------------------
-- CREATE OR REPLACE of an existing function: its ACL is preserved, so no revoke here.
-- Only change: two clauses at the head of the rung CASE.  Without them a recorded block survives
-- exactly until the next recompute — measured, 0 of 13 rows survived one call.
create or replace function public.fn_role_readiness_recompute()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_counts jsonb;
begin
  with fact as (
    select
      i.agent_key, i.packaged_role_id, a.active, a.department,
      exists (select 1 from ops_knowledge k
               where k.role_key = i.packaged_role_id and k.runtime_eligible
                 and k.supersession_state = 'current')                         as has_knowledge,
      exists (select 1 from org_departments d
               where d.lead_agent = i.agent_key or d.brain_agent = i.agent_key) as is_named_runner,
      exists (select 1 from agent_runs r where r.agent = i.agent_key)           as has_run,
      exists (select 1 from org_action_executor e
               where e.active and (e.department = a.department or e.target = i.agent_key)) as has_tools,
      exists (select 1 from ops_knowledge k
               where k.record_type = 'live_data_binding'
                 and (k.scope_type = 'company' or k.dept_key = a.department))   as has_live_data,
      exists (select 1 from agent_context_retrieval c where c.agent_key = i.agent_key)
        or exists (select 1 from agent_actions x where x.agent = i.agent_key)   as traceable,
      exists (select 1 from agent_remediation m
               where m.agent_key = i.agent_key and m.status = 'passed')         as trained,
      exists (select 1 from agent_remediation m
               where m.agent_key = i.agent_key and m.blocks_autonomy and m.status <> 'passed') as blocked,
      exists (select 1 from org_action_executor e
               where e.active and e.department = a.department
                 and (e.risk_tier in ('high','medium') or e.notifies_human))    as consequential,
      -- an isolation call outranks every rung below it
      (select d.resolution from role_isolation_decision d
        where d.agent_key = i.agent_key and d.packaged_role_id = i.packaged_role_id)
                                                                               as isolation_resolution
    from org_role_identity i
    join org_agents a on a.agent_key = i.agent_key
  ), rung as (
    select agent_key, packaged_role_id,
      case
        when isolation_resolution = 'block'                then 'blocked'
        when isolation_resolution = 'restrict_to_advisory' then 'restricted_to_advisory'
        when not active                       then 'blocked'
        when blocked                          then 'restricted_to_advisory'
        when not has_knowledge                then 'blocked'
        when trained and not blocked          then 'independent_certification_pending'
        when consequential and not trained    then 'restricted_to_advisory'
        when traceable and has_live_data and has_tools then 'decision_trace_connected'
        when has_live_data and has_tools      then 'live_data_connected'
        when has_tools                        then 'tools_connected'
        when is_named_runner or has_run       then 'runtime_mapped'
        else 'knowledge_imported'
      end as readiness
    from fact
  )
  update org_role_identity i set readiness = r.readiness, updated_at = now()
    from rung r
   where i.agent_key = r.agent_key and i.packaged_role_id = r.packaged_role_id
     and i.readiness is distinct from r.readiness;

  select jsonb_object_agg(readiness, n) into v_counts
    from (select readiness, count(*) n from org_role_identity group by 1) s;

  -- The one status a builder session may never assign.
  if exists (select 1 from org_role_identity where readiness = 'certified_for_defined_role_scope') then
    raise exception 'certified_for_defined_role_scope was assigned without an independent evaluator';
  end if;

  return jsonb_build_object('recomputed_at', now(), 'counts', v_counts,
    'ceiling', 'independent_certification_pending');
end $function$;

select public.fn_role_readiness_recompute();

-- ---------------------------------------------------------------------------------------------
-- 7. THE STATUS FUNCTION
-- ---------------------------------------------------------------------------------------------
-- Reports what is UNRESOLVED, and separately whether the guards that make "resolved" mean anything
-- are actually installed.  A zero that comes from a missing guard is not a zero worth having.
create or replace function public.fn_role_isolation_status()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'measured_at', now(),

    'collisions', (select count(*) from v_role_identity_collision),
    'roles_in_collision', (select coalesce(sum(roles_served),0) from v_role_identity_collision),

    -- the two targets
    'unresolved_cross_seniority_collisions', (
      select count(*) from v_role_identity_collision
       where spans_seniority_tiers and roles_without_decision > 0),
    'unresolved_self_approval_conflicts', (
      select count(*) from org_role_identity i
       where exists (select 1 from org_role_identity o
                      where o.agent_key = i.agent_key
                        and o.packaged_department = i.packaged_department
                        and o.packaged_role_id <> i.packaged_role_id
                        and ((    i.archetype = 'reviewer-auditor'
                              and o.archetype in ('director','operations-specialist','analyst-controller'))
                          or (    o.archetype = 'reviewer-auditor'
                              and i.archetype in ('director','operations-specialist','analyst-controller'))))
         and not exists (select 1 from role_isolation_decision d
                          where d.agent_key = i.agent_key
                            and d.packaged_role_id = i.packaged_role_id)),

    'decisions', (select jsonb_object_agg(resolution, n) from
                   (select resolution, count(*) n from role_isolation_decision group by 1) s),
    'roles_with_no_decision_and_no_conflict', (
      select count(*) from org_role_identity i
       where not exists (select 1 from role_isolation_decision d
                          where d.agent_key = i.agent_key and d.packaged_role_id = i.packaged_role_id)),

    -- the 14 certification roles that must each end with an explicit disposition
    'certification_dispositions', (
      select jsonb_object_agg(certification_status, n) from
        (select certification_status, count(*) n from role_isolation_decision
          where certification_status is not null group by 1) s),
    'certification_role_ids_dispositioned', (
      select count(distinct packaged_role_id) from role_isolation_decision
       where certification_status is not null),

    -- do the guards exist?  a 0 above is only meaningful if these are true.
    'guard_role_identity_installed', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname = 'org_role_identity'
         and t.tgname = 'a00_role_identity_isolation_guard' and not t.tgisinternal),
    'guard_review_chain_installed', exists (
      select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid
       where c.relname = 'review_chain' and con.conname = 'review_chain_no_self_approval_ck'),
    'guard_artifact_review_installed', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname = 'artifact_review'
         and t.tgname = 'a00_artifact_review_author_is_not_reviewer' and not t.tgisinternal),

    -- legacy rows the NOT VALID constraint exempts; reported, never rewritten
    'review_chain_legacy_self_rows', (
      select count(*) from review_chain where author_agent = reviewer_agent),
    'review_chain_legacy_self_approvals', (
      select count(*) from review_chain where author_agent = reviewer_agent and decision = 'approve'),

    -- has anything drifted away from the recorded call?
    'mapping_type_drift', (
      select count(*) from role_isolation_decision d join org_role_identity i
             on i.agent_key = d.agent_key and i.packaged_role_id = d.packaged_role_id
       where i.mapping_type is distinct from d.intended_mapping_type),
    'readiness_drift', (
      select count(*) from role_isolation_decision d join org_role_identity i
             on i.agent_key = d.agent_key and i.packaged_role_id = d.packaged_role_id
       where d.intended_readiness is not null
         and i.readiness is distinct from d.intended_readiness)
  );
$$;
revoke all on function public.fn_role_isolation_status() from public;
grant execute on function public.fn_role_isolation_status() to service_role;

comment on function public.fn_role_isolation_status() is
  'Unresolved cross-seniority collisions and self-approval conflicts, plus whether the guards that '
  'make "resolved" meaningful are installed. Target: both unresolved_* counts zero AND all three '
  'guard_*_installed true.';

commit;
