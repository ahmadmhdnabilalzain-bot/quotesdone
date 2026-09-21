// LTR IS NEVER FORCED ONTO A LOCALISED DATE, AND THERE IS ONLY ONE `Ltr`.
//
// THE DEFECT THIS GUARDS (production journey, 17 Sep 2026). `const Ltr = ({children}) =>
// <bdi dir="ltr">{children}</bdi>` was copy-pasted into FIVE files, and seven call sites in
// SupplierPortal.tsx handed it `fmtDate(d, 'ar')` — which returns Arabic, "18 سبتمبر 2026". Forced
// into an LTR paragraph the bidi algorithm reorders it, so the licence chip read
// "سبتمبر 2027 18" while the same date unwrapped a few pixels below read correctly.
//
// TWO ASSERTIONS, because the defect had two halves:
//   1. ONE `Ltr`. A second local copy is how the rule in src/lib/Ltr.tsx stops reaching a file.
//   2. NO date formatter inside a hard `dir="ltr"`. `Ltr` now decides per string, so the way to
//      reintroduce the bug is to hand-write `<bdi dir="ltr">` around a date again.
//
// COMMENTS ARE STRIPPED BEFORE MATCHING. A check that greps source matches its own prose, and this
// file and src/lib/Ltr.tsx both have to SAY `<bdi dir="ltr">` to explain what they forbid.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SRC = new URL('../../src/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const HELPER = 'lib/Ltr.tsx';

const walk = (dir) => readdirSync(dir).flatMap((n) => {
  const p = join(dir, n);
  return statSync(p).isDirectory() ? walk(p) : (/\.(tsx|ts)$/.test(n) ? [p] : []);
});

// Comments are MASKED, not deleted: every comment character becomes a space and every newline is
// kept, so the text stays byte-for-byte the same length and a reported line number is the line the
// reader will actually find. Deleting them shifted the numbers by four and sent the first run of
// this check at four innocent lines. (The masking matters at all because this file and
// src/lib/Ltr.tsx both have to SAY `<bdi dir="ltr">` in prose to explain what they forbid.)
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));

const files = walk(SRC).map((p) => ({ rel: p.slice(SRC.length).replace(/\\/g, '/'), text: code(readFileSync(p, 'utf8')) }));

test('there is exactly one Ltr, and it is src/lib/Ltr.tsx', () => {
  assert.ok(files.length > 50, `walked only ${files.length} source files — the walk is wrong, not the code`);
  const defs = files.filter((f) => /(?:const|function)\s+Ltr\b/.test(f.text)).map((f) => f.rel);
  assert.deepEqual(defs, [HELPER], `Ltr is defined in ${defs.length} file(s): ${defs.join(', ')}. `
    + 'It was duplicated across five files on 17 Sep 2026 and the same bidi defect existed in all of them. '
    + `Import it from '@/lib/Ltr' instead.`);
});

test('CSS does not override the dir attribute on .ltr/.tabular', () => {
  // A CSS `direction` BEATS the dir attribute, so `[dir="rtl"] :is(.ltr,.tabular){direction:ltr}`
  // silently defeated <Ltr> on every date carrying className="tabular" — measured 17 Sep 2026 on
  // the public footer: dir="auto" but getComputedStyle().direction === "ltr", date still backwards.
  // `:not([dir])` hands an element that states its own direction back to its attribute.
  const css = readFileSync(join(SRC, 'app', 'globals.css'), 'utf8');
  const rules = css.match(/^\[dir="rtl"\][^{\n]*\{[^}]*direction:\s*ltr[^}]*\}/gm) || [];
  assert.ok(rules.length > 0, 'the RTL direction-force rule vanished from globals.css — this check has lost its subject');
  for (const r of rules) {
    assert.match(r, /:not\(\[dir\]\)/, `${r.trim()} forces direction:ltr regardless of the element's own dir attribute, `
      + 'which overrides <Ltr> and renders Arabic dates backwards. Add :not([dir]).');
  }
});

test('no date formatter is wrapped in a hard dir="ltr"', () => {
  const DATE = /fmtDate\s*\(|toLocaleDateString\s*\(|\bdate\s*\(\s*[a-z]/i;
  const bad = [];
  for (const f of files) {
    if (f.rel === HELPER) continue;
    for (const [i, line] of f.text.split('\n').entries()) {
      // Only the span between a `dir="ltr"` and the end of that element on the same line: a date
      // elsewhere on a long JSX line is not inside it.
      for (const m of line.matchAll(/dir\s*=\s*["']ltr["']([^<]*)/g)) {
        if (DATE.test(m[1])) bad.push(`${f.rel}:${i + 1}`);
      }
    }
  }
  assert.deepEqual(bad, [], 'A localised date forced to dir="ltr" renders backwards in Arabic '
    + `("سبتمبر 2027 18" instead of "18 سبتمبر 2026"). Use <Ltr> from '@/lib/Ltr', which forces LTR `
    + `only for genuinely LTR strings. Offending sites: ${bad.join(', ')}`);
});
