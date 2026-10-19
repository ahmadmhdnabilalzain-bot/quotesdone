// 19 Oct 2026, seat it_engineer. The IT digest of 18 Oct (notifications 101206) put two technical items to the
// founder, cut its lines inside a word ("...the chosen reviewer fai.") and ended each with an internal key.
// #1446 stopped the routing; the_it_digest_reaches_the_founder_only_with_his_kind_of_decision_in_whole_words.sql
// fixed the email. These assert, on the canonical definition (a pending file wins over MANIFEST):
//   1. an item is emailed only when its class names one of his three categories, not on to_founder alone;
//   2. the title is shortened at a whole word (fn_trim_at_word), never with a bare left();
//   3. the founder-facing text carries no internal key, id or metric code;
//   4. fn_trim_at_word's rule, replayed here, never cuts inside a word (the 18 Oct inputs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const newest = (re) => {
  const defines = (f) => existsSync(f) && re.test(readFileSync(f, 'utf8'));
  const pending = readdirSync('scripts/sql/pending').map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
  const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql')).filter(defines);
  return pending.at(-1) ?? manifest.at(-1);
};
const body = (name) => {
  const re = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i');
  const file = newest(re);
  assert.ok(file, `no file defines ${name}`);
  const src = readFileSync(file, 'utf8');
  const start = src.search(re);
  const end = src.indexOf('$function$', src.indexOf('$function$', start) + 10);
  return { file, text: src.slice(start, end) };
};

test('an item reaches the founder only with one of his three categories', () => {
  const { file, text } = body('fn_customer_support_sends_the_it_digest');
  assert.match(text, /c\.founder_category into v_why, v_his, v_cat/, `${file}: the digest must read the class's founder_category`);
  assert.match(text, /not v_his or coalesce\(v_cat, ''\) not in \('money', 'destructive_production_change', 'fact_only_he_holds'\)/,
    `${file}: to_founder alone must not email him; the category must be one of his three`);
});

test('the digest shortens a title at a whole word and shows no internal key', () => {
  const { file, text } = body('fn_customer_support_sends_the_it_digest');
  assert.match(text, /fn_trim_at_word\(/, `${file}: the title must be shortened by fn_trim_at_word`);
  assert.doesNotMatch(text, /left\(f\.title/, `${file}: a bare left() on the title cuts inside a word`);
  assert.doesNotMatch(text, /reference ' \|\|/i, `${file}: the founder line must not carry an internal reference key`);
  // Every literal the digest writes into the founder's text: no snake_case code, no "duty:" key, no "#123" id.
  const literals = [...text.matchAll(/v_(?:event|detail) := ([\s\S]*?);\n/g)].map((m) => m[1]).join('\n')
    + [...text.matchAll(/string_agg\(([\s\S]*?)E'\\n' order by/g)].map((m) => m[1]).join('\n');
  for (const s of literals.matchAll(/'((?:[^']|'')*)'/g)) {
    if (/(when |->>)$/.test(literals.slice(0, s.index))) continue;   // a category key or a json key, not text
    assert.doesNotMatch(s[1], /\b[a-z]+_[a-z_]+\b|duty:|#\d+|\bid\b/i, `${file}: founder text literal "${s[1]}" reads like a code or an id`);
  }
});

test('fn_trim_at_word is defined and never cuts inside a word', () => {
  const { file, text } = body('fn_trim_at_word');
  assert.match(text, /regexp_replace\(left\(p_text, p_max \+ 1\), '\\s\+\\S\*\$', ''\)/, `${file}: the trim must drop the partial last word`);
  // The SQL rule, replayed: cut at max+1, drop the trailing partial word, strip trailing punctuation, add an ellipsis.
  const trim = (t, max) => t.length <= max ? t
    : ((t.slice(0, max + 1).replace(/\s+\S*$/, '').replace(/[\s.,;:(\-]+$/, '')) || t.slice(0, max)) + '…';
  const words = (s) => new Set(s.split(/\s+/));
  for (const [src, max] of [
    ["1 visitor_chat review(s) HELD: no healthy reviewer outside the authors' families (not even a last-resort family), or the chosen reviewer failed", 140],
    ["1 knowledge_validation review(s) from sales_engineer_conversation_drill in 7 days named an author model that is not in model_registry (or 'unknown')", 140],
  ]) {
    const out = trim(src, max);
    assert.ok(out.length <= max + 1, 'trimmed text is within the limit');
    const whole = words(src);
    for (const w of out.replace(/…$/, '').split(/\s+/)) assert.ok(whole.has(w) || whole.has(w + ','), `"${w}" is not a whole word of the source`);
  }
});
