// AUDIT 9.5 - move the inbound gate of every cron-reached edge function onto requireInternal().
//
// Deliberately MINIMAL. It replaces only the boolean CONDITION, leaving every existing refusal
// side-effect (logRun / logThrottled / bespoke agent_runs rows) exactly as it is, and leaving any
// `const __exp = await sec('inbound_secret')` line in place because later OUTBOUND calls in the
// same file still use it. Anything it cannot match with certainty is reported and left alone -
// a codemod that half-understands a gate is worse than one that refuses.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'C:/Users/Opera/quotesdone/supabase/functions';
const APPLY = process.argv.includes('--apply');
const TARGETS = process.argv.slice(2).filter((a) => !a.startsWith('--'));

const IMPORT_LINE = "import { requireInternal } from '../_shared/internal_auth.ts';";

// The condition shapes seen in production, most specific first. Each captures the request-body
// variable name, because these files are split roughly evenly between `body` and `b` and emitting
// the wrong one is a compile error rather than a silent bug - but only if we emit ONE of them.
// A `typeof body !== 'undefined' ? body : b` hedge does NOT work: TypeScript resolves both
// branches statically and fails on whichever name does not exist. (Learned the hard way.)
const CONDS = [
  // if (!secretOk(__exp) || !body.__secret || body.__secret !== __exp)
  /!secretOk\(__exp\)\s*\|\|\s*!(body|b)\.__secret\s*\|\|\s*(?:body|b)\.__secret\s*!==\s*__exp/,
  // if (!secretOk(__exp) || body.__secret !== __exp)      and the b./no-space variants
  /!secretOk\(__exp\)\s*\|\|\s*(body|b)\??\.__secret\s*!==\s*__exp/,
];

const results = { changed: [], skipped: [], already: [] };

for (const fn of TARGETS) {
  const p = path.join(ROOT, fn, 'index.ts');
  if (!fs.existsSync(p)) { results.skipped.push([fn, 'no file']); continue; }
  let src = fs.readFileSync(p, 'utf8');

  if (src.includes('requireInternal')) { results.already.push(fn); continue; }

  let matched = null, bodyVar = null;
  for (const re of CONDS) { const m = src.match(re); if (m) { matched = m[0]; bodyVar = m[1]; break; } }
  if (!matched) { results.skipped.push([fn, 'gate condition not recognised']); continue; }

  // Replace the condition with the verifier decision. The __auth const is declared immediately
  // before the if, so the existing refusal block is untouched.
  const idx = src.indexOf(matched);
  const lineStart = src.lastIndexOf('\n', idx) + 1;
  const indent = (src.slice(lineStart, idx).match(/^\s*/) || [''])[0];
  const decl = `${indent}// AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new\n`
             + `${indent}// per-context credential and the legacy shared secret, and records which one called.\n`
             + `${indent}const __auth = await requireInternal(admin, ${bodyVar}?.__secret, '${fn}');\n`;
  src = src.slice(0, lineStart) + decl + src.slice(lineStart);
  src = src.replace(matched, '!__auth.ok');

  // Import goes straight after the supabase-js import so it survives any later edits above it.
  const impRe = /^import .*['"]jsr:@supabase\/supabase-js@2['"];?$/m;
  if (impRe.test(src)) src = src.replace(impRe, (m) => m + '\n' + IMPORT_LINE);
  else src = IMPORT_LINE + '\n' + src;

  if (APPLY) fs.writeFileSync(p, src, 'utf8');
  results.changed.push(fn);
}

const out = [];
out.push(`mode: ${APPLY ? 'APPLY' : 'dry run'}`);
out.push(`changed  (${results.changed.length}): ${results.changed.join(' ')}`);
out.push(`already  (${results.already.length}): ${results.already.join(' ')}`);
out.push(`SKIPPED  (${results.skipped.length}):`);
for (const [f, why] of results.skipped) out.push(`   ${f.padEnd(26)} ${why}`);
fs.writeFileSync('C:/Users/Opera/qd-check/migrate_gates.out.txt', out.join('\n'), 'utf8');
console.log(out.join('\n'));
