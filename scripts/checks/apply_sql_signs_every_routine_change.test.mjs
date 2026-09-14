// EVERY ROUTINE CHANGE APPLY_SQL MAKES CARRIES ITS SIGNATURE.
//
// Review of #661, 15 Sep 2026. scripts/apply_sql.mjs signs each write with `set application_name =
// 'qd-apply <rev> ...'`, and IT duty 24 (a_routine_change_nobody_signed_is_a_finding_within_minutes.sql)
// reports any routine change without it. A file that must run outside a transaction (CONCURRENTLY) is sent
// alone and so unsigned. This fails when:
//   1. a file in scripts/sql both runs a CONCURRENTLY statement and defines a routine;
//   2. apply_sql.mjs does not refuse such a file before touching the database;
//   3. a comment that merely mentions the word makes a routine file run unsigned again.
// No database access: the refusal comes before the token is read.
//
//   node --test scripts/checks/apply_sql_signs_every_routine_change.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { runsOutsideTransaction, definesRoutine, refuseUnsignable } from '../lib/sql_text.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = join(REPO, 'scripts', 'sql');

test('no file in scripts/sql runs a CONCURRENTLY statement and defines a routine', () => {
  const both = readdirSync(SQL).filter((f) => f.endsWith('.sql'))
    .filter((f) => refuseUnsignable(readFileSync(join(SQL, f), 'utf8')) !== null);
  assert.deepEqual(both, [], 'move each CONCURRENTLY statement into its own file, listed in MANIFEST right after');
});

test('a comment that mentions the word does not make a routine file run unsigned', () => {
  for (const f of ['fn_dr_restore_clear_one_bounded_delete_per_pass.sql', 'ops_knowledge_semantic_retrieval.sql',
                   'the_detector_that_finds_it_and_the_alert_that_sends_it_are_now_one_thing.sql']) {
    const sql = readFileSync(join(SQL, f), 'utf8');
    assert.equal(runsOutsideTransaction(sql), false, `${f} mentions "concurrently" only in a comment; it must be signed`);
  }
  assert.equal(runsOutsideTransaction('create index concurrently if not exists x on t (a);'), true);
  assert.equal(runsOutsideTransaction("create function f() returns int language sql as $$ select 1 $$; -- concurrently"), false);
  assert.equal(definesRoutine('/* create function */ select 1;'), false);
  assert.equal(definesRoutine('alter function public.f() set search_path to public;'), true);
});

test('apply_sql refuses a file that does both, before touching the database', () => {
  const dir = mkdtempSync(join(tmpdir(), 'qd-apply-'));
  try {
    const f = join(dir, 'zz_demo_unsignable.sql');
    writeFileSync(f, 'create index concurrently if not exists zz_demo_idx on public.zz_demo (a);\n'
      + 'create or replace function public.zz_demo_fn() returns int language sql as $fn$ select 1 $fn$;\n');
    const r = spawnSync(process.execPath, [join(REPO, 'scripts', 'apply_sql.mjs'), f],
      { encoding: 'utf8', env: { ...process.env, SUPABASE_ACCESS_TOKEN: 'zz-not-a-token' } });
    assert.equal(r.status, 2, r.stdout + r.stderr);
    assert.match(r.stderr, /REFUSED: .*CONCURRENTLY statement and defines a routine/);
    assert.doesNotMatch(r.stdout, /DRY RUN|applied/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
