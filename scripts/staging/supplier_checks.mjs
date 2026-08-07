// THE SHARED MEASUREMENT CONTRACT FOR ROW #5's SECTION MODULES.
//
// ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────────────
// Row #5's refutation round 1 removed seven false METs from module 1, and THREE OF THE FIVE DEFECTS
// WERE THE SAME ERROR: a scan whose population was an artefact of the scan.
//
//   · `re.test(FN)` searched all fourteen reachable edge functions JOINED END TO END, so a field
//     named in supplier_api paired with a token in wa_optin_set and scored a MET.
//   · `field … within 400 chars … json` windowed across that same join.
//   · A conversation shape was certified by ChatWidget.tsx — the MARKETING chat bubble, which is in
//     the supplier route's closure but is not the supplier portal.
//
// Written out five more times by hand, that error returns five more times. So the legs are defined
// once, here, and every section module takes them from this file. A module that wants a different
// population has to say so explicitly rather than get one by accident.
//
// ── IT DOES NOT LIVE IN supplier_blueprint/ ──────────────────────────────────────────────────────
// The runner imports EVERY *.mjs in that directory as a section module and books anything without a
// default export as a shortfall, which invalidates the denominator. Helpers live beside
// portal_surface.mjs instead.
import { SUPPLIER, srcOf, EDGE } from './portal_surface.mjs';

/** Strip block and line comments. A COMMENT QUOTING MARKUP IS THAT MARKUP TO A STATIC SCAN — row #4
 *  lost two requirements to a comment reading `WAS A <table min-w-[380px]>`. Any count a comment
 *  could fake must run over stripped text. */
//
// ── THE BRAND NAME IS NEUTRALISED, AND IT IS NOT COSMETIC ───────────────────────────────────────
// The product is called **QuotesDone**, which contains the substring "quote". §24's
// struct-quote-builder read MET on the page heading "quotesdone — supplier portal": the brand name
// satisfying a requirement for an AI Quote Builder. Every /quote/ check in §9, §11 and §24 shares
// the hazard, and the brand appears in titles, meta tags and copy on every single file.
//
// A product's own name is not evidence that it has a feature. The token is replaced with a
// placeholder that matches nothing, in the ONE function every population flows through, so no
// module can forget it.
export const strip = (t) => String(t || '')
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/^\s*\/\/.*$/gm, ' ')
  .replace(/quotesdone/gi, 'BRANDNAME');

/** The site chrome. On the supplier's page, but NOT the supplier portal: a marketing chat bubble is
 *  not the portal's AI assistant and a cookie banner that fades in is not "the portal animates".
 *  Excluded from assistant/module legs, KEPT for background legs — NodeField.tsx genuinely is the
 *  animated landing background the supplier sees. */
export const CHROME = [
  'src/components/ChatWidget.tsx',
  'src/components/CookieConsent.tsx',
];

/** The whole supplier surface, comment-stripped. Use for background and chrome-inclusive legs. */
export const S = strip(SUPPLIER.SRC);
/** The supplier PORTAL, comment-stripped: the surface minus the marketing chrome. Use for every
 *  "the portal does X" leg — assistant, modules, navigation, intelligence. */
export const P = strip(SUPPLIER.FILES.filter((f) => !CHROME.includes(f)).map(srcOf).join('\n/*FILE*/\n'));
export const FILES = SUPPLIER.FILES;
/** The portal's own files — FILES minus the marketing chrome. Pass this to filesNear/filesMatching
 *  for any "the portal does X" leg. Three separate false METs in this row were ChatWidget.tsx
 *  answering for the portal, and defaulting to the wide list is what let it keep happening. */
export const P_FILES = SUPPLIER.FILES.filter((f) => !CHROME.includes(f));
export const FNS = SUPPLIER.FNS;

/** Per-file source, comment-stripped, so a leg can name WHICH file satisfied it. */
export const fileSrc = (f) => strip(srcOf(f));
/** Per-function source, comment-stripped. NEVER concatenate these for a proximity test. */
export const fnSrc = (f) => strip(EDGE.get(f) || '');

/** Count occurrences. THE `g` FLAG IS FORCED: String.match with a non-global regex returns the first
 *  match plus capture groups, so an unforced count reads 1 for everything present. That made
 *  entry-not-form-wall read "3 form controls" and PASS a `< 20` bar against a real 21 — a false MET
 *  with a wrong number in its evidence, which is defect class #5 exactly. */
export const n = (re, t = P) =>
  (String(t).match(re.flags.includes('g') ? re : new RegExp(re.source, re.flags + 'g')) || []).length;

export const has = (re, t = P) => re.test(String(t));

/** Which FILES of the supplier surface satisfy `re`? Returns names, so evidence can print them.
 *  This is the per-file leg: an unnamed "surface yes" cannot be refuted, a named one can. */
export const filesMatching = (re, files = FILES) => files.filter((f) => re.test(fileSrc(f)));

/** Which reachable EDGE FUNCTIONS satisfy `re` — each scored on its OWN text, never on the join.
 *  Optionally restricted to a candidate list, for legs that mean a specific endpoint. */
export const fnsMatching = (re, candidates = FNS) =>
  candidates.filter((f) => FNS.includes(f) && re.test(fnSrc(f)));

/** Both patterns inside ONE function's own source. The per-function replacement for a windowed
 *  proximity scan across a concatenation. */
export const fnsWithBoth = (reA, reB, candidates = FNS) =>
  candidates.filter((f) => FNS.includes(f) && reA.test(fnSrc(f)) && reB.test(fnSrc(f)));

/**
 * Two patterns within `win` characters of each other IN THE SAME TEXT.
 *
 * ── WHY THIS EXISTS, AND WHY IT IS NOT THE THING ROUND 1 BANNED ─────────────────────────────────
 * Round 1 killed a proximity scan because it windowed across a CONCATENATION of fourteen edge
 * functions — a field in supplier_api paired with a token in wa_optin_set, and the adjacency was an
 * artefact of the join. That remains banned: never pass a concatenation here.
 *
 * Round 3 found the opposite failure. `SupplierPortal.tsx` is 81,811 stripped characters and holds
 * the settings form, the registration uploader, the help desk, the catalog uploader AND the command
 * centre. Asking "does this FILE contain both X and Y" is nearly vacuous against it — per-file
 * scoping, which was the round-1 fix, is too coarse when one file is the whole product.
 *
 * So the unit shrinks again: within ONE file's own text, require the two things to be near each
 * other. Adjacency inside a single file is a real fact about that file; adjacency across a join is
 * not. Pass a single file's or a single function's source, never `P`, never `FN_SRC`.
 */
export const near = (text, reA, reB, win = 400) => {
  const t = String(text);
  const ga = new RegExp(reA.source, reA.flags.includes('g') ? reA.flags : reA.flags + 'g');
  for (const m of t.matchAll(ga)) {
    if (reB.test(t.slice(Math.max(0, m.index - win), m.index + win))) return true;
  }
  return false;
};

/** Which FILES carry both patterns within `win` chars of each other, scored per file. The
 *  monolith-safe replacement for `filesMatching(a).filter(f => b.test(fileSrc(f)))`. */
export const filesNear = (reA, reB, win = 400, files = FILES) =>
  files.filter((f) => near(fileSrc(f), reA, reB, win));

/** Which reachable FUNCTIONS carry both patterns within `win` chars, each scored on its OWN text. */
export const fnsNear = (reA, reB, win = 400, candidates = FNS) =>
  candidates.filter((f) => FNS.includes(f) && near(fnSrc(f), reA, reB, win));

/** DELIVERY, not occurrence — defect class #2. A value is delivered only when it appears inside a
 *  JSX interpolation, so `<Input name="products">` (a field the supplier TYPES) cannot satisfy a
 *  requirement that the portal DISPLAYS what was computed about them. Those are opposite claims. */
export const delivered = (re, t = P) =>
  re.test(String(t)) && new RegExp('\\{[^{}]*' + re.source + '[^{}]*\\}').test(String(t));

/** Coverage over an enumerated list — defect class #3. Where the spec enumerates contents, the
 *  verdict is a per-item count over ONE population, never "at least one of them exists".
 *  Returns { hit, total, missing } so evidence can name what is absent. */
export const cover = (items, t = P) => {
  const missing = items.filter(([, re]) => !re.test(String(t))).map(([name]) => name);
  return { hit: items.length - missing.length, total: items.length, missing };
};

/** Statement-emitting verdict and evidence helpers.
 *  BOTH EMIT A COMPLETE STATEMENT. req() hands its 4th and 5th arguments straight to the management
 *  API as the whole query, so a bare `true` is a 42601 syntax error — and the runner books that as
 *  an ERRORED check, an UNMEASURED requirement rather than a verdict. Nine checks were lost that
 *  way before this said `select`.
 *  Q also defuses bare write keywords: an evidence string quoting source easily contains `call` or
 *  `create`, qd_guard's read guard then refuses the statement as a write, and the check ERRORs. */
//
// ── THE SPLIT IS AT 1, NOT 2, AND THAT IS THE WHOLE POINT ───────────────────────────────────────
// Defusing by inserting `'||'` after the second character works for every keyword of three or more
// letters: `create` becomes `cr'||'eate` and `\bcreate\b` no longer matches. It is a NO-OP for the
// two-letter keyword `do`, which becomes `do'||'` — still a complete word, because the following
// quote is a non-word character and the boundary still holds.
//
// An evidence string reading "N fn(s) DO quote extraction" was therefore refused by qd_guard's read
// guard, the evidence query threw, and the check printed `MET` with an ERROR where its proof should
// have been. Splitting after the FIRST character defuses every length: `d'||'o`, `c'||'reate`.
const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
export const B = (v) => 'select ' + (v ? 'true' : 'false');
export const Q = (s) =>
  "select '" + String(s == null ? '' : s).replace(/'/g, "''").replace(GUARD, (m) => m.slice(0, 1) + "'||'" + m.slice(1)) + "'";

/** Non-writer readers of a relation, overloads collapsed — defect class #1. `count(distinct proname)`
 *  because fn_agent_context has two rows on production and inflated every row #2 count that forgot;
 *  the name filter excludes the writers, since a table's own updater is not its reader. */
export const READERS_SQL = (t) => `select count(distinct p.proname) from pg_proc p
  join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.prokind in ('f','p')
    and p.proname !~* '^(fn_)?(set|upd|ins|write|save|refresh|rebuild|sync)_'
    and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'`;
export const NROWS_SQL = (t, w = 'true') => `select count(*)::text from public.${t} where ${w}`;
