// A REGISTRATION FIELD THE SERVER DISCARDS IS NOT OFFERED AS EDITABLE (10 Nov 2026, customer_support, supplier-journey audit).
//
// Measured in the code on main, 10 Nov 2026. The registration form (supplier/core/ProfileForm.tsx) offered two editable
// fields, "Licence number" and "Issuing authority", sent them to save_profile with trade_license_no and license_expiry,
// and told a supplier whose licence did not read: "If the number did not fill in, type it below". save_profile copies only
// PROFILE_COLS (supplier_api/lib/fields.ts), and since 15 Sep 2026 the licence fields are deliberately NOT in it: they are
// written only from the stored file, so a supplier cannot type his own expiry. So the typed number was dropped without a
// word, while the form counted it as the licence item of the six (`licOnFile || trade_license_no`), showed "Done" on the
// licence heading, and let the supplier submit. The database (fn_supplier_mandatory_six) counts only a stored file, and
// fn_sales_engineer_verifies_supplier holds a licence whose number did not read as licence_number_unread, then asks for a
// clearer copy: the supplier was told one thing on screen and the opposite by e-mail. Two readings of one rule.
//
//   node --test scripts/checks/a_registration_field_the_server_discards_is_not_offered.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const FORM = read('src/components/portal/supplier/core/ProfileForm.tsx');
const FIELDS = read('supabase/functions/supplier_api/lib/fields.ts');
const COPY = read('src/components/portal/supplier/core/copy.ts');
const PROFILE_COLS = JSON.parse(FIELDS.match(/export const PROFILE_COLS = (\[[^\]]*\])/)[1].replace(/'/g, '"'));

test('every text field the form sends to save_profile is one save_profile keeps', () => {
  const strk = FORM.match(/const strk = (\[[^\]]*\])/);
  assert.ok(strk, 'the form names the text fields it sends');
  const sent = JSON.parse(strk[1].replace(/'/g, '"'));
  const dropped = sent.filter((k) => !PROFILE_COLS.includes(k));
  assert.deepEqual(dropped, [], 'sent to save_profile and silently discarded there: ' + dropped.join(', '));
});

test('the licence item of the six is the stored file, on screen as in the database', () => {
  assert.doesNotMatch(FORM, /licOnFile \|\| !?!?String\(f\.trade_license_no/, 'a typed licence number is not a licence (fn_supplier_mandatory_six)');
  // 11 Nov 2026 (customer_support, licenceReceived.ts): Submit also asks the row, so `onFile` is the stored file as the form
  // knows it OR as the row names it (license_doc_path), never a typed number.
  assert.match(FORM, /if \(!onFile\) missing\.push\('reg_licence'\)/);
  assert.match(FORM, /let onFile = licOnFile;/);
  assert.match(FORM, /if \(licenceStoredSince\('', row\)\) \{ onFile = true;/);
});

test('the licence number and authority are shown as read, never as an input the server ignores', () => {
  for (const k of ['lic_no', 'authority']) {
    const at = FORM.indexOf("text={t(lang, '" + k + "')}");
    assert.ok(at > 0, k + ' is still shown');
    const input = FORM.slice(at, FORM.indexOf('/>', at));
    assert.match(input, /readOnly/, k + ' is read-only: save_profile does not write it');
    assert.doesNotMatch(input, /onChange=/, k + ' takes no typing');
  }
});

test('the supplier is not told to type what is never saved', () => {
  const en = COPY.match(/lic_uploaded_type:'([^']*)'/)[1];
  assert.doesNotMatch(en, /type it/i, en);
});
