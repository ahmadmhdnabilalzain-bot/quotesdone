// prove_a01_remediation.mjs — Batch 0 step 3, done as a proof rather than an assertion.
//
// The brief's plan was: seed staging with the corrected importer, then delete the duplicates there.
// That plan cannot demonstrate the cleanup, because a corrected importer produces no duplicates -
// there would be nothing to delete and nothing to prove. So this does the stronger thing: it
// reproduces production's DEFECTIVE state in staging byte for byte, runs the remediation against
// that, and measures the result. The corrected importer is proved separately, by test_idempotency.py.
//
//   node prove_a01_remediation.mjs <staging_ref> [--apply]
//
// Production is read-only throughout, enforced by qd_guard, and re-verified at the end.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
const REPO = fileURLToPath(new URL('../../', import.meta.url));
import { splitStatements } from './sql_split.mjs';
import { PROD_REF, resolveStagingRef, mgmtWrite, mgmtRead } from '../lib/qd_guard.mjs';

const REF = resolveStagingRef(process.argv[2]);
const APPLY = process.argv.includes('--apply');
const MIGRATION = REPO + 'supabase/migrations/20260802122010_kb_corpus_staging_schema_2026_08_02.sql';
const PAGE = 500;
const log = [];
const say = (s) => { console.log(s); log.push(String(s)); };
const one = async (ref, sql) => (await mgmtRead(ref, sql))[0];

say(`prove_a01_remediation  staging=${REF}  apply=${APPLY}`);
say(`production ${PROD_REF} is READ-ONLY for the whole of this script`);

// ---- 0. production baseline, read-only --------------------------------------------------------
const DUP_PREDICATE = `d1.record_id is null and exists (
  select 1 from kb_stage.decision_rules d2
   where d2.category_slug = d1.category_slug
     and d2.record_id is not null
     and d2.source_rule_id = d1.rule_id)`;

const prodBase = await one(PROD_REF, `
  select (select count(*) from kb_stage.decision_rules) as total,
         (select count(*) from kb_stage.decision_rules d1 where ${DUP_PREDICATE}) as dups,
         (select count(*) from kb_stage.records) as records`);
say(`\nPRODUCTION BASELINE: rules=${prodBase.total} duplicates=${prodBase.dups} records=${prodBase.records}`);

// ---- 1. export the remediation set from production, with a checksum ---------------------------
// The brief requires the exact id set and a SHA-256 of the export, taken from production, BEFORE
// anything is deleted anywhere. This file is the thing a later reader checks the deletion against.
const dupRows = await mgmtRead(PROD_REF, `
  select d1.rule_id, d1.category_slug, d1.source_rule_id
    from kb_stage.decision_rules d1
   where ${DUP_PREDICATE}
   order by d1.category_slug, d1.rule_id`);
const exportBody = dupRows.map(r => `${r.category_slug}\t${r.rule_id}\t${r.source_rule_id ?? ''}`).join('\n') + '\n';
const exportSha = createHash('sha256').update(exportBody, 'utf8').digest('hex');
writeFileSync(tmpdir() + '/_a01_duplicate_ids.tsv', exportBody, 'utf8');
say(`\nREMEDIATION SET EXPORTED: ${dupRows.length} rows`);
say(`  file    _a01_duplicate_ids.tsv`);
say(`  sha256  ${exportSha}`);
if (dupRows.length !== 3325) say(`  WARNING: expected 3325, got ${dupRows.length}`);

// ---- 2. preconditions, measured on production -------------------------------------------------
const pre = await one(PROD_REF, `
with dup as (select d1.* from kb_stage.decision_rules d1 where ${DUP_PREDICATE}),
canon as (select d.rule_id, (select count(*) from kb_stage.decision_rules c
            where c.category_slug=d.category_slug and c.record_id is not null
              and c.source_rule_id=d.rule_id) n from dup d)
select (select count(*) from canon where n=1)  as exactly_one_canonical,
       (select count(*) from canon where n<>1) as wrong_canonical_count,
       (select count(*) from dup where record_id is null) as all_carry_null_record_id,
       (select count(*) from dup where when_json is null or when_json='{}'::jsonb) as all_bodyless_when,
       (select count(*) from dup where then_json is null or then_json='{}'::jsonb) as all_bodyless_then,
       (select count(*) from kb_stage.decision_rules c where c.record_id is not null
          and (c.when_json is null or c.when_json='{}'::jsonb)) as canonicals_that_are_bodyless,
       (select count(*) from kb_stage.decision_rules x join dup on x.source_rule_id=dup.rule_id
          and x.category_slug=dup.category_slug where x.record_id is null and x.rule_id<>dup.rule_id)
                                                as duplicate_referenced_by_another_row`);
say('\nPRECONDITIONS (production, read-only):');
for (const [k, v] of Object.entries(pre)) say(`  ${String(v).padStart(6)}  ${k}`);

const okPre = pre.exactly_one_canonical === dupRows.length && pre.wrong_canonical_count === 0
  && pre.all_carry_null_record_id === dupRows.length && pre.all_bodyless_when === dupRows.length
  && pre.all_bodyless_then === dupRows.length && pre.canonicals_that_are_bodyless === 0
  && pre.duplicate_referenced_by_another_row === 0;
if (!okPre) { say('\nABORT: preconditions not met. Nothing was deleted.'); process.exit(2); }
say('  -> every duplicate is bodyless, has exactly one non-bodyless canonical, and is referenced by nothing.');

if (!APPLY) { say('\nDRY RUN — staging untouched. Re-run with --apply.'); process.exit(0); }

// ---- 3. build kb_stage on the branch from the committed migration ------------------------------
// One migration is not enough: the creating migration does not define source_rule_id or record_id -
// they arrive in 20260802130025_kb_dump_migrations_and_late_schema_fixes.sql, and those two columns
// are the ones the whole A-01 diagnosis rests on. Every kb_stage migration is replayed, in order.
say('\n--- creating kb_stage on staging from the committed migrations, in order ---');
const MIG_DIR = REPO + 'supabase/migrations';
if (process.argv.includes('--skip-migrations')) {
  say('  skipped (--skip-migrations): kb_stage DDL already applied in a previous run');
} else {
  // Only the statements that actually touch kb_stage. Replaying whole files is 35 broad migrations
  // whose other statements need a `public` schema this branch does not have, so the run spends its
  // time collecting failures that say nothing about kb_stage.
  const kbMigs = readdirSync(MIG_DIR).filter(f => f.endsWith('.sql'))
    .filter(f => readFileSync(`${MIG_DIR}/${f}`, 'utf8').includes('kb_stage')).sort();
  let mOk = 0, mSkip = 0, mFail = [];
  for (const f of kbMigs) {
    for (const s of splitStatements(readFileSync(`${MIG_DIR}/${f}`, 'utf8'))) {
      if (!/kb_stage/.test(s)) { mSkip++; continue; }
      try { await mgmtWrite(REF, s, `migration ${f}`); mOk++; }
      catch (e) { mFail.push({ f, sql: s.slice(0, 90), err: String(e.message).slice(0, 160) }); }
    }
  }
  say(`  ${kbMigs.length} migrations touch kb_stage; applied ${mOk}, skipped ${mSkip} (no kb_stage), failed ${mFail.length}`);
  for (const f of mFail.slice(0, 12)) say(`  FAIL [${f.f}] ${f.sql.replace(/\s+/g, ' ')}\n       ${f.err}`);
}
const cols = await mgmtRead(REF, `select column_name from information_schema.columns
  where table_schema='kb_stage' and table_name='decision_rules' order by ordinal_position`);
say(`  decision_rules columns on staging (${cols.length}): ${cols.map(c => c.column_name).join(', ')}`);
const tabs = await one(REF, `select count(*) n from information_schema.tables where table_schema='kb_stage'`);
say(`  kb_stage tables on staging: ${tabs.n}`);

// ---- 4. reproduce production's DEFECTIVE state in staging --------------------------------------
// Copying is deliberate. A reconstruction from the archives would be a simulation of the defect;
// this is the defect.
say('\n--- copying production kb_stage.decision_rules into staging ---');
await mgmtWrite(REF, `truncate kb_stage.decision_rules`, 'reset');
const COLS = ['rule_id','category_slug','subcategory_slug','rule_type','priority','when_json','then_json',
  'source_ids','confidence','requires_human_review','version','payload','source_rule_id','record_id'];
let copied = 0;
for (let off = 0; ; off += PAGE) {
  const page = await mgmtRead(PROD_REF,
    `select ${COLS.join(', ')} from kb_stage.decision_rules order by rule_id limit ${PAGE} offset ${off}`);
  if (!page.length) break;
  // JSON.stringify of a string yields a DOUBLE-quoted literal, which Postgres reads as an
  // identifier, not a string. Quote it as SQL text, doubling embedded apostrophes.
  const lit = "'" + JSON.stringify(page).replace(/'/g, "''") + "'";
  await mgmtWrite(REF, `insert into kb_stage.decision_rules (${COLS.join(', ')})
    select ${COLS.join(', ')} from jsonb_populate_recordset(null::kb_stage.decision_rules, ${lit}::jsonb)`,
    'copy page');
  copied += page.length;
  if (off % 5000 === 0) say(`  ${copied} rows...`);
}
say(`  copied ${copied} rows`);

const fidelity = await one(REF, `
  select (select count(*) from kb_stage.decision_rules) as total,
         (select count(*) from kb_stage.decision_rules d1 where ${DUP_PREDICATE}) as dups`);
say(`  staging now: rules=${fidelity.total} duplicates=${fidelity.dups}`);
say(`  faithful reproduction: ${fidelity.total === prodBase.total && fidelity.dups === prodBase.dups}`);
if (fidelity.total !== prodBase.total || fidelity.dups !== prodBase.dups) {
  say('ABORT: staging is not a faithful copy; a cleanup proved here would prove nothing.');
  process.exit(3);
}

// ---- 5. the remediation, in staging, in one transaction ----------------------------------------
say('\n--- remediation (staging only) ---');
const CLEANUP = `
begin;
create temp table _a01_target as
  select d1.rule_id, d1.category_slug from kb_stage.decision_rules d1 where ${DUP_PREDICATE};
delete from kb_stage.decision_rules d
 using _a01_target t
 where d.rule_id = t.rule_id and d.category_slug = t.category_slug and d.record_id is null;
do $$
declare n int;
begin
  select count(*) into n from kb_stage.decision_rules;
  if n <> 12929 then
    raise exception 'post-cleanup count is %, expected 12929 - rolling back', n;
  end if;
end $$;
commit;`;
try {
  await mgmtWrite(REF, CLEANUP, 'cleanup');
  say('  cleanup committed (the transaction asserts 12,929 before commit and rolls back otherwise)');
} catch (e) {
  say(`  CLEANUP FAILED / ROLLED BACK: ${String(e.message).slice(0, 400)}`);
  process.exit(4);
}

// ---- 6. verify the endpoint --------------------------------------------------------------------
const post = await one(REF, `
  select (select count(*) from kb_stage.decision_rules) as total,
         (select count(*) from kb_stage.decision_rules d1 where ${DUP_PREDICATE}) as dups_remaining,
         (select count(*) from kb_stage.decision_rules where record_id is not null) as wrapped,
         (select count(*) from kb_stage.decision_rules where record_id is null) as flat_kept,
         (select count(*) from kb_stage.decision_rules where when_json is null or when_json='{}'::jsonb) as bodyless,
         (select count(distinct category_slug) from kb_stage.decision_rules) as categories`);
say('\nSTAGING AFTER REMEDIATION:');
for (const [k, v] of Object.entries(post)) say(`  ${String(v).padStart(6)}  ${k}`);
const good = post.total === 12929 && post.dups_remaining === 0 && post.wrapped === 10392
  && post.flat_kept === 2537 && post.bodyless === 0;
say(`  VERDICT: ${good ? 'REMEDIATION PROVEN' : 'UNEXPECTED RESULT'}`);

// ---- 7. production must be untouched ------------------------------------------------------------
const prodAfter = await one(PROD_REF, `
  select (select count(*) from kb_stage.decision_rules) as total,
         (select count(*) from kb_stage.decision_rules d1 where ${DUP_PREDICATE}) as dups,
         (select count(*) from kb_stage.records) as records`);
say('\nPRODUCTION AFTER (must be identical to the baseline):');
say(`  rules=${prodAfter.total} duplicates=${prodAfter.dups} records=${prodAfter.records}`);
const untouched = prodAfter.total === prodBase.total && prodAfter.dups === prodBase.dups
  && prodAfter.records === prodBase.records;
say(`  PRODUCTION UNCHANGED: ${untouched}`);

writeFileSync(tmpdir() + '/_a01_proof.txt', log.join('\n'), 'utf8');
say('\nwrote _a01_proof.txt and _a01_duplicate_ids.tsv');
process.exit(good && untouched ? 0 : 1);
