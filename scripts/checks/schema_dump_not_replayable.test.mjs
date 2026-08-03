// A stale schema dump that looks current is worse than no schema dump.
//
// supabase/schema/full_schema.sql was captured on 2 August 2026. Fifty-one migrations have been
// applied since, including the whole Audit 9.5 credential separation, and the file still contains
// ~199 references to `inbound_secret` - among them the wa_flush cron, whose live counterpart moved to
// cred_cron_notifications on 3 August. Replaying it would put cron jobs and database functions back
// on the single shared secret and undo WI-001 / spec_backlog#201 in one command, with nothing
// failing to announce it.
//
// The header said only "a faithful reference mirror, not a guaranteed one-click restore" - true, and
// not remotely alarming enough for what it would actually do.
//
// This guard is self-retiring by design: it demands the banner ONLY while the file still carries the
// thing that makes it dangerous. Regenerate the dump, and both the reference and the requirement to
// warn about it disappear together.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const dumpPath = join(root, 'supabase', 'schema', 'full_schema.sql');
const dump = readFileSync(dumpPath, 'utf8');

// The two protective functions legitimately NAME inbound_secret in a string array; they do not use it
// to authenticate. Everything else is a caller that would be reverted onto the shared secret.
const dangerous = dump
  .split('\n')
  .filter((l) => l.includes('inbound_secret'))
  .filter((l) => !/gate_keys|protected text\[\]|'content_secret'|'deploy_secret'/.test(l))
  .filter((l) => !l.trim().startsWith('--'));

test('a dump that still wires callers to the shared secret says so at the top', () => {
  if (dangerous.length === 0) return;   // regenerated: nothing to warn about, guard retires itself
  assert.match(dump.slice(0, 3000), /STALE\. DO NOT REPLAY THIS FILE\./,
    'full_schema.sql still contains ' + dangerous.length + ' line(s) that authenticate with inbound_secret, but ' +
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
  // The claim the banner makes has to be true, or it is just moving the trap. final_sync_check.mjs
  // asserts every applied migration has a file; this asserts the directory it points at is real.
  const files = readdirSync(join(root, 'supabase', 'migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(files.length > 100,
    'supabase/migrations contains only ' + files.length + ' files, so the banner is directing a rebuild at a set ' +
    'that cannot possibly be complete.');
});
