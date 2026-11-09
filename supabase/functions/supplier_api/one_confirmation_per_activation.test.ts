// deno test supabase/functions/supplier_api/one_confirmation_per_activation.test.ts
// 3 Nov 2026 (customer_support). An approved first save sent "Your QuotesDone supplier account is active" (registration_received)
// AND the approval trigger's supplier_approved notice, each with a WhatsApp twin: two confirmations for one activation.
// The approval trigger is the one confirmation; save_profile's notice goes only while the registration is not active.
import { assert, assertMatch } from 'jsr:@std/assert';
// The function is index.ts plus its modules (9 Nov 2026 split): read all of it, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const src = functionSource('supplier_api');

Deno.test('save_profile queues registration_received only for a decision short of approved', () => {
  assertMatch(src, /\.\.\.\(decision === 'approved' \? \[\] : \[\{ type: 'registration_received', to_email: email, to_role: 'supplier'/);
});

Deno.test('KNOWN-BAD control: no "account is active" copy is left in save_profile to send a second confirmation', () => {
  assert(!src.includes('Your QuotesDone supplier account is active'), 'the approved copy must not come back');
  const start = src.indexOf('const supplierMail =');
  assert(start > 0, 'supplierMail moved');
  assert(!src.slice(start, start + 400).includes("decision === 'approved'"), 'supplierMail must not open with an approved branch');
});
