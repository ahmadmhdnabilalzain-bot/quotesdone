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
export const strip = (t) => String(t || '').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*\/\/.*$/gm, ' ');

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
const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
export const B = (v) => 'select ' + (v ? 'true' : 'false');
export const Q = (s) =>
  "select '" + String(s == null ? '' : s).replace(/'/g, "''").replace(GUARD, (m) => m.slice(0, 2) + "'||'" + m.slice(2)) + "'";

/** Non-writer readers of a relation, overloads collapsed — defect class #1. `count(distinct proname)`
 *  because fn_agent_context has two rows on production and inflated every row #2 count that forgot;
 *  the name filter excludes the writers, since a table's own updater is not its reader. */
export const READERS_SQL = (t) => `select count(distinct p.proname) from pg_proc p
  join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.prokind in ('f','p')
    and p.proname !~* '^(fn_)?(set|upd|ins|write|save|refresh|rebuild|sync)_'
    and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'`;
export const NROWS_SQL = (t, w = 'true') => `select count(*)::text from public.${t} where ${w}`;
