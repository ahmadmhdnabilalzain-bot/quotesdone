// The supplier price is stated in four places that cannot see each other: the database, the Stripe
// checkout, the Supplier Agreement (a contract) and the public pages. Nothing kept them in step
// except somebody remembering. This is the check that remembers.
//
// The database half is asserted by public.v_pricing_consistency. This file covers everything that
// lives in the repo and therefore always runs in CI, with no secrets.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const C = JSON.parse(fs.readFileSync(path.join(HERE, 'pricing.canonical.json'), 'utf8'));
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const AGREEMENT = 'src/content/legal.json';
const PUBLIC_PAGES = 'src/content/marketing.json';
const PORTAL = 'src/components/portal/SupplierPortal.tsx';
const CHECKOUT = 'supabase/functions/supplier_api/index.ts';

// 1,000 written any of the ways a human writes it.
const feeRe = new RegExp(`${C.currency}\\s*1[,. ]?000\\b`, 'i');
const startRe = /1 August 2027|1 Aug 2027|2027-08-01/i;
const freeRe = /first (?:one thousand \(1,000\)|1[,. ]?000)/i;
const noCommissionRe = /no commission|does not charge Suppliers any commission|not charged commission/i;

test('the Supplier Agreement states all four pricing facts', () => {
  const s = read(AGREEMENT);
  assert.match(s, feeRe, `${AGREEMENT} does not state ${C.currency} ${C.annual_fee}`);
  assert.match(s, startRe, `${AGREEMENT} does not state the 1 August 2027 start`);
  assert.match(s, freeRe, `${AGREEMENT} does not state the first ${C.free_registrations} exemption`);
  assert.match(s, noCommissionRe, `${AGREEMENT} does not state that suppliers pay no commission`);
});

test('the public supplier pages state all four pricing facts', () => {
  const s = read(PUBLIC_PAGES);
  assert.match(s, feeRe);
  assert.match(s, startRe);
  assert.match(s, freeRe);
  assert.match(s, noCommissionRe);
});

test('the supplier portal states the exemption and the no-commission rule', () => {
  // The portal is not a pricing page, so it is not required to restate the fee or the date - but
  // what it does say has to be true.
  const s = read(PORTAL);
  assert.match(s, /first 1[,. ]?000/i);
  assert.match(s, noCommissionRe);
});

test('the Stripe supplier checkout charges in the canonical currency', () => {
  const s = read(CHECKOUT);
  assert.match(s, /\[price_data\]\[currency\]', 'aed'/,
    `${CHECKOUT} does not create the registration checkout in aed`);
  // The amount must come from the record the biller wrote, never from a literal in the handler.
  assert.match(s, /\[unit_amount\]', String\(Math\.round\(fee \* 100\)\)/,
    'the registration checkout amount is not taken from registration_fee_due');
  assert.match(s, /registration_fee_due/,
    'the registration checkout no longer reads registration_fee_due');
});

test('no file states a different annual supplier price', () => {
  // An annual AED price stated anywhere in the shipped sources, in a sentence that is about OUR
  // supplier fee, must be the canonical number. This catches a well-meaning edit that writes
  // AED 1,200/year on one page and nowhere else.
  //
  // The context window is load-bearing. The blog quotes real market prices - "between AED 1,200 and
  // AED 3,000 per year for a comprehensive AC contract" - which are not our fee and must not fail
  // the build. A match only counts when the surrounding text is talking about a subscription,
  // registration fee or membership.
  const files = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (['node_modules', '.next', '.git', '_archive'].includes(e.name)) continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(tsx?|json|md)$/.test(e.name)) files.push(p);
    }
  };
  walk(path.join(ROOT, 'src'));
  walk(path.join(ROOT, 'supabase', 'functions'));

  const annual = /AED\s*([0-9][0-9,. ]*)\s*(?:\/\s*year|per\s+year|a\s+year|\/\s*yr)/gi;
  const OURS = /subscription|registration fee|supplier fee|membership/i;
  const wrong = [];
  for (const f of files) {
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const src = read(rel);
    for (const m of src.matchAll(annual)) {
      const n = Number(String(m[1]).replace(/[,. ]/g, ''));
      if (n === C.annual_fee) continue;
      const around = src.slice(Math.max(0, m.index - 220), m.index + 220);
      if (!OURS.test(around)) continue; // a market price in an article, not our fee
      wrong.push(`${rel}: AED ${m[1]}/year`);
    }
  }
  assert.deepEqual(wrong, [], `annual supplier prices that are not ${C.currency} ${C.annual_fee}: ${wrong.join('; ')}`);
});

test('no file states a supplier commission rate', () => {
  // "No commission, ever" is a public promise and a contract term. A percentage attached to the word
  // commission anywhere in supplier-facing text contradicts it.
  const suspects = [AGREEMENT, PUBLIC_PAGES, PORTAL];
  const bad = [];
  for (const f of suspects) {
    for (const m of read(f).matchAll(/(\d+(?:\.\d+)?)\s*%\s*commission|commission\s*(?:of|:)?\s*(\d+(?:\.\d+)?)\s*%/gi)) {
      bad.push(`${f}: ${m[0]}`);
    }
  }
  assert.deepEqual(bad, [], `supplier commission rates found in supplier-facing text: ${bad.join('; ')}`);
});

test('the canonical file itself is internally coherent', () => {
  assert.equal(C.currency, 'AED');
  assert.equal(C.period, 'yearly');
  assert.equal(C.supplier_commission, 0);
  assert.equal(C.annual_fee, 1000);
  assert.equal(C.free_registrations, 1000);
  assert.match(C.paid_period_starts, /^2027-08-01$/);
});

test('the guard would catch a wrong price if one were introduced', () => {
  // Proves the previous test is not vacuous: the same matcher, run over a synthetic string.
  const fake = 'The QuotesDone annual supplier subscription is AED 1,200 per year from 2027.';
  const annual = /AED\s*([0-9][0-9,. ]*)\s*(?:\/\s*year|per\s+year|a\s+year|\/\s*yr)/gi;
  const OURS = /subscription|registration fee|supplier fee|membership/i;
  const hits = [...fake.matchAll(annual)]
    .filter((m) => Number(String(m[1]).replace(/[,. ]/g, '')) !== C.annual_fee)
    .filter((m) => OURS.test(fake.slice(Math.max(0, m.index - 220), m.index + 220)));
  assert.equal(hits.length, 1, 'the price guard does not actually detect a wrong price');
});
