// refunds_api's admin door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the real
// handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
// Before this change the aal1 admin case answered 200 with the refund queue: refunds_api:32 asked only admin_emails.
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('refunds_api', new URL('./index.ts', import.meta.url), {
  body: { action: 'list_pending' },
  admin: (r, j) => { assertEquals(r.status, 200); assertEquals(j.ok, true); },
  nonAdmin: (r, j) => { assertEquals(r.status, 403); assertEquals(j.error, 'forbidden'); },
});
