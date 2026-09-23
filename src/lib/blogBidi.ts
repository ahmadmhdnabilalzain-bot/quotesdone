// Bidi isolation for the Arabic blog (lifted out of src/components/BlogPost.tsx so a node test can run it).
//
// A Latin run (AED figures, units, phone numbers, emails, URLs, acronyms) inside RTL text is wrapped in
// <bdi> so "+971 50 931 9355" keeps its digit groups in order. Runs start at a Latin letter, digit or
// "+", may contain spaces and the punctuation such runs use, and end at a letter, digit, % or
// superscript. Only text between tags is touched.
//
// MEASURED 22 SEP 2026 (production walk, 24 /ar/blog posts): readers saw the words "mdash", "middot",
// "ldquo" and "rdquo" in the text. The run pattern treated the letters of a character reference as a
// Latin word, so the five letters between the ampersand and the semicolon were wrapped in <bdi> and the
// reference stopped being one. The text is now DECODED before runs are found and re-escaped after, so
// a character reference is a character, never a word. English pages never ran this pass and were fine.
// Prevented by: src/lib/blogBidi.test.mjs (every Arabic post in blog.json).
const LATIN_RUN = /[A-Za-z0-9+][A-Za-z0-9+@.,:;/\\\-–—%²³×&#_' ]*[A-Za-z0-9%²³]/g;

const NAMED: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–', middot: '·',
  ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', laquo: '«', raquo: '»', hellip: '…', rarr: '→', larr: '←',
  times: '×', deg: '°', sup2: '²', sup3: '³', plusmn: '±', bull: '•', copy: '©', reg: '®', trade: '™',
};
// An unknown named reference is left as written, and esc() below would then show it as text — the test
// fails on exactly that, so a new reference in the content gets a line in NAMED rather than a reader.
export function decodeRefs(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (m, n: string) => {
    if (n[0] === '#') {
      const cp = n[1] === 'x' || n[1] === 'X' ? parseInt(n.slice(2), 16) : parseInt(n.slice(1), 10);
      return Number.isFinite(cp) && cp > 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : m;
    }
    return NAMED[n] ?? m;
  });
}
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function isolateText(raw: string): string {
  const t = decodeRefs(raw);
  let out = '', last = 0;
  for (const m of t.matchAll(LATIN_RUN)) {
    out += esc(t.slice(last, m.index)) + '<bdi>' + esc(m[0]) + '</bdi>';
    last = m.index! + m[0].length;
  }
  return out + esc(t.slice(last));
}

// MEASURED 22 SEP 2026 (production walk, /ar/blog): 25 Arabic posts carry a FAQPage block as
// <script type="application/ld+json">, and this pass treated the JSON as prose — every Latin run in it
// was wrapped in <bdi> and every " became &quot;, so the structured data no longer parsed and Google
// read no FAQ on any of them. A <script> or <style> body is code, never text to isolate, so those
// segments are copied through untouched.
const CODE = /<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi;
const isolateProse = (html: string) =>
  html.replace(/(^|>)([^<]+)/g, (_m, lead: string, text: string) => lead + isolateText(text));

export function isolateLatin(html: string): string {
  let out = '', last = 0;
  for (const m of html.matchAll(CODE)) {
    out += isolateProse(html.slice(last, m.index)) + m[0];
    last = m.index! + m[0].length;
  }
  return out + isolateProse(html.slice(last));
}
export const bidiText = (s: string) => isolateLatin(esc(s));
