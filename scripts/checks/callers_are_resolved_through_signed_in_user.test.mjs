// A SIGNED-IN CALLER IS RESOLVED THROUGH _shared/signed_in_user.ts, WHICH REFUSES FAST AND NEVER
// CALLS AN AUTH OUTAGE "SIGNED OUT".
//
// 21 Sep 2026: supplier_portal and messages_api 401s had a p50 of 35,108 ms over 7 days. The tokens
// were valid; GoTrue GET /user timed out (3 x 10 s, then a 5xx) under database contention, and each
// function's inline `admin.auth.getUser(jwt)` + `if (!user) return 401` told signed-in people they
// were signed out, 35 s later. The same inline pattern is in the 28 functions listed below; they
// were not converted in that change (other seats were editing several of them). The list may only
// SHRINK: a new function with an inline getUser fails here, and so does converting one without
// removing it from the list. Comments are stripped before matching.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const root = fileURLToPath(new URL('../../supabase/functions/', import.meta.url));
// A function is its whole folder (scripts/lib/function_sources.mjs): a split function keeps its door in index.ts and its caller lookup in a module.
const code = (src) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');

const NOT_YET_CONVERTED = new Set([
  'customer_api', 'customer_documents', 'customer_intelligence',
  'customer_portal', 'inquiry_intake', 'kyc', 'mobile_otp',
  'procurement_api', 'project_api', 'refund_flow', 'reveal_invoice',
  'site_assistant', 'stripe_checkout', 'stripe_confirm', 'supplier_api',
  // supplier_pay left this list on 22 Sep 2026 (audit finding SP-N-08): a supplier clearing a debt that
  // accrues interest was told "Not signed in" whenever the auth server was the thing that timed out.
  // accountant, ceo_agent, compliance_archive, extract_text, it_engineer, pdf_native, quote_compare, refunds_api and
  // sales_engineer left it on 10 Nov 2026 (security audit item 1): their admin door is _shared/admin_session.ts
  // adminCaller(), which resolves the caller through signedInUser and also requires an aal2 session.
  'supplier_catalog_ingest', 'supplier_onboard', 'transcribe',
]);

test('no function outside the shrinking list calls auth.getUser inline', () => {
  const inline = readdirSync(root).filter((d) => !d.startsWith('_') && existsSync(`${root}${d}/index.ts`))
    .filter((d) => /\bauth\.getUser\(/.test(code(functionSource(d))));
  for (const d of inline) assert.ok(NOT_YET_CONVERTED.has(d), `${d} resolves its caller with an inline auth.getUser — use signedInUser() from _shared/signed_in_user.ts`);
  for (const d of NOT_YET_CONVERTED) assert.ok(inline.includes(d), `${d} no longer calls getUser inline — remove it from NOT_YET_CONVERTED`);
});

test('supplier_portal and messages_api resolve the caller through signedInUser', () => {
  for (const d of ['supplier_portal', 'messages_api']) {
    const s = code(functionSource(d));
    assert.match(s, /await signedInUser\(admin, req\.headers\.get\('Authorization'\)\)/, d);
    // supplier_portal wraps the same refusal in annotate() to mark its own launch-path probe (_shared/probe_caller.ts)
    assert.match(s, /if \(!who\.ok\) return (?:annotate\()?J\(refusalBody\(who\), who\.status\)/, d);
  }
});
