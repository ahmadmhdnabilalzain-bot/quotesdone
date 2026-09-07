// REMOVE THE SQL FILES WHOSE ROUTINES NO LONGER EXIST
//
// Dropping 673 routines from the database leaves their canonical files in scripts/sql, and the
// routine manifest reports every one as "canonical body not deployed". That is the check doing its
// job: a file that defines something nothing runs is how a deleted thing comes back, because the
// next person to apply that file recreates it.
//
// A FILE IS ONLY REMOVED WHEN EVERY ROUTINE IT DEFINES IS GONE. Many files define several routines
// and some of those survive; deleting such a file would take the surviving definition with it, so
// those are listed as MIXED and left alone for a human decision rather than guessed at.
//
// The MANIFEST.txt lines for removed files go too, otherwise the manifest points at files that are
// no longer there.
//
//   node scripts/kb/remove_files_for_dropped_routines.mjs [--apply]

import { readFileSync, writeFileSync, unlinkSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../phase_c/lib/db.mjs';

const APPLY = process.argv.includes('--apply');
const D = 'scripts/sql';

const live = new Set((await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'`)).map((x) => x.proname));

const files = readdirSync(D).filter((f) => f.endsWith('.sql'));
const DEF = /create\s+(or\s+replace\s+)?function\s+(public\.)?"?([a-z0-9_]+)"?\s*\(/gi;

let removable = [], mixed = [], untouched = 0;
for (const f of files) {
  let src;
  try { src = readFileSync(join(D, f), 'utf8'); } catch { continue; }
  const defined = new Set();
  let m; DEF.lastIndex = 0;
  while ((m = DEF.exec(src))) defined.add(m[3].toLowerCase());
  if (defined.size === 0) { untouched++; continue; }              // defines no routine; not ours to judge
  const gone = [...defined].filter((n) => !live.has(n));
  if (gone.length === 0) { untouched++; continue; }               // everything it defines still exists
  if (gone.length === defined.size) removable.push({ f, n: defined.size });
  else mixed.push({ f, gone: gone.length, kept: defined.size - gone.length });
}

console.log('files defining routines that are all gone : ' + removable.length);
console.log('files defining a MIX of gone and kept     : ' + mixed.length + '  (left alone)');
console.log('files untouched                           : ' + untouched);
for (const x of mixed.slice(0, 15)) console.log('  MIXED ' + x.f + '  (' + x.gone + ' gone, ' + x.kept + ' kept)');

if (!APPLY) { console.log('\nDRY RUN — nothing removed.'); process.exit(0); }

const manifestPath = join(D, 'MANIFEST.txt');
let manifest = readFileSync(manifestPath, 'utf8').split('\n');
let removed = 0;
for (const { f } of removable) {
  try { unlinkSync(join(D, f)); removed++; } catch { /* already gone */ }
  manifest = manifest.filter((l) => l.trim() !== 'scripts/sql/' + f);
}
writeFileSync(manifestPath, manifest.join('\n'));
console.log('removed ' + removed + ' file(s); MANIFEST.txt rewritten to ' + manifest.filter((l) => l.trim()).length + ' line(s)');
process.exit(0);
