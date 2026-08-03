// AUDIT 9.5 - second pass. The 16 gates the first codemod refused, in two families.
//
// FAMILY 1 (9): if (!secretOk(<VAR>) || [!body?.__secret ||] body.__secret !== <VAR>) { ...refuse... }
//   Same as pass one but the expected-secret variable is named differently in each file
//   (expected / secret / inbound / expectedSecret) rather than always __exp. A backreference
//   keeps the two halves tied together so a half-match cannot be rewritten.
//
// FAMILY 2 (7): inside an authed() helper -
//   if (body.__secret && body.__secret === (await sec('inbound_secret'))) return true;
//   This is a POSITIVE match with a JWT-admin fallback below it, so it is already fail-closed.
//   It becomes a positive match on the verifier instead, keeping the fallback intact.
//
// Both leave every surrounding line alone. Anything not matched is reported, not guessed at.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'C:/Users/Opera/quotesdone/supabase/functions';
const APPLY = process.argv.includes('--apply');
const TARGETS = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const IMPORT_LINE = "import { requireInternal } from '../_shared/internal_auth.ts';";

const F1 = /!secretOk\((\w+)\)\s*\|\|\s*(?:!\s*(?:body|b)\??\.__secret\s*\|\|\s*)?(body|b)\??\.__secret\s*!==\s*\1/;
const F2 = /(body|b)\??\.__secret\s*&&\s*(?:body|b)\??\.__secret\s*===\s*\(await sec\('inbound_secret'\)\)/;

const res = { f1: [], f2: [], skip: [], already: [] };

for (const fn of TARGETS) {
  const p = path.join(ROOT, fn, 'index.ts');
  if (!fs.existsSync(p)) { res.skip.push([fn, 'no file']); continue; }
  let src = fs.readFileSync(p, 'utf8');
  if (src.includes('requireInternal')) { res.already.push(fn); continue; }

  let m = src.match(F1);
  if (m) {
    const matched = m[0], bodyVar = m[2];
    const idx = src.indexOf(matched);
    const lineStart = src.lastIndexOf('\n', idx) + 1;
    const indent = (src.slice(lineStart, idx).match(/^\s*/) || [''])[0];
    const decl = `${indent}// AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new\n`
               + `${indent}// per-context credential and the legacy shared secret, and records which one called.\n`
               + `${indent}const __auth = await requireInternal(admin, ${bodyVar}?.__secret, '${fn}');\n`;
    src = src.slice(0, lineStart) + decl + src.slice(lineStart);
    src = src.replace(matched, '!__auth.ok');
    res.f1.push(fn);
  } else {
    m = src.match(F2);
    if (!m) { res.skip.push([fn, 'not recognised']); continue; }
    // Positive form: the helper returns true when the credential is good, and falls through to the
    // JWT-admin check when it is not. Preserved exactly - only what "good" means changes.
    src = src.replace(m[0], `(await requireInternal(admin, ${m[1]}?.__secret, '${fn}')).ok`);
    res.f2.push(fn);
  }

  const impRe = /^import .*['"]jsr:@supabase\/supabase-js@2['"];?$/m;
  if (impRe.test(src)) src = src.replace(impRe, (x) => x + '\n' + IMPORT_LINE);
  else src = IMPORT_LINE + '\n' + src;

  if (APPLY) fs.writeFileSync(p, src, 'utf8');
}

const out = [`mode: ${APPLY ? 'APPLY' : 'dry run'}`,
  `family1 (${res.f1.length}): ${res.f1.join(' ')}`,
  `family2 (${res.f2.length}): ${res.f2.join(' ')}`,
  `already (${res.already.length}): ${res.already.join(' ')}`,
  `SKIPPED (${res.skip.length}): ${res.skip.map(([f, w]) => f + '=' + w).join(' ')}`];
fs.writeFileSync('C:/Users/Opera/qd-check/migrate_gates2.out.txt', out.join('\n'), 'utf8');
console.log(out.join('\n'));
