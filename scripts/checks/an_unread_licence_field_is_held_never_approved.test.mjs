// A LICENCE NAME BECOMES THE COMPANY NAME; A FIELD NOBODY COULD READ IS HELD (sales_engineer, 7 Oct 2026).
// Founder gate ledger 1162 ("not a single mistake in any trade licence"), ruling 1176 ("auto fill the name from the
// attachment instead of rejection") and ruling 1177 ("it should always read"). Built on #1275's body.
// Offline, over the source. The behaviour is measured on production rows inside a rolled-back transaction by the
// gate probe of scripts/e2e/document_intake_accuracy.mjs (--gate-sql), whose corpus holds the mismatch, the unread
// and the approved-swap cases.
//   node --test scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';
const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = R('scripts/sql/a_licence_name_becomes_the_company_name_and_an_unreadable_field_is_held.sql');
const has = (s, why) => assert.ok(SQL.includes(s), why || s);

test('an unread name, expiry or number is held before automatic approval, for review', () => {
  const auto = SQL.indexOf("elsif coalesce(v_auto, false) then v_decision := 'approved';");
  for (const reason of ['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread']) {
    const at = SQL.indexOf(`v_decision := 'pending'; v_reason := '${reason}';`);
    assert.ok(at > 0, `no ${reason} hold`);
    assert.ok(auto > at, `automatic approval is decided before ${reason}`);
  }
  has("v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;");
  has("v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';");
  has("case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread') or (v_decision = 'pending'");
});

test('an approved supplier stays approved only while his licence was read in full (a swapped-in unread licence is held)', () => {
  assert.match(SQL, /= 'approved' and cardinality\(v_missing\) = 0 and not v_name_unread\s+and not v_name_mismatch and not v_expiry_unread and not v_number_unread then/);
});

test('ruling 1176: a read licence name that differs becomes the company name, the old one is kept, the supplier is told', () => {
  const fill = SQL.indexOf("update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;");
  const gate = SQL.indexOf("v_reason := case when cardinality(v_missing) > 0");
  assert.ok(fill > 0 && gate > fill, 'the name is filled before the gate decides');
  has("v_name_mismatch := false;", 'after the fill the gate goes on as for a matching name');
  has("'supplier_name_from_licence'", 'the old name is not kept in history');
  has("'previous_name', v_old_name");
  has("public.fn_sales_engineer_writes('company_name_from_licence', 'supplier'", 'the supplier is not told');
  // the one exception: a name another claimed supplier holds is not copied (unique index, identity) - #1275's hold
  has("public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name)");
  has("if not v_name_taken then");
});

// Review of #1285: this file is built on #1275, which applies first; rebuilding from an older body silently reverted it.
test("#1275's changes are kept", () => {
  has("elsif coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0\n        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';");
  has("(v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review'");
  has("'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name.");
  has("if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then");
});

test('the supplier is asked for a clearer copy when a field stays unread', () => {
  const copy = R('src/components/portal/supplier/serverCopy.ts');
  for (const k of ['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread'])
    assert.match(copy, new RegExp(`\\b${k}: s\\('[^']*Please upload a clearer copy`), `no re-upload request for ${k}`);
});

test('process_docs asks the model for every licence (with one retry), writes only its reading, and reads a photo profile', () => {
  const api = functionSource('supplier_api');
  // since 11 Nov 2026 supplier_api reads by code in lib/licence_store_first.ts readLicenceByCode (`fields`), within a budget
  assert.match(api, /(?:codeFields|fields) = await readLicenceFields\(/);
  // 12 Nov 2026 (sales_engineer; founder rulings 1663, 1664): the model reads EVERY licence, not only when licenceNeedsModel says a
  // field is unread, and the row carries the model's reading only, through the one shared row rule (modelReadingToRow, _shared
  // licence_model.ts). Until then this asserted that code wrote the number it read; review of #1978 F1 reversed that on purpose.
  assert.match(api, /const modelWanted = !!licBytes\?\.bytes;/, 'process_docs does not ask the model for every licence');
  assert.doesNotMatch(api, /upd\.trade_license_no = codeFields\.licence_no/, "code's number is written to the row");
  assert.match(api, /modelReadingToRow\(jd\.doc, /, 'process_docs does not apply the shared row rule');
  assert.match(R('supabase/functions/_shared/document_expiry/licence_model.ts'), /if \(merged\.licence_no\) upd\.trade_license_no = merged\.licence_no;/, "the model's number is not written");
  assert.match(api, /for \(let attempt = 0; attempt < 2; attempt\+\+\)/, 'a failed model read is not retried');
  // Since 19 Oct 2026 the profile is read after the response (supplier_docs_later.ts). Since #1796 (2 Nov 2026) registration and the
  // Documents tab read it through ONE function, readProfileByModel: a photo profile goes to the model as its own image, ahead of the
  // browser's rendered pages when there are any, and on its own bytes when there are none.
  assert.match(api, /const pqImage = !!\(pq\?\.bytes && pq\.mime && \/\^image\\\/\/i\.test\(pq\.mime\)\);/, 'a photo profile is not recognised');
  assert.match(api, /const images = profImgs\.length \? \[\.\.\.\(pqImage \? \[\{ b64: toB64\(pq!\.bytes!\), mime: pq!\.mime \}\] : \[\]\), \.\.\.profImgs\] : undefined;/, 'a photo profile is not sent ahead of the rendered pages');
  assert.match(api, /const holder: LaterDoc = pq \?\? /, 'the profile itself is not what the model reads');
  assert.match(api, /await readProfileByModel\(holder, /, 'process_docs does not read the profile through readProfileByModel');
  const later = R('supabase/functions/_shared/supplier_docs_later.ts');
  assert.match(later, /if \(\/\^image\\\/\/i\.test\(mime\)\) \{\n[^\n]*PROFILE_IMAGE_MAX[^\n]*\n\s*body = \{ images: \[\{ b64: toB64\(d\.bytes\), mime \}\] \};/, 'a photo-only profile is not sent to the model');
});

// Browser walk f4294be8 (12 Oct 2026, it_engineer): a clean text licence uploaded on the supplier portal's own Documents tab was held
// as licence_number_unread, because the model was not asked and code did not read the number. Until 12 Nov 2026 this check required
// every path to write the number CODE read. Founder rulings 1663 and 1664 ("Trade license reading ... there's no code first, 100%";
// review of #1978, F1) reverse that: every path asks the model for every licence, and the row carries the model's reading only.
test('every licence upload path asks the model for every licence and never writes the number code read', () => {
  for (const f of ['supabase/functions/supplier_api/index.ts', 'supabase/functions/supplier_portal/index.ts']) {
    const src = f === 'supabase/functions/supplier_api/index.ts' ? functionSource('supplier_api') : functionSource('supplier_portal');
    assert.ok(!/upd\.trade_license_no = codeFields\.licence_no/.test(src), f + " writes the number code read");
    assert.match(src, /modelReadingToRow\(/, f + ' does not write the model reading through the one row rule');
  }
});
