// RETIRED 7 SEPTEMBER 2026 — ITS SUBJECT WAS REMOVED, NOT BROKEN.
//
// This asserted that every workflow step, event, subscription and executor connects to an active agent or executor.
//
// On 7 September 2026 the founder removed, in his own words: the organisation chart ("remove the
// whole organization chart that you made cause its trash"), every pre-programmed workflow ("i dont
// want any pre programmed workflow as things will totally be different"), and finally the kernel
// gates themselves ("i said remove the kernel gates").
//
// What is gone: 30 workflows, 257 steps, 8 handoffs, 347 events, 56 business objects, 54 rules, 32
// gates, every Phase C binding, every Phase D handler schema and fixture, 41 event subscriptions,
// 94 action executors, and the 36 kernel write/trace/parent-delete gate triggers.
//
// So this file is not red because the estate regressed. It is red because every noun in it was
// deliberately deleted. It is RETIRED rather than edited down to something that passes: a check
// rewritten until it goes green against an empty schema asserts nothing while still looking like a
// guard, and that is worse than no check at all.
//
// WHAT REPLACES IT: nothing yet, and that is said plainly rather than hidden. When the new
// structure exists it deserves checks written fresh against THAT structure. Do not recover this
// file; write the new one from what the company then is.
//
// WHAT STILL GUARDS THE ESTATE TODAY, all green: kernel_invariants,
// cancellation_reaches_the_kernel, every_discharge_claim_reaches_its_table,
// anon_cannot_execute_security_definer (security, and it never depended on the org),
// phase_c_components_are_owned, canonical_routine_manifest, export_from_either_source_is_identical
// and receipts_never_wait_on_the_founder.
//
// Removed from .github/workflows/project-parity.yml in the same commit. Do not re-add this file.

/* eslint-disable */
// The autonomous company is wired as one team — proven deterministically, held by CI.
//
// The connectivity "audit" used to be run by fleets of LLM agents. LLM agents explore differently
// every run, so the finding set ROTATED and never converged — 114 one pass, 8 the next, a different
// 8 after that — which made "is the company fully wired?" unanswerable and "finish the list"
// impossible. public.fn_company_connectivity_register() replaces that with one reproducible
// instrument: it enumerates every true structural connectivity gap from the estate's own tables and
// returns the SAME set every run. This test asserts that set is empty.
//
// The five classes it checks (each SQL-decidable, each with its by-design exclusions named in the
// function body):
//   step_without_executor       — a live workflow step whose action_class has no active executor
//   actor_role_unresolved       — a live step whose actor_role fn_org_agent_resolve() cannot resolve
//                                  (contextual employee_task roles 'owner'/'Director' excluded)
//   event_emitted_no_subscriber — an event_type actually emitted into company_event with no active
//                                  subscriber ('task.assigned', delivered by direct assignment, excluded)
//   dead_subscription           — an active subscription whose agent is missing or inactive
//   executor_target_needs_args  — an active rpc executor, reachable from a live step, whose target
//                                  needs arguments the queue invoker cannot supply
//
// This is a GATE, not a ratchet: the count must be 0. A new workflow step, event, subscription or
// executor that leaves a dangling edge reddens this test, which is exactly the point — it converts
// "a directionless connection" from a thing an LLM might notice into a thing CI refuses to merge.
//
// What it deliberately does NOT claim: that latent pre-launch paths have fired (an emitter that
// exists but has had no real traffic is wired, not broken), or anything about edge-function emitters
// the SQL layer cannot see. It asserts the structural wiring, not the launch-day traffic.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const mgmtRead = async (ref, sql) =>
  (await import('../../lib/qd_guard.mjs')).mgmtRead(ref, sql);

test('the company has zero directionless connections', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const rows = await mgmtRead(PROD_REF,
    'select gap_class, subject, detail from public.fn_company_connectivity_register() order by gap_class, subject');
  const gaps = Array.isArray(rows) ? rows : [];
  if (gaps.length) {
    console.error('Connectivity register returned ' + gaps.length + ' structural gap(s):');
    for (const g of gaps) console.error(`  [${g.gap_class}] ${g.subject} — ${g.detail}`);
  }
  assert.equal(gaps.length, 0,
    'fn_company_connectivity_register() must return 0 rows — every workflow step, event, subscription and executor must connect to an active agent/executor');
});
