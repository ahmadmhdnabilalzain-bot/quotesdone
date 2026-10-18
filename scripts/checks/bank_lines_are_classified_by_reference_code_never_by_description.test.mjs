// BANK LINES ARE CLASSIFIED BY THEIR STRUCTURED REFERENCE CODE, NEVER BY THEIR DESCRIPTION
// (5 Oct 2026, accountant; ruling 890: no word matching).
//
// fn_accountant_classify_bank_lines_by_reference sets bank_statement_line.kind from public.bank_reference_code,
// matched on the bank's reference field (a structured code). Fails if the classifier, or the booking tick that
// calls it, ever reads the description column or matches text with a pattern; and, once the routine is live,
// if the schema mirror's body does.
//
//   node --test scripts/checks/bank_lines_are_classified_by_reference_code_never_by_description.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_bank_line_is_classified_by_its_structured_reference_code.sql';
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');   // comments may name the column
const body = (src, fn) => {
  const i = src.search(new RegExp(`function public\\.${fn}\\(`, 'i'));
  if (i < 0) return null;
  const tag = src.slice(i).match(/as (\$[a-z_]*\$)/i)[1];
  const a = src.indexOf(tag, i) + tag.length;
  return code(src.slice(a, src.indexOf(tag, a)));
};
const FORBIDDEN = /\bdescription\b|\bi?like\b|~\*?|regexp_|similar to|position\(|strpos\(/i;
const LIVE = /fn_accountant_classify_bank_lines_by_reference/;

for (const [where, src] of [['the SQL file', readFileSync(join(ROOT, FILE), 'utf8')], ['the schema mirror', readSchemaMirror()]]) {
  const pending = where === 'the schema mirror' && !LIVE.test(src);   // not live until the release applies it
  test(`${where}: the classifier reads the reference code, never the description`, { skip: pending }, () => {
    const c = body(src, 'fn_accountant_classify_bank_lines_by_reference');
    assert.ok(c, 'the classifier is missing');
    assert.doesNotMatch(c, FORBIDDEN, 'the classifier reads description text or matches a pattern (ruling 890)');
    assert.match(c, /b\.reference/, 'the classifier no longer matches on the reference field');
    assert.match(c, /from public\.bank_reference_code/i, 'the classifier no longer reads the code table');
  });
  test(`${where}: the booking tick classifies by reference before it books`, { skip: pending }, () => {
    const c = body(src, 'fn_accountant_cost_booking_tick');
    assert.ok(c, 'the tick is missing');
    assert.doesNotMatch(c, /\bdescription\b/i, 'the tick reads description text');
    const k = c.indexOf('fn_accountant_classify_bank_lines_by_reference()');
    assert.ok(k > 0 && k < c.indexOf('fn_accountant_book_bank_charges()'), 'classification does not run before booking');
  });
}
