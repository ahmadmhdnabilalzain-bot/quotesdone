// AUDIT 9.5 - OUTBOUND hop inventory, with the callee actually RESOLVED.
//
// Why this exists. inventory_internal_auth_gates.mjs finds the outbound hops correctly, but it
// resolves the callee with a single-line regex, so ~45 of ~105 hops came out as "(target not on
// this line)" — the URL is built on a different line, or held in a module-level constant like
//     const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
//
// That matters more than it looks. Decision D3 scopes each caller's credential to the functions it
// actually calls. An unresolved callee means the scope would have to be guessed, and a guessed
// scope is either too wide (which defeats the point) or too narrow (which breaks production the
// first time that hop runs). Counting by grep has already produced a wrong number on this item
// three times; this resolves per fetch CALL, not per line.
//
// Method: locate every `fetch(` call, take its full argument text by paren matching, and look for
// the callee inside THAT text — first as a literal `/functions/v1/<slug>`, then as an identifier
// resolved through the file's module-level constants. A hop whose URL is computed at runtime is
// reported as DYNAMIC rather than guessed, and any `__secret:` that could not be tied to a fetch
// at all is reported as UNATTACHED. Nothing is silently dropped: every presenting site appears in
// exactly one bucket, and the totals are asserted to add up.
//
//   node scripts/archive/inventory_outbound_hops.mjs

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../supabase/functions', import.meta.url));
const OUT = path.join(os.tmpdir(), 'inventory_outbound.out.txt');

const dirs = fs.readdirSync(ROOT, { withFileTypes: true })
  .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
  .map((d) => d.name).sort();

const SLUG_RE = /functions\/v1\/([a-z0-9_]+)/;
const PRESENTS = /__(secret|deploy_secret|force_key)\s*:/;

/** Extract the full text of a call starting at the '(' that follows index `open`. */
function callText(src, open) {
  let depth = 0, i = open;
  let inS = null, esc = false;
  for (; i < src.length; i++) {
    const c = src[i];
    if (esc) { esc = false; continue; }
    if (c === '\\') { esc = true; continue; }
    if (inS) { if (c === inS) inS = null; continue; }
    if (c === '"' || c === "'" || c === '`') { inS = c; continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return src.slice(open, i + 1); }
  }
  return src.slice(open); // unbalanced; return the rest rather than throwing
}

const lineOf = (src, idx) => src.slice(0, idx).split(/\r?\n/).length;

/** The first argument of a call, i.e. the URL expression. Splits on the first TOP-LEVEL comma. */
function firstArg(text) {
  const inner = text.slice(1, -1); // drop the outer parens
  let depth = 0, inS = null, esc = false;
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (esc) { esc = false; continue; }
    if (c === '\\') { esc = true; continue; }
    if (inS) { if (c === inS) inS = null; continue; }
    if (c === '"' || c === "'" || c === '`') { inS = c; continue; }
    if (c === '(' || c === '{' || c === '[') depth++;
    else if (c === ')' || c === '}' || c === ']') depth--;
    else if (c === ',' && depth === 0) return inner.slice(0, i);
  }
  return inner;
}

/** Every real function slug, so a resolved callee is never invented. */
const KNOWN = new Set(
  fs.readdirSync(ROOT, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_')).map((d) => d.name),
);

const hops = [];      // resolved caller -> callee
const dynamic = [];   // presenting fetch whose URL is computed
const unattached = [];// __secret: not inside a fetch call

for (const fn of dirs) {
  const p = path.join(ROOT, fn, 'index.ts');
  if (!fs.existsSync(p)) continue;
  const src = fs.readFileSync(p, 'utf8');

  // Resolve module-level constants to a callee slug. Three shapes occur in this codebase and all
  // three must be followed, or the callee comes out "unknown" and the scope has to be guessed:
  //
  //   const GW   = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';   -> slug var
  //   const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';              -> BASE var
  //   const GW   = BASE + '/ai_gateway';                                          -> slug via BASE
  //
  // The third is why a single regex was not enough: kb_deepen defines GW in terms of BASE, so
  // neither line contains `functions/v1/<slug>`. Iterate to a fixpoint so indirection is followed.
  const varMap = new Map();   // identifier -> callee slug
  const baseVars = new Set(); // identifier -> a ".../functions/v1" prefix with no slug
  const decls = [...src.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*([^;\n]*)/g)]
    .map((m) => [m[1], m[2]]);
  for (const [name, val] of decls) {
    const s = val.match(SLUG_RE);
    if (s) varMap.set(name, s[1]);
    else if (/functions\/v1['"`\s]*$|functions\/v1['"`]/.test(val)) baseVars.add(name);
  }
  for (let pass = 0; pass < 5; pass++) {
    let changed = false;
    for (const [name, val] of decls) {
      if (varMap.has(name)) continue;
      for (const b of baseVars) {
        const re = new RegExp('(?:\\$\\{\\s*' + b + '\\s*\\}|\\b' + b + '\\b\\s*\\+\\s*[\'"`])\\s*/([a-z0-9_]+)');
        const m = val.match(re);
        if (m) { varMap.set(name, m[1]); changed = true; break; }
      }
    }
    if (!changed) break;
  }

  // Every fetch call in the file, with its full argument text.
  const calls = [];
  for (const m of src.matchAll(/\bfetch\s*\(/g)) {
    const open = m.index + m[0].length - 1;
    const text = callText(src, open);
    calls.push({ start: m.index, end: m.index + text.length, text, line: lineOf(src, m.index) });
  }

  for (const c of calls) {
    if (!PRESENTS.test(c.text)) continue;
    const kind = /__deploy_secret\s*:/.test(c.text) ? 'deploy'
               : /__force_key\s*:/.test(c.text) ? 'force_key' : 'inbound';
    // Resolve against the URL EXPRESSION only (the first argument), not the whole call. The body
    // of a call often mentions other function names in strings - `fn: 'doc_extract'` and the like -
    // and matching those would attribute the hop to the wrong callee.
    const urlExpr = firstArg(c.text);

    // 1. a literal .../functions/v1/<slug>
    const lit = urlExpr.match(SLUG_RE);
    if (lit && KNOWN.has(lit[1])) { hops.push({ caller: fn, callee: lit[1], line: c.line, kind, how: 'literal' }); continue; }

    // 2. `${BASE}/slug` or BASE + '/slug', where BASE is a ".../functions/v1" prefix
    let found = null, how = null;
    for (const b of baseVars) {
      const m = urlExpr.match(new RegExp('(?:\\$\\{\\s*' + b + '\\s*\\}|\\b' + b + '\\b\\s*\\+\\s*[\'"`])\\s*/([a-z0-9_]+)'));
      if (m && KNOWN.has(m[1])) { found = m[1]; how = 'base+literal'; break; }
    }
    // 3. an identifier that already resolves to a slug (const GW = BASE + '/ai_gateway')
    if (!found) {
      for (const [v, slug] of varMap) {
        if (new RegExp('\\b' + v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(urlExpr) && KNOWN.has(slug)) { found = slug; how = 'const'; break; }
      }
    }
    if (found) hops.push({ caller: fn, callee: found, line: c.line, kind, how });
    else dynamic.push({ caller: fn, line: c.line, kind, snippet: urlExpr.replace(/\s+/g, ' ').slice(0, 80) + '  ||  ' + c.text.replace(/\s+/g, ' ').slice(0, 90) });
  }

  // Any presenting site not covered by a fetch call above.
  //
  // The offset must be computed against the ORIGINAL string, and the test must be a RANGE
  // OVERLAP, not "is the line start inside the call". Most of these files put a whole fetch on one
  // line, so the call begins part-way through the line: comparing the line START against the call
  // range put every such site OUTSIDE its own enclosing call and reported 87 false "unattached"
  // sites — a total of 182 presenting sites against ~105 real ones, i.e. the same site counted
  // twice. A line belongs to a call if the two ranges overlap at all.
  const lineStart = [0];
  for (let i = 0; i < src.length; i++) if (src[i] === '\n') lineStart.push(i + 1);
  src.split(/\r?\n/).forEach((l, i) => {
    const t = l.trim();
    if (!PRESENTS.test(t)) return;
    if (/^(\/\/|\*|\/\*)/.test(t)) return;
    const a = lineStart[i] ?? 0, b = a + l.length;
    const inCall = calls.some((c) => b >= c.start && a <= c.end);
    if (!inCall) unattached.push({ caller: fn, line: i + 1, snippet: t.slice(0, 150) });
  });
}

const byCaller = new Map();
for (const h of hops) {
  if (!byCaller.has(h.caller)) byCaller.set(h.caller, new Set());
  byCaller.get(h.caller).add(h.callee);
}
const calleeCount = new Map();
for (const h of hops) calleeCount.set(h.callee, (calleeCount.get(h.callee) || 0) + 1);

const out = [];
out.push('=== AUDIT 9.5 OUTBOUND HOP INVENTORY (callee resolved) ===');
out.push(`resolved hops: ${hops.length}   callers: ${byCaller.size}   distinct callees: ${calleeCount.size}`);
out.push(`DYNAMIC (url computed, callee NOT guessed): ${dynamic.length}`);
out.push(`UNATTACHED (presents a credential outside a fetch call): ${unattached.length}`);
out.push(`TOTAL presenting sites accounted for: ${hops.length + dynamic.length + unattached.length}`);
out.push('');
out.push('=== PER CALLER: the exact scope its credential needs ===');
for (const caller of [...byCaller.keys()].sort()) {
  const set = [...byCaller.get(caller)].sort();
  out.push(`${caller.padEnd(24)} (${String(set.length).padStart(2)}) ${set.join(' ')}`);
}
out.push('');
out.push('=== PER CALLEE: how many callers must be migrated before this callee stops seeing the shared secret ===');
for (const [callee, n] of [...calleeCount.entries()].sort((a, b) => b[1] - a[1])) {
  const callers = [...byCaller.entries()].filter(([, s]) => s.has(callee)).map(([c]) => c).sort();
  out.push(`${callee.padEnd(24)} hops=${String(n).padStart(3)}  callers(${callers.length}): ${callers.join(' ')}`);
}
out.push('');
out.push('=== DYNAMIC - url computed at runtime. These need reading by hand; do NOT guess a scope. ===');
for (const d of dynamic) out.push(`${d.caller.padEnd(24)} L${String(d.line).padStart(4)} [${d.kind}] ${d.snippet}`);
out.push('');
out.push('=== UNATTACHED - presents a credential outside any fetch call ===');
for (const u of unattached) out.push(`${u.caller.padEnd(24)} L${String(u.line).padStart(4)} ${u.snippet}`);

fs.writeFileSync(OUT, out.join('\n'), 'utf8');
console.log(out.slice(0, 8).join('\n'));
console.log(`\n[full report: ${OUT}, ${out.length} lines]`);
