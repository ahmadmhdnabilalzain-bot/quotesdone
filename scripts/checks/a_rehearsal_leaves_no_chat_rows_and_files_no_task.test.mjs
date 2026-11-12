// A REHEARSAL LEAVES NO SUPPORT ROWS (27 Oct 2026, customer_support; rebuilt by it_engineer 2 Nov 2026).
//
// MEASURED on PR #1635: one conversation-bank session (~270 portal turns as ZZ DEMO customers) opened a support profile
// and case for every customer:<id> chat row (z50_support_wire_widget): 76 ZZ DEMO profiles and 113 cases had accumulated.
//
// WHAT THIS CHECK NO LONGER GUARDS. The chat-row tag, the teardown of chat rows, "files no gap, no task" and the demo flag
// on a tagged readability score are a_harness_chat_turn_files_no_gap_and_is_torn_down_by_its_tag.test.mjs (on main,
// applied). The first form of this PR duplicated that in SQL and carried old bodies of fn_sales_assist and
// fn_support_knowledge_gap (applying it would have removed the live internal-knowledge rule of ruling 1338); it now
// carries no SQL at all.
//
// WHAT FAILS IF THE CAUSE RETURNS: teardown loses a support step; leftovers() stops counting support rows or the gaps a run
// filed; the stale-run sweep stops seeing a run that left only support profiles; the bank stops failing on a leftover.
//
//   node --test scripts/checks/a_rehearsal_leaves_no_chat_rows_and_files_no_task.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('static: teardown removes the support rows a chat turn opens, leftovers counts them, the bank fails on them', () => {
  const td = read('scripts/lib/demo_factory.mjs');
  assert.ok(td.includes('...(await chatTurnSteps(tag)),'), 'teardown no longer removes the run\'s chat turns');
  for (const t of ['feedback (support)', 'support_document_intake', 'support_notification', 'support_customer_profile'])
    assert.ok(td.includes(`['${t}', `), `teardown lost its ${t} step`);
  // 12 Nov 2026 (final audit H6): the run's cases go through fn_demo_support_case_purge (the step labelled
  // SUPPORT_CASE_PURGE), because a plain delete meets the append-only summary history and stops the teardown.
  assert.ok(td.includes('[SUPPORT_CASE_PURGE, `with r as (select public.fn_demo_support_case_purge('), 'teardown lost its support_case step');
  assert.match(td, /support_customer_profile where email like 'qd-\$\{tag\}-%@example\.%' or customer_id in \$\{CUST\} or lead_id in \$\{LEAD\}/,
    'support rows are no longer scoped to the run\'s own email and ids');

  const fx = read('scripts/e2e/fixtures.mjs');
  for (const k of ['assistant_logs', 'support_customer_profile', 'support_case'])
    assert.match(fx, new RegExp(`\\)::int ${k}[,\`]`), `leftovers() no longer counts ${k}`);
  assert.match(fx, /r\[k\] = tagged\.has\(x\) \? Number\(n\[x\]\) : 'not applied';/, 'an unmeasured tag count must say so, never read 0');
  assert.match(fx, /filed = await gapsFiled\(run\)/, 'closeRun no longer counts the gaps a run filed before its teardown');
  assert.match(fx, /left\.total \+= filed\.gaps \+ filed\.tasks;/, 'a filed gap or task no longer fails the run');
  // 12 Nov 2026: the support-profile line is no longer the last branch of the union (Resend-sink signups follow it), so
  // it no longer ends in the closing bracket; the line itself is what is asserted.
  assert.match(fx, /from public\.support_customer_profile where email like 'qd-%@example\.invalid'\n/, 'the stale-run sweep no longer finds runs that left only support profiles');

  const bank = read('scripts/e2e/live_seat_conversations.mjs');
  assert.match(bank, /if \(closed\.leftovers\?\.total \|\| closed\.leftovers\?\.knowledge_gaps_filed_error\) process\.exitCode = 1;/,
    'the bank no longer fails when its teardown leaves a row');
});
