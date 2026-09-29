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
import { homedir } from 'node:os';
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
  const q = files.join('\n') + `\ndo $x$ begin raise exception 'PLAYBOOKS<<%>>',
    (select jsonb_object_agg(seat, markdown) from public.seat_playbook)::text; end $x$;`;
  // Direct, not through lib/db.mjs: that helper cuts an error body at 2,000 characters and the
  // playbooks travel IN the error. No retry: a DDL batch must never be re-issued concurrently.
  const tok = process.env.SUPABASE_ACCESS_TOKEN?.trim()
    || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim();
  // A 429 is refused at the gateway before anything runs, so only that is retried, serially.
  let res;
  for (let attempt = 0; attempt < 7; attempt++) {
    res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: q }),
    });
    if (res.status !== 429) break;
    await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt));
  }
  const text = await res.text();
  let msg = text;
  try { msg = JSON.parse(text).message ?? text; } catch { /* keep the raw body */ }
  const m = /PLAYBOOKS<<([\s\S]*)>>/.exec(msg);
  if (m) return JSON.parse(m[1]);
  throw new Error(`the dry run did not return the playbooks: HTTP ${res.status} ${String(msg).slice(0, 500)}`);
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
