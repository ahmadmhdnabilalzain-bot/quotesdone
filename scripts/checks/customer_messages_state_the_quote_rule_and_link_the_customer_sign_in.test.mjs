// customer_support, 24 Sep 2026. The founder registered as a test customer and the activation e-mail
// (#904) told him a capped number of suppliers would quote, and linked him to the SUPPLIER portal.
// His rule: ANY number of verified suppliers in the trade may quote; "top three" is only the comparison
// report, which recommends the three best by value. And a customer is sent to the customer sign-in, /me.
//
// Two assertions, over every file that can put words in front of a customer or a seat:
//   1. no text caps the quotes at three (English or Arabic);
//   2. no routine that writes to a customer links the supplier portal.
// The forbidden shapes are built from parts below so this file does not match itself.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { definitions } from '../lib/canonical_sql.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SELF = path.basename(fileURLToPath(import.meta.url));

const UP_TO = String.raw`up\s+to\s+`;
export const QUOTE_CAP = [
  new RegExp(UP_TO + String.raw`(three|3)\b(?!\s*(\(3\)\s*)?(working\s+|business\s+)?(days?|hours?|times|retries|attempts|files)\b)[^.\n]{0,40}?\b(quotes?|quotations?|offers?|suppliers?)\b`, 'i'),
  new RegExp('حتى ' + 'ثلاث(ة)? (عروض|موردين)'),
  new RegExp('قارن ' + 'حتى ثلاث'),
];
const PORTAL_LINK = new RegExp(String.raw`quotesdone\.(com|ae)/(ar/|en/)?` + String.raw`portal\b`);

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.(sql|ts|tsx|mjs|js|json|md)$/.test(e.name) && e.name !== SELF) out.push(p);
  }
  return out;
}
const SURFACES = ['src', 'messages', 'supabase/functions', 'scripts/sql', 'content']
  .flatMap((d) => walk(path.join(REPO, d)));

test('no customer-facing text or knowledge caps the number of quotes at three', () => {
  const hits = [];
  for (const f of SURFACES) {
    const lines = fs.readFileSync(f, 'utf8').split('\n');
    lines.forEach((l, i) => {
      for (const re of QUOTE_CAP) if (re.test(l)) hits.push(`${path.relative(REPO, f)}:${i + 1}: ${l.trim().slice(0, 140)}`);
    });
  }
  assert.deepEqual(hits, [], 'any number of suppliers may quote; only the report recommends a top three:\n' + hits.join('\n'));
});

test('a routine that writes to a customer never links the supplier portal', () => {
  const hits = [];
  for (const f of SURFACES.filter((p) => p.endsWith('.sql') && !p.includes(`${path.sep}schema${path.sep}`))) {
    for (const d of definitions(fs.readFileSync(f, 'utf8'))) {
      if (!/customer/.test(d.name) || /supplier/.test(d.name)) continue;
      if (PORTAL_LINK.test(d.stmt)) hits.push(`${path.relative(REPO, f)}: ${d.name}`);
    }
  }
  assert.deepEqual(hits, [], 'customers sign in at /me (Arabic /ar/me), not /portal:\n' + hits.join('\n'));
});

test('the guard catches both shapes (it would fail if they returned)', () => {
  assert.ok(QUOTE_CAP.some((re) => re.test('and ' + 'up to three qualified UAE suppliers will quote')));
  assert.ok(QUOTE_CAP.some((re) => re.test('receive ' + 'up to three quotes from')));
  assert.ok(QUOTE_CAP.some((re) => re.test('من موردين مؤهلين، ' + 'حتى ثلاثة عروض')));
  assert.ok(!QUOTE_CAP.some((re) => re.test('verification takes up to 3 working days')));
  assert.ok(PORTAL_LINK.test('Start here: https://quotesdone.com/' + 'portal'));
  assert.ok(!PORTAL_LINK.test('https://quotesdone.com/me'));
});
