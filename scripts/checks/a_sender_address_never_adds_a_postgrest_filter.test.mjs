// A SENDER ADDRESS NEVER ADDS A POSTGREST FILTER. Seat: it_engineer (CWE audit 19 Oct 2026).
// resend_inbound and inbound_email put the sender's address into .or(); a crafted address must be refused.
import test from 'node:test'; import assert from 'node:assert/strict'; import { readFileSync } from 'node:fs';
const { orSafeEmail, orSafeDomain } = await import(new URL('../../supabase/functions/_shared/or_filter_email.ts', import.meta.url).href);
test('crafted values are refused, real ones pass', () => {
  for (const bad of ['a@b.com,claimed_by.not.is.null', '"a,verified.eq.true"@x.com', 'a@b.com)', 'x@y.c:z']) assert.equal(orSafeEmail(bad), '');
  assert.equal(orSafeDomain('b.com,claimed_by.not.is.null'), '');
  assert.equal(orSafeEmail('zz.demo@example.invalid'), 'zz.demo@example.invalid');
  assert.equal(orSafeDomain('example.invalid'), 'example.invalid');
});
test('both call sites use the guard', () => {
  assert.match(readFileSync(new URL('../../supabase/functions/resend_inbound/index.ts', import.meta.url), 'utf8'), /orSafeEmail\(from\)/);
  assert.match(readFileSync(new URL('../../supabase/functions/inbound_email/index.ts', import.meta.url), 'utf8'), /orSafeDomain\(dom\)/);
});
