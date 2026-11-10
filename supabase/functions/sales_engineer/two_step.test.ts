// sales_engineer's founder door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the
// real handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
// A signed-in customer is not an admin and needs no second factor: it is resolved to its customers row as before
// (measured on origin/main: the same status and body for the customer, aal1 or aal2).
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('sales_engineer', new URL('./index.ts', import.meta.url), {
  body: { action: 'zz_demo_unknown_action' },
  admin: (r, j) => { assertEquals(r.status, 400); assertEquals(j.error, 'unknown_action'); },
  nonAdmin: (r, j) => { assertEquals(r.status, 403); assertEquals(j.error, 'forbidden'); assertEquals(j.action, 'zz_demo_unknown_action'); },
});
