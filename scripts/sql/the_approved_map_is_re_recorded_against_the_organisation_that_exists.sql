-- THE APPROVED MAP IS RE-RECORDED AGAINST THE ORGANISATION THAT EXISTS
--
-- Founder ruling, 7 September 2026: "what is more recent is right."
--
-- That settles a question I could not settle by engineering. public.phase_c_reporting_authority was
-- recorded on 16 August 2026 from QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP_v2026.08.16.
-- The organisation was consolidated afterwards - thirteen live roles absorbed thirty-four canonical
-- ones - and the two were never reconciled, so fn_phase_c_reporting_map_drift reported 149 rows of
-- genuine disagreement between what was approved and what runs.
--
-- Either the map was right and the consolidation was unauthorised, or the consolidation was right and
-- the map was stale. He has ruled the second. So the map is re-recorded from the live organisation.
--
-- WHAT THIS CHANGES, PRECISELY. For every row, the four attributes that describe where a role sits are
-- taken from the live org_role and org_departments:
--
--   manager_role_id         from org_role.manager_role_id
--   department_id           from org_role.primary_department_id
--   runtime_mode            from org_role.runtime_mode
--   department_head_role_id from the department's recorded lead
--   reporting_path          WALKED up the live graph to the founder, not asserted
--
-- WHAT IT DOES NOT CHANGE. canonical_role_id and live_role_id are untouched, so the count stays at the
-- approved 90 and the consolidation mapping is preserved rather than flattened. role_class is untouched
-- because it describes the canonical seat, not where it now sits. source_package records THIS ruling,
-- with its date, so the next reader sees an authority rather than an unexplained edit.
--
-- WHY THE PATH IS WALKED AND NOT COPIED. The reporting_path arm compares the approved string against a
-- recursive walk of the live manager chain. Writing a path by hand would make the check compare a
-- string to itself and pass regardless of whether the chain is real. Walking it means a role whose
-- managers loop, or whose chain never reaches the founder, still fails - which is the cycle check, and
-- it must survive this.

begin;

-- Snapshot what the map said before, so this is reversible and auditable rather than a silent edit.
create table if not exists public.phase_c_reporting_authority_history (
  id              bigserial primary key,
  superseded_at   timestamptz not null default now(),
  superseded_by   text        not null,
  canonical_role_id text      not null,
  live_role_id    text,
  department_id   text,
  manager_role_id text,
  role_class      text,
  runtime_mode    text,
  department_head_role_id text,
  reporting_path  text,
  source_package  text,
  recorded_at     timestamptz
);

comment on table public.phase_c_reporting_authority_history is
  'Every version of the approved reporting map that was superseded, with who superseded it and when. A baseline that can be edited without a trail is not a baseline.';

insert into public.phase_c_reporting_authority_history
  (superseded_by, canonical_role_id, live_role_id, department_id, manager_role_id, role_class,
   runtime_mode, department_head_role_id, reporting_path, source_package, recorded_at)
select 'Founder ruling 7 Sep 2026: "what is more recent is right." Re-recorded against the live organisation.',
       canonical_role_id, live_role_id, department_id, manager_role_id, role_class,
       runtime_mode, department_head_role_id, reporting_path, source_package, recorded_at
  from public.phase_c_reporting_authority;

-- Re-record from live.
update public.phase_c_reporting_authority a
   set manager_role_id  = coalesce(r.manager_role_id, 'founder'),
       department_id    = coalesce(r.primary_department_id, a.department_id),
       runtime_mode     = coalesce(r.runtime_mode, a.runtime_mode),
       source_package   = 'Founder ruling 2026-09-07: what is more recent is right. Re-recorded from '
                       || 'the live organisation, superseding '
                       || 'QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP_v2026.08.16.',
       recorded_at      = now()
  from public.org_role r
 where r.role_id = a.live_role_id
   and r.status = 'active';

-- The department head each department actually records.
update public.phase_c_reporting_authority a
   set department_head_role_id = coalesce(h.role_id, a.department_head_role_id)
  from public.org_departments d
  left join public.org_role h on h.runtime_agent_key = d.lead_agent and h.status = 'active'
 where d.dept_key = a.department_id;

-- The path, WALKED up the live chain. A role that never reaches the founder keeps its previous value
-- rather than getting a fabricated one, so the cycle check still fires on it.
--
-- A CORRELATED SUBQUERY, not a lateral in the FROM: Postgres refuses to let an UPDATE's FROM clause
-- reference the row being updated, which is what the first attempt did.
update public.phase_c_reporting_authority a
   set reporting_path = coalesce((
         with recursive up(cur, depth, path) as (
           select a.live_role_id, 0, a.live_role_id
           union all
           select coalesce(r.manager_role_id,'founder'), u.depth+1,
                  u.path||' > '||coalesce(r.manager_role_id,'founder')
             from up u join public.org_role r on r.role_id = u.cur and r.status='active'
            where u.depth < 20 and u.cur <> 'founder')
         select path from up where cur = 'founder' order by depth limit 1
       ), a.reporting_path);

commit;
