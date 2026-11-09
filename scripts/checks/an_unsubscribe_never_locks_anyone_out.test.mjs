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
import { functionSource } from '../lib/function_sources.mjs';

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

// 28 Oct 2026 (sales_engineer, ledger 1401 audit): the three gates moved, unchanged and in the same order, into
// suppression_policy.ts replyStopRefusal, so email_triage's opt_out backstop stands behind the same ones. This asserts the
// gates in that one place, and that BOTH writers of a reply suppression ask it, and stop on its answer, before writing.
const POLICY = read('supabase/functions/_shared/suppression_policy.ts');
test('the three gates of a reply stop, in order: protected address, authenticated From domain, an address we invited', () => {
  const fn = POLICY.slice(POLICY.indexOf('export async function replyStopRefusal'));
  assert.ok(POLICY.includes('export async function replyStopRefusal'), 'replyStopRefusal is gone from suppression_policy.ts');
  const g1 = fn.indexOf('neverSuppressible(from,'), g2 = fn.indexOf('await o.authenticated()'), g3 = fn.indexOf(".in('type', [...OPT_OUT_TYPES]).eq('status', 'sent')");
  assert.ok(g1 > 0 && g2 > g1 && g3 > g2, 'protected-address, authentication and invited-address gates must all be in replyStopRefusal, in that order');
});

test('resend_inbound gates an unsubscribe email before writing a suppression', () => {
  const src = functionSource('resend_inbound');
  const gate = src.indexOf('await replyStopRefusal(admin, { from, protectedList: [...adminList, ...fwdList, EXPENSE_MAILBOX]');
  const auth = src.indexOf('senderAuthenticated(providerEmailId, hdrs');
  const refused = src.indexOf('if (why) {', auth);
  const write = src.indexOf("source: 'reply'");
  assert.ok(gate > 0 && auth > gate && refused > auth && write > refused, 'protected-address, authentication and invited-address gates must all precede the write');
});

test("email_triage's opt_out backstop stands behind the same gates before it writes a suppression", () => {
  const src = read('supabase/functions/email_triage/opt_out_backstop.ts');
  const gate = src.indexOf('await replyStopRefusal(admin, {');
  const refused = src.indexOf('if (!why)', gate);
  const write = src.indexOf("source: 'reply'");
  assert.ok(gate > 0 && refused > gate && write > refused, 'the backstop must ask replyStopRefusal, and write only when it answers nothing');
  assert.match(src, /authenticated: \(\) => m\.raw\?\.sender_authenticated === true/, 'the backstop reads the lane-aware verdict resend_inbound stored, nothing weaker');
});
