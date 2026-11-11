// The same message to the same person is sent once (founder ruling 1631, 11 Nov 2026). Measured: 6 seed-list emails were
// sent twice 42 s apart on 10 Nov, and 0 of 731 notifications in 30 days carried a dedupe_key. Two guards, both code:
//   - at send time: _shared/outbox_duplicate_guard.ts in send_outbox and send_whatsapp (deno tests prove the behaviour);
//   - at insert time: the a00 trigger in scripts/sql/notifications_refuse_the_same_message_to_the_same_person_within_the_window.sql.
// This fails if the trigger loses its order, its pinned search_path or its revoke, or if its probe stops raising.
// Offline. Assigned: it_engineer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SQL = fileURLToPath(new URL('../sql/', import.meta.url));
const NAME = 'notifications_refuse_the_same_message_to_the_same_person_within_the_window';

test('the insert guard runs first, is SECURITY DEFINER with a pinned search_path, and is closed to callers', () => {
  const s = readFileSync(SQL + NAME + '.sql', 'utf8');
  assert.match(s, /create trigger a00_notifications_the_same_message_is_sent_once\s+before insert on public\.notifications/);
  assert.match(s, /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(s, /revoke execute on function public\.fn_notifications_the_same_message_is_sent_once\(\) from public, anon, authenticated;/);
  assert.match(s, /new\.status := 'cancelled'/, 'the repeat is kept and cancelled, never deleted (ruling 1634)');
  assert.match(s, /pg_advisory_xact_lock/, 'two identical inserts at once serialise');
  assert.match(s, /'PROBE OK' end as verdict;\s*$/);
});

test('its probe is pure: it writes only to a reserved address and always raises', () => {
  const p = readFileSync(SQL + NAME + '_probe.sql', 'utf8');
  assert.match(p, /@example\.invalid/);
  assert.doesNotMatch(p, /\b(create|alter|drop)\s+(function|table|trigger)/i);
  assert.match(p, /raise exception 'CHK<<PROBE OK/);
});

test('both files are pending with a note, not in the MANIFEST, until they are applied', () => {
  const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split('\n');
  for (const f of [NAME, NAME + '_probe']) {
    const listed = manifest.includes('scripts/sql/' + f + '.sql');
    assert.ok(listed !== existsSync(SQL + 'pending/' + f + '.txt'), f + ': exactly one of a MANIFEST line or a pending note');
  }
});
