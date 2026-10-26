// REMOVE EVERY CRON SCHEDULE FROM THE CODE
//
// Founder, 7 September 2026: "there shouldn't be any job in the code except the stuff that I
// literally told you for the CEO. Nothing else... whatever is there, delete it... Remove it from the
// code. Delete, not archive. Delete. I don't wanna see it anywhere." The WhatsApp / customer support
// agent's job is kept, on hold.
//
// 234 of the 235 jobs were deleted from the database. This removes the code that would recreate
// them, because a deleted job whose CREATE statement is still in the repo comes back the moment
// anyone re-applies that file -- which is precisely how an estate accumulates 235 of them.
//
// WHAT IT TOUCHES: every cron.schedule(...) statement in scripts/sql, and every cron.unschedule that
// paired with one. Each is replaced by a single line saying it was removed and why, so a reader of
// that file learns what happened rather than finding a silent gap.
//
// WHAT IT DOES NOT TOUCH:
//   * wa_flush, the WhatsApp send for the customer support agent.
//   * supabase/migrations_history -- that is the applied history of this database. Editing it would
//     rewrite the record of what was actually run on which day, which is falsification, not cleanup.
//     Nothing re-applies it.
//
//   node scripts/kb/strip_cron_schedules.mjs [--apply]

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const APPLY = process.argv.includes('--apply');
const KEEP = /wa_flush/;

const files = execSync('grep -rl "cron\\.schedule(\\|cron\\.unschedule(" scripts/sql/*.sql', { encoding: 'utf8' })
  .split('\n').filter(Boolean);

let filesChanged = 0, stmtsRemoved = 0, kept = 0;
const NOTE = '-- CRON SCHEDULE REMOVED 7 September 2026 on the founder\'s instruction: "there shouldn\'t be\n'
           + '-- any job in the code except the stuff that I literally told you for the CEO... Remove it from\n'
           + '-- the code. Delete, not archive." The job it created was deleted from the database in the same\n'
           + '-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely\n'
           + '-- by each build adding one and nothing ever removing one.';

for (const f of files) {
  const src = readFileSync(f, 'utf8');
  const lines = src.split('\n');
  const out = [];
  let i = 0, changedHere = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!/cron\.(schedule|unschedule)\(/.test(line)) { out.push(line); i++; continue; }
    // Collect the whole statement: from this line to the one ending in a semicolon.
    const start = i;
    let stmt = line;
    while (!/;\s*$/.test(lines[i]) && i + 1 < lines.length) { i++; stmt += '\n' + lines[i]; }
    i++;
    if (KEEP.test(stmt)) { for (let k = start; k < i; k++) out.push(lines[k]); kept++; continue; }
    if (changedHere === 0) out.push(NOTE);
    changedHere++; stmtsRemoved++;
  }
  if (changedHere > 0) {
    filesChanged++;
    if (APPLY) writeFileSync(f, out.join('\n'));
    console.log((APPLY ? 'stripped ' : 'would strip ') + String(changedHere).padStart(3) + '  ' + f);
  }
}
console.log('\nfiles ' + filesChanged + ' · statements ' + stmtsRemoved + ' · kept (wa_flush) ' + kept);
if (!APPLY) console.log('DRY RUN — nothing written. Re-run with --apply.');
