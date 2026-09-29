// A stale schema dump that looks current is worse than no schema dump.
//
// The 2 August 2026 capture sat in the repo while fifty-one migrations landed, including the whole
// Audit 9.5 credential separation. It still contained 61 lines that fetched `inbound_secret` from
// app_secrets - among them the wa_flush cron, whose live counterpart moved to
// cred_cron_notifications on 3 August. Replaying it would have put cron jobs and database functions
// back on the single shared secret and undone WI-001 / spec_backlog#201 in one command, with nothing
// failing to announce it. The header said only "a faithful reference mirror, not a guaranteed
// one-click restore" - true, and not remotely alarming enough for what it would actually do.
//
// Regenerated 4 August 2026 from public.fn_schema_export(); zero such lines remain, and the live
// database has zero cron jobs matching key='inbound_secret'.
//
// Tests 1 and 2 are self-retiring by design: they demand a banner ONLY while the file still carries
// the thing that makes it dangerous. Test 4 is a permanent ratchet - however the file is
// regenerated, it has to keep saying when it was captured and what the real rebuild path is.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { allMigrations } from './_migration_files.mjs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const dump = readSchemaMirror();

// A line is dangerous when it RETRIEVES the shared secret's value, which is the only form that
// re-wires a caller onto it. Two other shapes MENTION the key without using it and must not be
// counted, or the guard cries wolf forever and gets deleted:
//   - fn_protect_gate_secrets lists 'inbound_secret' in a multi-line gate_keys array, to protect it;
//   - v_internal_secret_migration_progress quotes key\s*=\s*''inbound_secret'' inside a regex, to
//     DETECT jobs still on it. A detector that trips its own alarm is the wrong shape of guard.
// The earlier filter exempted these by matching `gate_keys` on the same line, which only worked
// while the array literal happened to be one line long.
const dangerous = dump.split('\n').filter((l) => {
  if (l.trim().startsWith('--')) return false;
  if (/\\s\*/.test(l)) return false;
  return /key\s*=\s*'inbound_secret'/.test(l) || (/app_secrets/.test(l) && /'inbound_secret'/.test(l));
});

test('a dump that still wires callers to the shared secret says so at the top', () => {
  if (dangerous.length === 0) return;   // regenerated: nothing to warn about, guard retires itself
  assert.match(dump.slice(0, 3000), /STALE\. DO NOT REPLAY THIS FILE\./,
    'the schema mirror contains ' + dangerous.length + ' line(s) that fetch inbound_secret from app_secrets, but ' +
    'carries no banner saying so. Anyone rebuilding from it would silently undo the credential separation.');
  assert.match(dump.slice(0, 3000), /managed backups \/ PITR/,
    'the banner does not name the correct way to rebuild, so it warns without helping.');
});

test('the banner names the specific damage, not just "may be out of date"', () => {
  if (dangerous.length === 0) return;
  const head = dump.slice(0, 3000);
  assert.match(head, /wa_flush/,
    'the banner does not name a concrete example. "May be stale" is ignorable; "would put wa_flush back on the ' +
    'shared secret" is not.');
  assert.match(head, /WI-001|spec_backlog#201/,
    'the banner does not say which work item replaying it would undo.');
});

test('the header does not point a rebuild at the migration set', () => {
  // REWRITTEN 5 Aug 2026. This used to assert `files.length > 100`, which passes at 285 while 466
  // of the 712 applied migrations are absent and 272 of 403 tables are never created by the set.
  // It could only fail if someone deleted four fifths of the directory, so it measured nothing and
  // read as evidence that the rebuild claim had been checked.
  //
  // The load-bearing claim is the opposite one: the header must NOT send a reader to
  // supabase/migrations/ for a rebuild, because that set cannot do it.
  assert.doesNotMatch(dump.slice(0, 3000), /replay supabase\/migrations\/ in order/,
    'the schema mirror directs rebuilds at supabase/migrations/, which holds 285 of 712 applied ' +
    'migrations and creates 131 of 403 tables. Measure with scripts/verify_repo_production_parity.mjs.');
  // And the history must not silently shrink either - that would be a different defect.
  //
  // COUNTED ACROSS BOTH DIRECTORIES since the squash of 8 Aug 2026. supabase/migrations/ is now the
  // generated replay path (a baseline a fresh database can actually be built from, proven by the
  // Supabase Preview check building 411 tables from empty); supabase/migrations_history/ holds the
  // 736 real migrations, applied by nothing and kept for the record.
  //
  // The ratchet is unchanged in what it protects: migrations are append-only history and none may
  // vanish. Counting only the replay path after the move would have read 2 and failed on a
  // relocation, and narrowing it to that path to make it pass would have retired the guard while
  // appearing to keep it. Both directories is the population the claim was always about.
  const files = allMigrations();
  assert.ok(files.length >= 285,
    'migrations dropped to ' + files.length + ' files from 285 across supabase/migrations and ' +
    'supabase/migrations_history; migrations are append-only history.');
});

test('every section header ends its own line', () => {
  // 14 Sep 2026. fn_schema_export wrote the TABLES header with its closing literal missing the E
  // prefix, so the header carried a two-character backslash-n instead of a line break and the first
  // CREATE TABLE of the section (accountant_issued_document; action_class_gate before it) sat inside
  // the comment. Every restore and every check reading the mirror silently lost that table.
  // The shape: a "-- =====" header line with a backslash immediately followed by n anywhere on it.
  const bad = dump.split('\n').filter((l) => l.startsWith('-- =====') && l.includes('\\' + 'n'));
  assert.deepEqual(bad, [],
    'a section header in the schema mirror runs onto the next statement through a literal backslash-n, ' +
    'so that statement is commented out. Fix the literal in fn_schema_export (it needs an E prefix).');
});

test('the dump says when it was captured and where the real rebuild path is', () => {
  // Permanent, unlike the two above. What made the 2 Aug file dangerous was not the secret
  // references by themselves - it was that nothing in the file let a reader tell how old it was or
  // what to use instead. Regenerating by any route that drops this header fails here, loudly,
  // instead of quietly restoring the original trap.
  const head = dump.slice(0, 3000);
  assert.match(head, /Captured \d{4}-\d{2}-\d{2}T[\d:.]+Z/,
    'the schema mirror does not state its capture time, so nobody can tell whether it is current. ' +
    'Regenerate with: node C:/Users/Opera/qd-check/regen_schema.mjs --apply');
  // Was /replay supabase\/migrations\/ in order/ until 5 Aug 2026 — this ratchet REQUIRED the false
  // claim to be present, so correcting the header turned npm test red. A guard that pins a lie in
  // place is worse than no guard: it makes the honest fix look like the regression.
  assert.match(head, /managed backups \/ PITR/,
    'the schema mirror does not name a restore path that actually works, so a reader who needs to ' +
    'restore a database is left pointing at a file or a directory that cannot do it.');
});
