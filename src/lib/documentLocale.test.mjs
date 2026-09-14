// documentLocale.test.mjs — every Arabic page renders right-to-left, and only one place decides it.
// node --test src/lib/documentLocale.test.mjs
// Measured 14 Sep 2026 (e2e journey a): the Arabic customer portal rendered dir=ltr.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { urlLocale, applyDocumentLocale } from './documentLocale.ts';

const SRC = join(import.meta.dirname, '..');

test('the URL names the language: /ar and /ar/... are Arabic, nothing else is', () => {
  for (const p of ['/ar', '/ar/', '/ar/me', '/ar/portal', '/ar/services/aluminium']) assert.equal(urlLocale(p), 'ar', p);
  for (const p of ['/', '/me', '/portal', '/arabic-guide', '/area', '', null, undefined]) assert.equal(urlLocale(p), 'en', String(p));
});

test('an Arabic document is rtl with lang ar; an English one is ltr with lang en', () => {
  const doc = { documentElement: { lang: '', dir: '' } };
  applyDocumentLocale('ar', doc); assert.deepEqual(doc.documentElement, { lang: 'ar', dir: 'rtl' });
  applyDocumentLocale('en', doc); assert.deepEqual(doc.documentElement, { lang: 'en', dir: 'ltr' });
});

// Every page lives under src/app/[locale], whose layout renders <html dir> from the locale; the
// client may change the root element only through applyDocumentLocale. A second writer is what
// turned the Arabic portal ltr.
const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const files = walk(SRC).filter((f) => /\.(tsx?|jsx?)$/.test(f) && !/\.test\./.test(f));

test('the [locale] layout renders <html dir> from the locale', () => {
  const layout = readFileSync(join(SRC, 'app', '[locale]', 'layout.tsx'), 'utf8');
  assert.match(layout, /<html lang=\{locale\} dir=\{lang === 'ar' \? 'rtl' : 'ltr'\}>/);
});

test('nothing but applyDocumentLocale writes the root element\'s dir or lang', () => {
  const writers = files.filter((f) => !f.endsWith(join('lib', 'documentLocale.ts')))
    .filter((f) => /documentElement\.(dir|lang)\s*=(?!=)|documentElement\.setAttribute\(\s*['"](dir|lang)['"]/.test(readFileSync(f, 'utf8')))
    .map((f) => relative(SRC, f));
  assert.deepEqual(writers, []);
});

test('both portals take their first language from the URL and apply it through the one helper', () => {
  for (const f of ['components/me/CustomerPortal.tsx', 'components/portal/SupplierPortal.tsx']) {
    const s = readFileSync(join(SRC, f), 'utf8');
    assert.match(s, /urlLocale\(window\.location\.pathname\)/, f + ' must start from the URL');
    assert.match(s, /applyDocumentLocale\(lang\)/, f + ' must write the root element through applyDocumentLocale');
  }
});
