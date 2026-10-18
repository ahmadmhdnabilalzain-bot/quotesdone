// EXPORT EVERY SEAT'S PLAYBOOK FOR AN AUDITOR. Seat: it_engineer. Founder instruction 1013 item 9, 29 Sep 2026.
//
// The playbook lives in public.seat_playbook (scripts/sql/every_seat_keeps_a_living_playbook.sql) and is
// rebuilt by the database whenever a lesson is recorded. This writes each one to
// docs/seats/<seat>_playbook.md, byte for byte as the database holds it.
//
//   node scripts/seats/export_playbooks.mjs            # write the files from production
//   node scripts/seats/export_playbooks.mjs --check    # exit 1 if a committed file differs from production
//   node scripts/seats/export_playbooks.mjs --dry      # before the apply: build the playbooks inside ONE
//                                                      # aborted transaction (the SQL file, then a raise
//                                                      # carrying the Markdown) and write the files; nothing
//                                                      # is left in the database
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const outDir = join(root, 'docs', 'seats');
const args = process.argv.slice(2);

async function fromDatabase() {
  const rows = await sql('select seat, markdown from public.seat_playbook order by seat', { readOnly: true });
  return Object.fromEntries(rows.map((r) => [r.seat, r.markdown]));
}

async function fromDryRun() {
  const files = ['every_handoff_carries_a_note_of_what_is_known_tried_and_needed.sql', 'every_seat_keeps_a_living_playbook.sql']
    .map((f) => readFileSync(join(root, 'scripts', 'sql', f), 'utf8'));
  // Through scripts/lib/safe_replay.mjs: the files are replayed and rolled back, the playbooks come back as the
  // rows of the last query (read from the untruncated answer), and nothing the files create survives. No retry:
  // a DDL batch must never be re-issued concurrently.
  const [row] = await replaySql(files.join('\n') + '\n;\nselect jsonb_object_agg(seat, markdown) as books from public.seat_playbook;',
    { rows: true, retry: false, label: 'the playbook dry run' });
  return row?.books ?? {};
}

const books = args.includes('--dry') ? await fromDryRun() : await fromDatabase();
if (!Object.keys(books).length) { console.error('no playbook in public.seat_playbook'); process.exit(1); }
mkdirSync(outDir, { recursive: true });
let differ = 0;
for (const [seat, md] of Object.entries(books)) {
  const path = join(outDir, `${seat}_playbook.md`);
  if (args.includes('--check')) {
    const same = existsSync(path) && readFileSync(path, 'utf8') === md;
    if (!same) { differ++; console.error(`DIFFERS: docs/seats/${seat}_playbook.md`); }
  } else {
    writeFileSync(path, md);
    console.log(`wrote docs/seats/${seat}_playbook.md (${md.length} chars)`);
  }
}
if (differ) process.exit(1);
