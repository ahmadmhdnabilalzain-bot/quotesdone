// RETIRED 9 September 2026 -- with its subject, not softened to green.
//
// fn_phase_b_invariants and every phase_b table it counted are gone.
//
// A check whose subject is gone is retired, never edited until it passes: a check that passes
// because the thing it checks no longer exists is a green light over nothing.
// Phase B invariants, read from the live database.
//
//   node scripts/checks/phase_b_invariants.test.mjs [--json]
//
// A thin wrapper over public.fn_phase_b_invariants() so the test and the database cannot
// disagree about what passed.  It adds three things the SQL function cannot check for itself:
// the package checksums, that the committed migration still regenerates byte-identically from
// the package, and that Phase B activated nothing.
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

// This check reads PRODUCTION, so it cannot run where there is no management token, and CI is
// exactly that place.  Skipping loudly beats failing the build on a missing credential.  It is
// scoped, not weakened: the registry it verifies is written only by an applied migration, and
// the next session that runs the sweep catches any drift.  The skip happens before the database
// module is imported so a missing token cannot throw on the way in.
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
if (!(process.env.SUPABASE_ACCESS_TOKEN
      || (existsSync(LOCAL_TOKEN) && readFileSync(LOCAL_TOKEN, 'utf8').trim()))) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so the Phase B '
    + 'registry cannot be read out of production. Run this from a session that holds the '
    + 'management token. It is not asserting anything here.');
  process.exit(0);
}

const { sql } = await import('../lib/db.mjs');
const { REPO, verifyChecksums } = await import('../phase_b/lib/package.mjs');
const { MIGRATION_FILES } = await import('../phase_b/rehearse.mjs');

const JSON_OUT = process.argv.includes('--json');
const rows = await sql('select * from public.fn_phase_b_invariants() order by check_name');
const extra = [];

// ---- the package bytes the registry was built from ----
const sums = verifyChecksums();
extra.push({ check_name: 'package.checksums_bad', expected: '0', actual: String(sums.bad.length), ok: sums.bad.length === 0 });
extra.push({ check_name: 'package.files_checked', expected: '60', actual: String(sums.checked), ok: sums.checked === 60 });

// ---- the committed migration must still be what the package generates ----
// Otherwise the SQL in the repository and the document the founder approved can drift apart
// silently, and the deployed registry would be neither.
const digestsBefore = MIGRATION_FILES.map(f => sha(readFileSync(join(REPO, 'scripts', 'sql', f))));
execFileSync(process.execPath, [join(REPO, 'scripts', 'phase_b', 'gen_migration.mjs')], { cwd: REPO });
const digestsAfter = MIGRATION_FILES.map(f => sha(readFileSync(join(REPO, 'scripts', 'sql', f))));
const drifted = MIGRATION_FILES.filter((f, i) => digestsBefore[i] !== digestsAfter[i]);
extra.push({ check_name: 'migration.regenerates_identically', expected: '0 drifted',
  actual: `${drifted.length} drifted${drifted.length ? ': ' + drifted.join(', ') : ''}`, ok: drifted.length === 0 });

function sha(b) { return createHash('sha256').update(b).digest('hex'); }

// ---- Phase B activated nothing ----
const act = (await sql(`select
    (select count(*) from cron.job where jobname like 'phase_b%')                      as phase_b_cron,
    (select count(*) from public.llm_route_health where open_until <= now())           as llm_routes_released,
    (select count(*) from public.org_action_executor
       where active and target like '%phase_b%')                                       as phase_b_executors`))[0];
extra.push({ check_name: 'activation.cron_jobs_created', expected: '0', actual: String(act.phase_b_cron), ok: Number(act.phase_b_cron) === 0 });
extra.push({ check_name: 'activation.llm_routes_released', expected: '0', actual: String(act.llm_routes_released), ok: Number(act.llm_routes_released) === 0 });
extra.push({ check_name: 'activation.executors_created', expected: '0', actual: String(act.phase_b_executors), ok: Number(act.phase_b_executors) === 0 });

const all = [...rows, ...extra].sort((a, b) => a.check_name.localeCompare(b.check_name));
const failed = all.filter(r => !r.ok);

if (JSON_OUT) {
  console.log(JSON.stringify({ ok: failed.length === 0, total: all.length, failed: failed.length, results: all }, null, 1));
} else {
  for (const r of all) {
    console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.check_name.padEnd(56)} ${r.actual}${r.ok ? '' : `  (expected ${r.expected})`}`);
  }
  console.log(`\n${all.length - failed.length}/${all.length} Phase B invariants passed`);
}
process.exit(failed.length === 0 ? 0 : 1);
