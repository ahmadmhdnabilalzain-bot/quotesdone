// A FORWARDED RECEIPT IS BOOKED OR OWNED BY FINANCE — IT NEVER WAITS ON THE FOUNDER.
//
// 6 Sep 2026: the founder opened the OS and found "Inbox — awaiting your reply" and "Reviews pending"
// filled with his own forwarded SaaS receipts (inbound_messages 67/73/74/75, doc_reviews 8-12). The
// receipt path in resend_inbound booked only after a model call that the paid hold had silenced since
// 15 Aug; the emails fell through to the supplier-document path and both surfaces read its flags.
// Fixed by a deterministic parser (supabase/functions/_shared/receipt_parse.ts), owner_role on both
// tables, fn_receipt_hand_to_bookkeeper, and owner-aware fn_inbox_list / fn_ws_documents. This is what
// keeps the hold from silently coming back. Three absolute zeros, the first two over rows OLDER than
// 24h so a row that is simply waiting for its next delivery does not flap the check:
//   1. inbound_messages needs_review, unreplied, older than 24h, with no owner_role;
//   2. doc_reviews pending, older than 24h, with no owner_role;
//   3. receipt-ish inbound_messages since 15 Aug 2026 (same isReceiptish shape as resend_inbound: the
//      expenses/receipts mailbox or a receipt/invoice/payment subject) that are neither handled
//      (needs_review false or replied) nor owned.
//
// READ-ONLY against production: every statement is a SELECT under an 8s statement timeout.
//
//   node --test scripts/checks/receipts_never_wait_on_the_founder.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('inbound_messages: no needs_review row older than 24h without an owner role', { skip: SKIP }, async () => {
  const r = await rows(`
    select id, from_email, left(subject, 100) as subject, created_at
      from public.inbound_messages
     where needs_review = true and replied_at is null and owner_role is null
       and created_at < now() - interval '24 hours'
     order by created_at limit 50`);
  assert.equal(r.length, 0, 'these inbound rows are held with nobody to own them (the founder is shown them as his work):\n' + JSON.stringify(r, null, 1));
});

test('doc_reviews: no pending row older than 24h without an owner role', { skip: SKIP }, async () => {
  const r = await rows(`
    select id, from_email, left(subject, 100) as subject, file_name, created_at
      from public.doc_reviews
     where coalesce(status, '') = 'pending' and owner_role is null
       and created_at < now() - interval '24 hours'
     order by created_at limit 50`);
  assert.equal(r.length, 0, 'these document reviews are pending with nobody to own them (the founder is shown Approve/Reject):\n' + JSON.stringify(r, null, 1));
});

test('every receipt-ish inbound since 15 Aug 2026 is booked/handled or owned', { skip: SKIP }, async () => {
  const r = await rows(`
    select id, to_email, left(subject, 100) as subject, needs_review, replied_at, owner_role, created_at
      from public.inbound_messages
     where created_at >= '2026-08-15'
       and (split_part(coalesce(to_email, ''), '@', 1) in ('receipts','receipt','billing','expenses','expense','finance','accounts','accounting','fin','subscriptions','subscription','bills','bill')
            or coalesce(subject, '') ~* '(receipt|invoice|payment (was )?(received|successful|confirmation)|tax invoice|subscription (renewed|payment|confirmation)|renewal|your plan|billing)')
       and needs_review = true and replied_at is null and owner_role is null
     order by created_at limit 50`);
  assert.equal(r.length, 0, 'these forwarded receipts were neither booked nor handed to finance:\n' + JSON.stringify(r, null, 1));
});
