// AN UNSUBSCRIBE NEVER LOCKS ANYONE OUT (22 Sep 2026, customer_support; independent review of PR #804).
//
// Measured on main: login_otp and kyc refused the sign-in / verification code for ANY email_suppressions row,
// and send_outbox suppressed every notification to a suppressed address -- so a supplier who clicked
// "unsubscribe" on an invitation could never sign in and stopped receiving quote and reveal notices.
// The rule lives in supabase/functions/_shared/suppression_policy.ts (its own deno test replays the cases);
// this asserts every sender that reads email_suppressions asks that rule instead of treating any row as "stop".
//
//   node --test scripts/checks/an_unsubscribe_never_locks_anyone_out.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

for (const f of ['supabase/functions/login_otp/index.ts', 'supabase/functions/kyc/index.ts']) {
  test(`${f}: a code is refused only for a deliverability fact, never for an unsubscribe`, () => {
    const src = read(f);
    assert.match(src, /from\('email_suppressions'\)\.select\('reason'\)[^\n]*return !!data && blocksTransactional\(data\.reason\)/);
    assert.match(src, /import \{ blocksTransactional \} from '\.\.\/_shared\/suppression_policy\.ts'/);
  });
}

test('send_outbox applies a suppression through suppressionStops(reason, type)', () => {
  const src = read('supabase/functions/send_outbox/index.ts');
  assert.match(src, /from\('email_suppressions'\)\.select\('email,reason'\)/);
  assert.match(src, /suppressionStops\(supReason\.get\(foldEmail\(n\.to_email\)\), n\.type\)/);
});

test('resend_inbound gates an unsubscribe email before writing a suppression', () => {
  const src = read('supabase/functions/resend_inbound/index.ts');
  const gate = src.indexOf('neverSuppressible(from,');
  const auth = src.indexOf('fromDomainAuthenticated(hdrs');
  const sent = src.indexOf(".in('type', [...OPT_OUT_TYPES])");
  const write = src.indexOf("source: 'reply'");
  assert.ok(gate > 0 && auth > gate && sent > auth && write > sent, 'protected-address, authentication and invited-address gates must all precede the write');
});
