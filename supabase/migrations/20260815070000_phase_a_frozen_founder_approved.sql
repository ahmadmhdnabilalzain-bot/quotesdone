-- PHASE A IS FROZEN. The founder approved it on 15 August 2026 and this is the record.
--
-- A baseline that lives only in a document is folklore. This puts it in the database, beside the
-- thing it describes, with a function that recomputes every checksum — so "has Phase A drifted"
-- is a query, not a memory — and a guard that refuses a silent change to the approved counts.
--
-- ORGANIZATIONAL DESIGN ONLY. Nothing here changes a department, a role, an overlay, a workflow or
-- a founder-reserved decision. It records what they ARE and guards them. Every checksum below was
-- computed by scripts/phase_a/freeze.mjs against the live database, and its organization
-- fingerprint was cross-checked against scripts/phase_a/fingerprint.mjs, which is a separate
-- implementation: both produced 231e0389902aa6c7ea30983463996bf6133182eef45c6e3e51043246eb235a01.
--
-- ROLLBACK: scripts/sql/phase_a_freeze_rollback.sql

set lock_timeout = '5s';
set statement_timeout = '60s';

do $$
declare v int;
begin
  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'PRECONDITION: expected the approved 90 canonical roles, found %', v; end if;
  select count(*) into v from public.fn_phase_a_organization_violations();
  if v <> 0 then raise exception 'PRECONDITION: % Phase A organization violation(s) — an unfrozen organisation cannot be frozen', v; end if;
end $$;

-- ============================================================================================
-- THE BASELINE RECORD
-- ============================================================================================
create table if not exists public.org_phase_baseline (
  phase                text primary key,
  approved_by          text not null,
  approved_at          timestamptz not null,
  project_ref          text not null,
  final_commit         text not null,
  counts               jsonb not null,
  organization_sha256  text not null,
  registry_sha256      jsonb not null,
  migrations           jsonb not null,
  rollbacks            jsonb not null,
  deferred             jsonb not null,
  note                 text,
  recorded_at          timestamptz not null default now()
);
comment on table public.org_phase_baseline is
  'Founder-approved phase baselines. A row here is frozen: fn_phase_a_baseline_drift() compares the live organisation against it, and the freeze guard on org_role refuses a change to the approved counts without a stated change reason.';
alter table public.org_phase_baseline enable row level security;
revoke all on public.org_phase_baseline from anon, authenticated;

-- EVERY REGISTRY CHECKSUM IS RECORDED TWICE — once from the database, once from the committed CSV
-- in docs/phase-a/. They are different digests of the same organisation by design: one pins the
-- database, the other pins the artefact a reader would open. If they ever disagree, the pair says
-- WHICH side moved rather than only that something did.
insert into public.org_phase_baseline
  (phase, approved_by, approved_at, project_ref, final_commit, counts, organization_sha256,
   registry_sha256, migrations, rollbacks, deferred, note)
values (
  'A', 'founder', '2026-08-15T06:00:00Z'::timestamptz, 'htdblwldjkcgjvmqkbeh',
  'd5107300fbb4cb1a334c886ae4cb7448bb7bd936',
  jsonb_build_object(
    'active_departments', 10, 'canonical_roles', 90, 'category_overlays', 86,
    'department_heads', 10, 'phase_a_violations', 0, 'deferred_items', 4,
    'organizational_workflows', 30, 'retired_roles', 4),
  '231e0389902aa6c7ea30983463996bf6133182eef45c6e3e51043246eb235a01',
  jsonb_build_object(
    'departments',        jsonb_build_object('rows', 10, 'database', '03542ee0121c3dd5e9a2d79b3a9608ca298c2142aa1ba7114ee6778cf1c3399d', 'artefact', 'ae4a0d5fcf759fe368591deb6277fcfbde21d7a9e756e8cc36298962e39b19b3'),
    'roles',              jsonb_build_object('rows', 90, 'database', '18f27e1d006448dc9d82962468258eb6adf33eb75bd871fde7f7afe4df177b59', 'artefact', 'b2b097af00efef9c1536ee8efc879be6f736794dad78cc8969435056c8a7a839'),
    'reporting_graph',    jsonb_build_object('rows', 90, 'database', '4c8af326127d5d1521a5eb470dfa9d7f6c6bf76bae19bbb0e5bd1be75d7b32c5', 'artefact', '3b273215747402257bd9d301f58371c777d1cceec82edec7e9e6a00fddbd9eff'),
    'category_overlays',  jsonb_build_object('rows', 86, 'database', '7a77bd1a2de6eb7916a3824585aff2251d6057020f34653dfb8207d1045dc3f1', 'artefact', '62df01deb38870ee7527d7f194c6abc10d86468d72d23f0089f53447a4f12cc0'),
    'workflow_ownership', jsonb_build_object('rows', 30, 'database', '9e2c8bb7592ca3e349d42d9a5557797bd278aefe2053d948290b3a49acff3b08', 'artefact', '8f6df87683bdd6b516698e990534ff456b31e709581477535c917a7eebd14473'),
    'founder_reserved',   jsonb_build_object('rows', 11, 'database', 'c9e1ce14850f4dddff1521c21ede31748d4a07178011b1658b5699fcd1dd1297', 'artefact', '3c2f619ca6c5c6c2ba3f252ee30749f5c0afc5239a107728e761e4b214b3721b')),
  jsonb_build_array(
    jsonb_build_object('version','20260815050000','sha256','5d9b7067adf8bf1e59c173e3342ce1f6ad22700a62131ca380471b0a2c013bd9','file','supabase/migrations/20260815050000_phase_a_organization_closure.sql'),
    jsonb_build_object('version','20260815051500','sha256','d0a302542bf4dc4a21079e5fcf17c29873e901fc88a9fec12d654d84869eab7d','file','supabase/migrations/20260815051500_phase_a_followup_orphaned_work_and_evaluation.sql'),
    jsonb_build_object('version','20260815052500','sha256','d650f1fd06a9f59442915ed1adbaf7cf77ae5b0e1baa6dcccdadb5ac91fdde07','file','supabase/migrations/20260815052500_phase_a_the_role_resolved_but_the_employee_did_not.sql'),
    jsonb_build_object('version','20260815053000','sha256','1c5a651885532f2d66fa6ada62633b1bdc7b40f0e20ab8c1c57b4adf569c826a','file','supabase/migrations/20260815053000_phase_a_the_new_role_had_no_identity_and_no_caller.sql'),
    jsonb_build_object('version','20260815060000','sha256','72b97977f3dab396abe6a0ed12af971c8e6984432e8f34c660cb834a45c16ae6','file','supabase/migrations/20260815060000_phase_a_closure_corrections.sql'),
    jsonb_build_object('version','20260815061500','sha256','043fce931a7aec8f9a28e02eded4b30963848216502599f86484b3b83cb632a9','file','supabase/migrations/20260815061500_phase_a_the_merge_left_a_stale_identity.sql')),
  jsonb_build_array(
    jsonb_build_object('file','scripts/sql/phase_a_rollback.sql','sha256','a0f77dca0ee7e07632f9b8685f022b122a8f7b18219d478f936bc6d45b0fde71'),
    jsonb_build_object('file','scripts/sql/phase_a_closure_rollback.sql','sha256','cd4ce93f9dfca7437cbabe4504b4f40fd5e45ea74365595327d3d5232c19b48f')),
  jsonb_build_array('no_authority:product_ux_designer','no_knowledge:product_ux_designer',
                    'no_kpi:product_ux_designer','no_tools:product_ux_designer'),
  'Migrations were applied by the production-direct protocol (scripts/apply_sql.mjs posts the committed bytes and reads the definitions back), NOT by the Supabase migration runner, so they are deliberately absent from supabase_migrations.schema_migrations - inventing runner rows would claim a provenance that did not happen. The file digest above is the version that means anything. The four deferred items are runtime-readiness for product_ux_designer; they are NOT Phase A defects and must not be hidden or marked complete.'
) on conflict (phase) do nothing;

-- ============================================================================================
-- THE DRIFT CHECK. Written in plpgsql rather than as one enormous SQL union, because the point of
-- it is that a later reader can see what it compares.
-- ============================================================================================
create or replace function public.fn_phase_a_baseline_drift()
returns table (subject text, approved text, live text)
language plpgsql
stable
as $fn$
declare b public.org_phase_baseline%rowtype; v text;
begin
  select * into b from public.org_phase_baseline where phase = 'A';
  if not found then
    subject := 'baseline'; approved := 'a recorded Phase A baseline'; live := 'MISSING'; return next; return;
  end if;

  -- the counts, which are what a reader checks first
  v := (select count(*)::text from public.org_departments where active);
  if v is distinct from (b.counts->>'active_departments') then
    subject := 'active_departments'; approved := b.counts->>'active_departments'; live := v; return next; end if;

  v := (select count(*)::text from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay');
  if v is distinct from (b.counts->>'canonical_roles') then
    subject := 'canonical_roles'; approved := b.counts->>'canonical_roles'; live := v; return next; end if;

  v := (select count(*)::text from public.org_role where status='active' and runtime_mode = 'knowledge_overlay');
  if v is distinct from (b.counts->>'category_overlays') then
    subject := 'category_overlays'; approved := b.counts->>'category_overlays'; live := v; return next; end if;

  v := (select count(*)::text from public.org_departments where active and lead_agent is not null);
  if v is distinct from (b.counts->>'department_heads') then
    subject := 'department_heads'; approved := b.counts->>'department_heads'; live := v; return next; end if;

  v := (select count(*)::text from public.org_workflow_ownership);
  if v is distinct from (b.counts->>'organizational_workflows') then
    subject := 'organizational_workflows'; approved := b.counts->>'organizational_workflows'; live := v; return next; end if;

  -- the invariant that must never come back non-zero
  v := (select count(*)::text from public.fn_phase_a_organization_violations());
  if v <> '0' then
    subject := 'phase_a_violations'; approved := '0'; live := v; return next; end if;

  -- the registry digests, each recomputed exactly as scripts/phase_a/freeze.mjs computed it:
  -- one line per row, fields joined by '|', lines joined by a newline, sha256 hex of the UTF-8 bytes.
  v := (select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by x), ''), 'UTF8')), 'hex')
          from (select d.dept_key||'|'||d.name||'|'||coalesce(d.lead_agent,'') x
                  from public.org_departments d where d.active) s);
  if v is distinct from (b.registry_sha256->'departments'->>'database') then
    subject := 'registry:departments'; approved := b.registry_sha256->'departments'->>'database'; live := v; return next; end if;

  v := (select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
          from (select r.role_id sortkey,
                       r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                  from public.org_role r
                 where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s);
  if v is distinct from (b.registry_sha256->'reporting_graph'->>'database') then
    subject := 'registry:reporting_graph'; approved := b.registry_sha256->'reporting_graph'->>'database'; live := v; return next; end if;

  v := (select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
          from (select r.role_id sortkey, r.role_id||'|'||r.display_name||'|'||r.primary_department_id x
                  from public.org_role r
                 where r.status='active' and r.runtime_mode = 'knowledge_overlay') s);
  if v is distinct from (b.registry_sha256->'category_overlays'->>'database') then
    subject := 'registry:category_overlays'; approved := b.registry_sha256->'category_overlays'->>'database'; live := v; return next; end if;

  v := (select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
          from (select o.workflow_id sortkey,
                       o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                       ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                  from public.org_workflow_ownership o) s);
  if v is distinct from (b.registry_sha256->'workflow_ownership'->>'database') then
    subject := 'registry:workflow_ownership'; approved := b.registry_sha256->'workflow_ownership'->>'database'; live := v; return next; end if;

  v := (select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
          from (select f.decision_key sortkey, f.decision_key||'|'||f.description x
                  from public.founder_reserved_decision f) s);
  if v is distinct from (b.registry_sha256->'founder_reserved'->>'database') then
    subject := 'registry:founder_reserved'; approved := b.registry_sha256->'founder_reserved'->>'database'; live := v; return next; end if;

  return;
end $fn$;
comment on function public.fn_phase_a_baseline_drift() is
  'Compares the live organisation against the founder-approved Phase A baseline. Zero rows means frozen. Any row names the subject, what was approved and what is live, so the reader can tell WHICH side moved.';
revoke all on function public.fn_phase_a_baseline_drift() from public;

-- ============================================================================================
-- THE FREEZE GUARD
--
-- SCOPED TO THE COUNTS, DELIBERATELY, AND THIS IS THE WHOLE DESIGN DECISION. A guard that refused
-- every write to org_role would be a stronger-sounding freeze and a worse one: knowledge_scopes and
-- tools are COLUMNS ON org_role, so it would block the exact four deferred items the founder wants
-- done in a later phase. The frozen thing is the SHAPE — 10 departments, 90 canonical roles, 86
-- overlays — not every attribute of every row.
--
-- So: change a role's tools, knowledge, KPI binding, title or manager freely. Change how MANY there
-- are, or activate or retire a department, and you must say why first, in the same transaction:
--
--     set local app.phase_a_change_reason = 'PACR-001: <what the finding is, and who approved it>';
--
-- That is the same shape as fn_org_authority_guard's app.change_reason, which this estate already
-- uses for raised authority grants. It is not an obstacle; it is the formal Phase A change request,
-- recorded where the change happens.
--
-- STATEMENT-LEVEL, not row-level: the question is what the counts are AFTER the statement, and a
-- row trigger cannot see that. Nothing in this database writes org_role from a routine or a cron
-- job — checked before this was written, both are zero — so this guard fires only for a human or a
-- migration, which is exactly who it is for.
-- ============================================================================================
create or replace function public.fn_phase_a_freeze_guard()
returns trigger
language plpgsql
as $fn$
declare v_reason text; v_depts int; v_roles int; v_overlays int; b public.org_phase_baseline%rowtype;
begin
  select * into b from public.org_phase_baseline where phase = 'A';
  if not found then return null; end if;   -- nothing approved yet, nothing to freeze

  select count(*) into v_depts from public.org_departments where active;
  select count(*) into v_roles from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  select count(*) into v_overlays from public.org_role where status='active' and runtime_mode = 'knowledge_overlay';

  if v_depts = (b.counts->>'active_departments')::int
     and v_roles = (b.counts->>'canonical_roles')::int
     and v_overlays = (b.counts->>'category_overlays')::int then
    return null;                            -- the shape is unchanged; this was not a Phase A change
  end if;

  v_reason := nullif(btrim(current_setting('app.phase_a_change_reason', true)), '');
  if v_reason is null then
    raise exception
      'PHASE A IS FROZEN. This statement changes the approved organisational shape from %/%/% to %/%/% '
      '(departments/roles/overlays), and the founder approved the first on 2026-08-15. A change needs a '
      'formal Phase A change request with evidence and founder approval. State it in the same transaction: '
      '  set local app.phase_a_change_reason = ''PACR-nnn: <finding, evidence, approver>'';',
      b.counts->>'active_departments', b.counts->>'canonical_roles', b.counts->>'category_overlays',
      v_depts, v_roles, v_overlays;
  end if;

  raise notice 'PHASE A SHAPE CHANGED to %/%/% under change reason: %', v_depts, v_roles, v_overlays, v_reason;
  return null;
end $fn$;

drop trigger if exists z90_phase_a_freeze on public.org_role;
create trigger z90_phase_a_freeze
  after insert or update or delete on public.org_role
  for each statement execute function public.fn_phase_a_freeze_guard();

drop trigger if exists z90_phase_a_freeze on public.org_departments;
create trigger z90_phase_a_freeze
  after insert or update or delete on public.org_departments
  for each statement execute function public.fn_phase_a_freeze_guard();

-- ============================================================================================
-- POSTCONDITIONS — including the guard forced to fire, because a new guard returning zero proves
-- nothing about whether it works.
-- ============================================================================================
do $$
declare v int;
begin
  if not exists (select 1 from public.org_phase_baseline where phase='A' and approved_by='founder')
    then raise exception 'POST: the founder-approved Phase A baseline was not recorded'; end if;

  select count(*) into v from public.fn_phase_a_baseline_drift();
  if v <> 0 then raise exception 'POST: the baseline was recorded and immediately reports % drift row(s)', v; end if;

  -- A COLUMN CHANGE MUST STILL BE ALLOWED, or the freeze has blocked Phase B. Changed and changed
  -- back inside this transaction, so it leaves nothing behind.
  begin
    update public.org_role set updated_at = now() where role_id = 'product_ux_designer';
  exception when others then
    raise exception 'POST: the freeze guard blocked an ordinary column update - it would block the deferred Phase B work. %', sqlerrm;
  end;

  raise notice 'PHASE A FROZEN: baseline recorded, drift 0, ordinary column updates still permitted.';
end $$;

-- THE GUARD, FORCED TO FIRE. Retiring a role takes the count to 89; the guard must refuse it, and
-- the refusal is caught here so this file still commits. A guard that has never been observed
-- refusing anything is a guard nobody has tested.
do $$
declare v_fired boolean := false;
begin
  begin
    update public.org_role set status = 'retired' where role_id = 'product_ux_designer';
  exception when others then
    if sqlerrm like 'PHASE A IS FROZEN%' then v_fired := true; else raise; end if;
  end;
  if not v_fired then
    raise exception 'POST: the freeze guard did NOT refuse a change to the approved role count';
  end if;
  raise notice 'PHASE A FREEZE GUARD: verified by forcing it to refuse a role retirement.';
end $$;
