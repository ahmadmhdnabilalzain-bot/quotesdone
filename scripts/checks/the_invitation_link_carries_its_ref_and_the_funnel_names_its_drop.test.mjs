// THE INVITATION LINK CARRIES ITS REF AND THE RECRUITMENT FUNNEL NAMES ITS DROP (marketing, 28 Sep 2026).
// Fails if the cause of "invited 54, registered 0, marketing_first_touch 0, and nothing noticed" returns:
//   1. this file redefines the invitation link or the candidates again (they are #1051's, English only);
//   2. the probe stops checking that the candidate link is English and carries its ref;
//   3. the diagnosis counts "sent" from the leads status column instead of the outbox (notifications status 'sent');
//   4. the daily duty stops carrying and filing the diagnosis.
// Behaviour was run on production in one rolled-back transaction (the _probe.sql beside the file: PROBE OK).
//
//   node --test scripts/checks/the_invitation_link_carries_its_ref_and_the_funnel_names_its_drop.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');
const SQL = code(readFileSync(join(REPO, 'scripts/sql/the_recruitment_funnel_counts_what_was_sent_and_names_the_stage_that_lost_them.sql'), 'utf8'));
const body = (name) => {
  const i = SQL.indexOf('create or replace function public.' + name + '(');
  assert.ok(i >= 0, name + ' is defined');
  return SQL.slice(i, SQL.indexOf('$fn$;', i));
};

test('this file does not define the invitation link or the candidates: #1051 holds the one English definition', () => {
  // review of #1051 and #1012, 29 Sep 2026: this file's first version copied fn_supplier_invite_candidates from an
  // old body that chose Arabic copy and /ar/portal links, and #1051 redefined the same routine. The ref lives in
  // #1051's file (checked, English only, by the_invitation_pool_set_states_the_row_rule.test.mjs).
  assert.doesNotMatch(SQL, /create or replace function public\.fn_supplier_invite_candidates\(/i);
  assert.doesNotMatch(SQL, /create or replace function public\.fn_supplier_invite_link\(/i);
});

test('the probe reads the English link with its ref through the language-free link function', () => {
  const probe = code(readFileSync(join(REPO, 'scripts/sql/the_recruitment_funnel_counts_what_was_sent_and_names_the_stage_that_lost_them_probe.sql'), 'utf8'));
  assert.ok(probe.includes("public.fn_supplier_invite_link('https://quotesdone.com', (select claim_token"), 'the probe calls the link with a language again');
  assert.ok(probe.includes("'/en/portal[?]t=[0-9a-f-]{36}&utm_source=invite&"), 'the probe no longer requires the English link with its ref');
  assert.ok(probe.includes("x.lang is distinct from 'en'"), 'the probe no longer checks every candidate is English');
});

test('sent is counted from the outbox, never from the invited status', () => {
  const d = body('fn_marketing_funnel_diagnosis');
  assert.match(d, /from public\.notifications x where x\.lead_id = l\.id and x\.type = 'supplier_invite'/);
  assert.match(d, /bool_or\(x\.status = 'sent'\) as sent/);
  assert.doesNotMatch(d, /invite_status\s*=\s*'sent'/);
  assert.match(d, /fn_ceo_improvement_open\('funnel_stage_drop'/);
});

test('the daily duty carries and files the diagnosis', () => {
  assert.match(body('fn_marketing_recruitment_funnel'), /'diagnosis', public\.fn_marketing_funnel_diagnosis\(false, true\)/);
  assert.match(SQL, /'funnel_stage_drop'\)\);/);
});
