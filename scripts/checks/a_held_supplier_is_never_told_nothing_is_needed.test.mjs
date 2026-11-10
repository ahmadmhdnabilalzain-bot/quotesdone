// A HELD SUPPLIER IS NEVER TOLD "NOTHING IS NEEDED" (13 Oct 2026, it_engineer, founder ruling 1230).
// Measured on production: a supplier whose licence could not be read (Arabic-only, blank) was e-mailed and WhatsApped at
// Save "your account activates automatically ... Nothing is needed from you", then held as licence_unreadable with no
// further word. supplier_api save_profile must ask for a clearer licence on EVERY decision short of approved whenever
// the licence name, number or expiry is unread - also when other items are missing too - and that one notice is what
// goes out on e-mail AND WhatsApp. The portal's own wording for the three hold reasons asks for a clearer copy too.
// Reads source only; runs in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readSupplierPortal } from '../lib/portal_sources.mjs';
import { functionSource } from '../lib/function_sources.mjs';
// raw source: stripping comments would eat the rest of any line holding 'https://'
const src = functionSource('supplier_api');
const copy = readFileSync(new URL('../../src/components/portal/supplier/serverCopy.ts', import.meta.url), 'utf8');

test('an unread licence is tested on all three fields', () => {
  for (const f of ['licence_legal_name', 'trade_license_no', 'license_expiry']) assert.ok(src.includes(`!full?.${f} &&`), `the unread test must cover ${f}`);
});

// 3 Nov 2026 (customer_support): supplierMail no longer has an approved branch (an approval is confirmed once, by
// supplier_approved; supplier_api/one_confirmation_per_activation.test.ts), so it opens with the non-UAE licence branch.
test('the clearer-licence ask comes first, before every other message, and keeps what else is missing', () => {
  const start = src.indexOf("const supplierMail = full?.licence_gate_reason === 'licence_authority_not_uae'");
  const ask = src.indexOf('          : licUnreadEn\n', start);
  assert.ok(start > 0 && ask > start, 'the clearer-licence branch is missing from save_profile');
  assert.ok(!/decision === 'pending'|stillNeeded\.length/.test(src.slice(start, ask)), 'only the non-UAE licence branch may come before the clearer-licence ask');
  const branch = src.slice(ask, src.indexOf('\n          : ', ask + 20));
  assert.match(branch, /stillNeeded\.length \? `[^`]*\$\{needEn\}/, 'with other items missing too, the ask must list them (the combined case)');
  assert.ok(src.lastIndexOf('Nothing is needed from you') > ask, '"Nothing is needed" must only be reachable after the ask');
});

test('the one notice goes to e-mail and WhatsApp alike', () => {
  assert.match(src, /type: 'registration_received', to_email: email, to_role: 'supplier'[^\n]*\.\.\.supplierMail/, 'registration_received must carry supplierMail (requestDelivery sends it on both channels)');
});

test('the portal wording for the three hold reasons asks for a clearer copy and promises no activation', () => {
  for (const k of ['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread']) {
    const line = copy.split('\n').find((l) => l.trimStart().startsWith(k + ':')) || '';
    assert.match(line, /clearer copy/, `${k} must ask for a clearer copy`);
    assert.doesNotMatch(line, /activat|nothing is needed/i, `${k} must not promise activation`);
  }
});

test('the portal header says a licence hold to a PENDING supplier too, not only to action_required', () => {
  const portal = readSupplierPortal();
  assert.match(portal, /approval_status === 'pending' && \/\^licence_\/\.test\(String\(ov\.supplier\.licence_gate_reason/, 'a pending supplier held for the licence must see why (licence_unreadable, _expiry_unread, _number_unread)');
});

test('the dashboard sends the hold reason and its deadline to the portal', () => {
  const idx = functionSource('supplier_portal');
  const ov = readFileSync(new URL('../../supabase/functions/supplier_portal/overview.ts', import.meta.url), 'utf8');
  assert.match(idx, /select\('id,company_name,approval_status,[^']*licence_gate_reason[^']*exception_due_at/, 'supplier_portal must read licence_gate_reason and exception_due_at');
  assert.match(ov, /licence_gate_reason: sup\.licence_gate_reason/, 'supplierCard must send licence_gate_reason');
  assert.match(ov, /exception_due_at: sup\.exception_due_at/, 'supplierCard must send exception_due_at');
});
