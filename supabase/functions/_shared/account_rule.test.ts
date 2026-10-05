// The founder's account rule (14 Sep 2026) — see account_rule.ts.
// Run: deno test supabase/functions/_shared/account_rule.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { accountMissing, ageOn, dobProblem } from './account_rule.ts';

const TODAY = new Date(Date.UTC(2026, 8, 14)); // 14 Sep 2026
const ok = { full_name: 'Test Buyer', date_of_birth: '1990-01-01', email_verified: true, phone_verified: false, tos_accepted_at: '2026-09-01T00:00:00Z' };

Deno.test('exactly 18 today passes', () => {
  assertEquals(ageOn('2008-09-14', TODAY), 18);
  assertEquals(dobProblem('2008-09-14', TODAY), null);
  assertEquals(accountMissing({ ...ok, date_of_birth: '2008-09-14' }, TODAY), []);
});

Deno.test('17 years 364 days fails as under_18', () => {
  assertEquals(ageOn('2008-09-15', TODAY), 17);
  assertEquals(dobProblem('2008-09-15', TODAY), 'under_18');
  assertEquals(accountMissing({ ...ok, date_of_birth: '2008-09-15' }, TODAY), ['age_18_or_over']);
});

Deno.test('missing DOB fails', () => {
  assertEquals(dobProblem('', TODAY), 'dob_required');
  assertEquals(dobProblem(null, TODAY), 'dob_required');
  assertEquals(accountMissing({ ...ok, date_of_birth: null }, TODAY), ['date_of_birth']);
});

Deno.test('unparseable, impossible, future and over-120 dates are dob_invalid', () => {
  for (const d of ['not-a-date', '2026-02-30', '14/09/1990', '2030-01-01', '1890-01-01']) assertEquals(dobProblem(d, TODAY), 'dob_invalid', d);
});

Deno.test('unverified fails; either OTP-verified channel passes', () => {
  assertEquals(accountMissing({ ...ok, email_verified: false, phone_verified: false }, TODAY), ['verified_email_or_mobile']);
  assertEquals(accountMissing({ ...ok, email_verified: false, phone_verified: true }, TODAY), []);
});

Deno.test('no terms fails', () => {
  assertEquals(accountMissing({ ...ok, tos_accepted_at: null }, TODAY), ['terms_accepted']);
});

Deno.test('no name fails; an empty account lists everything', () => {
  assertEquals(accountMissing({ ...ok, full_name: ' ' }, TODAY), ['name']);
  assertEquals(accountMissing(null, TODAY), ['name', 'date_of_birth', 'verified_email_or_mobile', 'terms_accepted']);
});

Deno.test('a customer on an older Terms version must accept the current one', () => {
  assertEquals(accountMissing({ ...ok, tos_version: 'v4' }, TODAY, 'v9'), ['terms_accepted']);
  assertEquals(accountMissing({ ...ok, tos_version: 'v9' }, TODAY, 'v9'), []);
  assertEquals(accountMissing({ ...ok, tos_version: 'v4' }, TODAY), []); // no current version given: unchanged
});
