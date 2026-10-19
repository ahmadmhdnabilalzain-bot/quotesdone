// Legal finding 1 (PDPL Art. 18): an objection to an automated decision is filed by the existing classifier output,
// stays with customer_support, is handed to the ceo seat if unresolved, and is never closed by silence. Fails if the
// route reaches the founder, if idle close can close it, or if the ceo handler stops waiting.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const raw = readFileSync(new URL('../sql/the_support_desk_takes_an_objection_to_an_automated_decision.sql', import.meta.url), 'utf8');
const sql = raw.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n');
const triage = readFileSync(new URL('../../supabase/functions/email_triage/index.ts', import.meta.url), 'utf8');

test('the classifier output decides, not word matching', () => {
  assert.match(triage, /\|automated_decision_objection\|/);
  assert.match(triage, /within 10 working days/);
  assert.match(sql, /\('email_category', 'automated_decision_objection', 'automated_decision_objection'\)/);
  assert.doesNotMatch(sql, /\b(ilike|similar to)\b|~\*/i);
});

test('support first, then the ceo seat; never the founder', () => {
  assert.match(sql, /\('automated_decision_objection', 'customer_support', true,/);
  assert.match(sql, /fn_seat_handoff\('customer_support', 'ceo', 'support\.decision_objection'/);
  assert.doesNotMatch(sql, /fn_notify_founder|founder_mail_policy/);
});

test('no seat closes it by silence', () => {
  assert.match(sql, /category is distinct from 'automated_decision_objection'/);
  assert.match(sql, /'waiting', 'the CEO reviews the automated decision/);
  assert.match(sql, /'fn_ceo_takes_decision_objection', interval '14 days', false,/);
});

test('routines closed; file ends with a verdict row', () => {
  for (const sig of ['fn_customer_support_escalates_decision_objections()', 'fn_ceo_takes_decision_objection(bigint)'])
    assert.ok(sql.includes(`revoke execute on function public.${sig} from public, anon, authenticated`), sig);
  assert.match(sql.trimEnd(), /else 'PROBE OK' end as verdict;$/);
});

test('the ruled-out word is absent from this file', () => {
  assert.doesNotMatch(raw, new RegExp(['hu', 'man'].join(''), 'i'));
});
