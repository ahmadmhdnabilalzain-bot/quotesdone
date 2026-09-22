// THE LAZY MATCHER FINDS EXACTLY WHAT THE EAGER ONE FOUND (22 Sep 2026). Seat: sales_engineer.
//
// service_rewrite.ts builds an alias's RegExp only when the phrase contains the alias's first word
// (the CPU fix for supplier_api's 546s). That pre-check must never skip a pattern that would have
// matched: "exact or none" routing and the Arabic BOQ reading both read these hits. This test keeps a
// brute-force reference — every alias compiled up front and run against every phrase, the matcher as it
// was before the fix — and asserts servicesFromText agrees with it on a deterministic phrase set built
// from the committed vocabulary (service_aliases.json, the seed taxonomy_trade_service.aliases is loaded
// from): every alias at least once, in one of eight shapes (as stored, upper case, plural inside a
// sentence, Arabic proclitics و ال / بال / ل, hyphenated, the service code as words), plus a second shape
// for every third alias and a set of mixed and no-hit sentences.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import aliases from './service_aliases.json' with { type: 'json' };
import { servicePattern, servicesFromText, splitPhrases, MAX_TEXT, type ServiceTerm } from './service_rewrite.ts';
import { foldForMatch } from './trade_words.ts';

const VOCAB: ServiceTerm[] = Object.entries(aliases as Record<string, { en: string[]; ar: string[] }>).map(([key, a]) => {
  const [trade_code, code] = key.split('.');
  return { trade_code, code, label_en: code.replace(/_/g, ' '), label_ar: code, aliases: [...a.en, ...a.ar] };
});

// ── The reference: the matcher before 22 Sep 2026, eager and unfiltered. ──────────────────────────
const WORD = /[\p{L}\p{N}]/u;
const EAGER = VOCAB.flatMap((term) => (term.aliases || []).map((a) => ({ key: `${term.trade_code}.${term.code}`, re: servicePattern(a) })))
  .filter((c): c is { key: string; re: RegExp } => !!c.re);
function referenceKeys(text: string): string[] {
  const keys = new Set<string>();
  for (const phrase of splitPhrases(String(text ?? '').slice(0, MAX_TEXT))) {
    const norm = foldForMatch(phrase).norm;
    const all: { key: string; start: number; end: number; len: number }[] = [];
    for (const c of EAGER) {
      c.re.lastIndex = 0;
      for (let m = c.re.exec(norm); m; m = c.re.exec(norm)) {
        let end = m.index + m[0].length;
        while (end < norm.length && WORD.test(norm[end])) end++;
        all.push({ key: c.key, start: m.index, end, len: m[0].length });
        if (m[0].length === 0) c.re.lastIndex++;
      }
    }
    all.sort((a, b) => b.len - a.len || a.start - b.start);
    const kept: typeof all = [];
    for (const h of all) if (!kept.some((k) => h.start < k.end && k.start < h.end && !(k.start === h.start && k.end === h.end))) kept.push(h);
    for (const h of kept) keys.add(h.key);
  }
  return [...keys].sort();
}

// ── The phrase set. ──────────────────────────────────────────────────────────────────────────────
const SHAPES: ((a: string, t: ServiceTerm) => string)[] = [
  (a) => a,
  (a) => a.toUpperCase(),
  (a) => `We do ${a}s and more`,
  (a) => `وال${a}`,
  (a) => `بال${a} في دبي`,
  (a) => `ل${a}`,
  (a) => a.replace(/ /g, '-'),
  (_a, t) => `${t.code.replace(/_/g, ' ')} works`,
  // The Arabic rule 4 of trade_words.ts: each later word may carry ال (after its و), so the alias is NOT
  // in the phrase verbatim ("مكافحة حريق" → "لمكافحة الحريق"). A pre-check keyed on more than the first
  // word would skip these.
  (a) => 'ل' + a.split(' ').map((w, i) => (i === 0 ? w : w.startsWith('و') ? 'وال' + w.slice(1) : 'ال' + w)).join(' '),
];
const MULTI_AR = /[ء-ي]/;
const PHRASES: string[] = [];
let n = 0;
for (const t of VOCAB) for (const a of t.aliases || []) {
  PHRASES.push(SHAPES[n % SHAPES.length](a, t));
  if (n % 3 === 0) PHRASES.push(SHAPES[(n + 3) % SHAPES.length](a, t));
  if (MULTI_AR.test(a) && a.includes(' ')) PHRASES.push(SHAPES[SHAPES.length - 1](a, t));   // every multi-word Arabic alias
  n++;
}
PHRASES.push(
  'Gypsum board partition, 100mm metal stud, both faces', 'Suspended false ceiling, 600x600 mineral fibre tiles',
  'نجارة وألمنيوم ومكافحة الحريق', 'CCTV, access control; fire alarm | HVAC maintenance', 'We are a leading company in Dubai',
  'Aluminium windows and doors, curtain wall, ACP cladding, pergolas and louvres', 'Interior painting and exterior painting',
);

Deno.test('the lazy matcher returns exactly what the eager reference returns, over every alias of the vocabulary', () => {
  assert(PHRASES.length >= 2000, `phrase set too small: ${PHRASES.length}`);
  const misses: string[] = [];
  let withHits = 0;
  for (const p of PHRASES) {
    const want = referenceKeys(p);
    if (want.length) withHits++;
    const got = servicesFromText(p, VOCAB);
    if (JSON.stringify(got) !== JSON.stringify(want)) misses.push(`${JSON.stringify(p)}: want ${want.join(',')} got ${got.join(',')}`);
  }
  assertEquals(misses.slice(0, 10), [], `${misses.length} of ${PHRASES.length} phrases differ`);
  assert(withHits > PHRASES.length / 2, `only ${withHits} phrases hit anything; the set no longer exercises the matcher`);
});
