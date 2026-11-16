// THE HARD RULES READ THE CIRCUMVENTION CLAUSE THE AGREEMENT PRINTS (16 Nov 2026, ceo; simplification wave B, SITE-01).
//
// MEASURED (SELECT, production, 16 Nov 2026): the company block every seat carries (fn_company_context, which embeds
// fn_company_hard_rules) said "AED 15,000 per incident OR five (5) times the fee" while the published Supplier Agreement
// v18 says AED 20,000. The routine read the sum with the v13 word 'liquidated' (v18 says 'agreed') and fell back to a
// hard-coded '15,000'. This check fails if that comes back:
//   1. the newest definition of fn_company_hard_rules (MANIFEST order, then pending files) has no figure fallback for the
//      circumvention sum, multiple or window;
//   2. its own regular expressions, run on the signed v18 body (signedBody(legal.json, '18'), byte-equal to production's
//      pages.legal_supplier_body on 16 Nov 2026, md5 831fadd6...), read exactly the figures src/content/company_facts.json
//      states (circumvention_min_aed, circumvention_fee_multiple, circumvention_tail_months).
// Offline: reads only the repository.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadFacts, signedBody } from '../legal/company_facts.mjs';
import { manifestWithPending } from '../lib/pending_sql.mjs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const F = loadFacts();
const legal = JSON.parse(read('src/content/legal.json'));

function newestBody() {
  let file = null;
  for (const f of manifestWithPending()) {
    let t; try { t = read(f); } catch { continue; }
    if (/create\s+or\s+replace\s+function\s+public\.fn_company_hard_rules\s*\(/i.test(t)) file = f;
  }
  assert.ok(file, 'no scripts/sql file defines public.fn_company_hard_rules');
  const t = read(file);
  const start = t.search(/create\s+or\s+replace\s+function\s+public\.fn_company_hard_rules\s*\(/i);
  const tag = t.slice(start).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  const open = t.indexOf(tag, start);
  return { file, body: t.slice(open + tag.length, t.indexOf(tag, open + tag.length)) };
}

// A Postgres string literal assigned with the given prefix, as a JavaScript RegExp (ARE \s and \( mean the same here).
function literalAfter(body, prefix) {
  const i = body.indexOf(prefix);
  assert.ok(i >= 0, `the routine no longer contains ${prefix}`);
  const m = body.slice(i + prefix.length).match(/^\s*'((?:[^']|'')*)'/);
  assert.ok(m, `no string literal after ${prefix}`);
  return new RegExp(m[1].replace(/''/g, "'"));
}

const { file, body } = newestBody();
const agreement = signedBody(legal['supplier-agreement'], F.documents['supplier-agreement'].version.replace(/^v/, ''));
const text = agreement.replace(/<[^>]+>/g, ' ');

test(`${file}: no remembered figure stands in for the circumvention clause`, () => {
  assert.doesNotMatch(body, /coalesce\(\s*v_(aed|mult|tail)\s*,\s*'[^']*\d/i, 'a hard-coded circumvention figure is back as a fallback');
  assert.doesNotMatch(body, /liquidated compensation of AED/i, 'the sum is read with the retired v13 wording');
});

test(`${file}: its own regular expressions read the figures company_facts.json states from the signed agreement`, () => {
  const clause = text.match(literalAfter(body, 'regexp_match(v_txt,'));
  assert.ok(clause, 'the clause-24 sentence (sum and multiple together) is not found in the signed agreement');
  const tail = text.match(literalAfter(body, "v_tail := substring(v_txt from"));
  assert.ok(tail, 'the protected period ("For N months from such introduction") is not found in the signed agreement');
  assert.equal(Number(clause[1].replace(/,/g, '')), F.facts.circumvention_min_aed.value);
  assert.equal(Number(clause[2].match(/\d+/)[0]), F.facts.circumvention_fee_multiple.value);
  assert.equal(Number(tail[1]), F.facts.circumvention_tail_months.value);
});
