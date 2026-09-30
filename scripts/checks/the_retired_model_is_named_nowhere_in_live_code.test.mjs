// THE RETIRED MODEL IS NAMED NOWHERE IN LIVE CODE (it_engineer, 30 Sep 2026).
//
// The founder, founder_instruction 1068: "[the model] shouldn't be anywhere in the code." The model he ruled in for
// routine work on 23 Sep (841) had 0 routes after his model matrix (1056), yet its name survived in a shared
// module, nine routine names, a table, a queue mark, the review router's last-resort families and a dozen checks
// and fixtures. scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql
// renamed or replaced every one of them (and put a live matrix model in every slot where it was a choice).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * the name appears in any file under the live code paths below - edge functions, the app, the checks,
//     the script libraries and the evals;
//   * the name appears in a routine body or name on production (read live when a management token exists),
//     or anywhere in the committed schema mirror of production.
// NOT SCANNED, ON PURPOSE: scripts/sql (the applied history - an applied file is a record and is never
// edited), lock files and binary assets (hashes and base64 contain any three letters sooner or later).
// While the retiring file is still pending (its note is in scripts/sql/pending/), production and the mirror
// still hold the old names by definition, so that half reports and waits; the moment the note is deleted at
// apply, it is strict.
//
// The pattern is assembled, never spelled, so this file and its messages cannot match themselves.
//
//   node --test scripts/checks/the_retired_model_is_named_nowhere_in_live_code.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const NAME = new RegExp(['g', 'l', 'm'].join(''), 'i');
const LIVE_DIRS = ['supabase/functions', 'src', 'scripts/checks', 'scripts/lib', 'scripts/eval'];
const TEXT = new Set(['.ts', '.tsx', '.js', '.mjs', '.cjs', '.jsx', '.json', '.sql', '.css', '.html', '.md', '.txt', '.yml', '.yaml', '.toml']);
const RETIRING = 'the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does';
const PENDING = existsSync(join(REPO, 'scripts/sql/pending', `${RETIRING}.txt`));

function* files(dir) {
  if (!existsSync(dir)) return;
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) yield* files(p);
    else if (TEXT.has(extname(e).toLowerCase())) yield p;
  }
}

const hits = (text) => text.split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => NAME.test(l));

test('the pattern catches the name in every spelling it was written in (positive control)', () => {
  for (const s of ['z-ai/' + 'g' + 'lm-5.3-flash', 'fn_' + 'g' + 'lm_sender_known', 'G' + 'LM 5.3 Flash', 'drain' + 'G' + 'lm']) {
    assert.ok(NAME.test(s), `the guard would miss ${s}`);
  }
  assert.ok(!NAME.test('routine_judgement google/gemini-3.8-flash deepseek/deepseek-v4.1-flash'));
});

test('no live code path names the retired model', () => {
  const found = [];
  for (const d of LIVE_DIRS) {
    for (const f of files(join(REPO, d))) {
      for (const [n, l] of hits(readFileSync(f, 'utf8'))) found.push(`${relative(REPO, f).replace(/\\/g, '/')}:${n}: ${l.trim().slice(0, 120)}`);
    }
  }
  assert.deepEqual(found, [], 'the retired model (founder_instruction 1068) is named in live code. Rename it to what it '
    + 'does, or where it was a model choice put the matrix model in its place (founder_instruction 1056):\n  ' + found.join('\n  '));
});

test('the committed schema mirror of production names it in no object', () => {
  const dir = join(REPO, 'supabase/schema/full_schema');
  const found = [];
  for (const f of files(dir)) for (const [n, l] of hits(readFileSync(f, 'utf8'))) found.push(`${relative(REPO, f)}:${n}: ${l.trim().slice(0, 100)}`);
  if (PENDING) { console.log(`WAITING (not a finding): ${RETIRING}.sql is pending, so the mirror still holds ${found.length} line(s).`); return; }
  assert.deepEqual(found, [], 'the schema mirror of production still names the retired model:\n  ' + found.join('\n  '));
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: no routine is named after it or carries it in its body', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname ~* '${NAME.source}' or p.prosrc ~* '${NAME.source}') order by 1`, { readOnly: true });
  if (PENDING) { console.log(`WAITING (not a finding): ${RETIRING}.sql is pending; ${rows.length} live routine(s) still name it.`); return; }
  assert.deepEqual(rows.map((r) => r.sig), [], 'a live routine names the retired model');
});
