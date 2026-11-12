// NO BOX IN THE SUPPLIER PORTAL MAKES AN IPHONE ZOOM (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, S6;
// founder ruling 1645: "a text box that is small"). Safari on an iPhone zooms the page into any input, select or textarea whose text
// is under 16 px when it is focused, and the page stays zoomed. The walk measured the quotation-chat reply at 14 px, the quote form's
// VAT and template boxes at 13 px and 36 px tall, the "available again" date at 14 px, and found the customer-message reply the same
// way in code. ui/input.tsx already sets 16 px under `pointer: coarse` (the registration form's H3 fix); the raw boxes did not.
// This reads every .tsx of the supplier portal (src/components/portal/supplier/**, and the shared portal files beside it) and fails
// for any text box whose classes, with the shared style names resolved, do not give it 16 px or more on a touch screen.
//   node --test scripts/checks/no_box_in_the_supplier_portal_makes_an_iphone_zoom.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const files = [];
const walk = (d, deep) => { for (const e of fs.readdirSync(path.join(ROOT, d), { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) { if (deep) walk(p, deep); } else if (e.name.endsWith('.tsx') && !e.name.includes('.test.')) files.push(p); } };
walk('src/components/portal/supplier', true);
walk('src/components/portal', false);

// The shared style names a box may use: core/styles.ts `S.<name>: '...'`.
const styles = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/core/styles.ts'), 'utf8');
const S = Object.fromEntries([...styles.matchAll(/^\s*(\w+):\s*'([^']*)'/gm)].map((m) => [m[1], m[2]]));

// Comments are blanked (kept as spaces and newlines, so line numbers hold): a check that greps source would match a comment.
const blank = (c) => c.replace(/[^\n]/g, ' ');
// Only comments as this codebase writes them: a line that starts with //, a {/* ... */} in JSX, a /* ... */ that opens a line. A
// pattern inside a string ('image/*', 'https://') is left alone.
const uncomment = (src) => src.replace(/\{\/\*[\s\S]*?\*\/\}/g, blank).replace(/^([ \t]*)\/\*[\s\S]*?\*\//gm, blank).replace(/^[ \t]*\/\/[^\n]*/gm, blank);

/** Each <input|select|textarea|Input ...> opening tag, read to its closing '>' outside braces and quotes. */
function* tags(raw) {
  const src = uncomment(raw);
  const re = /<(input|select|textarea|Input)\b/g; let m;
  while ((m = re.exec(src))) {
    let i = re.lastIndex, depth = 0, q = '';
    for (; i < src.length; i++) {
      const c = src[i];
      if (q) { if (c === q && src[i - 1] !== '\\') q = ''; continue; }
      if (c === '"' || c === "'" || c === '`') { q = c; continue; }
      if (c === '{') depth++; else if (c === '}') depth--; else if (c === '>' && depth === 0) break;
    }
    yield { tag: m[1], attrs: src.slice(re.lastIndex, i), at: m.index };
  }
}

const SIXTEEN = /(^|[\s'"`:])text-(base|lg|xl|\[(1[6-9]|[2-9]\d)(\.\d+)?px\])(?=[\s'"`]|$)/;
const SMALL_ON_TOUCH = /pointer-coarse:text-(sm|xs|\[(\d|1[0-5])(\.\d+)?px\])/;

test('every text box in the supplier portal is 16 px or more on a touch screen', () => {
  const bad = [];
  for (const f of files) {
    const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
    // a file's own `const name = '...classes...'` is resolved where a box uses it by name
    const local = Object.fromEntries([...src.matchAll(/const (\w+) = '([^']*)'/g)].map((m) => [m[1], m[2]]));
    for (const { tag, attrs, at } of tags(src)) {
      if (/\btype=["'{]?["']?(checkbox|radio|file|hidden|range|submit|button|color)\b/.test(attrs)) continue;
      const cm = /className=(?:"([^"]*)"|\{([\s\S]*?)\}(?=\s+[\w-]+=|\s*\/?$))/.exec(attrs);
      // a literal class string is read as written; in an expression, S.<name> and a local const are resolved outside the quotes only
      const cls = !cm ? '' : cm[1] !== undefined ? cm[1]
        : cm[2].split(/('[^']*'|"[^"]*"|`[^`]*`)/).map((part, i) => (i % 2 ? part
          : part.replace(/\bS\.(\w+)/g, (_, k) => ` '${S[k] ?? ''}' `).replace(/\b([a-z]\w*)\b/g, (w) => (local[w] !== undefined ? ` '${local[w]}' ` : w)))).join('');
      const line = src.slice(0, at).split('\n').length;
      const ok = tag === 'Input' ? !SMALL_ON_TOUCH.test(cls) : (SIXTEEN.test(cls) && !SMALL_ON_TOUCH.test(cls));
      if (!ok) bad.push(`${f}:${line} <${tag}>`);
    }
  }
  assert.deepEqual(bad, [], 'boxes under 16 px on a touch screen (iPhone Safari zooms into them):\n  ' + bad.join('\n  '));
});

test('the check reads the boxes it is meant to read', () => {
  // a check that finds nothing proves nothing: the walk's own boxes are among those it reads
  const read = files.flatMap((f) => [...tags(fs.readFileSync(path.join(ROOT, f), 'utf8'))].map((t) => f));
  for (const f of ['QuoteReviewChat.tsx', 'SupplierMailbox.tsx', 'core/QuoteForm.tsx', 'QuoteTemplateBar.tsx', 'SupplierAvailability.tsx']) {
    assert.ok(read.some((r) => r.endsWith(f)), 'no box read in ' + f);
  }
  assert.ok(read.length >= 40, 'only ' + read.length + ' boxes read');
});
