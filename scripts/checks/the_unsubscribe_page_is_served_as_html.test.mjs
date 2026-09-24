// The unsubscribe link in supplier mail opens a page a person can read and press (24 Sep 2026, marketing).
//   node --test scripts/checks/the_unsubscribe_page_is_served_as_html.test.mjs
// Measured 24 Sep 2026: https://quotesdone.com/u/unsubscribe answered Content-Type text/plain with nosniff
// (Supabase forces it on edge functions), so the browser printed the page's HTML source. The route handler
// src/app/u/unsubscribe/route.ts re-serves it as HTML. This reads PRODUCTION: it stays red until deployed.
// A bad token is used on purpose, so the check can never unsubscribe anybody (GET never suppresses anyway).
import test from 'node:test';
import assert from 'node:assert/strict';

const SITE = process.env.QD_SITE || 'https://quotesdone.com';

test('the unsubscribe page is HTML, not its own source code', async () => {
  const r = await fetch(`${SITE}/u/unsubscribe?e=zz-demo%40example.invalid&t=check-only`, { redirect: 'follow' });
  assert.match(r.headers.get('content-type') || '', /^text\/html/, 'served as text/plain: the supplier sees raw HTML');
  assert.match(await r.text(), /<title>/);
});
