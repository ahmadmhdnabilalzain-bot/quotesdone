// /m/brand/* on quotesdone.com proxies the public `brand` storage bucket so our mail can name our own domain
// (next.config.mjs rewrites()). Security checklist audit, 10 Nov 2026: with `:path*` a `..` segment reached the
// upstream URL, and https://quotesdone.com/m/brand/../site/admin/index.html served the stale admin page from another
// bucket (measured 200). This compiles the live rewrite with Next's own matcher and asserts that the brand files the
// mail uses still resolve, and that no dot segment can.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { getPathMatch } = require('next/dist/shared/lib/router/utils/path-match');
const { prepareDestination } = require('next/dist/shared/lib/router/utils/prepare-destination');
const config = (await import('../../next.config.mjs')).default;

const rewrites = await config.rewrites();
const list = Array.isArray(rewrites) ? rewrites : [...(rewrites.beforeFiles || []), ...(rewrites.afterFiles || []), ...(rewrites.fallback || [])];
const brand = list.filter((r) => r.source.startsWith('/m/brand/'));

const resolve = (path) => {
  for (const r of brand) {
    const params = getPathMatch(r.source, { removeUnnamedParams: true, strict: true })(path);
    if (params) return prepareDestination({ appendParamsToQuery: false, destination: r.destination, params, query: {} }).newUrl;
  }
  return null;
};

test('there is exactly one brand proxy, and it points at the brand bucket', () => {
  assert.equal(brand.length, 1);
  assert.match(brand[0].destination, /\/storage\/v1\/object\/public\/brand\/:path$/);
});

test('the brand files our mail names still resolve to the brand bucket', () => {
  assert.equal(resolve('/m/brand/icon_192.png'), '/storage/v1/object/public/brand/icon_192.png');
  assert.equal(resolve('/m/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png'),
    '/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png');
});

test('no dot segment, empty name or hidden file is proxied', () => {
  for (const p of ['/m/brand/../site/admin/index.html', '/m/brand/a/../../site/os/app.html', '/m/brand/./x.png',
    '/m/brand/..', '/m/brand/', '/m/brand/.env', '/m/brand/a//b.png']) assert.equal(resolve(p), null, p);
});
