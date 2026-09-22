// blogBidi.test.mjs — an Arabic blog post never shows a character reference as a word.
// node --test src/lib/blogBidi.test.mjs
// Measured 22 Sep 2026 on production: 24 /ar/blog posts read "mdash", "middot", "ldquo", "rdquo"
// in the text, because the Latin-run isolation wrapped the letters of a reference in <bdi>.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isolateLatin, bidiText, decodeRefs } from './blogBidi.ts';

const posts = JSON.parse(readFileSync(join(import.meta.dirname, '..', 'content', 'blog.json'), 'utf8'));
// After the pass the only ampersands left are the three it writes itself.
const STRAY = /&(?!(amp|lt|gt);)/;
const textOf = (html) => decodeRefs(html.replace(/<[^>]*>/g, ''));
const WORDS = /(^|[^A-Za-z])(mdash|ndash|middot|ldquo|rdquo|lsquo|rsquo|rarr|nbsp|hellip|amp|quot)(;|[^A-Za-z]|$)/;

test('the failing input: a dash reference between Arabic words stays a dash', () => {
  const out = isolateLatin('<p>التكييف &mdash; والصيانة AED 300&rdquo; ثم R&amp;D</p>');
  assert.equal(textOf(out), 'التكييف — والصيانة AED 300” ثم R&D');
  assert.ok(!STRAY.test(out), out);
  assert.match(out, /<bdi>AED 300<\/bdi>/);
});

test('titles are escaped once, not twice', () => {
  assert.equal(textOf(bidiText('Movers & Packers <3')), 'Movers & Packers <3');
});

test('every Arabic post in blog.json renders with no reference left as text', () => {
  let n = 0;
  for (const [slug, p] of Object.entries(posts)) {
    if (!p.ar) continue;
    n++;
    for (const [field, v] of Object.entries({ body: p.ar.body_html, title: p.ar.title, excerpt: p.ar.excerpt })) {
      if (!v) continue;
      const out = field === 'body' ? isolateLatin(v) : bidiText(v);
      assert.ok(!STRAY.test(out), `${slug} ${field}: a stray ampersand survives: ${out.match(/.{0,30}&(?!(amp|lt|gt);).{0,30}/)?.[0]}`);
      const txt = textOf(out);
      assert.ok(!WORDS.test(txt), `${slug} ${field}: a reference name is visible: ${txt.match(/.{0,30}(mdash|ndash|middot|ldquo|rdquo|lsquo|rsquo|rarr|nbsp|hellip|amp|quot).{0,30}/)?.[0]}`);
    }
  }
  assert.ok(n >= 20, `expected the Arabic posts, found ${n}`);
});
