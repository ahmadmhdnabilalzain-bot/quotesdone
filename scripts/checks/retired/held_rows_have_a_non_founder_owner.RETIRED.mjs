// RETIRED 9 September 2026 -- with its subject, not softened to green.
//
// it read public.founder_command, dropped with the founder-command layer on 9 Sep 2026.
//
// A check whose subject is gone is retired, never edited until it passes: a check that passes
// because the thing it checks no longer exists is a green light over nothing.
// A HELD ROW ALWAYS HAS AN OWNER WHO IS NOT THE FOUNDER.
//
// The founder's standing rule: nothing routes to his approval except a Stripe refund. A read-only audit on
// 5 Sep 2026 found four tables holding non-refund rows in "pending / proposed / awaiting" states that the
// OS showed him as his decisions — 14 agent_actions, 34 org_tasks, 7 decision_records, 6 founder_commands —
// each because a mechanism routed the row and then left it where it was. The mechanisms were fixed
// (fn_agent_action_work_sweep, fn_task_approve, fn_decide + fn_decision_record_route, rule CR-005 in
// fn_founder_command_submit); this check is what keeps the hold from silently coming back.
//
// Each assertion is an absolute zero over rows OLDER than the window, because a row inside the window is
// simply waiting for its hourly sweep and would only make the check flap:
//   1. agent_actions at pending/needs_review older than 24h whose kind's policy is not 'founder'
//      (no kind is 'founder' today, so this is every stale pending row);
//   2. decision_record at 'proposed' with approved_by null older than 24h that no org_task links to
//      (the link is the literal marker [decision_record:<id>] in org_tasks.detail);
//   3. org_tasks at 'proposed' older than 24h that do not carry needs_founder — the only rows that may wait
//      at 'proposed' are refund decisions (a00_org_tasks_founder_routing_refund_only admits nothing else).
//      This is stronger than "in a department with no org_authority row": a hold on a clamped class was
//      just as ownerless, and fn_task_approve now sends every non-refund hold into the lane;
//   4. founder_command at 'clarification_required' older than 7 days.
//
// READ-ONLY against production: every statement is a SELECT under an 8s statement timeout.
//
//   node --test scripts/checks/held_rows_have_a_non_founder_owner.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('agent_actions: no pending/needs_review row older than 24h whose kind is not a founder kind', { skip: SKIP }, async () => {
  const r = await rows(`
    select a.id, a.kind, a.status, a.agent, coalesce(p.policy, '(no policy row)') as policy, a.created_at
      from public.agent_actions a
      left join public.agent_action_kind_policy p on p.kind = a.kind
     where a.status in ('pending', 'needs_review')
       and a.created_at < now() - interval '24 hours'
       and coalesce(p.policy, '') <> 'founder'
     order by a.created_at
     limit 50`);
  assert.equal(r.length, 0, 'these agent_actions are held with nobody to own them (fn_agent_action_work_sweep should have settled or handed them off):\n' + JSON.stringify(r, null, 1));
});

test('decision_record: no proposed row older than 24h without an org_task', { skip: SKIP }, async () => {
  const r = await rows(`
    select d.id, d.decided_by, d.dept_key, left(d.problem, 120) as problem, d.created_at
      from public.decision_record d
     where d.status = 'proposed' and d.approved_by is null
       and d.created_at < now() - interval '24 hours'
       and not exists (select 1 from public.org_tasks t where t.detail like '%[decision_record:' || d.id || ']%')
     order by d.id
     limit 50`);
  assert.equal(r.length, 0, 'these proposed decisions have no org_task owner (fn_decision_record_route should have routed them):\n' + JSON.stringify(r, null, 1));
});

test('org_tasks: no proposed row older than 24h that is not a refund waiting on the founder', { skip: SKIP }, async () => {
  const r = await rows(`
    select t.id, t.dept_key, t.action_class, t.tier, left(t.title, 80) as title, t.created_at,
           left(coalesce(t.result->'held'->>'reason', ''), 160) as held_reason,
           exists (select 1 from public.org_authority a where a.dept_key = t.dept_key and a.action_class = t.action_class) as has_authority_row
      from public.org_tasks t
     where t.status = 'proposed'
       and t.created_at < now() - interval '24 hours'
       and not coalesce(t.needs_founder, false)
     order by t.created_at
     limit 50`);
  assert.equal(r.length, 0, 'these proposals are held with nobody to own them (fn_task_approve should have approved them or sent the hold into the lane; has_authority_row=false is a configuration gap to fill in org_authority):\n' + JSON.stringify(r, null, 1));
});

test('founder_command: no clarification_required row older than 7 days', { skip: SKIP }, async () => {
  const r = await rows(`
    select c.command_id, c.intent_id, c.outcome, c.created_at, left(m.raw_text, 120) as said
      from public.founder_command c
      join public.founder_command_message m on m.message_id = c.message_id
     where c.state = 'clarification_required'
       and c.created_at < now() - interval '7 days'
     order by c.command_id
     limit 50`);
  assert.equal(r.length, 0, 'these founder commands have been bounced back to him for over a week; register the intent (phase_c_command_rule) or resolve them:\n' + JSON.stringify(r, null, 1));
});
