// AN ARABIC SPEC ANSWER REACHES SUPPLIERS ONLY IN ENGLISH (5 Oct 2026, sales_engineer; ledger 993, founder_instruction
// 1026). A customer's free-text answer to a missing spec (customer_api add_missing_specs -> fn_inquiry_add_missing_specs)
// was e-mailed to every matched supplier verbatim and shown in the portal's spec. It now follows #1195's design: kept
// as written, the supplier copy held on a note filed for its English (surface sales_engineer.supplier_english), sent
// only by finishEnglish once no Arabic is left; spec_masked never carries an Arabic value.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the routine stops splitting Arabic answers off, or puts them on the mailed lines / the supplier note;
//   * the held note is not filed for its English, or is filed under another surface or dedupe key than finishEnglish's;
//   * the filed question drifts from supplier_english.ts englishQuestion (the replay's prompt);
//   * the supplier copy of the spec (spec_masked) keeps Arabic values.
// The behaviour on production is proved by the aborted probe
// scripts/sql/an_arabic_spec_answer_reaches_suppliers_only_in_english_probe.sql.
//   node --test scripts/checks/an_arabic_spec_answer_reaches_suppliers_only_in_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = readFileSync(join(ROOT, 'scripts/sql/an_arabic_spec_answer_reaches_suppliers_only_in_english.sql'), 'utf8')
  .split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');   // code only, never the comments
const fn = (name) => {
  const from = SQL.indexOf('function public.' + name + '(');
  assert.ok(from >= 0, name + ': gone from the file');
  return SQL.slice(from, SQL.indexOf('$function$;', from));
};
const AR = /v_val ~ '\[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾\]'/;

test('an Arabic answer is split off the mailed lines and onto a held note', () => {
  const f = fn('fn_inquiry_add_missing_specs');
  const gate = f.search(new RegExp(AR.source + ' then\\s+v_held := v_held'));
  assert.ok(gate > 0, 'no Arabic branch that collects the held lines');
  const held = f.slice(f.indexOf("if v_held <> '' then"), f.indexOf("if v_lines <> '' then"));
  assert.match(held, /answer_as_written, english_held_at/, 'the held note does not keep the text as written and held');
  assert.match(held, /values \(i\.id, null, 'note', null,/, 'the held note writes a supplier copy');
  assert.doesNotMatch(held, /fn_customer_support_takes_delivery|notifications/, 'the held lines are mailed');
  const mailed = f.slice(f.indexOf("if v_lines <> '' then"), f.indexOf('v_missing := public.fn_inquiry_missing_specs(i.id, null)'));
  assert.doesNotMatch(mailed, /v_held/, 'the held lines reach the supplier note or e-mail');
});

test('the held note is filed for the replay finishEnglish delivers', () => {
  const f = fn('fn_inquiry_add_missing_specs');
  assert.match(f, /fn_reason_hold\('sales_engineer', 'sales_engineer\.supplier_english'/, 'not filed on the supplier_english surface');
  assert.match(f, /'clarification_id', v_held_note\)/, 'the subject does not name the held note');
  assert.match(f, /'supplier_english:' \|\| v_held_note\);/, 'another dedupe key than holdForEnglish files');
  const ts = readFileSync(join(ROOT, 'supabase/functions/_shared/supplier_english.ts'), 'utf8');
  const from = ts.indexOf("return 'Translate");
  const prompt = ts.slice(from, ts.indexOf('+ text;', from));
  const parts = [...prompt.matchAll(/'([^'\n]*)'/g)].map((m) => m[1]).join('').replace(/\\n\\n$/, '');
  const sqlPrompt = [...f.slice(f.indexOf("v_q := 'Translate")).split('chr(10)')[0].matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'")).join('');
  assert.equal(sqlPrompt, parts, 'the filed question drifted from englishQuestion');
});

test('budget and emirate in Arabic are never written to the columns suppliers read raw', () => {
  const f = fn('fn_inquiry_add_missing_specs');
  assert.match(f, /in \('budget', 'emirate'\) and v_val ~ '[^']+' then\s+v_kept := v_kept[^;]*; continue;/, 'an Arabic budget or emirate is written');
});

// 12 Nov 2026 (sales_engineer, final audit B2): scrub_inquiry_contacts is now defined by
// a_supplier_reads_every_answer_the_customer_gave_in_english.sql, which removes the Arabic member by member instead of
// dropping a whole top-level key (that dropped customer_requirements with its English). This assertion reads the
// canonical file; the member-by-member rule itself is asserted in that file's own check.
test('the supplier copy of the spec drops every Arabic value', () => {
  const canon = readFileSync(join(ROOT, 'scripts/sql/a_supplier_reads_every_answer_the_customer_gave_in_english.sql'), 'utf8')
    .split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  const from = canon.indexOf('function public.scrub_inquiry_contacts(');
  assert.ok(from >= 0, 'scrub_inquiry_contacts: gone from the canonical file');
  const f = canon.slice(from, canon.indexOf('$function$;', from));
  assert.match(f, /new\.spec_masked\s+:= case when jsonb_typeof\(v_spec\) = 'object'[\s\S]*?public\.fn_jsonb_without_arabic\(v_spec\)/, 'spec_masked keeps Arabic values');
  assert.doesNotMatch(f, /new\.spec_masked\s+:= public\.mask/, 'spec_masked is assigned straight from the mask again');
});
