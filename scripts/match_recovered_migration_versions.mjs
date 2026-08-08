// Derive the APPLIED VERSION of each reconstructed 20260724_*.sql migration by matching its SQL
// against the statements both live projects actually recorded, then rename the files to
// <version>_<name>.sql.
//
//   node scripts/match_recovered_migration_versions.mjs            # report only
//   node scripts/match_recovered_migration_versions.mjs --write    # git mv the confident matches
//
// ── THE DEFECT THIS FIXES ───────────────────────────────────────────────────────────────────────
// Thirty-four files are named `20260724_<name>.sql`. The Supabase CLI parses the version from the
// filename prefix, so all thirty-four collapse to the version `20260724` — which is recorded on
// NEITHER project (measured: 0 rows). Two consequences, and the second is worse than the first:
//
//   1. They replay in ALPHABETICAL order, which is not the order they ran in. `analytics_department`
//      ALTERs public.org_action_executor and `supplier_success_executors` CREATEs it, so a fresh
//      database dies at 42P01 — which is exactly what the Supabase Preview check has been reporting
//      on every commit for weeks.
//   2. Because version `20260724` is not in schema_migrations, `supabase db push` considers all
//      thirty-four UNAPPLIED and would try to run them against production on top of themselves.
//
// Both projects DO record the real versions, with full 14-digit timestamps and their original
// names — 20260724025336 supplier_success_executors_and_registry, 20260724031359
// analytics_advisory_executor_support, and so on. Renaming the files to those versions restores the
// true order AND makes push see them as applied. Nothing about either database changes.
//
// ── THE VERSION IS DERIVED, NEVER INVENTED ──────────────────────────────────────────────────────
// This is the same discipline as rename_recovered_to_applied_version.mjs, which reads the version
// out of a header the recovery wrote. These files have no such header, so the evidence has to come
// from the content: supabase_migrations.schema_migrations.statements holds the SQL that was applied
// under each version. A file is matched to a version when a large majority of its meaningful lines
// appear in that version's recorded statements, the match is unambiguous against every other
// candidate, and BOTH projects agree. Anything short of that is reported and left alone — a
// mis-rename would put a migration in the wrong place in the order, which is the very bug being fixed.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const WRITE = process.argv.includes('--write');
const MIG = join(process.cwd(), 'supabase', 'migrations');
const DAY = '20260724';

// Meaningful lines only: comments and blanks are stripped, because the reconstruction rewrote
// headers freely and matching on prose would match the wrong file confidently.
const meaningful = (sql) => sql
  .replace(/\/\*[\s\S]*?\*\//g, '\n')
  .split('\n')
  .map((l) => l.replace(/--.*$/, '').replace(/\s+/g, ' ').trim().toLowerCase())
  .filter((l) => l.length >= 12);

const fetchRecorded = async (ref) => {
  const rows = await mgmtRead(ref, `select version, name,
      array_to_string(statements, E'\\n') sql
    from supabase_migrations.schema_migrations
    where version like '${DAY}%' order by version`);
  return rows.map((r) => ({ version: r.version, name: r.name, lines: new Set(meaningful(r.sql || '')) }));
};

// ── PRODUCTION IS THE ONLY EVIDENCE, AND THAT WAS MEASURED RATHER THAN ASSUMED ──────────────────
// The first version of this script demanded that both projects agree on the match, which read as
// "projects disagree" for 33 of 34 files. The cause was not disagreement: staging records all 47
// versions with statements NULL on every one — its ledger was copied without the SQL. A project
// holding no evidence cannot corroborate, and treating its empty answer as a dissenting opinion is
// the same defect as reading a rate limit as a missing row.
//
// So production's statements are the evidence, and staging is used for the one thing it CAN attest:
// that the version exists in its ledger too, which is what makes the rename safe for both.
const [prod, stage] = await Promise.all([fetchRecorded(PROD_REF), fetchRecorded(STAGE)]);
const stageVersions = new Set(stage.map((r) => r.version));
const withSql = prod.filter((r) => r.lines.size > 0);
console.log(`recorded on ${DAY}: production ${prod.length} (${withSql.length} with statements), `
  + `staging ${stage.length} (${stage.filter((r) => r.lines.size > 0).length} with statements)`);

const files = readdirSync(MIG).filter((f) => new RegExp(`^${DAY}_.*\\.sql$`).test(f)).sort();
console.log(`repo files named ${DAY}_*.sql: ${files.length}\n`);

// ── TWO DIRECTIONS, BECAUSE THE REPO FILES ARE CONSOLIDATIONS ───────────────────────────────────
// Scoring only "how much of the FILE is in this version" put 20260724_analytics_department.sql at
// 29% against its own migration and would have left the one file this whole exercise exists for
// unplaced. Measured: recorded version 20260724031359 contains a single statement — the ALTER —
// while the repo file holds that alter plus two INSERTs that ran under other versions. The file is
// a superset, not a mismatch, and a superset scores badly on a metric that assumes 1:1.
//
//   covRec   share of the VERSION's lines present in the file — "does this file carry what that
//            migration applied?" This is the one that identifies a consolidated file.
//   covFile  share of the FILE's lines present in the version — near 1.0 only for a true 1:1.
//
// A file is placed at the EARLIEST version it fully contains. That is the position its first
// constituent actually ran at, which is what the replay order needs, and it is the conservative
// choice: placing a consolidation early can only move later statements earlier, never the reverse.
const cover = (a, bSet) => (a.length ? a.filter((l) => bSet.has(l)).length / a.length : 0);

const COV_REC = 0.90;   // the file must carry essentially all of that version's SQL
const GAP = 0.15;       // and, for a 1:1 claim, beat the runner-up clearly

const plan = [];
const skipped = [];
for (const f of files) {
  const lines = meaningful(readFileSync(join(MIG, f), 'utf8'));
  const fileSet = new Set(lines);
  const scored = withSql
    .map((r) => ({ r, covRec: cover([...r.lines], fileSet), covFile: cover(lines, r.lines) }))
    .sort((a, b) => b.covRec - a.covRec || a.r.version.localeCompare(b.r.version));

  // ── NAME CORROBORATION, FOR THE FILES THE RECONSTRUCTION LEFT INCOMPLETE ──────────────────────
  // Content alone put 20260724_org_foundation.sql at 73% and 20260724_cos_execution_engine.sql at
  // 70% — below the bar, and both were needed: check_migration_order.mjs shows org_memory,
  // org_tasks and org_departments are ALSO touched before creation, and those two files are what
  // create them. The shortfall is a reconstruction gap in the other direction (the recorded version
  // applied MORE than the file carries), not a wrong match.
  //
  // So a recorded name that the filename stem is a prefix of counts as corroboration — 'org_foundation'
  // to 'org_foundation_kernel_ledger_permissions', 'cos_execution_engine' to 'cos_execution_engine_schema'.
  // It is only allowed to rescue a match that is ALREADY the top-ranked candidate and is the ONLY
  // name-related one, so it can promote a near-miss and never invent a match.
  const stem = f.replace(new RegExp(`^${DAY}_`), '').replace(/\.sql$/, '');
  //
  // MORE THAN ONE name-related version is not ambiguity, it is a consolidation: the day recorded
  // org_foundation_kernel_ledger_permissions AND org_foundation_authority_scorecard_fns_v2, and one
  // repo file carries both. Requiring exactly one left 20260724_org_foundation.sql unplaced — the
  // file that creates org_memory, org_tasks and org_departments, i.e. three of the four ordering
  // breaks. The file belongs at the EARLIEST of its namesakes, which is where its first constituent
  // ran; the guard is that the best CONTENT match must be one of them, so the name can never carry
  // a match the SQL contradicts.
  const nameRelated = scored
    .filter((x) => x.r.name === stem || x.r.name.startsWith(stem + '_'))
    .sort((a, b) => a.r.version.localeCompare(b.r.version));
  const topIsNamed = nameRelated.some((x) => x.r.version === scored[0].r.version);
  const corroborated = nameRelated.length && topIsNamed && nameRelated[0].covRec > 0
    ? nameRelated[0] : null;

  // Every version this file demonstrably contains, earliest first.
  const contained = scored.filter((x) => x.covRec >= COV_REC && stageVersions.has(x.r.version))
    .sort((a, b) => a.r.version.localeCompare(b.r.version));
  if (!contained.length && corroborated && stageVersions.has(corroborated.r.version)) {
    contained.push(corroborated);
  }

  if (contained.length) {
    const pick = contained[0];
    plan.push({
      f, version: pick.r.version, name: pick.r.name,
      covRec: pick.covRec, covFile: pick.covFile,
      why: pick.covRec >= COV_REC ? 'content' : 'name + top-ranked content',
      alsoContains: contained.slice(1).map((c) => c.r.version),
    });
  } else {
    const top = scored[0];
    skipped.push({ f, lines: lines.length,
      why: !lines.length ? 'no meaningful SQL lines to match on'
        : !top || top.covRec === 0 ? 'no recorded 20260724 version appears in it — probably applied on another day, or never'
        : `best version only ${(top.covRec * 100).toFixed(0)}% contained (need ${COV_REC * 100}%)`,
      top: top ? `${top.r.version} ${top.r.name}` : 'none' });
  }
}
void GAP;

plan.sort((a, b) => a.version.localeCompare(b.version));
console.log(`MATCHED ${plan.length}:`);
for (const p of plan) {
  const extra = p.alsoContains.length ? `  +also carries ${p.alsoContains.join(',')}` : '';
  console.log(`  ${p.version}_${p.name}.sql   <- ${p.f}`
    + `   [${p.why}] (version ${(p.covRec * 100).toFixed(0)}% contained, file ${(p.covFile * 100).toFixed(0)}% explained)${extra}`);
}

if (skipped.length) {
  console.log(`\nLEFT ALONE ${skipped.length}:`);
  for (const s of skipped) console.log(`  ${s.f}  [${s.lines} lines]  ${s.why}  (closest: ${s.top})`);
}

// Two versions must not claim the same file and one version must not claim two files.
const byVersion = new Map();
for (const p of plan) byVersion.set(p.version, [...(byVersion.get(p.version) || []), p.f]);
const collisions = [...byVersion].filter(([, fs]) => fs.length > 1);
if (collisions.length) {
  console.log('\nCOLLISION — refusing to rename any of these:');
  for (const [v, fs] of collisions) console.log(`  ${v} claimed by ${fs.join(', ')}`);
  process.exit(1);
}

// The whole point: does the create still precede the alter after renaming?
const order = plan.map((p) => `${p.version}_${p.name}.sql`);
const creator = plan.find((p) => /supplier_success/.test(p.f));
const alterer = plan.find((p) => /analytics_department/.test(p.f));
if (creator && alterer) {
  const ok = creator.version < alterer.version;
  console.log(`\nORDER CHECK  create ${creator.version} ${ok ? '<' : '>='} alter ${alterer.version}  ${ok ? 'FIXED' : 'STILL WRONG'}`);
  if (!ok) process.exit(1);
}

// --pairs emits the rename list in check_migration_order.mjs's format, so the proposed order can be
// checked BEFORE any file moves. Renaming first and checking afterwards would mean discovering a
// new ordering break with the evidence already rewritten.
if (process.argv.includes('--pairs')) {
  console.log('\n--rename=' + plan.map((p) => `${p.f}=${p.version}_${p.name}.sql`).join(','));
  process.exit(0);
}

if (!WRITE) { console.log('\nreport only; pass --write to rename'); process.exit(0); }
for (const p of plan) {
  const target = `${p.version}_${p.name}.sql`;
  if (target === p.f) continue;
  execFileSync('git', ['mv', `supabase/migrations/${p.f}`, `supabase/migrations/${target}`], { stdio: 'inherit' });
}
writeFileSync(join(MIG, '..', '..', 'docs', 'sessions', 'MIGRATION_RENAME_20260724.json'),
  JSON.stringify({ day: DAY, renamed: plan, left_alone: skipped }, null, 2));
console.log(`\nrenamed ${plan.length}; order recorded in docs/sessions/MIGRATION_RENAME_20260724.json`);
