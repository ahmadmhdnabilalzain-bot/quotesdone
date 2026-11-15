// The judges of the invitation link probe, offline (15 Nov 2026, customer_support; founder ledger 1692). Each case fails if a
// judge weakens so far that a broken preview card, a redirect to the wrong page or an oversized card picture would pass.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { entryChecks, headFacts, imageSize, judgeCard, judgeOgImage, judgeRedirect, JOIN_PATH, OG_IMAGE_MAX_BYTES } from './invitation_link_probe.mjs';

// The head of /portal?join=1 as production served it on 15 Nov 2026 (plain GET, WhatsApp user agent), shortened.
const PORTAL_HEAD = `<!DOCTYPE html><html data-dpl-id="x" lang="en" dir="ltr"><head><title>Supplier portal — QuotesDone</title>
<meta name="description" content="Quote on jobs from anywhere in the UAE, matched to your licence and trade."/>
<link rel="canonical" href="https://quotesdone.com/portal"/>
<meta property="og:title" content="Supplier portal — QuotesDone"/>
<meta property="og:description" content="Quote on jobs from anywhere in the UAE, matched to your licence and trade."/>
<meta property="og:url" content="https://quotesdone.com/portal"/>
<meta property="og:image" content="https://quotesdone.com/en/opengraph-image"/>
<meta name="twitter:card" content="summary_large_image"/></head>`;

test('a full card passes; each missing or broken part is named', () => {
  const f = headFacts(PORTAL_HEAD);
  assert.equal(f.metas['og:title'], 'Supplier portal — QuotesDone');
  assert.equal(f.canonical, 'https://quotesdone.com/portal');
  assert.deepEqual(judgeCard(f), []);
  for (const k of ['og:title', 'og:description', 'og:image', 'og:url', 'twitter:card']) {
    const bad = judgeCard(headFacts(PORTAL_HEAD.replace(new RegExp(`<meta [^>]*"${k}"[^>]*>`), '')));
    assert.ok(bad.includes(`no ${k}`), k);
  }
  assert.match(judgeCard(headFacts(PORTAL_HEAD.replace('https://quotesdone.com/en/opengraph-image', '/en/opengraph-image'))).join(), /absolute https/);
  assert.match(judgeCard(headFacts(PORTAL_HEAD.replace('Supplier portal — QuotesDone"/>\n<meta property="og:desc', 'undefined — QuotesDone"/>\n<meta property="og:desc'))).join(), /template artefact/);
  assert.match(judgeCard(headFacts(PORTAL_HEAD), { lang: 'ar' }).join(), /html lang is "en", expected "ar"/);
  assert.match(judgeCard(headFacts(PORTAL_HEAD.replace('lang="en" dir="ltr"', 'lang="ar" dir="ltr"')), { lang: 'ar' }).join(), /rtl/);
});

test('a redirect passes only as one permanent hop to the exact page, a relative Location read as a browser reads it', () => {
  const want = 'https://quotesdone.com' + JOIN_PATH;
  assert.deepEqual(judgeRedirect({ status: 308, location: want }, want), []);
  assert.deepEqual(judgeRedirect({ status: 308, location: JOIN_PATH }, want, 'https://quotesdone.com/portal/?join=1'), []);
  assert.equal(judgeRedirect({ status: 302, location: want }, want).length, 1, 'a temporary redirect is not what a forwarded link should get');
  assert.equal(judgeRedirect({ status: 308, location: 'https://quotesdone.com/portal' }, want).length, 1, '?join=1 lost: the page opens on "Sign in"');
  assert.equal(judgeRedirect({ status: 308, location: JOIN_PATH }, want, 'https://quotesdone.ae/portal/?join=1').length, 1, 'another host');
  assert.equal(judgeRedirect({ status: 200 }, want).length, 1);
});

test('the card picture passes only small, PNG or JPEG, of the card shape', () => {
  assert.deepEqual(judgeOgImage({ status: 200, contentType: 'image/png', bytes: 128945, width: 1200, height: 630 }), []);
  assert.equal(judgeOgImage({ status: 200, contentType: 'image/png', bytes: OG_IMAGE_MAX_BYTES + 1, width: 1200, height: 630 }).length, 1);
  assert.equal(judgeOgImage({ status: 200, contentType: 'image/webp', bytes: 1000, width: 1200, height: 630 }).length, 1);
  assert.equal(judgeOgImage({ status: 200, contentType: 'image/png', bytes: 1000, width: 1000, height: 1000 }).length, 1);
  assert.equal(judgeOgImage({ status: 404, contentType: 'text/html', bytes: 0 }).length, 3);
});

test('imageSize reads a PNG header and a JPEG frame header', () => {
  const png = Buffer.alloc(32); png.writeUInt32BE(0x89504e47, 0); png.writeUInt32BE(1200, 16); png.writeUInt32BE(630, 20);
  assert.deepEqual(imageSize(png), { width: 1200, height: 630 });
  const jpg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x02, 0x76, 0x04, 0xb0, 0x03, 0, 0, 0]);
  assert.deepEqual(imageSize(jpg), { width: 1200, height: 630 });
  assert.equal(imageSize(Buffer.from('not an image')), null);
});

test('the list holds every way the link reaches a person: both domains, http, www, a trailing slash, the supplier page, Arabic', () => {
  const ids = entryChecks().map((c) => c.id);
  for (const h of ['quotesdone.com', 'quotesdone.ae']) for (const k of ['card', 'http', 'www', 'slash', 'supplier']) assert.ok(ids.includes(`${k}:${h}`), `${k}:${h}`);
  assert.ok(ids.includes('supplier_ar') && ids.includes('portal_ar'));
  for (const c of entryChecks()) if (c.kind === 'redirect') assert.ok(c.want.endsWith(JOIN_PATH), `${c.id} must keep ?join=1, or the page opens on "Sign in"`);
});
