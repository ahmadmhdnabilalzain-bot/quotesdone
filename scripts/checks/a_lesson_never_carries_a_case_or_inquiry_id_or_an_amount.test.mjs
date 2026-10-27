// A LESSON NEVER CARRIES A CASE OR INQUIRY ID OR AN AMOUNT (it_engineer, 18 Oct 2026; follow-up of #1441).
//
// WHAT FAILS IF THE CAUSE RETURNS: fn_reason_apply_learning__distil stores the model's lesson as written, and the model
// copies the case numbers, inquiry ids and prices of the cases it read ("case 16269", "AED 3,728.30" were on production).
// An approved lesson is retrieved by meaning into a seat's prompts, so it carries one party's record to another.
// Offline: the canonical distil scrubs the answer before anything is stored. Production, in ONE aborted transaction:
// the _probe.sql plants every identifier kind through the real routine and answers PROBE OK only when none is stored,
// the know-how survives, and no stored lesson still carries one after the backfill.
//
//   node --test scripts/checks/a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'a_lesson_never_carries_a_case_or_inquiry_id_or_an_amount';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;

test('the canonical distil scrubs the lesson before it is stored anywhere', () => {
  const canonical = manifestWithPending().filter((p) => { try { return /function public\.fn_reason_apply_learning__distil\(/.test(R(p)); } catch { return false; } }).pop();
  assert.equal(canonical, FILE, 'a later file redefines the distil routine; it must keep the scrub');
  const src = R(FILE);
  const body = src.slice(src.indexOf('function public.fn_reason_apply_learning__distil('));
  assert.match(body, /v_answer := public\.fn_lesson_scrub\(/);
  assert.ok(body.indexOf('fn_lesson_scrub(') < body.indexOf('insert into public.reasoning_knowledge_candidate'), 'scrubbed after it was stored');
  // a new routine is granted to PUBLIC by CREATE: revoked in the same file, with a pinned search_path
  for (const sig of ['fn_lesson_scrub\\(text\\)', 'fn_lesson_scrub_backfill\\(\\)', 'fn_reason_apply_ceo__lesson_reapproval\\(bigint, jsonb\\)']) {
    assert.match(src, new RegExp(`revoke execute on function public\\.${sig} from public, anon, authenticated;`), sig + ' keeps the PUBLIC grant CREATE gives it');
  }
  // an approved lesson is never edited in place: the backfill writes a new version and asks the CEO seat
  assert.doesNotMatch(src, /update public\.agent_knowledge\s+set content\s*=/, 'an approved lesson is edited in place');
  assert.match(src, /supersedes_id/);
  assert.match(src, /if public\.fn_reason_hold\('ceo', 'ceo\.lesson_reapproval'[\s\S]{0,300}?is null then\s+raise exception/,
    'a lesson withheld while its CEO question was never filed (fn_reason_hold returned null) must abort the backfill');
  // a lapsed re-approval (expired / failed) is escalated to the CEO seat by a registered handoff, never left silent
  assert.match(src, /after update of status on public\.reasoning_held_question[\s\S]{0,300}new\.surface = 'ceo\.lesson_reapproval'[\s\S]{0,200}new\.status in \('expired', 'failed', 'applied'\)/);
  // one open handoff per version, re-asks capped, and an escalation error never aborts the statement that fired it
  const trig = src.slice(src.indexOf('function public.fn_lesson_reapproval_lapse_escalates()'));
  assert.match(trig, /status not in \('done', 'failed'\)[\s\S]{0,400}perform public\.fn_seat_handoff_act\(v_open\);\s+return null;/);
  assert.match(trig, /exception when others then[\s\S]{0,200}fn_it_engineer_finding_upsert/);
  assert.match(src, /v_cap constant int := 3;/);
  assert.match(src, /insert into public\.seat_handoff_kind[\s\S]{0,120}'ceo\.lesson_reapproval_overdue', 'it_engineer', 'ceo'/);
  assert.match(src, /revoke execute on function public\.fn_lesson_reapproval_overdue_act\(bigint\) from public, anon, authenticated;/);
  assert.match(src, /function public\.fn_lesson_scrub\(p_text text\)\s+returns text language sql immutable parallel safe set search_path/);
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production, rolled back: planted ids, amounts and contacts never reach a stored lesson', { skip: SKIP }, async () => {
  // The lapse escalation (4b) is a real handoff on a ZZ DEMO lesson; ruling 1199 (demo_activity_files_no_seat_task_or_handoff.sql,
  // #1479) files none for a demo subject, so fn_seat_handoff_act(null) aborted the probe. seatWorkFixtures() switches that
  // off for this rolled-back transaction only (a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.sql).
  const pre = seatWorkFixtures() + '\n;\n' + (pendingNotes().has(FILE) ? R(FILE) + '\n' : '');
  let out = null;
  try { await replaySql(pre + R(PROBE), { retry: false }); } catch (e) {
    const m = String(e.message || e).match(/CHK<<([\s\S]*)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
    out = m[1];
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log('  ' + out);
  assert.match(out, /^PROBE OK\b/, out);
});
