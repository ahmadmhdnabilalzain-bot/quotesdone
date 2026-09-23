// The reader for src/content/company_facts.json — the one source of truth for company figures (founder rule C,
// 23 Sep 2026: "every change to company knowledge must reach every place at once, with no mismatch").
//
// A fact is stated in prose in many places (the legal pages, the FAQ, the seats' knowledge, templates). Each fact
// carries the regexes that recognise a statement of it; `findings()` reads a text and returns every statement whose
// number differs from the fact, and `rewrite()` puts the fact's number into every statement it recognises. The
// check and the sync both go through here, so what the check calls drift is exactly what the sync repairs.
import { readFileSync } from 'node:fs';

export const FACTS_URL = new URL('../../src/content/company_facts.json', import.meta.url);
export const loadFacts = () => JSON.parse(readFileSync(FACTS_URL, 'utf8'));

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
// A small number may be stated as a word ("three times the fee"); it counts, and it is rewritten as a word.
const WORD = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
export const toNumber = (s) => WORD.includes(String(s).toLowerCase()) ? WORD.indexOf(String(s).toLowerCase()) : Number(String(s).replace(/[٠-٩]/g, (d) => AR_DIGITS.indexOf(d)).replace(/[,٬\s]/g, ''));
// Every surface writes AED amounts with Latin digits and a thousands comma, in both languages (measured over
// legal.json 23 Sep 2026), so the rewrite keeps that form rather than inventing an Arabic-digit one.
export const format = (n) => (Number.isInteger(n) && n >= 1000 ? n.toLocaleString('en-US') : String(n));

const compiled = new Map();
export function patternsOf(fact) {
  if (!compiled.has(fact)) compiled.set(fact, fact.patterns.map((p) => new RegExp(p, 'giu')));
  return compiled.get(fact);
}

// Detection reads the text with its tags removed, so "<b>AED 1,000 per year</b>" is still a statement.
export const plain = (t) => String(t).replace(/<[^>]+>/g, '').replace(/&nbsp;|\s+/g, ' ');

/** Every statement in `text` of any fact, with the number it gives. */
export function statements(text, facts = loadFacts().facts) {
  const out = []; const t = plain(text);
  for (const [key, fact] of Object.entries(facts)) {
    for (const re of patternsOf(fact)) {
      re.lastIndex = 0;
      for (const m of t.matchAll(re)) out.push({ fact: key, want: fact.value, got: toNumber(m.groups.n), at: m.index, text: m[0].slice(0, 160) });
    }
  }
  return out;
}

/** Every statement in `text` of any fact whose number is not the fact's value. */
export const findings = (text, facts) => statements(text, facts).filter((s) => s.got !== s.want);

/** Wordings the source rules out for a rule it states once (canonical_statements[*].forbid). */
export function wrongWordings(text, F = loadFacts()) {
  const t = plain(text);
  return Object.entries(F.canonical_statements || {}).filter(([k]) => !k.startsWith('_')).flatMap(([k, s]) =>
    (s.forbid || []).flatMap((f) => [...t.matchAll(new RegExp(f.re ?? f, 'giu'))].map((m) => ({ rule: k, text: m[0], say: s.en }))));
}

/** `text` with every ruled-out wording that has a mechanical correction (`forbid[].fix`) corrected. */
export function fixWordings(text, F = loadFacts()) {
  let changed = 0;
  for (const s of Object.values(F.canonical_statements || {})) for (const f of (s && s.forbid) || []) {
    if (!f.fix) continue;
    text = text.replace(new RegExp(f.re, 'giu'), (...a) => { changed++; return a[0].replace(new RegExp(f.re, 'iu'), f.fix); });
  }
  return { text, changed };
}

/** `text` with the fact's number written into every statement of it. Returns { text, changed }. */
export function rewrite(text, facts = loadFacts().facts) {
  let changed = 0;
  for (const fact of Object.values(facts)) {
    for (const re of patternsOf(fact)) {
      re.lastIndex = 0;
      text = text.replace(re, (...a) => {
        const m = a[0]; const g = a[a.length - 1];
        if (toNumber(g.n) === fact.value) return m;
        // the group's own position inside the match: replace that span only
        const local = m.indexOf(g.n);
        changed++;
        const put = WORD.includes(g.n.toLowerCase()) ? (WORD[fact.value] ?? format(fact.value)) : format(fact.value);
        return m.slice(0, local) + put + m.slice(local + g.n.length);
      });
    }
  }
  return { text: agreeNumberWords(text), changed };
}

// "three (5) times" is what a digit-only rewrite leaves behind; the legal texts spell each small number and
// then give it in digits, so the word follows the digit.
const EN_WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
const AR_WORDS = ['صفر', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة'];
export function agreeNumberWords(text) {
  return text
    .replace(new RegExp(`\\b(${EN_WORDS.join('|')}) \\((\\d+)\\)`, 'gi'), (m, w, d) => (EN_WORDS[+d] && EN_WORDS[+d] !== w.toLowerCase() ? `${EN_WORDS[+d]} (${d})` : m))
    .replace(new RegExp(`(${AR_WORDS.join('|')}) \\((\\d+)\\)`, 'g'), (m, w, d) => (AR_WORDS[+d] && AR_WORDS[+d] !== w ? `${AR_WORDS[+d]} (${d})` : m));
}

/** Clause-pattern denylist hits (unlawful or founder-forbidden wording) in a public text. */
export function denylisted(text, list = loadFacts().unsafe_clause_denylist) {
  const plain = text.replace(/<[^>]+>/g, ' ');
  return list.flatMap((d) => [...plain.matchAll(new RegExp(d.re, 'giu'))].map((m) => ({ id: d.id, why: d.why, text: m[0] })));
}

/** The current (not archived) documents of legal.json. */
export function currentDocs(legal, facts = loadFacts()) {
  return Object.keys(legal).filter((k) => !facts.surfaces.archived_documents.includes(k) && !/-v\d+$/.test(k));
}

// THE SIGNED BODY a party accepts, derived from legal.json. MEASURED 23 Sep 2026: production's
// pages.legal_supplier_body (v12, 41,938 chars) is byte-for-byte this function applied to legal.json's v12 text
// with n='12' — the English card, then the Arabic card inside <div class="ar" dir="rtl" lang="ar">. Before v9 the
// customer body was English only, with a stale page script appended; Arabic now prevails, so it carries both.
export function card(html) {
  const s = html.slice(html.indexOf('<div class="body">') + 18);
  return s.slice(0, s.lastIndexOf('</p></div>') + 10);
}
export function signedBody(doc, versionNumber) {
  let en = card(doc.en.html), ar = card(doc.ar.html);
  if (versionNumber) {
    en = en.replace(/(<div class="muted">[^<]*?)(<\/div>)/, `$1 Version ${versionNumber} · governed by the laws of the United Arab Emirates.$2`);
    ar = ar.replace(/(<div class="muted">[^<]*?)(<\/div>)/, `$1 الإصدار ${versionNumber} · تخضع لقوانين دولة الإمارات العربية المتحدة.$2`);
  }
  return en.slice(0, -6) + '\n<div class="ar" dir="rtl" lang="ar">' + ar;
}
