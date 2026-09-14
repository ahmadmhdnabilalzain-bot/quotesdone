// documentLocale.test.mjs — every Arabic page renders right-to-left, and only one place decides it.
// node --test src/lib/documentLocale.test.mjs
// Measured 14 Sep 2026 (e2e journey a): the Arabic customer portal rendered dir=ltr. Review of #651:
// an Arabic-registered customer on /me painted ltr, then flipped; the supplier portal did not apply
// its registered language the way the customer portal did.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { urlLocale, applyDocumentLocale, localisedPath, adoptLocale, LOCALE_COOKIE } from './documentLocale.ts';

const SRC = join(import.meta.dirname, '..');
const ROOT = join(SRC, '..');
const read = (p) => readFileSync(p, 'utf8');

test('the URL names the language: /ar and /ar/... are Arabic, nothing else is', () => {
  for (const p of ['/ar', '/ar/', '/ar/me', '/ar/portal', '/ar/services/aluminium']) assert.equal(urlLocale(p), 'ar', p);
  for (const p of ['/', '/me', '/portal', '/arabic-guide', '/area', '', null, undefined]) assert.equal(urlLocale(p), 'en', String(p));
});

test('an Arabic document is rtl with lang ar; an English one is ltr with lang en', () => {
  const doc = { documentElement: { lang: '', dir: '' } };
  applyDocumentLocale('ar', doc); assert.deepEqual(doc.documentElement, { lang: 'ar', dir: 'rtl' });
  applyDocumentLocale('en', doc); assert.deepEqual(doc.documentElement, { lang: 'en', dir: 'ltr' });
});

test('the same page in the other language', () => {
  assert.equal(localisedPath('/me', 'ar'), '/ar/me');
  assert.equal(localisedPath('/ar/me', 'en'), '/me');
  assert.equal(localisedPath('/ar/me', 'ar'), '/ar/me');
  assert.equal(localisedPath('/', 'ar'), '/ar');
  assert.equal(localisedPath('/ar', 'en'), '/');
  assert.equal(localisedPath('/area', 'ar'), '/ar/area');
});

function fakeWin(pathname, cookie = '') {
  const w = { document: { cookie }, location: { pathname, search: '?request=1', hash: '' }, replaced: [],
    history: { state: null, replaceState(_s, _t, u) { w.replaced.push(u); w.location.pathname = u.split('?')[0]; } } };
  return w;
}

test('adopting the registered language: cookie for the next first paint, URL moved without a reload, state set', () => {
  const w = fakeWin('/me', `${LOCALE_COOKIE}=en`); const set = [];
  adoptLocale('ar', (l) => set.push(l), w);
  assert.match(w.document.cookie, /^NEXT_LOCALE=ar;path=\/;/);
  assert.deepEqual(w.replaced, ['/ar/me?request=1']);
  assert.deepEqual(set, ['ar']);
});

test('a stale cookie is reconciled to the registered value, and a matching URL is left alone', () => {
  const w = fakeWin('/me', `${LOCALE_COOKIE}=ar`); const set = [];
  adoptLocale('en', (l) => set.push(l), w);
  assert.match(w.document.cookie, /^NEXT_LOCALE=en;/);
  assert.deepEqual(w.replaced, []);
  assert.deepEqual(set, ['en']);
});

test('anything that is not en or ar is ignored', () => {
  const w = fakeWin('/me'); const set = [];
  for (const v of [undefined, null, '', 'fr', 'AR']) adoptLocale(v, (l) => set.push(l), w);
  assert.deepEqual(set, []); assert.equal(w.document.cookie, '');
});

// Every page lives under src/app/[locale], whose layout renders <html dir> from the locale; the
// client may change the root element only through applyDocumentLocale. A second writer is what
// turned the Arabic portal ltr.
const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const all = walk(SRC);
const code = all.filter((f) => /\.(tsx?|jsx?|mjs)$/.test(f) && !/\.test\./.test(f) && !f.endsWith(join('lib', 'documentLocale.ts')));

// Every way to write the root element's direction or language that a file could use.
const WRITERS = [
  /documentElement\s*\.\s*(dir|lang)\s*=(?!=)/,                                   // .dir = / .lang =
  /documentElement\s*\[\s*['"`](dir|lang)['"`]\s*\]\s*=(?!=)/,                     // ['dir'] =
  /Object\.assign\(\s*document\.documentElement\b/,                               // Object.assign(document.documentElement, ...)
  /documentElement\s*\.\s*setAttribute\(\s*['"`](dir|lang)['"`]/,                  // setAttribute('dir' | "lang" | `dir`)
  /documentElement\s*\.\s*(toggleAttribute|removeAttribute)\(\s*['"`](dir|lang)['"`]/,
];

test('the [locale] layout renders <html dir> from the locale', () => {
  assert.match(read(join(SRC, 'app', '[locale]', 'layout.tsx')), /<html lang=\{locale\} dir=\{lang === 'ar' \? 'rtl' : 'ltr'\}>/);
});

test('the detector catches every form of a second writer', () => {
  for (const s of ["document.documentElement.dir = 'ltr'", 'document.documentElement["lang"] = x', "document.documentElement[`dir`]='rtl'",
                   'Object.assign(document.documentElement, { dir: "ltr" })', "document.documentElement.setAttribute('dir', 'ltr')",
                   'document.documentElement.setAttribute("lang","en")', 'document.documentElement.removeAttribute(`dir`)'])
    assert.ok(WRITERS.some((re) => re.test(s)), 'missed: ' + s);
  assert.ok(!WRITERS.some((re) => re.test("const rtl = document.documentElement.dir === 'rtl';")), 'a read is not a write');
});

test("nothing but applyDocumentLocale writes the root element's dir or lang", () => {
  const writers = code.filter((f) => WRITERS.some((re) => re.test(read(f)))).map((f) => relative(SRC, f));
  assert.deepEqual(writers, []);
});

// A CSS rule that sets `direction` on the root or body overrides <html dir> for the whole page.
// Returns the offending selectors. `flex-direction` / `animation-direction` are not `direction`, and a
// rule aimed at a descendant ([dir="rtl"] .x, body .x) only styles that element.
function rootDirectionRules(cssText) {
  const out = [];
  for (const m of String(cssText).matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!/(^|[;{\s])direction\s*:/.test(m[2])) continue;
    for (const sel of m[1].split(',').map((s) => s.trim())) {
      if (/^(html|body|:root)(\[[^\]]*\]|:[a-z-]+(\([^)]*\))?)*$/i.test(sel)) out.push(sel);
    }
  }
  return out;
}

test('the stylesheet detector catches direction on html, body and :root, and nothing else', () => {
  assert.deepEqual(rootDirectionRules('html{direction:ltr}'), ['html']);
  assert.deepEqual(rootDirectionRules('.a, body { color: red; direction: rtl }'), ['body']);
  assert.deepEqual(rootDirectionRules(':root[dir="rtl"]{direction:ltr}'), [':root[dir="rtl"]']);
  assert.deepEqual(rootDirectionRules('html:lang(ar) { direction: ltr; }'), ['html:lang(ar)']);
  assert.deepEqual(rootDirectionRules('.mk .bpost{display:flex;flex-direction:column}'), []);
  assert.deepEqual(rootDirectionRules('[dir="rtl"] :is(.ltr,.tabular){direction:ltr;unicode-bidi:isolate}'), []);
  assert.deepEqual(rootDirectionRules('body .x{direction:ltr}'), []);
  assert.deepEqual(rootDirectionRules('[dir="rtl"] .beam::after{animation-direction:reverse}'), []);
});

test('no stylesheet sets a direction on html, body or :root', () => {
  const bad = all.filter((f) => f.endsWith('.css')).flatMap((f) => rootDirectionRules(read(f)).map((s) => relative(SRC, f) + ': ' + s));
  assert.deepEqual(bad, []);
});

test('both portals start from the URL, adopt the registered language, and write <html> through the one helper', () => {
  for (const f of ['components/me/CustomerPortal.tsx', 'components/portal/SupplierPortal.tsx']) {
    const s = read(join(SRC, f));
    assert.match(s, /urlLocale\(window\.location\.pathname\)/, f + ' must start from the URL');
    assert.match(s, /applyDocumentLocale\(lang\)/, f + ' must write the root element through applyDocumentLocale');
    assert.match(s, /onAuth\(j\.access_token, j\.refresh_token, j\.locale\)/, f + ' must take the account language at sign-in');
    assert.match(s, /const onAuth = \(access, refresh, locale\) => \{ (onServedLocale\(locale\)|adoptLocale\(locale, setLang\));/, f + ' must adopt it before the first paint');
  }
  const sup = read(join(SRC, 'components/portal/SupplierPortal.tsx'));
  assert.match(sup, /if \(l === 'ar' \|\| l === 'en'\) adoptLocale\(l, setLang\);/, 'SupplierPortal must apply leads.locale after sign-in like the customer portal');
  assert.doesNotMatch(sup, /switchLang\(/, 'the reloading switchLang must be gone');
  assert.match(sup, /action: 'save_settings', locale: l/, 'switching while signed in must save leads.locale');
  assert.match(read(join(SRC, 'components/me/CustomerPortal.tsx')), /const onServedLocale = [^\n]*\n[^\n]*\n[^\n]*\n\s*adoptLocale\(l, setLangState\);/, 'CustomerPortal must adopt the served locale');
});

test('sign-in returns the account language (login_otp, both verify paths)', () => {
  const s = read(join(ROOT, 'supabase', 'functions', 'login_otp', 'index.ts'));
  assert.equal((s.match(/return J\(\{ ok: true, \.\.\.s, user_kind: kind, email, locale: await registeredLocale\(admin, \{ role: kind, email \}, body\.lang\) \}\);/g) || []).length, 2);
});

test('each language switch carries the note, in both languages', () => {
  const text = read(join(SRC, 'components/me/portalText.ts'));
  assert.equal((text.match(/lang_note:/g) || []).length, 2);
  assert.match(read(join(SRC, 'components/me/PortalShell.tsx')), /title=\{t\('lang_note'\)\}/);
  assert.match(read(join(SRC, 'components/me/PortalShell.tsx')), /\{t\('lang_note'\)\}<\/p>/);
  assert.match(read(join(SRC, 'components/me/CustomerPortal.tsx')), /\{t\(lang, 'lang_note'\)\}/);
  const ss = read(join(SRC, 'components/portal/supplier/SupplierSettings.tsx'));
  assert.equal((ss.match(/langNote:/g) || []).length, 2); assert.match(ss, /t\(lang, 'langNote'\)/);
  assert.match(read(join(SRC, 'components/portal/SupplierPortal.tsx')), /title=\{token \? LANG_NOTE\[/);
});
