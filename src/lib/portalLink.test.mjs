// node --test src/lib/portalLink.test.mjs
// The deep link the PDFs print and the portal opens. The literal below is the same one
// supabase/functions/_shared/quote_documents.test.ts expects on the report, so the two sides
// cannot drift apart without one of the tests failing.
import test from 'node:test';
import assert from 'node:assert/strict';
import { quoteLink, parseQuoteLink, resolveQuoteLink } from './portalLink.ts';

const R = '0f8e1c2a-1111-4a00-9a00-000000000001';
const Q = '0f8e1c2a-2222-4a00-9a00-000000000002';

test('builds the English and Arabic links on the canonical origin', () => {
  assert.equal(quoteLink('https://quotesdone.com', 'en', R, Q), `https://quotesdone.com/me?request=${R}&quote=${Q}`);
  assert.equal(quoteLink('https://quotesdone.com/', 'ar', R, Q), `https://quotesdone.com/ar/me?request=${R}&quote=${Q}`);
  assert.equal(quoteLink('https://quotesdone.com', 'en', R), `https://quotesdone.com/me?request=${R}`);
});

test('parses what it builds, and nothing when the params are absent', () => {
  assert.deepEqual(parseQuoteLink(`?request=${R}&quote=${Q}`), { request: R, quote: Q });
  assert.deepEqual(parseQuoteLink(`?request=${R.toUpperCase()}`), { request: R, quote: '' });
  assert.equal(parseQuoteLink(''), null);
  assert.equal(parseQuoteLink('?draft=1'), null);
});

test('a malformed id is blanked, never looked up', () => {
  assert.deepEqual(parseQuoteLink("?request=1%20or%201=1&quote=abc"), { request: '', quote: '' });
});

const MINE = [
  { id: R, quotes: [{ id: Q }] },
  { id: 'c0mb1ned', is_combined: true, children: [{ id: '0f8e1c2a-3333-4a00-9a00-000000000003', quotes: [{ id: '0f8e1c2a-4444-4a00-9a00-000000000004' }] }] },
];

test('resolves a quote in the customer\'s own requests, combined projects included', () => {
  assert.deepEqual(resolveQuoteLink(MINE, { request: R, quote: Q }), { inquiryId: R, quoteId: Q });
  assert.deepEqual(resolveQuoteLink(MINE, { request: '0f8e1c2a-3333-4a00-9a00-000000000003', quote: '0f8e1c2a-4444-4a00-9a00-000000000004' }),
    { inquiryId: '0f8e1c2a-3333-4a00-9a00-000000000003', quoteId: '0f8e1c2a-4444-4a00-9a00-000000000004' });
  assert.deepEqual(resolveQuoteLink(MINE, { request: R, quote: '' }), { inquiryId: R, quoteId: '' });
});

test('a foreign or mismatched id resolves to nothing', () => {
  const other = '0f8e1c2a-9999-4a00-9a00-000000000009';
  assert.equal(resolveQuoteLink(MINE, { request: other, quote: Q }), null);          // someone else's request
  assert.equal(resolveQuoteLink(MINE, { request: R, quote: other }), null);          // not a quote on this request
  assert.equal(resolveQuoteLink(MINE, { request: '0f8e1c2a-3333-4a00-9a00-000000000003', quote: Q }), null); // quote of a different request
  assert.equal(resolveQuoteLink(MINE, { request: '', quote: '' }), null);
  assert.equal(resolveQuoteLink(null, { request: R, quote: Q }), null);
});
