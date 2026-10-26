-- LESSONS REACH THE CURRENT DEPARTMENT (autonomy audit, degrading gap 14).
--
-- MEASURED. org_memory holds 71 kind='lesson' rows, but only 16 sit under a currently-active department
-- key; the other 55 are stranded under inactive pre-reorg scopes (the exact-match-scoping-breaks-on-merge
-- defect), so a merged department cannot read its own inherited history and departments plan in isolation
-- with no peer-learning channel.
--
-- THIS FILE adds a read-only view that resolves each lesson's legacy scope to its current department AT
-- READ TIME via org_departments.merged_into (already the fully-populated reorg alias — NOT a new
-- dept_scope_alias table, which would be a second source of truth), and also surfaces 'global' shared
-- lessons. org_memory is never rewritten; origin_scope keeps the provenance. The deterministic read layer
-- is complete here; the reasoning that consumes these lessons in dept_plan is model-held (OpenRouter), so
-- this ships correct-but-inert until inference is funded.
--
--   node scripts/apply_sql.mjs scripts/sql/v_peer_lessons.sql --apply --ddl

begin;

create or replace view public.v_peer_lessons as
  select m.id,
         coalesce(d.merged_into, m.scope) as current_dept,   -- single-hop merge resolve
         m.scope as origin_scope, m.kind, m.content, m.created_at, m.source,
         (m.scope = 'global') as is_shared
    from public.org_memory m
    left join public.org_departments d on d.dept_key = m.scope
   where m.active and m.kind = 'lesson'
     and ( m.scope = 'global'
           or coalesce(d.merged_into, m.scope) in (select dept_key from public.org_departments where active) );

revoke all on public.v_peer_lessons from anon, authenticated;   -- internal ops content
grant select on public.v_peer_lessons to service_role;

commit;
