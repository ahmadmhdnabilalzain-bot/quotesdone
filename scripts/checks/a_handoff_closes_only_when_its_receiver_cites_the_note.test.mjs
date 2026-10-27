// A HANDOFF CLOSES ONLY WHEN ITS RECEIVER CITES THE HANDOVER NOTE, OR SAYS WHY NOT (ceo, 27 Oct 2026; founder ledger 1013).
//
// MEASURED 27 Oct 2026: 199 handoffs closed in 30 days with a complete note and neither a citation nor a reason, all
// of them delivery.request rows that fn_customer_support_adopts_untracked_send writes already 'done'. Citing had been
// stamped by two close paths, never required.
//
// WHAT FAILS IF THE CAUSE RETURNS (offline: the repository only):
//   * the trigger a02_handoff_close_cites_its_note is gone, stops firing on a close, or stops refusing;
//   * any routine whose CANONICAL body (last in MANIFEST order, pending files after) closes a handoff -- inserts one as
//     'done', or sets status 'done' on kind 'handoff' -- neither cites the note nor records not_cited;
//   * the measurement stops separating 'neither' from a recorded reason.
// On production after apply: select public.fn_handoff_citation_gaps(<apply time>) -> neither = 0.
//
//   node --test scripts/checks/a_handoff_closes_only_when_its_receiver_cites_the_note.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { definitions } from '../lib/canonical_sql.mjs';
import { manifestWithPending } from '../lib/pending_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql';
const s = readFileSync(join(REPO, FILE), 'utf8');

// The canonical body of every routine, the way the manifest gate resolves it, with this PR's pending files last.
function canonical() {
  const winner = new Map();
  for (const p of manifestWithPending(REPO)) {
    if (!existsSync(join(REPO, p))) continue;
    for (const d of definitions(readFileSync(join(REPO, p), 'utf8'))) winner.set(d.key, { file: p, stmt: d.stmt });
  }
  return winner;
}

// The two shapes that close a handoff. Comments are stripped first so a sentence describing the shape cannot match.
const stripComments = (t) => t.replace(/--[^\n]*/g, '');
const INSERT_DONE = /insert\s+into\s+public\.agent_actions\b[^;]*?values\s*\([^;]*?'handoff'\s*,\s*'done'/i;
const UPDATE_DONE = /update\s+public\.agent_actions\b[^;]*?\bset\b[^;]*?\bstatus\s*=\s*'done'[^;]*?\bkind\s*=\s*'handoff'/i;

test('the trigger refuses a handoff that reaches done without a citation or a reason', () => {
  const trg = s.match(/create trigger a02_handoff_close_cites_its_note[\s\S]*?execute function public\.trg_handoff_close_cites_its_note\(\);/);
  assert.ok(trg, 'trigger a02_handoff_close_cites_its_note is not created');
  assert.match(trg[0], /before insert or update of status, evidence on public\.agent_actions/);
  assert.match(trg[0], /when \(new\.kind = 'handoff' and new\.status = 'done'\)/);
  const fn = definitions(s).find((d) => d.name === 'trg_handoff_close_cites_its_note');
  assert.ok(fn, 'trg_handoff_close_cites_its_note is not defined');
  assert.match(fn.stmt, /'cites_note'->>'handoff_id'\) = new\.id::text/);
  assert.match(fn.stmt, /'not_cited'->>'reason'/);
  assert.match(fn.stmt, /raise exception using\s+errcode = 'check_violation'/);
  assert.match(fn.stmt, /security definer\s+set search_path to 'public', 'pg_temp'/i);
  assert.ok(s.includes('revoke execute on function public.trg_handoff_close_cites_its_note() from public, anon, authenticated;'));
  // the name sorts after a01 (BEFORE triggers fire in name order; a01 builds the note this one reads past)
  assert.ok('a02_handoff_close_cites_its_note' > 'a01_handoff_carries_its_note');
});

test('every canonical routine that closes a handoff cites the note or records why not', () => {
  const offenders = [];
  let closers = 0;
  for (const [key, { file, stmt }] of canonical()) {
    const code = stripComments(stmt);
    if (!INSERT_DONE.test(code) && !UPDATE_DONE.test(code)) continue;
    closers++;
    if (!/'cites_note'/.test(code) && !/'not_cited'/.test(code)) offenders.push(`${key} (${file})`);
  }
  assert.ok(closers >= 2, `expected at least the closer and the adoption, found ${closers}: the shape regexes no longer match`);
  assert.deepEqual(offenders, [], 'routines that close a handoff without citing its note or recording why not');
});

test('the adoption records a reason and does not pretend to cite', () => {
  const fn = definitions(s).find((d) => d.name === 'fn_customer_support_adopts_untracked_send');
  assert.ok(fn);
  assert.match(fn.stmt, /'not_cited', jsonb_build_object\(\s*'reason', [\s\S]+?'by', 'fn_customer_support_adopts_untracked_send'\)/);
  assert.doesNotMatch(stripComments(fn.stmt), /'cites_note'/);
});

test('the measurement separates a recorded reason from neither', () => {
  const fn = definitions(s).find((d) => d.name === 'fn_handoff_citation_gaps');
  assert.ok(fn);
  for (const k of ['cited', 'reason_recorded', 'reason_by', 'neither', 'uncited_ids']) assert.ok(fn.stmt.includes(`'${k}'`), `no ${k}`);
});

// The regexes are the guard; prove they catch the original shape and pass the fixed one.
test('the shape regexes catch the 27 Oct adoption body and pass the citing closer', () => {
  const before = `insert into public.agent_actions (agent, kind, status) values ('customer_support', 'handoff', 'done', 'low');`;
  assert.ok(INSERT_DONE.test(before));
  const closer = `update public.agent_actions set status = 'done', decided_at = now() where id = p_id and kind = 'handoff' and status <> 'done';`;
  assert.ok(UPDATE_DONE.test(closer));
  const other = `update public.agent_actions set status = 'done' where agent = 'ceo' and kind = 'support_question_handover';`;
  assert.ok(!UPDATE_DONE.test(other));
});
