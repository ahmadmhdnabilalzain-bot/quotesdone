// WHAT "THE CUSTOMER'S SCREEN" IS, COMPUTED ONCE, FOR EVERY SECTION MODULE OF ROW #4.
//
// ── THE DEFECT THIS FILE EXISTS TO REMOVE ────────────────────────────────────────────────────────
// The five section modules of verify_portal_blueprint were written in parallel and they did not
// agree about what surface they were scoring. projects_and_rfq.mjs and spatial_and_structure.mjs
// each compute the /me route's IMPORT CLOSURE — 53 files on 7 Aug 2026. entry_and_twin.mjs and
// documents_and_comms.mjs each hardcoded `src/components/me/CustomerPortal.tsx` and scored that ONE
// file. When those modules were written the two were the same thing. They stopped being the same
// thing when the portal was split into src/components/portal/*, which CustomerPortal.tsx imports
// and mounts, and no module noticed.
//
// The consequence is a FALSE MISSING, and it is the same class of error the scorer's own headers
// are written against — one measured fact meaning two different things in one run. doc-customer-ui
// reported "0 document-list calls ... the surface exists for suppliers only" while DocumentVault.tsx
// is imported at CustomerPortal.tsx:19, mounted at ModuleWindow, and fetches customer_documents
// action:'list'. The vault was on the customer's screen and the check was looking at one file of
// the fifty-three that screen is made of.
//
// ── THIS IS NOT A WEAKENING, AND HERE IS THE TEST OF THAT ────────────────────────────────────────
// Widening a surface makes "X is present" easier AND "X is absent" harder. Both directions are in
// this file's blast radius: mob-responsive-portal fails if ANY of the 53 files declares a fixed
// width over 343px, and ui-not-sidebar-pages-tables fails on a <table> anywhere in the closure.
// The score after this change is not predictable in advance and is not meant to be.
//
// A surface is what the customer's browser renders. It is not a filename.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Every source file under src/, keyed by repo-relative posix path — the population the closure is
// resolved against. Files over 4MB are skipped: nothing that large is a component, and reading one
// per section module five times over is the difference between a slow run and a stalled one.
const SRC = (function walk(dir, acc = new Map()) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) walk(p, acc); continue; }
    if (!/\.(ts|tsx|js|jsx)$/.test(e.name)) continue;
    try { if (statSync(p).size > 4e6) continue; } catch { continue; }
    try { acc.set(p.slice(ROOT.length + 1).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
  }
  return acc;
})(join(ROOT, 'src'));

// The /me route's rendered tree: its page, the layouts wrapping it, and everything they import,
// transitively. Identical resolution to projects_and_rfq.mjs's importClosure so the two can never
// disagree about which files are on the customer's screen.
function importClosure(entries) {
  const seen = new Map(); const queue = entries.filter((e) => SRC.has(e));
  const resolve = (from, spec) => {
    let base = null;
    if (spec.startsWith('@/')) base = 'src/' + spec.slice(2);
    else if (spec.startsWith('.')) base = join(dirname(from), spec).split(sep).join('/');
    if (!base) return null;
    for (const ext of ['', '.tsx', '.ts', '.jsx', '.js', '/index.tsx', '/index.ts']) if (SRC.has(base + ext)) return base + ext;
    return null;
  };
  while (queue.length) {
    const p = queue.shift();
    if (seen.has(p)) continue;
    const text = SRC.get(p); if (text === undefined) continue;
    seen.set(p, text);
    for (const m of text.matchAll(/from\s+['"]([^'"]+)['"]/g)) { const r = resolve(p, m[1]); if (r && !seen.has(r)) queue.push(r); }
  }
  return seen;
}

export const ENTRY = 'src/components/me/CustomerPortal.tsx';
const surface = importClosure(['src/app/[locale]/me/page.tsx', 'src/app/[locale]/layout.tsx', 'src/app/layout.tsx', ENTRY]);

/** Repo-relative paths of every file the customer's page renders. */
export const PORTAL_FILES = [...surface.keys()].sort();
/** The concatenated source of all of them — THE customer surface, for any count over "the screen". */
export const PORTAL_SRC = [...surface.values()].join('\n/*FILE*/\n');
/** CustomerPortal.tsx alone, for the few evidence strings that genuinely mean that one file. */
export const ENTRY_SRC = SRC.get(ENTRY) || '';
export const srcOf = (p) => SRC.get(p) || '';
export const allSrcPaths = () => [...SRC.keys()];

// ── ROW #5: THE SAME COMPUTATION, ROOTED AT A DIFFERENT PAGE ─────────────────────────────────────
// The brief's instruction was "parameterise the entry list — one implementation, two roots" rather
// than copy this file to supplier_surface.mjs. The copy is what produced row #4's 104-vs-124 split:
// two files each holding a definition of "what the user sees", drifting apart silently. One
// implementation cannot drift from itself.
//
// surfaceFor() is the whole of it. The /me exports above are now just its first instantiation kept
// under their original names so every row #4 module keeps working untouched.
export function surfaceFor(entries, entryPath = null) {
  const s = importClosure(entries);
  const FILES = [...s.keys()].sort();
  const SURFACE_SRC = [...s.values()].join('\n/*FILE*/\n');
  // The edge functions THIS surface can cause to run: the ones it names, then the ones those name.
  const FNS = (() => {
    const seen = new Set(); const queue = [];
    for (const m of SURFACE_SRC.matchAll(/(?:call\(\s*|functions\/v1\/)['"]?([a-z0-9_]+)['"]?/g)) queue.push(m[1]);
    while (queue.length) {
      const n = queue.shift();
      if (seen.has(n) || !EDGE.has(n)) continue;
      seen.add(n);
      for (const m of EDGE.get(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) if (!seen.has(m[1])) queue.push(m[1]);
    }
    return [...seen].sort();
  })();
  return {
    FILES,
    SRC: SURFACE_SRC,
    ENTRY_SRC: entryPath ? (SRC.get(entryPath) || '') : '',
    FNS,
    FN_SRC: FNS.map((n) => EDGE.get(n)).join('\n/*FILE*/\n'),
  };
}

// SUPPLIER is instantiated at the END of this file, below EDGE. surfaceFor() reads EDGE, EDGE is a
// const, and `export const SUPPLIER = surfaceFor(...)` placed here would run inside EDGE's temporal
// dead zone and throw a ReferenceError at IMPORT time — which the runner catches per-module, so the
// symptom would not be an error, it would be all 234 checks silently unmeasured.

// Every edge function's source, and the subset a customer's browser can cause to run: the ones the
// surface names as call('<n>') or functions/v1/<n>, then the ones THOSE name, transitively.
export const EDGE = (() => {
  const out = new Map();
  const dir = join(ROOT, 'supabase', 'functions');
  let names = [];
  try { names = readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name); } catch { /* none */ }
  for (const n of names) {
    const p = join(dir, n, 'index.ts');
    if (!existsSync(p)) continue;
    try { out.set(n, readFileSync(p, 'utf8')); } catch { /* unreadable */ }
  }
  return out;
})();

export const CUST_FNS = (() => {
  const seen = new Set(); const queue = [];
  for (const m of PORTAL_SRC.matchAll(/(?:call\(\s*|functions\/v1\/)['"]?([a-z0-9_]+)['"]?/g)) queue.push(m[1]);
  while (queue.length) {
    const n = queue.shift();
    if (seen.has(n) || !EDGE.has(n)) continue;
    seen.add(n);
    for (const m of EDGE.get(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) if (!seen.has(m[1])) queue.push(m[1]);
  }
  return [...seen].sort();
})();
export const CUST_SRC = CUST_FNS.map((n) => EDGE.get(n)).join('\n/*FILE*/\n');

/**
 * The supplier's screen — row #5's surface, from the same importClosure the customer's uses.
 *
 * There is NO entryPath argument on purpose. A section module that wants "the supplier's surface"
 * must take SUPPLIER.SRC, which is the whole import closure. Hardcoding SupplierPortal.tsx is the
 * exact bug that made row #4 report 104/147 against a truth of 124, and the way to make that bug
 * unwritable is to not export a handle for it.
 */
export const SUPPLIER = surfaceFor([
  'src/app/[locale]/supplier/page.tsx',
  'src/app/[locale]/layout.tsx',
  'src/app/layout.tsx',
]);

/**
 * The source of one component, from `function Name(` to the next top-level declaration.
 *
 * RETURNS '' WHEN THE COMPONENT IS ABSENT, and that is the whole reason this helper is shared.
 * The hand-rolled version in documents_and_comms.mjs was `text.slice(text.indexOf('function
 * Messages('))` — and indexOf returns -1 for a component that no longer exists, so slice(-1)
 * handed the check THE LAST CHARACTER OF THE FILE and every count over it was 0. A missing
 * component then reads exactly like a present one with no matches, which is a false MISSING that
 * cannot be told apart from a true one by looking at the number.
 */
export function componentSrc(name, text = PORTAL_SRC) {
  const m = new RegExp('^(?:export )?(?:default )?(?:async )?function ' + name + '\\b', 'm').exec(text);
  if (!m) return '';
  const rest = text.slice(m.index + 1);
  const nxt = /\n(?:export )?(?:default )?(?:function |const [A-Z])/.exec(rest);
  return text.slice(m.index, nxt ? m.index + 1 + nxt.index : text.length);
}
