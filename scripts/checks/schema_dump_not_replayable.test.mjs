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
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const dumpPath = join(root, 'supabase', 'schema', 'full_schema.sql');
const dump = readFileSync(dumpPath, 'utf8');

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
    'full_schema.sql contains ' + dangerous.length + ' line(s) that fetch inbound_secret from app_secrets, but ' +
    'carries no banner saying so. Anyone rebuilding from it would silently undo the credential separation.');
  assert.match(dump.slice(0, 3000), /replay supabase\/migrations\/ in order/,
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

test('the live migration set is the thing that can be replayed', () => {
  // The claim the header makes has to be true, or it is just moving the trap. final_sync_check.mjs
  // asserts every applied migration has a file; this asserts the directory it points at is real.
  const files = readdirSync(join(root, 'supabase', 'migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(files.length > 100,
    'supabase/migrations contains only ' + files.length + ' files, so the header is directing a rebuild at a set ' +
    'that cannot possibly be complete.');
});

test('the dump says when it was captured and where the real rebuild path is', () => {
  // Permanent, unlike the two above. What made the 2 Aug file dangerous was not the secret
  // references by themselves - it was that nothing in the file let a reader tell how old it was or
  // what to use instead. Regenerating by any route that drops this header fails here, loudly,
  // instead of quietly restoring the original trap.
  const head = dump.slice(0, 3000);
  assert.match(head, /Captured \d{4}-\d{2}-\d{2}T[\d:.]+Z/,
    'full_schema.sql does not state its capture time, so nobody can tell whether it is current. ' +
    'Regenerate with: node C:/Users/Opera/qd-check/regen_schema.mjs --apply');
  assert.match(head, /replay supabase\/migrations\/ in order/,
    'full_schema.sql does not name the supported rebuild path, so a reader who needs to restore a ' +
    'database is left pointing at this file - which is exactly the failure this guard exists for.');
});
