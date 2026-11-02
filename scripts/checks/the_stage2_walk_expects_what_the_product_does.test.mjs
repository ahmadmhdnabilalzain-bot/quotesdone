// Stage-2 run f0b2de8f (2 Nov 2026) failed 28 lines whose cause was the walk's own expectation, not the product. Each is pinned here with a
// known-bad control: the same predicate fails on the old text, so it cannot pass by being vacuous.
//   node --test scripts/checks/the_stage2_walk_expects_what_the_product_does.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { profileBytes } from '../e2e/document_intake_corpus.mjs';
import { factSheet } from '../lib/fact_sheet.mjs';

const src = readFileSync(new URL('../e2e/stage2.mjs', import.meta.url), 'utf8');
const s10 = src.slice(src.indexOf('S10: async'), src.indexOf('S11: async'));
const s20 = src.slice(src.indexOf('S20: async'), src.indexOf('S21: async'));
const s21 = src.slice(src.indexOf('S21: async'), src.indexOf('S22: async'));

// S10 / S24: a bare quote names none of its trade's exact specs, so it is held (draft); the supplier releases it through its own door.
const walksTheHold = (t) => /status === 'draft'/.test(t) && /walkSpecHold\(arSup, arQ\.id\)/.test(t);
test('S10: the Arabic customer\'s quote is released through the supplier\'s spec-hold door before the reveal', () => {
  assert.ok(walksTheHold(s10));
  assert.ok(!walksTheHold("const arQ = (await read(`select id, status from public.quotes`))[0]; if (arQ?.status === 'submitted') {"), 'known-bad: the old step expected submitted straight away');
});

// S20: the token is read when the call is made; a plan that holds token strings sends the expired one on the caller's second call.
const readsTokenAtCallTime = (t) => /who === 'cu' \? cu\.jwt/.test(t) && !/\['customer_intelligence', cu\.jwt/.test(t) && !/\['supplier_catalog_ingest', su\.jwt/.test(t);
test('S20: customer_intelligence and supplier_catalog_ingest take the caller\'s token at call time', () => {
  assert.ok(readsTokenAtCallTime(s20));
  assert.ok(!readsTokenAtCallTime("['customer_intelligence', cu.jwt, { action: 'savings' }]"), 'known-bad: the old plan captured the token string');
});

// S04: painting's scope question is "interior, exterior or both?"
test('S04: the painting customer answers interior and exterior, in both languages', () => {
  assert.match(factSheet('painting', { lang: 'en' }).answerFor({ missing_keys: ['scope'] }), /interior.*exterior/i);
  assert.match(factSheet('painting', { lang: 'ar' }).answerFor({ missing_keys: ['scope'] }), /داخلي.*خارجي/);
  assert.doesNotMatch(factSheet('painting', {}).answerFor({ missing_keys: ['scope'] }), /Supply and install/);
});

// S21: the profile prints the registered company, because a profile of another company proposes no trade.
test('S21: each shape uploads a profile that prints the supplier\'s registered name', async () => {
  assert.match(s21, /company_profile: await ownProfile\(prof, d\.registered_name\)/);
  assert.doesNotMatch(s21, /company_profile: b64\(prof\)/, 'known-bad: the old upload sent the corpus\'s fictional company');
  const name = 'ZZ DEMO Registered Company LLC';
  const { bytes, mime } = await profileBytes('pdf', name, ['painting'], ['Jotun'], 1);
  assert.equal(mime, 'application/pdf');
  assert.ok(Buffer.from(bytes).toString('latin1').includes(name), 'the profile prints the name it was given');
});
