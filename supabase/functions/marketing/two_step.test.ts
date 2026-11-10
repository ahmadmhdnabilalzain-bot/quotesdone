// marketing's founder door needs a two-step session (security checklist audit 10 Nov 2026, item 1). Drives the real
// handler over a stubbed auth server and PostgREST (_shared/admin_two_step_harness.ts); ZZ DEMO identities only.
import { assertEquals } from 'jsr:@std/assert@1';
import { twoStepCases } from '../_shared/admin_two_step_harness.ts';

twoStepCases('marketing', new URL('./index.ts', import.meta.url), {
  body: { action: 'zz_demo_unknown_action' },
  admin: (r, j) => { assertEquals(r.status, 400); assertEquals(j.error, 'unknown action'); },
  nonAdmin: (r, j) => { assertEquals(r.status, 401); assertEquals(j.error, 'unauthorized'); },
});
