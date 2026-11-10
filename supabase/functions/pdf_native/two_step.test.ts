// pdf_native's admin door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the real
// handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('pdf_native', new URL('./index.ts', import.meta.url), {
  body: {},
  admin: (r, j) => { assertEquals(r.status, 500); assertEquals(j.error, 'The input is not a PNG file!'); },
  nonAdmin: (r, j) => { assertEquals(r.status, 403); assertEquals(j.error, 'forbidden'); },
});
