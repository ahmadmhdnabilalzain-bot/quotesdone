// A ROW ADDED WITHOUT ITS ARTEFACT.
//
// public.phase_d_fixture_catalogue is the committed Phase D content catalogue the founder's section
// B requires: explicit, clearly marked test values for the business content a deterministic handler
// must not invent. "Committed" means the repository holds it, and a table nobody compares against a
// file is a table anybody can add a row to without review.
//
// This check fails in BOTH directions:
//   * a row in the database that is not in docs/phase-d/PHASE_D_FIXTURE_CATALOGUE.csv;
//   * a row in the file that is not in the database;
//   * a row present in both whose checksum differs, which means the CONTENT differs.
//
// It also asserts the catalogue board is green, and — separately, because they are different claims
// — that no fixture context, scenario record or capability result is committed on production. Those
// three tables exist only inside a transaction that is aborted; a committed row in any of them is
// residue, and this is the check that would find it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../phase_b/lib/db.mjs';

// EVERY TEST HERE READS PRODUCTION, and the checks job does not hold the management credential.
// A file that threw would be a red nobody could fix from CI; a file that VANISHED would be worse --
// node --test reports zero tests and a runner reading that as success is how a check goes quiet.
// So the tests SKIP with a stated reason, and the file prints the exact marker
// .github/workflows/project-parity.yml greps for, so a skip inside the one job that does hold the
// credential still reads as unverified rather than as a pass.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const FILE = 'docs/phase-d/PHASE_D_FIXTURE_CATALOGUE.csv';

/** Minimal RFC4180 reader: the builder quotes every cell, so this only has to handle "" escapes. */
function parseCsv(text) {
  const rows = []; let row = []; let cell = ''; let inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') inQ = false;
      else cell += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
    else if (c !== '\r') cell += c;
  }
  if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
  return rows.filter(r => r.length > 1 && !String(r[0]).startsWith('#'));
}

test('the committed fixture catalogue and the database agree, row for row', { skip: SKIP }, async () => {
  const text = readFileSync(FILE, 'utf8');
  const rows = parseCsv(text);
  const header = rows.shift();
  const idIdx = header.indexOf('fixture_id');
  const ckIdx = header.indexOf('checksum');
  assert.ok(idIdx >= 0 && ckIdx >= 0, 'the committed file must carry fixture_id and checksum');

  const file = new Map(rows.map(r => [r[idIdx], r[ckIdx]]));
  const live = new Map((await sql('select fixture_id, checksum from public.phase_d_fixture_catalogue'))
    .map(r => [r.fixture_id, r.checksum]));

  const onlyDb = [...live.keys()].filter(k => !file.has(k));
  const onlyFile = [...file.keys()].filter(k => !live.has(k));
  const differ = [...live.keys()].filter(k => file.has(k) && file.get(k) !== live.get(k));

  assert.deepEqual(onlyDb, [],
    `these fixture rows exist on production and not in ${FILE}. Run: node scripts/phase_d/build_fixture_catalogue.mjs`);
  assert.deepEqual(onlyFile, [],
    `these fixture rows are committed and not on production. The catalogue is applied by scripts/sql/phase_d_f03*.sql and phase_d_f07*.sql.`);
  assert.deepEqual(differ, [],
    `these fixture rows differ in CONTENT between production and ${FILE} — the checksum covers every field that decides what a fixture means.`);
  assert.ok(live.size >= 40, `the catalogue holds ${live.size} rows; the board requires at least 40`);
});

test('the fixture catalogue board is green', { skip: SKIP }, async () => {
  const board = await sql('select check_name, expected, actual, ok from public.fn_phase_d_fixture_catalogue_state()');
  const red = board.filter(b => !b.ok);
  assert.deepEqual(red.map(r => `${r.check_name}: expected ${r.expected}, got ${r.actual}`), []);
});

test('no Phase D fixture row is committed on production', { skip: SKIP }, async () => {
  // Each of these lives only inside a transaction that is aborted. A committed row is residue, and
  // naming the tables separately means a reader can see WHICH kind of residue without re-deriving it.
  const r = (await sql(`select
    (select count(*) from public.phase_d_test_context_grant)  fixture_contexts,
    (select count(*) from public.phase_d_scenario_record)     scenario_records,
    (select count(*) from public.phase_d_capability_request)  capability_requests,
    (select count(*) from public.phase_d_capability_result)   capability_results,
    -- 27 AUG 2026. NOT a bare count any more, and the change is not a relaxation.
    -- public.phase_c_founder_auth_event was empty from the day PCCR-006 created it until the
    -- governance door was repaired, because fn_phase_c_governance_decide was not on
    -- kernel_write_authority and the kernel write guard refused its every mint with 42501. While the
    -- table could never hold a row, "count = 0" was a serviceable way to say "no fixture leaked one".
    --
    -- It holds two real founder sessions now: the founder binding his own subject over HTTPS, and
    -- the purpose-bound GOVERNANCE_DECISION session that carried his approval of PCCR-007. The table
    -- is APPEND-ONLY — a00_phase_c_founder_auth_event_is_server_minted refuses DELETE outright — so
    -- "expected 0" is an expectation the estate can never satisfy again, and a check that can only
    -- fail is not a check.
    --
    -- A FIXTURE CANNOT PUT A ROW HERE AT ALL: the mint refuses any connection whose session_user is
    -- not 'authenticator', and no check in this repository has one. So the question worth asking is
    -- not how many rows there are but whether each one could only have come from a verified session.
    -- Same predicate as fn_phase_c_founder_auth_state's own row, so the two instruments agree.
    (select count(*) from public.phase_c_founder_auth_event e
      where e.txid is null
         or not exists (select 1 from public.phase_c_founder_identity f
                         where f.identity = e.identity and f.active and f.kind = 'email')
         or (e.action_class = 'GOVERNANCE_DECISION' and e.consumed_at is null))
      founder_auth_events_not_backed_by_a_verified_session,
    (select count(*) from public.founder_command
      where intent_id like 'PHASE_D_FIXTURE%')                fixture_founder_commands`))[0];
  for (const [k, v] of Object.entries(r)) {
    assert.equal(Number(v), 0, `${k} holds ${v} committed row(s); every one of them should have rolled back`);
  }
});
