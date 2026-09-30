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
const SQL = R('scripts/sql/an_approved_supplier_is_told_and_the_licence_name_must_match.sql');

test('the review holds an unread name before it reaches automatic approval', () => {
  const unread = SQL.indexOf("elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_name_unread';");
  const auto = SQL.indexOf("elsif coalesce(v_auto, false) then v_decision := 'approved';");
  assert.ok(unread > 0, 'no unread-name branch');
  assert.ok(auto > unread, 'automatic approval is decided before the unread name is held');
  assert.match(SQL, /v_name_unread := public\.fn_company_name_norm\(coalesce\(l\.licence_legal_name, ''\)\) = ''/);
  assert.match(SQL, /case when v_reason = 'licence_name_unread' then 'needs_review' else 'auto_done' end/);
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
