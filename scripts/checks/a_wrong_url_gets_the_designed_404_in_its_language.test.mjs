// a_wrong_url_gets_the_designed_404_in_its_language.test.mjs
// node --test scripts/checks/a_wrong_url_gets_the_designed_404_in_its_language.test.mjs
//
// Measured 10 Nov 2026 on production (website audit, customer_support): /zz-nope and /about/zz served
// Next.js's bare white "404: This page could not be found." (no lang, no header, no way onward), while
// /ar/zz-nope and /services/zz-nope served src/app/[locale]/not-found.tsx. A path reaches that page only
// if src/middleware.ts lets next-intl rewrite it to /en/<path>; an unnamed top-level path was read as
// [locale]='zz-nope' instead and rejected by the layout. The matcher now ends with one catch-all.
//
// This compiles the matcher with Next's OWN compiler (getMiddlewareMatchers, the function `next build`
// uses), so it proves what the deployed middleware will match, not what a regex copied here would.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const ROOT = join(import.meta.dirname, '..', '..');
const require = createRequire(join(ROOT, 'package.json'));
const { getMiddlewareMatchers } = require('next/dist/build/analysis/get-page-static-info.js');

const src = readFileSync(join(ROOT, 'src', 'middleware.ts'), 'utf8');
const block = src.slice(src.indexOf('matcher:'), src.indexOf('\n  ]', src.indexOf('matcher:')));
// Each entry is one single-quoted string; the comments between them are dropped first. In the source a
// backslash is escaped ('\\.'), so it is unescaped here the way the TypeScript compiler reads it.
const patterns = [...block.replace(/\/\/.*$/gm, '').matchAll(/'([^']+)'/g)].map((m) => m[1].replace(/\\\\/g, '\\'));
const matchers = getMiddlewareMatchers(patterns, { basePath: '' }).map((m) => new RegExp(m.regexp));
const runs = (path) => matchers.some((re) => re.test(path));

test('the matcher was read and compiled by Next', () => {
  assert.ok(patterns.length > 20, `read ${patterns.length} matcher entries`);
  assert.equal(matchers.length, patterns.length);
});

test('an unknown path, at the top level or under a known page, reaches next-intl', () => {
  for (const p of ['/zz-nope', '/about/zz', '/contact/old-form', '/a/b/c', '/ar/zz-nope', '/services/zz-nope', '/u'])
    assert.ok(runs(p), `${p} would get the framework's bare 404, not the designed one`);
});

test('the pages that are not under [locale] are left alone', () => {
  for (const p of ['/api/health', '/api/resilience-ping', '/u/unsubscribe', '/u/followup', '/u/o/x', '/m/brand/logo',
    '/robots.txt', '/sitemap.xml', '/llms.txt', '/favicon.ico', '/icon.png', '/apple-icon.png', '/manifest.webmanifest',
    '/fonts/geist-latin.woff2', '/brand/pwa-512.png', '/_next/static/chunks/main.js', '/_vercel/insights/script.js'])
    assert.ok(!runs(p), `${p} would be rewritten by next-intl into /en${p}`);
});

test('the social cards are not redirected: og:image names /en/opengraph-image', () => {
  // next-intl (localePrefix as-needed) redirects /en/<x> to /<x>; next.config.mjs exempts the cards for the same reason.
  for (const p of ['/en/opengraph-image', '/ar/opengraph-image', '/en/twitter-image'])
    assert.ok(!runs(p), `${p} would be redirected away from the URL every page's og:image names`);
});

test('the designed page is what an unknown path renders', () => {
  const catchAll = readFileSync(join(ROOT, 'src', 'app', '[locale]', '[...rest]', 'page.tsx'), 'utf8');
  assert.match(catchAll, /notFound\(\)/);
  const nf = readFileSync(join(ROOT, 'src', 'app', '[locale]', 'not-found.tsx'), 'utf8');
  assert.match(nf, /<SiteHeader \/>/);
  assert.match(nf, /href="\/"/);
});
