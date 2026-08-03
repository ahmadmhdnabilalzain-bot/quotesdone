// AUDIT 9.5 pass 3 - the gate shapes passes 1 and 2 refused.
//
// Pass 1/2 only understood `!secretOk(__exp) || body.__secret !== __exp`, i.e. a hard gate whose
// expected value lived in a variable literally named __exp. Three other shapes exist in production
// and are handled here. Anything else is still refused rather than guessed at.
//
// RULE A  hard gate, expected value in a differently-named local:
//           if (!secretOk(inbound) || body.__secret !== inbound) ...
// RULE A2 hard gate, expected value read as a row:
//           if (!sec?.value || body.__secret !== sec.value) ...
// RULE B  PRIVILEGE ELEVATION, not a gate:
//           if (body.__secret && body.__secret === (await sec('inbound_secret'))) authed = true;
//         These fall through to JWT/other auth when the secret is absent, so the rewrite MUST keep
//         the `body.__secret &&` short-circuit - both to preserve semantics and so an ordinary
//         unauthenticated request does not pay for a verifier round trip.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'C:/Users/Opera/quotesdone/supabase/functions';
const APPLY = process.argv.includes('--apply');
const TARGETS = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const IMPORT_LINE = "import { requireInternal } from '../_shared/internal_auth.ts';";

const RULE_A  = /!secretOk\((\w+)\)\s*\|\|\s*(body|b)\??\.__secret\s*!==\s*\1\b/;
const RULE_A2 = /!(\w+)\?\.value\s*\|\|\s*(body|b)\??\.__secret\s*!==\s*\1\.value/;
const RULE_B  = /(body|b)\??\.__secret\s*&&\s*(?:body|b)\??\.__secret\s*===\s*\(\s*await sec\(\s*'inbound_secret'\s*\)\s*\)/g;

const results = { changed: [], skipped: [], already: [] };

function addImport(src) {
  if (src.includes(IMPORT_LINE)) return src;
  const impRe = /^import .*['"]jsr:@supabase\/supabase-js@2['"];?$/m;
  return impRe.test(src) ? src.replace(impRe, (m) => m + '\n' + IMPORT_LINE) : IMPORT_LINE + '\n' + src;
}

function declareBefore(src, matched, bodyVar, fn) {
  const idx = src.indexOf(matched);
  const lineStart = src.lastIndexOf('\n', idx) + 1;
  const indent = (src.slice(lineStart, idx).match(/^\s*/) || [''])[0];
  const decl = `${indent}// AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new\n`
             + `${indent}// per-context credential and the legacy shared secret, and records which one called.\n`
             + `${indent}const __auth = await requireInternal(admin, ${bodyVar}?.__secret, '${fn}');\n`;
  return src.slice(0, lineStart) + decl + src.slice(lineStart);
}

for (const fn of TARGETS) {
  const p = path.join(ROOT, fn, 'index.ts');
  if (!fs.existsSync(p)) { results.skipped.push([fn, 'no file']); continue; }
  let src = fs.readFileSync(p, 'utf8');
  if (src.includes('requireInternal')) { results.already.push(fn); continue; }
  if (!/^\s*const\s+admin\s*=\s*createClient\(/m.test(src)) {
    results.skipped.push([fn, 'service-role client is not named "admin"']); continue;
  }

  let rule = null;
  const mA = src.match(RULE_A), mA2 = src.match(RULE_A2);

  if (mA) {
    rule = 'A';
    src = declareBefore(src, mA[0], mA[2], fn).replace(mA[0], '!__auth.ok');
  } else if (mA2) {
    rule = 'A2';
    src = declareBefore(src, mA2[0], mA2[2], fn).replace(mA2[0], '!__auth.ok');
  }

  // Rule B can co-exist with A/A2 in the same file, and can occur more than once.
  const bCount = (src.match(RULE_B) || []).length;
  if (bCount) {
    rule = rule ? rule + '+B' : 'B';
    src = src.replace(RULE_B, (_m, v) => `${v}?.__secret && (await requireInternal(admin, ${v}.__secret, '${fn}')).ok`);
  }

  if (!rule) { results.skipped.push([fn, 'no recognised shape - needs hand work']); continue; }
  src = addImport(src);
  if (APPLY) fs.writeFileSync(p, src, 'utf8');
  results.changed.push(`${fn}[${rule}${bCount ? 'x' + bCount : ''}]`);
}

const out = [];
out.push(`mode: ${APPLY ? 'APPLY' : 'dry run'}`);
out.push(`changed  (${results.changed.length}): ${results.changed.join(' ')}`);
out.push(`already  (${results.already.length}): ${results.already.join(' ')}`);
out.push(`SKIPPED  (${results.skipped.length}):`);
for (const [f, why] of results.skipped) out.push(`   ${f.padEnd(24)} ${why}`);
fs.writeFileSync('C:/Users/Opera/qd-check/migrate_gates_pass3.out.txt', out.join('\n'), 'utf8');
console.log(out.join('\n'));
