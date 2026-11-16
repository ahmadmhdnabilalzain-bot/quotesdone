// THE SUPPLIER IS KNOWN IN THE QUOTATION CHAT (customer_support, 16 Nov 2026; founder ledgers 1711-1713, who-knows-what item 7).
// The portal quotation chat's voice (actions/quote_review_chat.ts reviewVoice, also the e-mailed quotation's door) knew the job
// only: it could write "ready to submit" while WhatsApp had told him his licence expired or that he was held for unanswered
// requests. Its facts now carry his own account from the reading WhatsApp and e-mail give, and his collaboration rows.
// Run: deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/supplier_api/the_supplier_is_known_in_the_quotation_chat.test.ts
import { assert, assertMatch } from 'jsr:@std/assert@1';
import { supplierKnownFacts, withSupplierKnown } from '../_shared/supplier_known.ts';

Deno.test('the chat voice reads his account beside the case and hands it to the model after the job', async () => {
  const src = await Deno.readTextFile(new URL('./actions/quote_review_chat.ts', import.meta.url));
  assertMatch(src, /supplierKnownFacts\(admin, email\)\]\)/);
  assertMatch(src, /facts: withSupplierKnown\(v\.situation, known\)/);
  // the job number the model must carry is still read from the review's own facts, never from his account
  assertMatch(src, /must: v\.kind === 'text' \? \[\] : jobsIn\(v\.situation\)/);
});

Deno.test('a review that says "ready to submit" reaches the model with his expired licence and his hold beside it', async () => {
  const reading = { scope: 'supplier', known: true, company: 'ZZ DEMO Held Steel Rival',
    profile: { approval_status: 'approved', verified: true, trade_licence_no: 'ZZ-DEMO-1002', licence_expiry: '2026-11-06', licence_expired: true, licence_days_left: -10 },
    services: { confirmed: true, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: true }], emirates_covered: [] },
    matching: { receives_requests_now: false, jobs_sent_30d: 2, requests_in_his_trades_30d: 3, strikes: 3, strike_limit: 3,
      collaboration: { unanswered_in_a_row: 3, on_hold: true, held_at: '2026-11-14T10:00:00Z' },
      why_no_jobs: [{ code: 'licence_expired', says: 'His trade licence expired on 06 Nov 2026. He should upload the renewed licence in the Documents tab.' },
        { code: 'strike_limit', says: 'Matching is paused: he has 3 unanswered-request strikes (limit 3). A quotation clears the run.' }] } };
  const db = { rpc: async (fn: string) => fn === 'fn_wa_context' ? { data: reading, error: null }
    : { data: { events: [{ kind: 'collaboration', at: '2026-11-14T10:00:00Z', summary: 'held — 3 in a row — RFQ 1A2B3C4D' }] }, error: null } };
  const facts = withSupplierKnown('Job 164941: the quotation is complete and ready to submit.', await supplierKnownFacts(db, 'zz-demo-supknown-b@example.invalid'));
  for (const s of ['Job 164941', 'EXPIRED 10 day(s) ago', 'renewed licence in the Documents tab', '3 unanswered-request strikes', 'on hold since 2026-11-14',
    'held — 3 in a row', 'never tell him he is verified, ready to submit']) assert(facts.includes(s), `missing "${s}":\n${facts}`);
  assert(!/Sukayna|buyer@/i.test(facts));
});
