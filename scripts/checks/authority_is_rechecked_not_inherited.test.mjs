// A permission carried in the payload is not a permission. It is a claim by the caller.
//
// Audit 7.3. cos_execute is the engine that runs registered executors - real side effects, including
// the refunds_api executor. It gated execution on org_tasks.tier, a column written by whoever created
// the row. Three things write tasks and only intent_router consulted the authority model, so
// fn_event_dispatch hard-coded tier 'autonomous' on every task it created and cos_execute ran them
// without ever asking whether that department may act on that class.
//
// The audit's own words: "cos_execute re-checks nothing - whoever writes the row decides."
//
// Both halves are asserted here because either alone is insufficient: the dispatcher must stop
// granting authority, AND the executor must stop trusting the grant.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const cos = readFileSync(join(root, 'supabase', 'functions', 'cos_execute', 'index.ts'), 'utf8');

const loopStart = cos.indexOf('for (const t of batch)');
assert.ok(loopStart > 0, 'the task loop is gone from cos_execute - this guard is now testing nothing');
const loop = cos.slice(loopStart);

test('the executor resolves authority at execution time, from the model', () => {
  assert.match(loop, /rpc\('fn_dept_authority', \{ p_dept: t\.dept_key, p_action_class: t\.action_class \}\)/,
    'cos_execute does not ask fn_dept_authority before running an executor. It is trusting org_tasks.tier, which ' +
    'is written by whoever created the row.');
  assert.match(loop, /const grantedTier = String\(authRow\?\.tier \|\| 'gated'\)/,
    'the resolved tier is not defaulted to gated. An unreadable authority answer must refuse, not permit.');
});

test('a real executor runs only on a tier the model granted', () => {
  // Match the whole guard line. The condition contains its own parentheses, so a [^)]* scan stops
  // at the first ')' and silently reads only a prefix of the thing being asserted about.
  const guard = loop.split('\n').find((l) => l.trim().startsWith('if (ex &&'));
  assert.ok(guard, 'could not find the executor guard in cos_execute');
  assert.match(guard, /grantedTier === 'autonomous'/,
    'the executor guard does not require the MODEL to have granted autonomy. Before this it read ' +
    "`if (ex && (t.tier !== 'advisory' || ex.advisory_safe))` - which executes on the strength of a column the " +
    'caller supplied. refunds_api is one of the registered executors.');
});

test('a task claiming more authority than the model grants is reported', () => {
  assert.match(loop, /tier_claim_exceeds_grant/,
    'a row written with tier=autonomous that the model does not grant is silently downgraded. Silently is wrong: ' +
    'something upstream minting authority it does not have is the signal worth keeping, not the one to swallow.');
});

test('the event dispatcher no longer grants the tier it writes', () => {
  const migDir = join(root, 'supabase', 'migrations');
  const mig = readdirSync(migDir).filter((f) => f.endsWith('_audit_71_declared_gates_become_the_runtime_gate.sql'));
  assert.equal(mig.length, 1, 'the migration that rewrote fn_event_dispatch is not in the repo');
  const sql = readFileSync(join(migDir, mig[0]), 'utf8');
  const fn = sql.slice(sql.indexOf('function public.fn_event_dispatch'));
  assert.ok(fn.length > 0, 'fn_event_dispatch is not defined in that migration');
  assert.match(fn, /fn_dept_authority\(v_dept, 'analysis'\)/,
    'fn_event_dispatch does not read the tier from the model.');
  assert.doesNotMatch(fn, /'assigned', 'autonomous'/,
    "fn_event_dispatch still hard-codes 'assigned','autonomous' on every task it creates.");
});
