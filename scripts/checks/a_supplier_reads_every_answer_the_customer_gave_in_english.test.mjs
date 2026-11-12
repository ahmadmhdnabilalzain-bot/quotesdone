// A SUPPLIER READS EVERY ANSWER THE CUSTOMER GAVE, IN ENGLISH (sales_engineer, 12 Nov 2026; final audit customer_journey
// B2, fix group Q2). scrub_inquiry_contacts dropped every top-level spec key whose value held Arabic anywhere, and
// customer_requirements always holds display.ar beside display.en, so the supplier PDF and the portal said "the
// customer's answers were not recorded" on 2 of 2 requests. The Arabic is now removed member by member.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * spec_masked is built by dropping whole top-level keys again (the `s.value::text !~` filter);
//   * fn_jsonb_without_arabic stops dropping `ar` / `*_ar` members or Arabic strings, or stops recursing;
//   * the identity masks stop running on the spec before the Arabic is removed;
//   * the data repair is gone.
// The behaviour on production is proved by the aborted probe
// scripts/sql/a_supplier_reads_every_answer_the_customer_gave_in_english_probe.sql (PROBE FAILED on the 12 Nov routine).
//   node --test scripts/checks/a_supplier_reads_every_answer_the_customer_gave_in_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_supplier_reads_every_answer_the_customer_gave_in_english.sql';
const SQL = readFileSync(join(ROOT, FILE), 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const fn = (name) => {
  const from = SQL.indexOf('function public.' + name + '(');
  assert.ok(from >= 0, name + ': gone from the file');
  return SQL.slice(from, SQL.indexOf('$function$;', from));
};

test('the supplier copy removes the Arabic member by member, never a whole key that also holds English', () => {
  const f = fn('scrub_inquiry_contacts');
  assert.match(f, /v_spec\s+:= public\.mask_project_identity_jsonb\(public\.mask_contacts_jsonb\(new\.spec\)\);/, 'the identity masks no longer run on the spec');
  assert.match(f, /new\.spec_masked\s+:= case when jsonb_typeof\(v_spec\) = 'object'\s+then coalesce\(public\.fn_jsonb_without_arabic\(v_spec\), '\{\}'::jsonb\)/);
  assert.doesNotMatch(f, /s\.value::text !~/, 'a whole top-level key is dropped for Arabic anywhere inside it');
});

test('fn_jsonb_without_arabic drops ar / *_ar members and Arabic strings at every depth, and keeps the rest', () => {
  const f = fn('fn_jsonb_without_arabic');
  assert.match(f, /when 'string' then return case when \(j #>> '\{\}'\) ~ ar then null else j end;/);
  assert.match(f, /lower\(t\.k\) <> 'ar' and lower\(t\.k\) !~ '_ar\$'/, 'the ar / *_ar members are kept');
  assert.equal((f.match(/public\.fn_jsonb_without_arabic\(/g) || []).length, 3, 'arrays and objects are not both recursed');   // the declaration and the two recursive calls
  assert.match(SQL, /revoke execute on function public\.fn_jsonb_without_arabic\(jsonb\) from public, anon, authenticated;/);
  assert.match(f, /set search_path to 'public', 'pg_temp'/);
});

test('the requests that lost the answers are re-saved, guarded to exactly those rows', () => {
  assert.match(SQL, /update public\.inquiries\s+set spec = spec\s+where jsonb_typeof\(spec\) = 'object' and spec \? 'customer_requirements'\s+and not coalesce\(spec_masked \? 'customer_requirements', false\);/);
});

test('the file waits for its apply with a note, and its probe is never applied', () => {
  const note = readFileSync(join(ROOT, 'scripts/sql/pending/a_supplier_reads_every_answer_the_customer_gave_in_english.txt'), 'utf8');
  assert.match(note, /sales_engineer/);
  readFileSync(join(ROOT, 'scripts/sql/pending/a_supplier_reads_every_answer_the_customer_gave_in_english_probe.txt'), 'utf8');
});
