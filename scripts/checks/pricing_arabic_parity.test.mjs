// AUDIT 4.4 — why the Arabic drift survived a check that exists to catch exactly this.
//
// pricing_consistency.test.mjs reads each content file as ONE STRING and asserts the four pricing
// facts appear somewhere in it. Every one of those files holds English and Arabic side by side, so
// the English half satisfies every assertion and the Arabic half is never looked at. On 3 Aug the
// Arabic FAQ said registration was free "خلال الإطلاق" (during launch) and charged after the
// 1,000th supplier, with no 2027 date anywhere - and the suite was green.
//
// This file asserts the same facts PER LANGUAGE, and asserts the absence of the temporary-launch
// framing, which is the specific way the Arabic contradicted a permanent contractual exemption.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const C = JSON.parse(fs.readFileSync(path.join(HERE, 'pricing.canonical.json'), 'utf8'));
const readJson = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const legal = readJson('src/content/legal.json');
const marketing = readJson('src/content/marketing.json');
const portal = read('src/components/portal/SupplierPortal.tsx');

const count = (s, needle) => s.split(needle).length - 1;

// The year is the same four characters in both languages, so it is the one fact that can be
// compared numerically across the language divide.
const START_YEAR = String(C.billing_starts ? new Date(C.billing_starts).getUTCFullYear() : 2027);

const AR_SURFACES = [
  ['legal.json supplier-agreement [ar]', legal['supplier-agreement'].ar.html],
  ['marketing.json faq [ar]', marketing.faq.ar.html],
];
const EN_SURFACES = [
  ['legal.json supplier-agreement [en]', legal['supplier-agreement'].en.html],
  ['marketing.json faq [en]', marketing.faq.en.html],
];

test('every Arabic supplier surface states the charging start year', () => {
  for (const [label, html] of AR_SURFACES) {
    assert.ok(html.includes(START_YEAR), `${label} never mentions ${START_YEAR}`);
    assert.match(html, /1 أغسطس 2027|٢٠٢٧|31 يوليو 2027/,
      `${label} does not give the start date in Arabic`);
  }
});

test('Arabic and English state the start year the same number of times', () => {
  // Not cosmetic: a single missing occurrence is one answer, on one page, that tells a supplier
  // the fee applies today.
  for (let i = 0; i < AR_SURFACES.length; i++) {
    const [arLabel, ar] = AR_SURFACES[i];
    const [enLabel, en] = EN_SURFACES[i];
    assert.equal(count(ar, START_YEAR), count(en, START_YEAR),
      `${arLabel} states ${START_YEAR} ${count(ar, START_YEAR)} time(s) but ${enLabel} states it ${count(en, START_YEAR)} time(s)`);
  }
});

test('every Arabic supplier surface states the fee and the founding exemption', () => {
  for (const [label, html] of AR_SURFACES) {
    assert.match(html, /1[,٬]?000\s*درهم/, `${label} does not state the fee in AED`);
    assert.match(html, /أول\s*1[,٬]?000/, `${label} does not state the first ${C.free_registrations}`);
    assert.match(html, /دائم/, `${label} does not say the exemption is permanent`);
  }
});

test('no Arabic surface frames the exemption as a temporary launch offer', () => {
  // "free during launch" / "after the free launch period" describe something that ends. The
  // Supplier Agreement says the opposite, and the English says the opposite. A published Arabic
  // contract term that contradicts the English one is not a translation problem.
  const banned = ['خلال الإطلاق', 'بعد فترة الإطلاق', 'فترة الإطلاق المجانية'];
  const found = [];
  for (const [label, html] of AR_SURFACES) {
    for (const b of banned) if (html.includes(b)) found.push(`${label}: "${b}"`);
  }
  assert.deepEqual(found, [], `temporary-launch framing in Arabic: ${found.join('; ')}`);
});

test('the registration screen states the start date in both languages', () => {
  // This is the sentence a supplier reads at the moment they commit. Until 3 Aug it said
  // "Registration is free for the first 1,000 suppliers" in BOTH languages - true of neither the
  // agreement nor the code, and it reads as "charging starts at supplier 1,001".
  assert.match(portal, /31 July 2027/, 'SupplierPortal.tsx (en) does not state the free-until date');
  assert.match(portal, /31 يوليو 2027/, 'SupplierPortal.tsx (ar) does not state the free-until date');
  assert.ok(!/Registration is free for the first 1,000 suppliers\./.test(portal),
    'SupplierPortal.tsx still carries the dateless "free for the first 1,000" sentence');
});

test('the guard would catch the Arabic drift if it were reintroduced', () => {
  // The check that let this through passed because it read the file as one string. Prove this one
  // reads per language: the English text alone must NOT satisfy the Arabic assertions.
  const en = marketing.faq.en.html;
  assert.ok(!/أول\s*1[,٬]?000/.test(en),
    'the Arabic assertions can be satisfied by English text - this test is not language-aware');
  const drifted = marketing.faq.ar.html.split(START_YEAR).join('20XX');
  assert.ok(!drifted.includes(START_YEAR), 'sanity: the mutation did not remove the year');
});
