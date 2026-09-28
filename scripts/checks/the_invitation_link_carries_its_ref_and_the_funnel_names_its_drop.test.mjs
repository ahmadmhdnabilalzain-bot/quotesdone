// THE INVITATION LINK CARRIES ITS REF AND THE RECRUITMENT FUNNEL NAMES ITS DROP (marketing, 28 Sep 2026).
// Fails if the cause of "invited 54, registered 0, marketing_first_touch 0, and nothing noticed" returns:
//   1. the invitation link loses its ref (utm_source=invite ... utm_content=lead-<id>), so no registration can be attributed;
//   2. the candidate query builds {{link}} by hand again instead of through fn_supplier_invite_link;
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

test('the invitation link carries a stable ref naming channel, campaign and lead', () => {
  const link = body('fn_supplier_invite_link');
  assert.match(link, /\/portal\?t=' \|\| p_token::text/);
  assert.match(link, /utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' \|\| p_lead_id::text/);
});

test('the candidate query builds its link through the ref, not by hand', () => {
  const cand = body('fn_supplier_invite_candidates');
  assert.match(cand, /'\{\{link\}\}', public\.fn_supplier_invite_link\(v_site, e\.lang, e\.claim_token, e\.id\)/);
  assert.doesNotMatch(cand, /'\/portal\?t=' \|\| e\.claim_token/);
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
