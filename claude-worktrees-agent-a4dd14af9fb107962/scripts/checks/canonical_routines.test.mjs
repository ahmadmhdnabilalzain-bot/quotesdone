// ONE SOURCE OF TRUTH FOR ROUTINE CANONICALITY, AND THIS FILE IS NOT IT.
//
//   node scripts/checks/canonical_routines.test.mjs
//
// WHAT THIS FILE USED TO BE, and why it was replaced on 17 Aug 2026.
//   It was written on 16 Aug to catch a real defect: two files defining one routine, resolved by
//   git commit time, with production matching the wrong one. It fixed that by reading
//   scripts/sql/MANIFEST.txt — but it read ONLY scripts/sql, with its own parser and its own DDL
//   matchers. scripts/checks/canonical_routine_manifest.mjs then answered the same question over
//   all four apply tiers (migrations_history, migrations, ai-organization/db-functions,
//   scripts/sql).
//
//   Both stayed in the repository, and `npm test` ran both. The final Phase C re-acceptance found
//   them disagreeing on the same production, on the same day, from the same commit:
//
//       canonical_routine_manifest.mjs      0 findings,   exit 0
//       canonical_routines.test.mjs       436 findings,   exit 1  (15 "uncommitted DDL")
//
//   All 436 were artefacts of the narrower source set and the older matchers — spot-checked,
//   phase_c_historical_repair.active_effect_now is committed in kernel_k23 as part of a
//   multi-column `add column`, and kernel_signal_inbox is created in kernel_k16 with an inline
//   primary key whose Postgres-generated name appears in no file. Neither was uncommitted. But a
//   reader had no way to know which number to believe, and two committed checks claiming to be the
//   source of truth is not a source of truth.
//
// WHAT IT IS NOW. A thin test over the canonical engine. It owns NO parser, NO winner rule, NO DDL
// matcher and NO manifest reading of its own. It runs the engine and asserts two things:
//
//   1. the engine reports zero findings against this repository and this production;
//   2. the engine FAILS on a forced counterexample — two canonical files claiming one routine at
//      one sequence key — because a check that has never refused anything is indistinguishable
//      from no check.
//
// The counterexample runs in a throwaway directory with the token suppressed, so it touches
// neither the repository nor production.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const ENGINE = 'scripts/checks/canonical_routine_manifest.mjs';
let pass = 0, fail = 0;
const line = (ok, name, detail) => {
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? '   — ' + detail : ''}`);
};

// ---------------------------------------------------------------- 1. the engine, on this repo
{
  const r = spawnSync(process.execPath, [ENGINE, '--all'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const findings = Number((out.match(/countable findings\s+(\d+)/) || [])[1]);
  const repoOnly = /PRODUCTION COMPARISON SKIPPED/.test(out);
  line(r.status === 0, 'the canonical routine engine reports no findings',
       `exit ${r.status}, countable findings ${Number.isFinite(findings) ? findings : '?'}`
       + (repoOnly ? ' (repository-side only: no management token here)' : ''));
  for (const [label, re] of [
    ['conflicting current definitions', /conflicting current definitions\s+(\d+)/],
    ['ambiguous routine winners', /ambiguous routine winners\s+(\d+)/],
    ['manifest gaps', /manifest gaps\s+(\d+)/],
  ]) {
    const n = (out.match(re) || [])[1];
    line(n === '0', `${label} = 0`, `reported ${n ?? 'nothing'}`);
  }
  if (!repoOnly) {
    for (const [label, re] of [
      ['repository -> production drift', /repository -> production drift\s+(\S+)/],
      ['production -> repository drift', /production -> repository drift\s+(\S+)/],
      ['uncommitted application DDL', /uncommitted application DDL\s+(\S+)/],
    ]) {
      const n = (out.match(re) || [])[1];
      line(n === '0', `${label} = 0`, `reported ${n ?? 'nothing'}`);
    }
  } else {
    console.log('    the three production directions were NOT asserted: this environment holds no '
              + 'management token, and the engine says so rather than passing quietly.');
  }
}

// ---------------------------------------------------------------- 2. the forced counterexample
{
  const dir = mkdtempSync(join(tmpdir(), 'canonical-counterexample-'));
  try {
    mkdirSync(join(dir, 'supabase', 'migrations'), { recursive: true });
    mkdirSync(join(dir, 'scripts', 'sql'), { recursive: true });
    writeFileSync(join(dir, 'scripts', 'sql', 'MANIFEST.txt'), '');
    // ONE migration version, TWO files, ONE routine, TWO different bodies. The dollar tag carries a
    // digit on purpose: $k34$ is what made the engine's predecessor drop every kernel routine.
    for (const [name, body] of [['alpha', 'ALPHA'], ['beta', 'BETA']]) {
      writeFileSync(join(dir, 'supabase', 'migrations', `20990101000000_${name}.sql`),
        `create or replace function public.fn_zz_counterexample() returns text language sql as $k34$ select '${body}'::text $k34$;\n`);
    }
    const r = spawnSync(process.execPath, [join(process.cwd(), ENGINE), '--all'], {
      cwd: dir, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
      env: { ...process.env, SUPABASE_ACCESS_TOKEN: ' ' },     // repository-side only, no production
    });
    const out = (r.stdout || '') + (r.stderr || '');
    line(r.status === 1, 'two files claiming one routine at one sequence key FAIL the engine', `exit ${r.status}`);
    line(/CONFLICTING current definitions \(two files at one sequence key\): 1/.test(out),
         'the conflict is reported as a conflict, not resolved by a heuristic');
    line(/AMBIGUOUS routine winners: 1/.test(out), 'the winner is reported as ambiguous');
    line(/distinct bodies 2/.test(out),
         'both $k34$ bodies were parsed, so the digit-bearing dollar tag did not drop the routine');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

console.log(`\n${fail === 0 ? 'ONE CANONICAL ENGINE, AND IT REFUSES A FORCED CONFLICT' : `${fail} case(s) failed`}  (${pass} passed)`);
process.exit(fail === 0 ? 0 : 1);
