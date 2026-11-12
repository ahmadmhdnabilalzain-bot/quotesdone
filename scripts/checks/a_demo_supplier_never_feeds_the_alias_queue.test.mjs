// A DEMO SUPPLIER NEVER FEEDS THE ALIAS QUEUE (12 Nov 2026, sales_engineer).
//
// Measured 12 Nov 2026: 26 of the 28 open rows of public.service_alias_proposal had been filed by the registration
// certification's ZZ DEMO fixtures ("equipment" for studio equipment, "800 m2 office floor" for office leasing); the other
// 2 are lead 19398's, a real supplier. scripts/sql/a_demo_supplier_never_feeds_the_alias_queue.sql makes
// fn_service_alias_propose refuse a demo supplier and rejects the 26. What fails if that breaks:
//   * the refusal goes, or the routine's body drifts from its earlier definition in anything but the refusal -> static
//   * the routine is reopened to the public roles, or a real supplier's proposal is in the rejection list    -> static
//   * on production, rolled back: a ZZ DEMO supplier files nothing, the queue still files for anyone else, the 26
//     are rejected and the real supplier's 2 are untouched                                                    -> probe
//
//   node --test scripts/checks/a_demo_supplier_never_feeds_the_alias_queue.test.mjs
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
const NAME = 'a_demo_supplier_never_feeds_the_alias_queue';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const EARLIER = 'scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql';
const bodyOf = (src) => { const at = src.indexOf('create or replace function public.fn_service_alias_propose('); assert.ok(at >= 0); return src.slice(at).split('$fn$')[1]; };
const REFUSAL = /\n {2}-- 12 Nov 2026: a demo supplier[\s\S]*?'refused', 'demo_supplier'\);\n {2}end if;/;

test('the routine refuses a demo supplier and is otherwise the earlier body, byte for byte', () => {
  const now = bodyOf(R(FILE));
  assert.match(now, REFUSAL, 'the demo refusal is gone');
  assert.match(now, /public\.fn_supplier_is_demo\(p_supplier_id\)/);
  assert.equal(now.replace(REFUSAL, ''), bodyOf(R(EARLIER)), 'the body changed in more than the refusal');
  assert.match(R(FILE), /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(R(FILE), /revoke execute on function public\.fn_service_alias_propose\(bigint, jsonb, text\) from public, anon, authenticated;/);
});

test('the rejection names only the 26 demo rows, never the real supplier\'s 475 and 476, and goes through the decision routine', () => {
  const s = R(FILE);
  const lists = [...s.matchAll(/array\[([0-9,]+)\]::bigint\[\]/g)].map((m) => m[1].split(',').map(Number));
  assert.ok(lists.length >= 1);
  for (const l of lists) { assert.equal(l.length, 26); assert.ok(!l.includes(475) && !l.includes(476), 'a real supplier\'s proposal is rejected'); }
  assert.match(s, /public\.fn_service_alias_decide\(v_id, 'rejected', 'sales_engineer',/);
  assert.match(s, /not exists \(select 1 from public\.leads l where l\.id = any\(p\.supplier_ids\) and not l\.is_demo\)/);
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back: a demo supplier files nothing and the demo rows are rejected', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE }); } catch (e) {
    const m = String(e.body ?? e.message ?? e).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body ?? e.message ?? e).slice(0, 800));
    verdict = m[1].replace(/\\"/g, '"');
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /"verdict": "PROBE OK"/, verdict);
});
