// Blog HTML is sanitised when it is published (it_engineer, 19 Oct 2026). See scripts/lib/sanitize_blog_html.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sanitizeBlogHtml as S } from '../lib/sanitize_blog_html.mjs';

test('the article structure we publish survives unchanged', () => {
  const ok = '<h2>Costs</h2><p>A <strong>villa</strong> in <em>Dubai</em>.</p><ul><li>one</li></ul>'
    + '<table><thead><tr><th>a</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table><p>x<br>y</p>';
  assert.equal(S(ok), ok);
  assert.equal(S('<a href="/en/services">s</a>'), '<a href="/en/services">s</a>');
  assert.equal(S('<a href="https://dm.gov.ae/x?a=1&amp;b=2">d</a>'), '<a href="https://dm.gov.ae/x?a=1&amp;b=2" rel="noopener noreferrer">d</a>');
});

test('script, handlers and dangerous containers never survive', () => {
  for (const bad of [
    '<script>alert(1)</script>', '<SCRIPT src=//x></SCRIPT>', '<script>never closed',
    '<img src=x onerror=alert(1)>', '<svg onload=alert(1)><circle/></svg>', '<iframe src="//evil"></iframe>',
    '<style>*{}</style>', '<p onclick="alert(1)">t</p>', '<p style="background:url(javascript:alert(1))">t</p>',
    '<a href="javascript:alert(1)">x</a>', '<a href="&#106;avascript:alert(1)">x</a>', '<a href=" java\tscript:alert(1)">x</a>',
    '<a href="data:text/html,<script>alert(1)</script>">x</a>', '<a href="//evil.example">x</a>',
    '<!-- <script>alert(1)</script> -->', '<a title="x" href="#a" onmouseover="alert(1)">x</a>', '<<script>script>alert(1)<</script>/script>',
  ]) {
    const out = S(bad);
    assert.doesNotMatch(out, /<script|<svg|<iframe|<style|<img|\son\w+=|javascript:|data:text|href="\/\//i, `${bad} -> ${out}`);
  }
  assert.equal(S('<p onclick="alert(1)" class="x">t</p>'), '<p>t</p>');
  assert.equal(S('a < b'), 'a &lt; b');
});

test('the bake runs every released body through the sanitiser', () => {
  const src = readFileSync(new URL('../marketing/business_development.mjs', import.meta.url), 'utf8');
  assert.match(src, /body_html: sanitizeBlogHtml\(r\.body_html_en\)/);
  assert.match(src, /body_html: sanitizeBlogHtml\(r\.body_html_ar\)/);
});
