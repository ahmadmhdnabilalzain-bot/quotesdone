// AN UNREAD LICENCE NAME IS NEVER APPROVED AUTOMATICALLY (sales_engineer, 24 Sep 2026, on #945).
// A scanned licence yields its name through license_extract (vision); when it cannot (unreadable, or the model
// held) the review must hold the registration for a human, never approve it on auto_approve_suppliers.
// Offline, over the source: fails if the unread branch is removed or placed after the auto-approve branch.
// The behaviour itself is proved by an_approved_supplier_is_told_and_the_licence_name_must_match_probe.sql
// (unread + auto ON -> pending/needs_review; read match -> approved), and the upload paths by
// supabase/functions/_shared/document_expiry.test.ts.
//   node --test scripts/checks/an_unread_licence_name_is_never_approved_automatically.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = R('scripts/sql/a_supplier_whose_licence_could_not_be_read_is_held_never_approved.sql');

test('the review holds an unread name before it reaches automatic approval', () => {
  const unread = SQL.indexOf("elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';");
  const auto = SQL.indexOf("elsif coalesce(v_auto, false) then v_decision := 'approved';");
  assert.ok(unread > 0, 'no unread-name branch');
  assert.ok(auto > unread, 'automatic approval is decided before the unread name is held');
  assert.match(SQL, /v_name_unread := public\.fn_company_name_norm\(coalesce\(l\.licence_legal_name, ''\)\) = ''/);
  assert.match(SQL, /case when v_reason = 'licence_unreadable' then 'needs_review' else 'auto_done' end/);
});

// Stage-2 #1230 S02 (7 Oct 2026): an ALREADY approved supplier whose licence was never read kept the approval
// with reason null, because the "approved and complete" branch did not ask whether the name had been read.
test('an approval stands only while the licence name has been read', () => {
  assert.match(SQL, /= 'approved' and cardinality\(v_missing\) = 0 and not v_name_unread then/);
});

test('every upload path records the licence name, a scan included', () => {
  assert.match(R('supabase/functions/supplier_api/index.ts'), /licenceModelPayload\(/);
  assert.match(R('supabase/functions/resend_inbound/index.ts'), /licence_legal_name: licenceNameFromModel\(dc\)/);
  assert.match(R('supabase/functions/wa_inbound/index.ts'), /licence_legal_name: licenceNameFromModel\(doc\)/);
  // The portal's Documents tab (E2E stage 1, D1, 30 Sep 2026): it read only the expiry, so every licence uploaded
  // there was held as licence_name_unread. Same shared reader, same "a new licence replaces the old name" rule.
  const sp = R('supabase/functions/supplier_portal/index.ts');
  assert.match(sp, /codeName = await readLicenceName\(stored\.bytes, stored\.mime\)/, 'supplier_portal does not read the licence name');
  assert.match(sp, /upd\.licence_legal_name = codeName;/, 'supplier_portal does not record the licence name');
});

// Stage-2 S02 again (7 Oct 2026): the routine held an approved supplier with an unread name, but z20 only re-ran
// it for a WAITING supplier, so a new licence uploaded by an approved supplier never reached the review.
test('a new licence or licence name re-reviews an APPROVED supplier too', () => {
  const z20 = R('scripts/sql/an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql');
  assert.match(z20, /new\.approval_status = 'approved'\s+and \(old\.license_doc_path is distinct from new\.license_doc_path\s+or old\.licence_legal_name is distinct from new\.licence_legal_name\)/);
});

// Review of #1275 (7 Oct 2026): an approved supplier holding another company's licence stayed approved and the log
// said "the licence name matches". The approved branch now requires a match, whatever asked; a mismatch is held.
test("an approved supplier is approved only while his licence names his company", () => {
  const z20 = R("scripts/sql/an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql");
  assert.match(z20, /then 'licence_changed' else 'mandatory_item_changed' end/);
  assert.match(z20, /= 'approved' and cardinality\(v_missing\) = 0 and not v_name_unread\s+and not v_name_mismatch then/);
  assert.match(z20, /elsif coalesce\(l\.approval_status, ''\) = 'approved' and cardinality\(v_missing\) = 0\s+and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';/);
});
