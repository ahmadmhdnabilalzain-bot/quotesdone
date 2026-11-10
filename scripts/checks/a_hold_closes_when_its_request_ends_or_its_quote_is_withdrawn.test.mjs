// A HOLD CLOSES WHEN ITS REQUEST ENDS OR ITS QUOTE IS WITHDRAWN (customer_support for the sales engineer's hold desk,
// 10 Nov 2026; supplier follow-up of #1909, item 3).
//
// MEASURED on origin/main: a quote_spec_hold or quote_quality_hold closed only on the customer's reveal; on a request that
// ended without one (expired, lost, cancelled, closed, completed) or a withdrawn quote it stayed open and counted in the
// supplier's bell. scripts/sql/a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.sql closes them from two
// triggers. This holds that file to the one list of request ends, to the bell's idea of a live hold, and to the rule that
// such a close is not an "ignored hold" incident. Its _probe.sql proves the behaviour on production, rolled back.
//
//   node --test scripts/checks/a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SQL = read('scripts/sql/a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.sql');
const ENDS = [.../CLOSED_REQUEST_STATUSES\s*=\s*\[([^\]]*)\]/.exec(read('supabase/functions/_shared/request_closed.ts'))[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();

test('the trigger ends a request on exactly the one list of request ends', () => {
  const body = SQL.slice(SQL.indexOf('function public.trg_request_end_closes_its_holds'), SQL.indexOf('create trigger z31_request_end_closes_its_holds'));
  for (const m of body.matchAll(/in \(([^)]*)\)/g)) assert.deepEqual([...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort(), ENDS);
  assert.match(SQL, /create trigger z31_request_end_closes_its_holds after update of status on public\.inquiries/);
  assert.match(SQL, /create trigger z31_withdrawn_quote_closes_its_holds after update of status on public\.quotes/);
});

test('a closed hold leaves the bell and is not counted as ignored', () => {
  const live = /const LIVE_HOLD = \[([^\]]*)\]/.exec(read('supabase/functions/supplier_portal/overview.ts'))[1];
  assert.deepEqual([...live.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort(), ['awaiting_approval', 'open']);
  const close = SQL.slice(SQL.indexOf('function public.fn_quote_holds_close_without_decision'), SQL.indexOf('create or replace function public.trg_request_end_closes_its_holds'));
  assert.doesNotMatch(close, /fn_supplier_collaboration_incident|fn_supplier_collaboration_cooperated/, 'an ended request is no decision: no incident, no credit');
  assert.match(close, /set superseded_at = now\(\)/, 'a quality hold closes as superseded, which the quality tick skips');
  assert.match(read('supabase/functions/_shared/line_specs/workflow.ts'), /'request_ended' \| 'quote_withdrawn'/);
});
