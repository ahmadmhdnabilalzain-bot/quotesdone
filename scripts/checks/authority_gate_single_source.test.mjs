// There must be one authority model, and it must be the one the company wrote down.
//
// Audit 7.1. Two models disagreed and the one that ran decided by regex over the action-class NAME:
//
//   if p_action_class ~* 'money|payout|payment|gl_|...|ban' then v_cap := 'gated';
//
// Measured live, that regex fired on 37 of 153 rows and changed the answer on exactly ONE -
// it/code_deploy. `refund_within_window` contains none of those words, so a refund escaped the money
// cap by not spelling "money". Meanwhile fn_ops_authority_check, which reads the ten declared hard
// gates, had zero callers and could not have matched anything anyway: it compared the ten gate names
// against the 153 operational class names, two different vocabularies with no mapping between them.
//
// These are source assertions over the migrations, because the behaviour lives in the database and
// the Node test runner cannot reach it. What they protect is the SHAPE: one signature, no regex, an
// explicit mapping table, and a rule that unreviewed is not unrestricted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const migDir = join(root, 'supabase', 'migrations');
const migs = readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort();
const find = (suffix) => {
  const hit = migs.filter((f) => f.endsWith(suffix));
  assert.equal(hit.length, 1, 'expected exactly one migration ending ' + suffix + ', found ' + hit.length);
  return readFileSync(join(migDir, hit[0]), 'utf8');
};

const gates = find('_audit_71_declared_gates_become_the_runtime_gate.sql');
const dropOverload = find('_audit_71_drop_the_regex_overload_that_would_have_won.sql');
const reviewed = find('_audit_71_every_non_gated_class_is_reviewed.sql');

test('the mapping between the two vocabularies exists and is constrained to the declared gates', () => {
  assert.match(gates, /create table if not exists public\.action_class_gate/,
    'action_class_gate is missing. Without it the ten declared gate names can never match the 153 operational ' +
    'class names, which is why fn_ops_authority_check could not have worked even when called.');
  assert.match(gates, /constraint action_class_gate_known_gate check/,
    'a class can be mapped to a gate that does not exist, so a typo silently means "no gate".');
  assert.match(gates, /rationale\s+text not null/,
    'rationale is nullable, so "no hard gate applies" can be recorded without saying why. An unexplained NULL is ' +
    'indistinguishable from an unreviewed one.');
});

test('unreviewed is not unrestricted', () => {
  assert.match(gates, /if v_map\.action_class is null and v_tier <> 'gated' then/,
    'fn_ops_authority_check does not refuse an autonomous class that has no mapping row. That is precisely how ' +
    'refund_within_window, content_publish, code_selfheal and role_define ran outside the gates that name them.');
  assert.match(reviewed, /max_tier in \('autonomous','supervised'\) and g\.action_class is null/,
    'nothing asserts that every class allowed to act without a human has been reviewed, so the next migration can ' +
    're-open the hole silently.');
});

test('a delegated threshold requires the amount to be stated', () => {
  assert.match(gates, /if v_thresh is not null and p_amount_aed is not null and p_amount_aed <= v_thresh then/,
    'the gate does not honour a delegated threshold, so the founder\'s AED 2,000 in-window refund authority ' +
    'cannot survive being mapped to money_move.');
  assert.match(gates, /a delegated threshold of ' \|\| v_thresh \|\| ' AED exists but no amount was stated/,
    'a caller that omits the amount is not told why it was gated. No amount means no proof it is under the ' +
    'ceiling, and that has to be sayable.');
});

test('the regex cap is gone and cannot return', () => {
  // Only the executable body. The migration quotes the old regex in its header on purpose - the
  // comment explaining a defect must be allowed to name it, or the record of why becomes unwritable.
  const body = gates.slice(gates.indexOf('create or replace function public.fn_ops_authority_check'));
  assert.ok(body.length > 0, 'fn_ops_authority_check is not defined in this migration');
  assert.doesNotMatch(body, /~\*\s*'money\|payout/,
    'the class-name regex is still present in the new authority function.');
  assert.match(dropOverload, /prosrc ilike '%money\|payout\|payment%'/,
    'nothing asserts that the regex is absent after the change, so it could be reintroduced by the next edit of ' +
    'either function.');
});

test('the defaulted parameter did not leave two functions behind', () => {
  // fn_dept_authority gained an optional p_amount_aed, so `create or replace` published a SECOND
  // function rather than replacing the first, and Postgres prefers the exact two-argument signature.
  // intent_router calls it with two arguments, so the old regex version would have kept winning.
  assert.match(dropOverload, /drop function if exists public\.fn_dept_authority\(text, text\)/,
    'the two-argument fn_dept_authority is not dropped, so the single live caller (intent_router) still resolves ' +
    'to the old regex implementation and this entire change is inert.');
  assert.match(dropOverload, /if n <> 1 then/,
    'nothing asserts that exactly one fn_dept_authority signature survives. Adding a defaulted parameter is not ' +
    'editing a function, it is publishing a second one.');
});

test('the event dispatcher reads the tier instead of granting it', () => {
  assert.match(gates, /v_tier := coalesce\(public\.fn_dept_authority\(v_dept, 'analysis'\)->>'tier', 'gated'\)/,
    'fn_event_dispatch does not consult the authority model, so a subscriber is granted autonomy by the ' +
    'dispatcher rather than by the model. This is the 7.3 precondition.');
  assert.doesNotMatch(gates.slice(gates.indexOf('function public.fn_event_dispatch')), /'assigned', 'autonomous'/,
    "fn_event_dispatch still hard-codes 'assigned','autonomous' on every task it creates.");
});
