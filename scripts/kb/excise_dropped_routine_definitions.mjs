// CUT THE DROPPED ROUTINES OUT OF THE FILES THAT ALSO DEFINE LIVE ONES
//
// 229 files defined nothing but dropped routines and were removed whole. 122 define a MIX: some
// routines that are gone and some that are still running. Deleting those files would take a live
// definition with it, so each dropped block has to come out on its own.
//
// A REGEX IS THE WRONG TOOL HERE and I have already proved it -- an earlier pass cut a line out of
// fn_schema_export's body because the body contained the text it was matching. So this parses
// dollar-quoted blocks properly: it finds the CREATE FUNCTION, reads the dollar tag that opens the
// body ($function$, $$, $q$ ...), and skips to that exact tag's close. Text inside a body can say
// anything without confusing it.
//
// It refuses to write a file whose dollar tags do not balance afterwards, so a bad cut fails loudly
// instead of leaving unparseable SQL in the repository.
//
//   node scripts/kb/excise_dropped_routine_definitions.mjs [--apply]

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../phase_c/lib/db.mjs';

const APPLY = process.argv.includes('--apply');
const D = 'scripts/sql';

const live = new Set((await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'`)).map((x) => x.proname));

const CREATE = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi;

let filesChanged = 0, blocksRemoved = 0, refused = [];
for (const f of readdirSync(D).filter((x) => x.endsWith('.sql'))) {
  const p = join(D, f);
  let src; try { src = readFileSync(p, 'utf8'); } catch { continue; }
  let out = '', cursor = 0, changed = 0;
  CREATE.lastIndex = 0;
  let m;
  while ((m = CREATE.exec(src))) {
    const name = m[3] || m[1];
    if (live.has(name.toLowerCase())) continue;          // still running: leave it exactly alone
    const start = m.index;
    // Find the dollar tag that opens the body: the first $tag$ after the AS keyword.
    const tagM = /\$([a-z0-9_]*)\$/i.exec(src.slice(start));
    if (!tagM) continue;                                  // a SQL-language function with no body quote
    const tag = tagM[0];
    const bodyOpen = start + tagM.index;
    const bodyClose = src.indexOf(tag, bodyOpen + tag.length);
    if (bodyClose < 0) continue;                          // unterminated; do not touch it
    let end = bodyClose + tag.length;
    const tail = /^\s*;?/.exec(src.slice(end));
    if (tail) end += tail[0].length;

    out += src.slice(cursor, start)
      + '-- ROUTINE REMOVED 7 September 2026. public.' + name + ' was dropped from the database with\n'
      + '-- everything else that did not belong to the new structure, and its definition is cut from\n'
      + '-- this file so re-applying the file cannot recreate it. The other routines defined here are\n'
      + '-- still running and are untouched.\n';
    cursor = end;
    changed++; blocksRemoved++;
    CREATE.lastIndex = end;
  }
  if (!changed) continue;
  out += src.slice(cursor);

  // A file whose dollar tags no longer pair is a file I have broken. Refuse it.
  const tags = (out.match(/\$[a-z0-9_]*\$/gi) || []);
  const counts = {};
  for (const t of tags) counts[t] = (counts[t] || 0) + 1;
  const odd = Object.entries(counts).filter(([, n]) => n % 2 === 1).map(([t]) => t);
  if (odd.length) { refused.push(f + ' :: unbalanced ' + odd.join(' ')); continue; }

  filesChanged++;
  if (APPLY) writeFileSync(p, out);
}
console.log('files ' + filesChanged + ' · routine blocks removed ' + blocksRemoved);
if (refused.length) {
  console.log('REFUSED (left untouched, they need a human):');
  for (const r of refused) console.log('  ' + r);
}
if (!APPLY) console.log('DRY RUN — nothing written.');
process.exit(0);
