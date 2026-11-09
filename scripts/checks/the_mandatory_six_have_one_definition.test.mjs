// THE MANDATORY SIX HAVE ONE DEFINITION (sales_engineer, 15 Sep 2026).
//
// The six used to be decided twice, differently: in _shared/supplier_registration.ts and in
// fn_supplier_mandatory_check. The database now decides (fn_supplier_mandatory_six); the TypeScript only
// orders and words the codes. This fails if the two lists of codes drift apart, if the portal lacks EN or
// AR words for one, or if the doors this build closed are opened again.
//   node --test scripts/checks/the_mandatory_six_have_one_definition.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SIX_SQL = read('scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql');
const SWEEP_SQL = read('scripts/sql/the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql');
const MATCH_SQL = read('scripts/sql/a_supplier_is_matchable_only_once_approved.sql');
const REG_TS = read('supabase/functions/_shared/supplier_registration.ts');
const API = functionSource('supplier_api');
const KYC = read('supabase/functions/kyc/index.ts');
const COPY = read('src/components/portal/supplier/serverCopy.ts');
const MANIFEST = read('scripts/sql/MANIFEST.txt');

const sqlBody = (src, fn) => {
  const a = src.indexOf('create or replace function public.' + fn + '(');
  assert.ok(a >= 0, fn + ' is defined');
  return src.slice(a, src.indexOf('$fn$;', a));
};
const sqlCodes = [...sqlBody(SIX_SQL, 'fn_supplier_mandatory_six').matchAll(/then '(reg_[a-z]+)' end/g)].map((m) => m[1]);
const tsCodes = [...REG_TS.matchAll(/\{ code: '(reg_[a-z]+)'/g)].map((m) => m[1]);

test('the database and the TypeScript name the same six, in the same order', () => {
  assert.deepEqual(sqlCodes, ['reg_name', 'reg_mobile', 'reg_email', 'reg_licence', 'reg_profile', 'reg_terms']);
  assert.deepEqual(tsCodes, sqlCodes);
});

test('the TypeScript asks the database rather than deciding', () => {
  assert.match(REG_TS, /rpc\('fn_supplier_mandatory_six_for'/);
  assert.doesNotMatch(REG_TS, /license_doc_path|accepted_terms_at|owner_phone_verified/, 'no row field decides an item in TypeScript');
});

test('the six are documents, verified identities and the signed certificate', () => {
  const body = sqlBody(SIX_SQL, 'fn_supplier_mandatory_six');
  assert.match(body, /storage\.objects o where o\.bucket_id = 'supplier-docs' and o\.name = p\.license_doc_path/);
  assert.match(body, /storage\.objects o where o\.bucket_id = 'supplier-docs' and o\.name = p\.company_profile_doc_path/);
  assert.match(body, /p\.owner_phone_verified/);
  assert.match(body, /p\.owner_email_verified/);
  assert.match(body, /p\.signed_terms_path/);
  assert.doesNotMatch(body, /trade_license_no/, 'a licence number is not a licence');
});

test('the WhatsApp/support answer reads the same six', () => {
  assert.match(sqlBody(SIX_SQL, 'fn_supplier_mandatory_check'), /public\.fn_supplier_mandatory_six\(l\)/);
});

test('the portal has English and Arabic words for every code', () => {
  for (const c of sqlCodes) {
    const m = COPY.match(new RegExp('\\n\\s*' + c + ": s\\('([^']+)', '([^']+)'\\)"));
    assert.ok(m, c + ' has copy');
    assert.match(m[2], /[؀-ۿ]/, c + ' has Arabic');
  }
});

test('the database refuses an incomplete approval and verifies through the sales engineer', () => {
  assert.match(SIX_SQL, /create trigger trg_leads_e0_mandatory_six_gate\s+before insert or update on public\.leads/);
  assert.match(SIX_SQL, /errcode = 'check_violation'/);
  assert.match(API, /rpc\('fn_sales_engineer_verifies_supplier'/);
  assert.doesNotMatch(API, /upd\.approval_status\s*=/, 'supplier_api no longer approves inline');
});

test('the browser cannot write the licence fields', () => {
  const cols = API.match(/const PROFILE_COLS = \[([^\]]+)\]/)[1];
  for (const c of ['license_doc_path', 'license_expiry', 'trade_license_no']) assert.ok(!cols.includes("'" + c + "'"), c);
});

test('terms are accepted only when the flag is exactly true, and recorded once, with the hash', () => {
  assert.match(API, /const accepting = body\.accept_terms === true\b/);
  assert.doesNotMatch(API, /if \(body\.accept_terms\)/);
  assert.match(API, /supplierTermsRecord\(/);
  assert.match(KYC, /supplierTermsRecord\(/);
  assert.doesNotMatch(KYC, /accepted_terms_version: supV/, 'kyc no longer writes a version without the hash');
});

test('save_profile keeps the services the supplier typed', () => {
  assert.doesNotMatch(API, /upd\.services = prior\.extracted/);
});

test('matching requires approval', () => {
  assert.match(sqlBody(MATCH_SQL, 'fn_is_matchable'), /coalesce\(p_approval_status, ''\) = 'approved'/);
});

test('the 14-day close and the expiry jobs are scheduled on the heartbeat', () => {
  assert.match(SWEEP_SQL, /insert into public\.it_duty_schedule[\s\S]*'supplier_docs'/);
  assert.match(SWEEP_SQL, /public\.fn_reconcile_doc_blocks\(0\)/);
  assert.match(SWEEP_SQL, /perform public\.fn_it_duty_ran\('supplier_docs'/);
  assert.match(functionSource('resilience_ping'), /rpc\('fn_sales_engineer_supplier_documents_tick'\)/);
});

test('the three files are in the apply order, in dependency order', () => {
  const at = (f) => MANIFEST.split(/\r?\n/).indexOf('scripts/sql/' + f);
  const six = at('the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql');
  const sweep = at('the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql');
  const match = at('a_supplier_is_matchable_only_once_approved.sql');
  assert.ok(six >= 0 && sweep > six && match >= 0, 'listed, the sweep after the six it calls');
});
