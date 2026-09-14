// 14 SEP 2026 — website audit, ia_and_pages + arabic_rtl. The /blog index was baked HTML in
// marketing.json that had drifted from its own data file (two posts missing), and the 32 posts had
// no Arabic. The index is now rendered from src/content/blog.json by src/components/BlogIndex.tsx,
// and every post carries an "ar" branch. This check proves the properties that make that true:
//
//   1. no duplicate post keys in the raw file (JSON.parse silently keeps the last of two),
//   2. every key equals the post's own slug (shared titles are reported, not failed),
//   3. every post has an Arabic title, excerpt, meta description, category and body, in Arabic,
//   4. the Arabic keeps every number of the English (multiset of digit runs) and every structural
//      element (headings, paragraphs, list items, table rows and cells) — translate, never invent,
//   5. the /blog route renders BlogIndex, and BlogIndex reads blog.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');
const problems = [];
const raw = read('src/content/blog.json');
const data = JSON.parse(raw);

// 1. top-level keys straight from the text: a depth counter over the raw JSON.
const topKeys = [];
{
  let depth = 0, inStr = false, esc = false, start = -1;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (inStr) {
      if (esc) esc = false; else if (c === '\\') esc = true;
      else if (c === '"') { inStr = false; if (depth === 1 && /^\s*:/.test(raw.slice(i + 1, i + 4))) topKeys.push(raw.slice(start + 1, i)); }
    } else if (c === '"') { inStr = true; start = i; }
    else if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') depth--;
  }
}
const dup = topKeys.filter((k, i) => topKeys.indexOf(k) !== i);
if (dup.length) problems.push('duplicate post keys in blog.json: ' + [...new Set(dup)].join(', '));
if (topKeys.length !== Object.keys(data).length) problems.push(`raw scan found ${topKeys.length} keys, JSON.parse ${Object.keys(data).length}`);

const strip = (h) => (h || '').replace(/<[^>]*>/g, ' ');
const digits = (s) => (strip(s).match(/\d+(?:[.,]\d+)*/g) || []).sort().join('|');
const AR = /[؀-ۿ]/;
const titles = { en: new Set(), ar: new Set() };
for (const [key, p] of Object.entries(data)) {
  if (p.slug !== key) problems.push(`${key}: slug field is "${p.slug}"`);
  for (const [lang, t] of [['en', p.title], ['ar', p.ar?.title]]) {
    // measured 14 Sep 2026: cost-of-cctv-installation-uae and the later how-much CCTV guide are two
    // different articles under one English title — reported for the content owner, not failed.
    if (t && titles[lang].has(t)) console.warn(`report: ${key} shares its ${lang} title with an earlier post`);
    titles[lang].add(t);
  }
  if (!p.ar) { problems.push(`${key}: no Arabic branch`); continue; }
  for (const f of ['title', 'excerpt', 'meta_desc', 'category', 'body_html']) {
    if (p[f] && !AR.test(p.ar[f] || '')) problems.push(`${key}: ar.${f} missing or not Arabic`);
  }
  const en = [p.title, p.excerpt, p.meta_desc, p.body_html].join('\n');
  const ar = [p.ar.title, p.ar.excerpt, p.ar.meta_desc, p.ar.body_html].join('\n');
  if (digits(en) !== digits(ar)) problems.push(`${key}: the numbers differ between English and Arabic`);
  for (const t of ['h2', 'h3', 'p', 'li', 'tr', 'td', 'th', 'table']) {
    const re = new RegExp('<' + t + '[\\s>]', 'g');
    const a = (p.body_html.match(re) || []).length, b = (p.ar.body_html.match(re) || []).length;
    if (a !== b) problems.push(`${key}: <${t}> ${a} in English, ${b} in Arabic`);
  }
}

// 5. the route and the component.
const page = read('src/app/[locale]/blog/page.tsx');
if (!/<BlogIndex\b/.test(page)) problems.push('src/app/[locale]/blog/page.tsx does not render <BlogIndex>');
if (!/from '@\/content\/blog\.json'/.test(read('src/components/BlogIndex.tsx'))) problems.push('BlogIndex.tsx does not read blog.json');

if (problems.length) {
  console.error('blog_index_matches_data: FAIL\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`blog_index_matches_data: ok — ${Object.keys(data).length} posts, all with Arabic, index rendered from data`);
