// A CUSTOMER WITH QUOTES WHO HAS NOT REVEALED IS NUDGED, TWICE AT MOST, AND OFFERED HELP
// (5 Oct 2026, sales_engineer, founder_instruction 1027 under backlog 1019 T1).
//
// What fails if that breaks:
//   * the duty leaves the sales_engineer clock, or customer_support stops being the one sender      -> static
//   * a held (draft) or expired quote, a revealed request or a closed one starts getting nudges   -> static + probe
//   * the message stops speaking the request's language                                           -> static
//   * on production, ZZ DEMO only, rolled back: one message per request, never twice, none after a reveal -> probe
//
//   node --test scripts/checks/a_customer_with_quotes_who_has_not_revealed_is_nudged.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const NAME = 'a_customer_with_quotes_who_has_not_revealed_is_nudged_and_offered_help';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;

test('the duty is the sales engineer\'s, every 6 hours, and customer_support delivers', () => {
  const s = code(R(FILE));
  assert.match(s, /\('sales_engineer\.reveal_followup', 'sales_engineer', interval '6 hours', 'fn_sales_engineer_reveal_followup_tick'/);
  assert.match(s, /public\.fn_customer_support_duty_send\('reveal\.' \|\| r\.stage, r\.root::text/, 'not one subject per request through the one sender');
  assert.match(s, /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(s, /revoke execute on function public\.fn_sales_engineer_reveal_followup_tick\(\) from public, anon, authenticated/);
});

test('only live quotes, never after a reveal, never on a closed request, in the request\'s language', () => {
  const s = code(R(FILE));
  assert.match(s, /qt\.status = 'submitted' and \(qt\.expires_at is null or qt\.expires_at > now\(\)\)/, 'a draft (quality-held) or expired quote would count');
  assert.match(s, /not exists \(select 1 from public\.transactions t join public\.inquiries x[\s\S]{0,120}t\.revealed_at is not null and coalesce\(x\.parent_inquiry_id, x\.id\) = q\.root\)/, 'a revealed request would be nudged');
  assert.match(s, /not in \('cancelled', 'closed', 'completed', 'revealed'\)/);
  assert.match(s, /public\.fn_customer_message_lang\(r\.root, r\.locale\)/);
  assert.match(s, /= v_fx/, 'a fixture run must select only demo customers');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back, ZZ DEMO only: one message per quoted request, never twice, none after a reveal', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE, retry: false }); } catch (e) {
    const m = String(e.message || e).match(/CHK<<([\s\S]*)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
    verdict = m[1];
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /^PROBE OK/, verdict);
  const left = await sql(`select count(*)::int as n from public.customers where full_name = 'ZZ DEMO reveal probe'`);
  assert.equal(left[0].n, 0, 'the probe left a customer behind');
});
