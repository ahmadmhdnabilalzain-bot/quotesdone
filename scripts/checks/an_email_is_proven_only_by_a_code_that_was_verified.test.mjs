// AN E-MAIL IS PROVEN ONLY BY A CODE THAT WAS VERIFIED (10 Nov 2026, customer_support; item 7 of the supplier-journey audit's
// report, #1901).
//
// "Proven" was read off email_verifications.used_at, which a resend (fn_login_otp_email_issue) and the attempt cap
// (fn_login_otp_email_verify 'burned') also set, and it was decided in two places (supplier_api emailProven, the derive
// trigger fn_leads_derive_owner_email_verified). This fails if: the verify that wins the apply order stops marking ONLY its
// 'ok' path; the resend or the cap starts marking; the one definition (fn_email_proven) reads used_at; the trigger or
// supplier_api decide it any other way; or kyc's own verify stops writing the mark. Routine bodies are read with -- comments
// removed. Behaviour on production: the probe of the same name (rolled back).
//   node --test scripts/checks/an_email_is_proven_only_by_a_code_that_was_verified.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const SQL = 'scripts/sql/';
const FIX = 'an_email_is_proven_only_by_a_code_that_was_verified.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defRe = (fn) => new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
function winning(fn) {
  const defines = (f) => existsSync(SQL + f) && defRe(fn).test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length, `no file defines ${fn}`);
  return listed[listed.length - 1];
}
function body(fn) {
  const src = readFileSync(SQL + winning(fn), 'utf8');
  const open = src.search(defRe(fn));
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${fn} has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  return src.slice(start, src.indexOf(m[1], start)).replace(/--[^\n]*/g, '');
}

test('only a code entered right is marked verified; a resend and the attempt cap are not', () => {
  const v = body('fn_login_otp_email_verify');
  const marks = [...v.matchAll(/verified_at\s*=\s*now\(\)/g)];
  assert.equal(marks.length, 1, 'verified_at must be set in exactly one place');
  const ok = v.indexOf("return 'ok'");
  const at = v.search(/set used_at = now\(\), verified_at = now\(\) where id = r\.id and used_at is null;\s*if found then return 'ok';/);
  assert.ok(at > 0 && at < ok, "verified_at must be set by the update that answers 'ok'");
  assert.ok(v.indexOf("return 'burned'") < at, 'the burn must not be the update that marks');
  assert.doesNotMatch(body('fn_login_otp_email_issue'), /verified_at/, 'a resend must never mark a code verified');
});

test('fn_email_proven is the one definition and reads the mark, never used_at', () => {
  const p = body('fn_email_proven');
  assert.match(p, /verified_at is not null/);
  assert.doesNotMatch(p, /used_at/);
  const src = readFileSync(SQL + winning('fn_email_proven'), 'utf8');
  assert.match(src, /revoke execute on function public\.fn_email_proven\(text\) from public, anon, authenticated;/);
  assert.match(src.slice(src.search(defRe('fn_email_proven'))), /set search_path to 'public', 'pg_temp'/);
});

test('the derive trigger and every supplier_api path ask that one definition', () => {
  const t = body('fn_leads_derive_owner_email_verified');
  assert.match(t, /public\.fn_email_proven\(NEW\.claimed_by\)/);
  assert.doesNotMatch(t, /used_at/, 'the trigger must not decide proof on its own');
  const api = functionSource('supplier_api');
  assert.match(api, /export async function emailProven\(email: string\) \{\n[^\n]*rpc\('fn_email_proven'/);
  assert.doesNotMatch(api, /email_verifications'\)[^\n]*used_at/, 'supplier_api must not read used_at as proof');
  // create_company (claim and insert) and the token claim all take emailProven
  assert.match(api, /createCompany\(admin, email, body, \{ emailProven,/);
  assert.match(api, /Promise\.all\(\[admin\.from\('leads'\)\.select\('id,claimed,claimed_by,permanently_closed,banned'\)\.eq\('claim_token', token\)\.maybeSingle\(\), [^\n]*emailProven\(email\)\]\)/);
});

test("kyc's own code verify writes the same mark", () => {
  assert.match(functionSource('kyc'), /update\(\{ used_at: at, verified_at: at \}\)/);
});
