// every_page_is_routed_and_every_sitemap_url_is_a_page.test.mjs
// node --test scripts/checks/every_page_is_routed_and_every_sitemap_url_is_a_page.test.mjs
//
// Measured 22 Sep 2026 (production walk, both hosts): /supplier-agreement/v10 and /v11 were in the
// sitemap and answered 404, while /ar/supplier-agreement/v10 answered 200. Every page lives under
// src/app/[locale]; an unprefixed URL reaches it only if src/middleware.ts's matcher lets next-intl
// rewrite it, and the matcher listed the bare /supplier-agreement only. This check walks every page
// file and every legal.json version the sitemap derives a URL from, and asks the matcher about each.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(import.meta.dirname, '..', '..');
const APP = join(ROOT, 'src', 'app', '[locale]');

const src = readFileSync(join(ROOT, 'src', 'middleware.ts'), 'utf8');
const block = src.slice(src.indexOf('matcher:'), src.indexOf(']', src.indexOf('matcher:')));
const patterns = [...block.replace(/\/\/.*$/gm, '').matchAll(/'([^']+)'/g)].map((m) => m[1]);
// Next's matcher syntax, as used here: literal paths, an (ar|en) group, and a trailing :path*.
const toRe = (p) => new RegExp('^' + p.replace(/\./g, '\\.').replace(/\/:path\*$/, '(?:/.*)?') + '$');
const matchers = patterns.map(toRe);
const routed = (path) => matchers.some((re) => re.test(path));

function pages(dir, rel = '') {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...pages(p, `${rel}/${name}`));
    else if (name === 'page.tsx') out.push(rel || '/');
  }
  return out;
}

test('the matcher was read', () => {
  assert.ok(patterns.length > 20, `read ${patterns.length} matcher entries`);
});

test('every page under [locale] is reachable with and without the /ar prefix', () => {
  const missing = [];
  for (const r of pages(APP)) {
    // A catch-all ([...rest], #1455) is the not-found page for every unknown path. It has no URL of its own to route,
    // so it is skipped here. Every named page is still checked.
    if (/\[\.\.\.[^\]]+\]/.test(r)) continue;
    const path = r.replace(/\[[^\]]+\]/g, 'x');
    for (const url of [path, path === '/' ? '/ar' : '/ar' + path]) if (!routed(url)) missing.push(url);
  }
  assert.deepEqual(missing, [], `pages the middleware never rewrites (they 404 on production): ${missing.join(', ')}`);
});

test('every legal.json version the sitemap lists is a page and is routed', () => {
  const legal = JSON.parse(readFileSync(join(ROOT, 'src', 'content', 'legal.json'), 'utf8'));
  for (const slug of Object.keys(legal)) {
    const path = '/' + slug.replace(/-(v\d+(?:\.\d+)?)$/, '/$1'); // the same rewrite src/app/sitemap.xml/route.ts applies
    assert.ok(existsSync(join(APP, ...path.split('/').filter(Boolean), 'page.tsx')), `${path} is in the sitemap but has no page`);
    assert.ok(routed(path), `${path} is in the sitemap but the middleware does not route it`);
  }
});
