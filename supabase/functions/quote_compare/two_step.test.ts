// quote_compare's admin door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the real
// handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
// A signed-in customer is not an admin and needs no second factor: it is resolved to its customers row as before
// (measured on origin/main: the same status and body for the customer, aal1 or aal2).
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('quote_compare', new URL('./index.ts', import.meta.url), {
  body: { inquiry_id: '0b0b0b0b-0000-4000-8000-0000000e0001' },
  admin: (r, j) => { assertEquals(r.status, 404); assertEquals(j.error, 'not_found'); },
  nonAdmin: (r, j) => { assertEquals(r.status, 404); assertEquals(j.error, 'not_found'); },
});
