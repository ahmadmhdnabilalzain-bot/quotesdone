// EVERY RUNTIME COMPONENT IS OWNED, AND EVERY LIVE ENTRY POINT IS A COMPONENT — read from
// production, never from a committed copy of it (3 Sep 2026).
//
// This replaces phase_c_component_crosswalk.test.mjs (now .RETIRED.mjs). That check kept the
// component registry three times — as SQL literals in scripts/sql, as a committed CSV, and as the
// live table — and compared the copies on 23 columns. The copies were right only on the day they
// were emitted: a cron re-enable, a role rename or a department re-carve made them wrong, the gate
// went red for bookkeeping, and the day's work became re-emitting mirrors. On 3 Sep 2026 the org
// re-carve took one file and the mirrors took six.
//
// What the mirror was DEFENDING is kept, as properties of production itself:
//   1. every component is accountable to an ACTIVE canonical role;
//   2. every component sits in an ACTIVE department, and that department is its role's;
//   3. every active component carries a trace policy;
//   4. every active cron job, every active event subscription and every deployed edge function
//      IS a component (nothing runs in this estate without an owner), and no cron/subscription
//      component names a job or subscription that no longer exists.
// A new cron, subscription or function that lands without an owner reddens this test — that is
// the defect the old "declared, not in the crosswalk" line caught, measured where it lives.
//
// The classification-versus-reachability rule (an INACTIVE row that is reachable, an ACTIVE row
// that is not) is enforced at write time by a00_phase_c_component_classification_guard and read
// by the kernel boards; it is not repeated here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
const skip = hasToken ? false : 'no Supabase management token';

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const mgmtRead = async (ref, sql) => (await import('../staging/qd_guard.mjs')).mgmtRead(ref, sql);
const rows = async (sql) => { const r = await mgmtRead(PROD_REF, sql); return Array.isArray(r) ? r : []; };
const show = (label, list, fmt) => {
  if (!list.length) return;
  console.error(`${label}: ${list.length}`);
  for (const r of list.slice(0, 25)) console.error('  ' + fmt(r));
  if (list.length > 25) console.error(`  ... and ${list.length - 25} more`);
};

test('every component is accountable to an active canonical role', { skip }, async () => {
  const bad = await rows(`
    select c.component_id, c.accountable_role_id, coalesce(r.status, '(no such role)') role_status
      from public.phase_c_component c
      left join public.org_role r on r.role_id = c.accountable_role_id
     where r.role_id is null or r.status <> 'active'
     order by 1`);
  show('components whose accountable role is not an active canonical role', bad,
    (r) => `${r.component_id}  ->  ${r.accountable_role_id} (${r.role_status})`);
  assert.equal(bad.length, 0);
});

test('every component sits in an active department, and it is its role\'s department', { skip }, async () => {
  const bad = await rows(`
    select c.component_id, c.department_id, r.primary_department_id role_dept, coalesce(d.active, false) dept_active
      from public.phase_c_component c
      join public.org_role r on r.role_id = c.accountable_role_id and r.status = 'active'
      left join public.org_departments d on d.dept_key = c.department_id
     where d.dept_key is null or not d.active or c.department_id is distinct from r.primary_department_id
     order by 1`);
  show('components whose department is inactive or is not their role\'s', bad,
    (r) => `${r.component_id}  department ${r.department_id} (active=${r.dept_active}), role sits in ${r.role_dept}`);
  assert.equal(bad.length, 0);
});

test('every active component carries a trace policy', { skip }, async () => {
  const bad = await rows(`
    select component_id from public.phase_c_component
     where activation_state = 'active' and coalesce(btrim(trace_policy_id), '') = ''
     order by 1`);
  show('active components with no trace policy', bad, (r) => r.component_id);
  assert.equal(bad.length, 0);
});

test('every active cron job is a component, and every cron component names a live job', { skip }, async () => {
  const missing = await rows(`
    select j.jobid, j.jobname from cron.job j
     where j.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'cron:' || j.jobname)
     order by 2`);
  const orphan = await rows(`
    select c.component_id from public.phase_c_component c
     where c.component_id like 'cron:%'
       and not exists (select 1 from cron.job j where 'cron:' || j.jobname = c.component_id)
     order by 1`);
  show('active cron jobs with no component (nothing owns them)', missing, (r) => `${r.jobname} (jobid ${r.jobid})`);
  show('cron components naming a job that no longer exists', orphan, (r) => r.component_id);
  assert.equal(missing.length + orphan.length, 0);
});

test('every active event subscription is a component, and every subscription component is live', { skip }, async () => {
  const missing = await rows(`
    select s.agent_key, s.event_type from public.event_subscription s
     where s.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type)
     order by 1, 2`);
  const orphan = await rows(`
    select c.component_id from public.phase_c_component c
     where c.component_id like 'evsub:%' and c.activation_state = 'active'
       and not exists (select 1 from public.event_subscription s where s.active and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id)
     order by 1`);
  show('active subscriptions with no component', missing, (r) => `${r.agent_key} @ ${r.event_type}`);
  show('active subscription components whose subscription is gone or inactive', orphan, (r) => r.component_id);
  assert.equal(missing.length + orphan.length, 0);
});

test('every deployed edge function in the repository is a component', { skip }, async () => {
  const dir = join(process.cwd(), 'supabase', 'functions');
  const slugs = readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_') && existsSync(join(dir, d.name, 'index.ts')))
    .map((d) => d.name);
  const known = new Set((await rows(`select component_id from public.phase_c_component where component_id like 'edge:%'`))
    .map((r) => r.component_id.slice(5)));
  const missing = slugs.filter((s) => !known.has(s));
  show('edge functions in supabase/functions with no component', missing, (s) => s);
  assert.ok(slugs.length > 100, `only ${slugs.length} edge functions found under supabase/functions — wrong directory?`);
  assert.equal(missing.length, 0);
});
