// A ROUTINE CANNOT RAISE A TIMEOUT THAT WAS ARMED BEFORE IT STARTED.
// Assigned: it_engineer. 22 September 2026.
//
// WHY THIS CHECK EXISTS. Three backup routines were given `SET statement_timeout TO '30s'` in their
// CREATE FUNCTION headers to stop the 8 s cancellations of 21-22 Sep. It does not work, and it looks
// exactly like it does: PostgreSQL arms statement_timeout when the statement BEGINS, and a value set
// afterwards — by a function's proconfig, or by set_config(..., true) inside the call — cannot extend the
// statement already running. Proved on production the same day: 3 s armed, 30 s set locally inside a DO
// block, pg_sleep(6) still died with SQLSTATE 57014. Measured role settings: authenticator 8 s,
// authenticated 8 s, anon 3 s, service_role none — PostgREST arms the value before the RPC begins.
//
// So a remedy has to live where the statement starts (the role, or the caller's own transaction) or the
// routine has to fit the budget. A header clause is a remedy that reads as done and changes nothing, which
// is the worst of the three. This check refuses the clause in a routine definition so the mistake cannot
// come back quietly. It is a SOURCE check: it reads the repository, asks nothing of production, and so
// costs nothing to run in CI.
//
// The pattern is spelled from parts on purpose: a check that greps for a string matches the comment that
// explains it, and that has already failed two correct files in this repository.
import { test } from 'node:test';
import assert from 'node:assert';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const DIR = 'scripts/sql';
const SETTING = ['statement', 'timeout'].join('_');
// Anywhere on a definition line, not only at its start: a header often carries several SET clauses on one
// line (`… security definer set search_path to 'public' set <setting> to '30s'`), and an anchor at the
// start of the line would let exactly that spelling through — which is how the clause was first written.
const CLAUSE = new RegExp(String.raw`(^|\s)set\s+${SETTING}\b`, 'i');

test('no routine definition tries to set its own statement timeout', () => {
  const offenders = [];
  for (const f of readdirSync(DIR).filter((n) => n.endsWith('.sql'))) {
    const lines = readFileSync(join(DIR, f), 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      if (line.trimStart().startsWith('--')) return;         // prose about this rule is not a breach of it
      if (CLAUSE.test(line)) offenders.push(`${DIR}/${f}:${i + 1}: ${line.trim()}`);
    });
  }
  assert.deepEqual(offenders, [],
    'a routine sets its own timeout, which cannot extend a statement already running — fix the caller, the role, or the routine:\n' + offenders.join('\n'));
});
