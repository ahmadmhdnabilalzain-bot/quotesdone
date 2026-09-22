// RETIRED 9 September 2026 -- with its subject, not softened to green.
//
// phase_c_component and phase_c_component_crosswalk are gone.
//
// A check whose subject is gone is retired, never edited until it passes: a check that passes
// because the thing it checks no longer exists is a green light over nothing.
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
const mgmtRead = async (ref, sql) => (await import('../../lib/qd_guard.mjs')).mgmtRead(ref, sql);
const rows = async (sql) => { const r = await mgmtRead(PROD_REF, sql); return Array.isArray(r) ? r : []; };
const show = (label, list, fmt) => {
  if (!list.length) return;
  console.error(`${label}: ${list.length}`);
  for (const r of list.slice(0, 25)) console.error('  ' + fmt(r));
  if (list.length > 25) console.error(`  ... and ${list.length - 25} more`);
};

// A COMPONENT THAT NAMES AN OWNER NAMES A REAL ONE. Until 7 Sep 2026 this asserted that EVERY
// component had an active owner. The founder removed the organisation chart that day and said "keep
// them unlinked now till we come up with the new structure", so 1,664 components are deliberately
// unowned and that assertion would now fail on the company's own intended state.
//
// What is still worth asserting, and is asserted here: a component that DOES name a role names one
// that exists and is active. That is the defect this check was written for -- a stale reference to
// somebody who left -- and it is untouched. An absent owner is the founder's decision; a wrong owner
// is a bug.
test('every component that names an owner names an active canonical role', { skip }, async () => {
  const bad = await rows(`
    select c.component_id, c.accountable_role_id, coalesce(r.status, '(no such role)') role_status
      from public.phase_c_component c
      left join public.org_role r on r.role_id = c.accountable_role_id
     where coalesce(btrim(c.accountable_role_id), '') <> ''
       and (r.role_id is null or r.status <> 'active')
     order by 1`);
  show('components whose accountable role is not an active canonical role', bad,
    (r) => `${r.component_id}  ->  ${r.accountable_role_id} (${r.role_status})`);
  assert.equal(bad.length, 0);
});

// THERE ARE NO DEPARTMENTS. This asserted that every component sat in an ACTIVE department and that
// the department was its role's. The founder removed every department on 7 Sep 2026 -- "so no
// departments from now" -- so the old assertion has no subject left.
//
// It is not deleted, it is INVERTED, because the ruling is worth guarding: no component may name a
// department, and no department may exist. If either creeps back the check goes red, which is the
// only way this ruling survives contact with the next person who reaches for a dept_key.
test('no component names a department, because there are none', { skip }, async () => {
  const withDept = await rows(`
    select component_id, department_id from public.phase_c_component
     where coalesce(btrim(department_id), '') <> '' order by 1`);
  const depts = await rows(`select dept_key from public.org_departments order by 1`);
  show('components still naming a department', withDept,
    (r) => `${r.component_id}  ->  ${r.department_id}`);
  show('departments that exist again', depts, (r) => r.dept_key);
  assert.equal(withDept.length + depts.length, 0);
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
  // The floor was 100 and the estate now has 68: 137 functions were deleted on 8 Sep 2026 under the
  // founder's rule that anything belonging to neither the CEO, the customer-support agent nor the
  // website does not exist.
  //
  // Lowered rather than removed, because this assertion is not a business rule about how large the
  // estate should be -- its own message says what it is for: "wrong directory?". It exists to catch
  // a path mistake, where the glob resolves somewhere with no functions in it and every downstream
  // check then passes vacuously over an empty list. 20 still catches that (a wrong directory yields
  // zero or a handful) while letting the real count through.
  //
  // Deleting the guard would have been the easier edit and the wrong one: vacuous passes over an
  // empty set are exactly what it was written to prevent.
  assert.ok(slugs.length > 20, `only ${slugs.length} edge functions found under supabase/functions — wrong directory?`);
  assert.equal(missing.length, 0);
});
