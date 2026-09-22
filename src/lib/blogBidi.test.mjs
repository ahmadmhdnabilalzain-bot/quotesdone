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
// A <script>/<style> body is code, not visible text, and since 22 Sep 2026 the pass leaves it exactly
// as the author wrote it — a raw "F&B" inside a post's JSON-LD is correct JSON, not a stray reference.
// Both checks below are about what a READER sees, so the code blocks come out first.
const prose = (html) => html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
const textOf = (html) => decodeRefs(prose(html).replace(/<[^>]*>/g, ''));
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

test('a JSON-LD block inside a post survives the pass as parseable JSON', () => {
  const ld = '{"@type":"FAQPage","mainEntity":[{"name":"كم تكلفة AED 300?","text":"Movers & Packers"}]}';
  const out = isolateLatin(`<p>مرحبًا AED 300</p><script type="application/ld+json">${ld}</script>`);
  assert.deepEqual(JSON.parse(out.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1]), JSON.parse(ld));
  assert.match(out, /<p>مرحبًا <bdi>AED 300<\/bdi><\/p>/);
});

test('every JSON-LD block in every Arabic post still parses after the pass', () => {
  let n = 0;
  for (const [slug, p] of Object.entries(posts)) {
    if (!p.ar?.body_html) continue;
    for (const m of isolateLatin(p.ar.body_html).matchAll(/<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi)) {
      n++;
      assert.doesNotThrow(() => JSON.parse(m[1]), `${slug}: JSON-LD no longer parses: ${m[1].slice(0, 200)}`);
    }
  }
  console.log(`JSON-LD blocks checked in Arabic posts: ${n}`);
});

test('every Arabic post in blog.json renders with no reference left as text', () => {
  let n = 0;
  for (const [slug, p] of Object.entries(posts)) {
    if (!p.ar) continue;
    n++;
    for (const [field, v] of Object.entries({ body: p.ar.body_html, title: p.ar.title, excerpt: p.ar.excerpt })) {
      if (!v) continue;
      const out = field === 'body' ? isolateLatin(v) : bidiText(v);
      assert.ok(!STRAY.test(prose(out)), `${slug} ${field}: a stray ampersand survives: ${prose(out).match(/.{0,30}&(?!(amp|lt|gt);).{0,30}/)?.[0]}`);
      const txt = textOf(out);
      assert.ok(!WORDS.test(txt), `${slug} ${field}: a reference name is visible: ${txt.match(/.{0,30}(mdash|ndash|middot|ldquo|rdquo|lsquo|rsquo|rarr|nbsp|hellip|amp|quot).{0,30}/)?.[0]}`);
    }
  }
  assert.ok(n >= 20, `expected the Arabic posts, found ${n}`);
});
