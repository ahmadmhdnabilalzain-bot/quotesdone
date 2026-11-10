// extract_text's admin door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the real
// handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('extract_text', new URL('./index.ts', import.meta.url), {
  body: {},
  admin: (r, j) => { assertEquals(r.status, 400); assertEquals(j.error, 'b64 required'); },
  nonAdmin: (r, j) => { assertEquals(r.status, 403); assertEquals(j.error, 'forbidden'); },
});
