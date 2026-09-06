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
//
// 6 SEP 2026 — the founder's ruling, final: "supplier registration is free for the first 1000
// registration. after that its 1000 AED per year. dont use a deadline with dates." Until that day
// the rule was date-based ("free until 31 July 2027, from 1 August 2027 ...") and this file asserted
// the year per language. The fact to hold equal across the language divide is now the count: the
// 1,001st registration is where the fee starts, and no calendar date may appear on any surface.
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

const count = (s, re) => (s.match(re) || []).length;

// The threshold is the same digits in both languages (Arabic surfaces use Western digits with a
// comma or an Arabic thousands separator), so it is the one fact that can be compared numerically
// across the language divide — as the year was until 6 Sep 2026.
const NEXT_RE = /1[,٬]?001/g;            // "the 1,001st registration" / "التسجيل رقم 1,001"
const DATE_RE = /2027|٢٠٢٧|يوليو|أغسطس|July 20|August 20/;

const AR_SURFACES = [
  ['legal.json supplier-agreement [ar]', legal['supplier-agreement'].ar.html],
  ['marketing.json faq [ar]', marketing.faq.ar.html],
];
const EN_SURFACES = [
  ['legal.json supplier-agreement [en]', legal['supplier-agreement'].en.html],
  ['marketing.json faq [en]', marketing.faq.en.html],
];

test('the canonical pricing carries no calendar start date', () => {
  assert.ok(C.billing_starts == null,
    `pricing.canonical.json still names a billing start date (${C.billing_starts}); the founder ruled out dates on 6 Sep 2026`);
});

test('every Arabic supplier surface states charging by count and never by date', () => {
  for (const [label, html] of AR_SURFACES) {
    assert.ok(!DATE_RE.test(html), `${label} still states a calendar date for the fee`);
    assert.match(html, NEXT_RE, `${label} does not say the fee starts at registration 1,001`);
  }
});

test('Arabic and English state the 1,001st-registration rule the same number of times', () => {
  // Not cosmetic: a single missing occurrence is one answer, on one page, that tells a supplier
  // the fee applies today, or never.
  for (let i = 0; i < AR_SURFACES.length; i++) {
    const [arLabel, ar] = AR_SURFACES[i];
    const [enLabel, en] = EN_SURFACES[i];
    assert.ok(!DATE_RE.test(en), `${enLabel} still states a calendar date for the fee`);
    assert.equal(count(ar, NEXT_RE), count(en, NEXT_RE),
      `${arLabel} states the 1,001 rule ${count(ar, NEXT_RE)} time(s) but ${enLabel} states it ${count(en, NEXT_RE)} time(s)`);
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

test('the registration screen states the count rule in both languages and no date', () => {
  // This is the sentence a supplier reads at the moment they commit. It must say who is exempt
  // (the first 1,000, permanently), where the fee starts (registration 1,001) and how much, in
  // both languages, with no calendar date.
  assert.ok(!/2027|July 20|August 20|يوليو|أغسطس/.test(portal), 'SupplierPortal.tsx still carries a calendar date for the fee');
  assert.match(portal, /first 1,000 suppliers to register, permanently; from the 1,001st registration it is AED 1,000 per year/,
    'SupplierPortal.tsx (en) does not state the count rule');
  assert.match(portal, /لأول 1,000 مورّد يسجّلون، إعفاءً دائمًا؛ واعتبارًا من التسجيل رقم 1,001/,
    'SupplierPortal.tsx (ar) does not state the count rule');
});

test('the guard would catch the Arabic drift if it were reintroduced', () => {
  // The check that let this through passed because it read the file as one string. Prove this one
  // reads per language: the English text alone must NOT satisfy the Arabic assertions.
  const en = marketing.faq.en.html;
  assert.ok(!/أول\s*1[,٬]?000/.test(en),
    'the Arabic assertions can be satisfied by English text - this test is not language-aware');
  const drifted = marketing.faq.ar.html.replace(NEXT_RE, '1,0XX');
  assert.equal(count(drifted, NEXT_RE), 0, 'sanity: the mutation did not remove the threshold');
  assert.notEqual(count(drifted, NEXT_RE), count(en, NEXT_RE), 'the parity assertion would not notice the Arabic losing the rule');
});
