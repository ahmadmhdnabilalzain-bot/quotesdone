import { readFileSync, writeFileSync } from 'node:fs';
const p = 'scripts/phase_d/build_migration_rollback_classification.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 60)}`); s = s.replace(o, n); };

rep(`export function classify(file) {`,
`// WHICH FILE INTRODUCED A ROUTINE. \`create or replace function\` reads the same whether it is the
// first definition or the ninth, and the two need opposite rollbacks: a REPLACEMENT is reversed by
// re-applying the predecessor, and an INTRODUCTION is reversed by dropping the routine, because
// there is no predecessor to restore. A routine that appears in exactly one phase_d file was
// introduced by that file — measured from the corpus rather than assumed from the file's name.
const DEFINES = /^create (?:or replace )?function\\s+(public\\.[a-z0-9_]+)\\s*\\(([^)]*)\\)/gmi;
const definedIn = new Map();   // routine -> [file, ...]
const signature = new Map();   // routine -> the argument list as written
for (const f of FILES) {
  const text = readFileSync(\`\${DIR}/\${f}\`, 'utf8');
  for (const m of text.matchAll(DEFINES)) {
    const name = m[1].toLowerCase();
    if (!definedIn.has(name)) definedIn.set(name, []);
    if (!definedIn.get(name).includes(f)) definedIn.get(name).push(f);
    if (!signature.has(name)) signature.set(name, m[2].replace(/\\s+/g, ' ').trim());
  }
}
/** Routines this file is the only definer of — the ones its rollback has to drop. */
export function introducedBy(file) {
  const text = readFileSync(\`\${DIR}/\${file}\`, 'utf8');
  const out = [];
  for (const m of text.matchAll(DEFINES)) {
    const name = m[1].toLowerCase();
    if (definedIn.get(name).length === 1 && !out.some(x => x.name === name)) {
      out.push({ name, args: m[2].replace(/\\s+/g, ' ').trim() });
    }
  }
  return out;
}

export function classify(file) {`);

rep(`  else if (dropFunction) cls = 'ROUTINE_SIGNATURE_CHANGE';`,
`  else if (dropFunction) cls = 'ROUTINE_SIGNATURE_CHANGE';
  // A file that is the only definer of a routine INTRODUCED it. Re-applying a predecessor cannot
  // reverse that — there is no predecessor — so the reversal is a named drop, and the file needs a
  // down script exactly as one that created a table does.
  else if (introduced.length) cls = 'ROUTINE_INTRODUCED';`);

rep(`  const stem = file.replace(/\\.sql$/, '');`,
`  const introduced = introducedBy(file);
  const stem = file.replace(/\\.sql$/, '');`);

rep(`  const downNeeded = cls === 'EXPLICIT_DOWN_REQUIRED' || cls === 'IRREVERSIBLE_WITH_FOUNDER_APPROVAL';`,
`  const downNeeded = cls === 'EXPLICIT_DOWN_REQUIRED' || cls === 'IRREVERSIBLE_WITH_FOUNDER_APPROVAL'
    || cls === 'ROUTINE_INTRODUCED' || introduced.length > 0;`);

rep(`    routines, additive_ddl: ddl.join(', ') || 'none',`,
`    routines, routines_introduced: introduced.map(x => x.name).join(' ') || 'none',
    additive_ddl: ddl.join(', ') || 'none',`);

writeFileSync(p, s);
console.log('patched');
