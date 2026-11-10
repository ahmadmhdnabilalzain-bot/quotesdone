// EVERY COPY OF A COPY-PASTED HELPER MUST SAY THE SAME THING.
//
// The word-by-word audit of 11 Aug 2026 counted `sec()` — the credential reader — copy-pasted into
// 134 of 198 edge functions, `J()` into 153 and a CORS constant into 105, with NO TEST ANYWHERE that
// the copies agree. That is not a style complaint: two authentication holes were found and fixed in
// July inside `cost_snapshot`'s own copy of a helper, and nothing checked the other hundred-odd.
//
// This does NOT migrate 134 files to a shared module. That is a large, risky diff, and the thing
// that makes it safe to do later — or safe not to do — is a check that fails the moment two copies
// diverge. `_shared/internal_auth.ts` already proves the shared-module route works: `requireInternal`
// has zero copies.
//
// The comparison is on TOKENS, not bytes: whitespace and the position of a brace are not a security
// property. A different table, a different column, a missing `.eq()`, a changed fail-open branch —
// those change the token stream and fail this test.
//
//   node scripts/checks/shared_helpers_agree.test.mjs
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { functionSource } from '../lib/function_sources.mjs';

// A RATCHET, NOT A CLIFF. There are 8 variants of sec() and 11 of J() TODAY, and failing the build
// on that would block every merge until 134 files are rewritten — which is a large, risky diff that
// nobody has costed. So the baseline below records what exists, and the check fails only when a
// helper gains a NEW variant. Divergence can only shrink from here. Lower a number when you unify
// copies; never raise one to make the check pass.
//
// MEASURED 11 Aug 2026, and stated precisely: the differences are in the RETURN TYPE on a miss --
// '' (99 functions), undefined (30), null (4) -- plus one function (wa_templates_watch) that reads
// through a different Supabase client. A sec() returning '' is the ingredient of a real hole: a
// strict comparison against it lets a caller posting {"__secret":""} match, which is exactly the
// bug kb_search's own header records from 27 Jul 2026. Checked today across all 198 functions:
// functions whose sec() returns '' AND that strict-compare a caller-supplied value -- ZERO. So this
// is a latent hazard, not a live hole, and it is written down as such.
const BASELINE = { sec: 8, J: 11 };

const ROOT = 'supabase/functions';
// Helpers worth pinning, and why each one is here.
const HELPERS = [
  { name: 'sec', re: /(?:export\s+)?(?:async\s+)?function\s+sec\s*\(/,
    why: 'reads app_secrets — the credential reader. A divergent copy is an auth bug that only one function has.' },
  { name: 'J', re: /(?:export\s+)?(?:const|function)\s+J\s*[=(]/,
    why: 'the JSON responder. A copy that omits the CORS headers or the status argument breaks one endpoint silently.' },
];

// Extract a balanced top-level declaration starting at `from`, ignoring braces inside strings.
function extract(src, from) {
  let i = from, depth = 0, started = false, q = null, esc = false;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) {
      if (esc) { esc = false; continue; }
      if (c === '\\') { esc = true; continue; }
      if (c === q) q = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === '{') { depth++; started = true; continue; }
    if (c === '}') { depth--; if (started && depth === 0) return src.slice(from, i + 1); continue; }
    if (started && depth === 0) break;
    if (!started && c === ';') return src.slice(from, i + 1);   // arrow form, no block body
  }
  return src.slice(from, Math.min(src.length, from + 4000));
}

// Token stream: identifiers, numbers, strings and punctuation, with all whitespace gone.
const tokens = (s) => (s.match(/[A-Za-z_$][\w$]*|\d+|'[^']*'|"[^"]*"|`[^`]*`|[^\sA-Za-z0-9_$]/g) || []).join(' ');

const dirs = readdirSync(ROOT, { withFileTypes: true })
  .filter(d => d.isDirectory() && d.name !== '_shared').map(d => d.name).sort();

let failed = 0;
for (const h of HELPERS) {
  const groups = new Map();
  for (const d of dirs) {
    const p = join(ROOT, d, 'index.ts');
    if (!existsSync(p)) continue;
    // the whole function, index.ts first: a function split into modules keeps its helpers in them (9 Nov 2026)
    const src = functionSource(d);
    const m = h.re.exec(src);
    if (!m) continue;
    // `export` only says another module of the same function imports it; it is not part of what the helper does
    const key = tokens(extract(src, m.index).replace(/^export\s+/, ''));
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(d);
  }
  const variants = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);
  const total = variants.reduce((a, v) => a + v[1].length, 0);
  console.log(`\n${h.name}()  —  ${total} definition(s), ${variants.length} distinct variant(s)`);
  console.log(`   ${h.why}`);
  variants.forEach(([key, fns], i) => {
    const head = i === 0 ? 'CANONICAL' : `VARIANT ${i + 1}`;
    console.log(`   ${head.padEnd(10)} ${String(fns.length).padStart(3)} function(s)` +
      (i === 0 ? '' : `  ->  ${fns.join(', ')}`));
    if (i > 0) console.log(`               ${key.slice(0, 220)}`);
  });
  const base = BASELINE[h.name] ?? 1;
  if (variants.length > base) {
    failed++;
    console.log(`   FAIL: ${variants.length} variants against a baseline of ${base}. A NEW divergent copy of ${h.name}() was added.`);
  } else if (variants.length > 1) {
    console.log(`   HELD: ${variants.length} variants, baseline ${base}. Not worse. Unify one and lower the baseline.`);
  } else if (variants.length === 1) {
    console.log(`   PASS: all ${total} copies are token-identical.`);
  }
}

console.log('');
if (failed) {
  console.error(`${failed} helper(s) gained a NEW divergent copy. Make the outliers match the canonical ` +
    `definition, or move the helper into supabase/functions/_shared/ — which is what ` +
    `requireInternal did, and it has zero copies.`);
  process.exit(1);
}
console.log('no pinned helper gained a new variant. Divergence is at or below the recorded baseline '
  + JSON.stringify(BASELINE) + ' — which is NOT the same as the copies agreeing, and is not reported as such.');
