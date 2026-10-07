// AN UNREAD LICENCE FIELD IS HELD, NEVER APPROVED (sales_engineer, 7 Oct 2026, founder gate ledger 1162).
// The document intake accuracy suite (scripts/e2e/document_intake_accuracy.mjs) measured the gate approving on the
// licence NAME alone: a licence whose expiry or number nobody read was approved with auto_approve_suppliers on, and an
// approved supplier whose new licence printed another company's name kept the approval. Offline, over the source:
// fails if either hold is removed or placed after automatic approval, or if the approved branch stops asking about a
// mismatch. The behaviour is measured on production rows inside a rolled-back transaction by the suite's gate probe.
//   node --test scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = R('scripts/sql/a_licence_whose_expiry_or_number_could_not_be_read_is_held_and_a_wrong_name_unapproves.sql');

test('an unread expiry and an unread number are held before automatic approval', () => {
  const auto = SQL.indexOf("elsif coalesce(v_auto, false) then v_decision := 'approved';");
  for (const reason of ['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread']) {
    const at = SQL.indexOf(`v_decision := 'pending'; v_reason := '${reason}';`);
    assert.ok(at > 0, `no ${reason} hold`);
    assert.ok(auto > at, `automatic approval is decided before ${reason}`);
  }
  assert.match(SQL, /v_expiry_unread := l\.license_doc_path is not null and l\.license_expiry is null;/);
  assert.match(SQL, /v_number_unread := l\.license_doc_path is not null and coalesce\(btrim\(l\.trade_license_no\), ''\) = '';/);
  assert.match(SQL, /case when v_reason in \('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread'\) then 'needs_review'/);
});

test('an approval stands only while the licence name is read AND matches', () => {
  assert.match(SQL, /= 'approved' and cardinality\(v_missing\) = 0 and not v_name_unread and not v_name_mismatch then/);
});

test('the supplier is told, in both languages, why each new hold happened', () => {
  const copy = R('src/components/portal/supplier/serverCopy.ts');
  for (const k of ['licence_expiry_unread', 'licence_number_unread']) assert.match(copy, new RegExp(`\\b${k}: s\\('`), `no supplier copy for ${k}`);
});

test('process_docs reads every labelled field by code and asks the model when any of the three is unread', () => {
  const api = R('supabase/functions/supplier_api/index.ts');
  assert.match(api, /codeFields = await readLicenceFields\(/);
  assert.match(api, /licenceNeedsModel\(/);
  assert.match(api, /if \(codeFields\.licence_no\) upd\.trade_license_no = codeFields\.licence_no;/);
  assert.match(api, /if \(d\.license_number && !codeFields\.licence_no\) upd\.trade_license_no = d\.license_number;/, 'the model overwrites the number code read');
});
