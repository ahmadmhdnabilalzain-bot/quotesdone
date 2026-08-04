// The third writer, and the constraint the registry declared but never enforced.
//
// Audit 7.3 made fn_event_dispatch and cos_execute read the authority model instead of trusting a
// column. `dept_plan` — the third and busiest thing that writes org_tasks — was not included. It
// decided both `status` and `tier` from AUTONOMOUS_SAFE, a hardcoded, DEPARTMENT-BLIND set.
//
// Measured 4 Aug 2026 against fn_dept_authority over every active department x every known action
// class: that constant granted tier='autonomous' to 112 (department, action_class) pairs the model
// grants nothing for, and to one it grants only 'advisory'.
//
// It was not theoretical. org_tasks#20, supplier_success/invite, was created 'autonomous' by this
// path and executed on 25 Jul 2026 — 10 real supplier invites enqueued for a department
// org_authority has no row for, through procurement's fn_org_exec_invite, because cos_execute keyed
// its executor registry on action_class alone and ignored org_action_executor.department.
//
// Three layers should have stopped that and none did. These guards hold two of them.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const plan = readFileSync(join(root, 'supabase', 'functions', 'dept_plan', 'index.ts'), 'utf8');
const cos = readFileSync(join(root, 'supabase', 'functions', 'cos_execute', 'index.ts'), 'utf8');

// The routing site: everything from where the task rows are built to where they are inserted.
const routeStart = plan.indexOf('const rows: any[] = []');
assert.ok(routeStart > 0, 'the task-building block is gone from dept_plan — this guard is testing nothing');
const routing = plan.slice(routeStart, plan.indexOf("from('org_tasks').insert(rows)"));
assert.ok(routing.length > 0, 'dept_plan no longer inserts the rows it builds — this guard is testing nothing');

test('dept_plan resolves the tier from the authority model, not from a set in the file', () => {
  assert.match(routing, /rpc\('fn_dept_authority', \{ p_dept: deptKey, p_action_class: ac \}\)/,
    'dept_plan does not ask fn_dept_authority when it creates a task. It is deciding the tier from a constant, ' +
    'which is how supplier_success/invite came to be written tier=autonomous for a department the model grants ' +
    'nothing to.');
});

test('an unreadable or unknown authority answer refuses rather than permits', () => {
  assert.match(routing, /KNOWN_TIERS\.has\(tv\) \? tv : 'gated'/,
    'a tier the model returns that is not one of the four known tiers must fall to gated. Anything else lets a ' +
    'typo or a schema change become a grant.');
  assert.match(routing, /catch \(_e\) \{ granted = 'gated'; \}/,
    'if fn_dept_authority cannot be reached, dept_plan must create the task gated. An unavailable permission ' +
    'system is not a permissive one.');
});

test('the surviving constant can only refuse autonomy, never confer it', () => {
  // Match the CALL, not the name: the name still appears in the block comment that records the
  // defect, and a guard that fails on its own history would just get the history deleted.
  assert.doesNotMatch(plan, /AUTONOMOUS_SAFE\.has\(/,
    'AUTONOMOUS_SAFE is being consulted again. That set GRANTED autonomy; the whole defect was that a constant ' +
    'in a file could grant.');
  assert.match(routing, /rank\(granted\) > rank\(ceiling\) \? ceiling : granted/,
    'the ceiling is not applied as a minimum. It must only ever lower the model tier — a file may restrict, ' +
    'it may not permit.');
  // The ceiling is a clamp, so it can never be the thing that produces 'autonomous'.
  assert.doesNotMatch(routing, /tier: gated \? 'gated' : 'autonomous'/,
    'the old constant-driven tier assignment is still present.');
});

test('the department head may tighten its own routing but never loosen it', () => {
  assert.match(routing, /needs_founder === true && rank\(tier\) > rank\('gated'\)/,
    'needs_founder from the model output must only be able to move a task toward gated. If it can move a task ' +
    'away from gated, the plan text is deciding its own permissions.');
});

test('a clamp between the model and the ceiling is recorded, not swallowed', () => {
  assert.match(routing, /clamped\.push/,
    'where the model grants more than the ceiling allows, the gap must be recorded. An invisible clamp is a ' +
    'policy decision nobody can find later.');
  assert.match(plan, /routing_clamped/,
    'the clamp signal never reaches agent_runs, so the 14 pairs the ceiling withholds cannot be measured.');
});

test('a department cannot be given an action class it has no executor for', () => {
  assert.match(routing, /!ownClasses\.has\(ac\)/,
    'dept_plan writes whatever action_class the model returned straight into org_tasks. The prompt asks for one ' +
    'of the department’s own capabilities; nothing made it comply, and an invented class goes on to be looked ' +
    'up in an authority model that has never heard of it.');
});

// ---- the executor registry ----

test('the executor registry is keyed on action_class AND department', () => {
  assert.match(cos, /const execKey = \(ac: string, dept: string\)/,
    'cos_execute has no composite executor key. org_action_executor.department is declared on every active row ' +
    'and was being ignored: org_tasks#20 ran procurement’s invite executor as supplier_success.');
  assert.match(cos, /execMap\.get\(execKey\(t\.action_class, t\.dept_key\)\)/,
    'the executor lookup does not use the composite key, so a task can still reach another department’s executor.');
  // The class-only map still exists — it is how the refusal names the foreign executor — so the
  // assertion has to be that nothing LOOKS UP an executor by class alone.
  assert.doesNotMatch(cos, /execMap\.get\(t\.action_class\)/,
    'an executor is still being resolved from action_class alone. That single lookup is what let ' +
    'supplier_success run procurement’s invite executor.');
  assert.doesNotMatch(cos, /const ex(: any)? = execAnyDept/,
    'the class-only map is feeding the execution path. It exists to NAME a refused foreign executor, never to ' +
    'supply one.');
});

test('a cross-department executor match is refused loudly, not silently', () => {
  assert.match(cos, /executor_department_mismatch/,
    'when a task’s class has an executor owned by another department, the refusal must be reported. Silence here ' +
    'is indistinguishable from "no executor exists", which is the state that hid this for six weeks.');
});
