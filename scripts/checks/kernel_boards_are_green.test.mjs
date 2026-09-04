// EVERY KERNEL BOARD IS READ, AND A NEW ONE IS READ WITHOUT ANYONE REMEMBERING TO ADD IT.
//
// The final acceptance audit on 18 Aug 2026 found two boards red on production while `npm test` was
// green across 288 tests and PHASE_C_BUILDER_CLOSURE.md reported "headlines FAILED 0":
//
//   fn_kernel_trigger_state      active_autonomous_source_not_yet_routing_through_the_inbox 26 of 37
//   fn_kernel_retired_path_state kernel_primitives_called_from_outside_the_kernel            1 of 9
//
// Neither was new. Six of the seven kernel boards were read by no test and no CI job, so a board
// could be red from the day it was written and nothing would ever say so. That is the defect this
// file closes, and it is the reason the discovery is BY SIGNATURE rather than by a list here: a
// hard-coded list would have the same hole the moment somebody deploys board number twenty-two.
//
// Default is GATE. A board must be all-ok unless kernel-boards.json says otherwise, with a reason.
// A named board is a RATCHET: its disclosed gap may stand but may not grow.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = join(homedir(), '.supabase', 'access-token');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();

const cfg = JSON.parse(readFileSync(join(REPO, 'scripts', 'checks', 'kernel-boards.json'), 'utf8'));
const RATCHET = cfg.ratchet ?? [];

// WITHOUT THE CREDENTIAL THIS NAMES ITSELF UNVERIFIED; IT NEVER SKIPS QUIETLY.
//
// Three versions of this block, and the middle one broke CI, so both are recorded.
//
// FIRST: `if (!token) t.skip(...)` on every test. No credential meant 6 of 7 skipped, exit 0,
// green — the silent credential-based pass the acceptance audit names as a finding, reproduced
// inside the check written to close a finding. The Phase C gate greps for `^SKIP` and node prints
// `ℹ skipped 6`, so that guard would not have caught it either.
//
// SECOND: print the marker and `process.exit(1)`. Correct in the gate, wrong everywhere else — the
// `checks` workflow runs `npm test` with NO env block at all, so this killed the whole suite on a
// machine that was never going to have a credential. PR #439's `classification, pricing and refund
// checks` went red on exactly that.
//
// THIRD, and the pattern this repository already settled on for the crosswalk: print
// NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL, assert the half that needs no database, and exit 0.
// The Phase C gate's own guard greps for that marker and fails the job — so it is a hard failure in
// the one place a credential is guaranteed, and an honest "not verified" everywhere else. The
// difference from the FIRST version is that the estate is never reported green: the marker is the
// headline, and the boards are explicitly not claimed.
const LIVE = !!token;
if (!LIVE) {
  console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
  console.log('kernel_boards_are_green cannot open the boards without the management credential.');
  console.log('The file-only assertions below still run. NOTHING is claimed about the estate.');
}

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if ((r.status === 429 || r.status >= 500) && attempt < 5) {
    await new Promise((res) => setTimeout(res, Math.min(2000 * 2 ** attempt, 30000)));
    return q(sql, attempt + 1);
  }
  const body = await r.text();
  if (!r.ok) throw new Error(`database ${r.status}: ${body.slice(0, 300)}`);
  return JSON.parse(body);
}

/** The leading integer of "26 of 37" / "7 of 1209". null when the actual is not a count. */
const numerator = (actual) => {
  const m = String(actual ?? '').match(/^\s*(\d+)/);
  return m ? Number(m[1]) : null;
};

// 4 SEP 2026: ONE STATEMENT PER BOARD. fn_kernel_all_boards() ran all 41 boards inside one statement,
// and under load (five parallel agents, the scorer's regex queries) the statement hit the management
// API's timeout inside the slowest board and the whole gate read as "database 57014" — no board
// measured, every PR red. The boards are discovered here by the same signature fn_kernel_all_boards
// uses (a zero-argument public function returning check_name/expected/actual/ok), each is asked in
// its own statement, and a board that raises or times out is reported as a red BOARD_RAISED row for
// THAT board, exactly as fn_kernel_all_boards reports a raise — never as an absent board.
async function allBoards() {
  const boards = (await q(`select p.proname
                              from pg_proc p
                             where p.pronamespace = 'public'::regnamespace and p.pronargs = 0
                               and pg_get_function_result(p.oid) = 'TABLE(check_name text, expected text, actual text, ok boolean)'
                               and p.proname <> 'fn_kernel_all_boards'
                             order by 1`)).map((r) => r.proname);
  const out = [];
  for (const b of boards) {
    try {
      // The management API's default statement timeout is 2 minutes; a board is granted 4 in its
      // own request (the API honours `set local` inside the request's transaction). A board that
      // needs more than that is a board to fix, and it still reads as BOARD_RAISED below.
      for (const r of await q(`set local statement_timeout = '240s'; select check_name, expected, actual, ok from public.${b}()`)) out.push({ board: b, ...r });
    } catch (e) {
      out.push({ board: b, check_name: 'BOARD_RAISED', expected: 'rows', actual: String(e.message).slice(0, 200), ok: false });
    }
  }
  return out;
}
const rows = token ? await allBoards() : [];

test('the boards are reachable and there are many of them', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  const boards = new Set(rows.map((r) => r.board));
  assert.ok(boards.size >= 20,
    `fn_kernel_all_boards() found ${boards.size} board(s). It discovers by signature — a zero-argument `
    + 'function returning (check_name, expected, actual, ok). A sudden drop means boards were dropped '
    + 'or the signature changed, and either way the estate is being watched less than it was.');
  assert.ok(rows.length >= 250, `only ${rows.length} checks across all boards; expected 250+`);
  console.log(`      ${boards.size} boards, ${rows.length} checks, ${rows.filter((r) => !r.ok).length} red`);
});

test('a board that raises is reported red, never as an absent board', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  const raised = rows.filter((r) => r.check_name === 'BOARD_RAISED');
  assert.deepEqual(raised.map((r) => `${r.board}: ${r.actual}`), [],
    'a board raised instead of returning rows. fn_phase_c_invariants once raised 22007 on every call '
    + 'after a column retype and took fn_phase_c_baseline_drift down with it; a board that throws '
    + 'must read as red, not as a board that quietly returned nothing.');
});

test('every ratchet entry still matches a real check', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  for (const e of RATCHET) {
    const hit = rows.find((r) => r.board === e.board && r.check_name === e.check);
    assert.ok(hit,
      `kernel-boards.json ratchets ${e.board}.${e.check}, and no such check exists on production. `
      + 'A ratchet that outlives its subject silences any future check that takes the same name. '
      + 'Delete the entry, or correct it.');
  }
});

test('every ratchet entry carries a reason and an owner', () => {
  for (const e of RATCHET) {
    assert.ok(typeof e.why === 'string' && e.why.length > 40,
      `ratchet ${e.board}.${e.check} has no usable reason`);
    assert.ok(typeof e.owner === 'string' && e.owner.length > 5,
      `ratchet ${e.board}.${e.check} has no owner. A disclosed gap with nobody's name on it is a `
      + 'hiding place, not a disclosure.');
    assert.ok(Number.isInteger(e.max_numerator) && e.max_numerator >= 0,
      `ratchet ${e.board}.${e.check} has no integer max_numerator, so it cannot ratchet`);
  }
});

test('no board is red except the ones this repository has disclosed', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  const ratcheted = new Set(RATCHET.map((e) => `${e.board} ${e.check}`));
  const undisclosed = rows.filter((r) => !r.ok && !ratcheted.has(`${r.board} ${r.check_name}`));
  assert.deepEqual(
    undisclosed.map((r) => `${r.board}.${r.check_name} — expected ${r.expected}, got ${r.actual}`), [],
    'a kernel board is red and kernel-boards.json does not disclose it. Either the estate regressed, '
    + 'or this is a gap that must be recorded with an owner and a reason before it is allowed to '
    + 'stand. Do not add it to kernel-boards.json to make this pass unless the gap is genuinely '
    + 'deliberate and someone owns it.');
});

test('no disclosed gap has grown', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  const grown = [];
  for (const e of RATCHET) {
    const hit = rows.find((r) => r.board === e.board && r.check_name === e.check);
    if (!hit) continue;
    const n = numerator(hit.actual);
    if (n === null) continue;
    if (n > e.max_numerator) {
      grown.push(`${e.board}.${e.check} — disclosed at ${e.max_numerator}, now ${n}. ${e.owner}`);
    }
    if (n < e.max_numerator) {
      console.log(`      ratchet improved: ${e.board}.${e.check} ${e.max_numerator} -> ${n}`
        + ' (lower kernel-boards.json to lock the gain in)');
    }
  }
  assert.deepEqual(grown, [],
    'a disclosed gap grew. The ratchet allows debt already on the record to stand; it does not allow '
    + 'more of the same debt to be added.');
});

test('the open Phase C cutover is still counted and still owned', () => {
  if (!LIVE) { console.log('      not verified — no credential'); return; }
  const e = RATCHET.find((x) => x.check === 'active_autonomous_source_not_yet_routing_through_the_inbox');
  if (!e) return; // deleted because it reached zero — that is the goal, not a failure
  const hit = rows.find((r) => r.board === e.board && r.check_name === e.check);
  const n = numerator(hit?.actual);
  console.log(`      Phase C kernel cutover: ${n} of 37 active autonomous sources still bypass the kernel`);
  console.log(`      owner: ${e.owner}`);
  assert.ok(e.owner.startsWith('OPEN'),
    'the cutover ratchet must stay marked OPEN until it reaches zero. Marking it closed while the '
    + 'count is non-zero is how a gap stops being work and starts being furniture.');
});
