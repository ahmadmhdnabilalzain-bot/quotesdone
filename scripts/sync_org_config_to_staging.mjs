// THE REHEARSAL SURFACE COULD NOT REHEARSE THE ORGANIZATION.
//
// Measured 6 Aug 2026: eleven founder-authored org-config tables hold rows in production and ZERO
// in staging — collaboration_rule 10/0, employee_authority 285/0, company_goals 63/0,
// employee_kpi 95/0, department_objective 44/0, delegation_rule 10/0, challenge_heuristic 8/0,
// policy_rules 7/0, org_onboarding 16/0, company_vision 1/0, institutional_memory 30/0.
//
// verify_prod_parity did not see it because it asks "is anything STAGING-only" — one direction.
// A config table that exists in production and is empty in staging passes every check in the repo
// while making every org-layer behaviour untestable before it ships. fn_pick_reviewer resolves to
// null without delegation_rule; fn_review_submit has no quality bar; fn_dept_authority answers
// but no per-employee limit exists to enforce.
//
// These are CONFIGURATION the founder wrote, not business data. Business/telemetry tables
// (org_tasks, goal_period, review_chain, agent_runs, leads) are deliberately NOT copied: they are
// operational history and belong to the project that produced them.
//
//   node scripts/sync_org_config_to_staging.mjs [--dry-run]
import { mgmtRead, mgmtWrite, mgmtWriteData, PROD_REF } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const DRY = process.argv.includes('--dry-run');

// Ordered so that anything another row references exists first. Schema-qualified where it is not
// public: ops_kb_stage.hard_gates is read by fn_ops_authority_check every time authority is
// resolved, and it is not in the public schema.
//
// THE TWO GATE TABLES ARE WHY THIS MATTERED. fn_ops_authority_check reads org_authority AND
// action_class_gate AND ops_kb_stage.hard_gates, and its rule is "an action class nobody has
// reviewed cannot be autonomous". With action_class_gate empty, staging answered `gated` to EVERY
// (department, action_class) pair while production answered advisory or autonomous for most of
// them. org_authority's 196 rows were present and identical on both, so every count in the repo
// agreed — and any autonomy behaviour rehearsed on staging was measuring a database where nothing
// is ever permitted. That is worse than an untested change: it is a test that passes for the
// wrong reason.
const TABLES = [
  'action_class_gate',
  // hard_gates.record_id → records.record_id → ingestion_runs.id, so the chain lands parent-first.
  // The whole ops_kb_stage schema was empty on staging (21 tables, ~4,000 rows in production).
  //
  // Deliberately NOT the other twelve projections of records (sops, kpis, scenarios, decision_rules,
  // exception_playbooks …): they are the same corpus as public.ops_knowledge, which is already on
  // both projects and already digest-identical, and nothing in the authority path reads them.
  // hard_gates is the one fn_ops_authority_check actually consults.
  'ops_kb_stage.ingestion_runs',
  'ops_kb_stage.records',
  'ops_kb_stage.hard_gates',
  'company_vision',
  'company_goals',
  'department_objective',
  'collaboration_rule',
  'delegation_rule',
  'challenge_heuristic',
  'quality_standard',
  'policy_rules',
  'employee_authority',
  'employee_kpi',
  'org_onboarding',
  'institutional_memory',
];

// Which of these actually own a sequence is a fact in the catalog, not a list to maintain by hand:
// company_goals is keyed on `key` (text) and has no `id` at all, so a hardcoded list got it wrong.

const one = (rows) => (rows && rows[0]) ? Object.values(rows[0])[0] : null;
// A bare name means public; anything already qualified is left alone.
const q = (t) => (t.includes('.') ? t : `public.${t}`);

// The digest must cover CONTENT, not row count. A copy that drops a column or truncates a text
// field preserves the count exactly the way `on conflict do nothing` preserves a key set.
const DIGEST = (t) => `select md5(coalesce(string_agg(x, '|' order by x), '')) from
  (select md5(to_jsonb(q)::text) x from ${q(t)} q) s`;

// TWO PASSES, AND THE ORDER IS A FOREIGN KEY, NOT A PREFERENCE.
// department_objective.goal_key references company_goals(key), so clearing company_goals while its
// children still hold rows raises 23503. Clear every table in REVERSE dependency order first, then
// load in forward order — a per-table delete-then-insert cannot express that and failed on the
// second run, after the first had already loaded the children.
if (!DRY) {
  for (const t of [...TABLES].reverse()) {
    await mgmtWrite(STAGE, `delete from ${q(t)}`, `clear ${t}`);
  }
}

const results = [];
for (const t of TABLES) {
  // ::text, and it is NOT cosmetic. jsonb renders a numeric with the scale it was stored at, so
  // production's confidence=1.00 serialises as "1.00" — but the moment the payload is parsed into
  // JavaScript it becomes the number 1 and re-serialises as "1". Twelve of institutional_memory's
  // 30 rows differed on exactly that, at an identical row count and identical parsed values.
  // Semantically 1.00 = 1; the point is that a copy which silently rewrites values is a copy whose
  // digest cannot be trusted to mean anything. The payload never enters JS as a value.
  const nRows = Number(one(await mgmtRead(PROD_REF, `select count(*) from ${q(t)}`)));
  const before = Number(one(await mgmtRead(STAGE, `select count(*) from ${q(t)}`)));
  const prodDigest = one(await mgmtRead(PROD_REF, DIGEST(t)));

  if (DRY) {
    results.push({ table: t, prod: nRows, staging_before: before, action: 'would copy' });
    continue;
  }

  // Two doors on purpose, and qd_guard is right to insist. The clear-out is a plain DDL-ish write
  // (mgmtWrite); the payload is row data that may legitimately CONTAIN the production ref inside a
  // text value — employee_authority notes and policy_rules regexes discuss the projects by name —
  // and only mgmtWriteData permits that in a value while still refusing anything executable.
  //
  // Replace, not upsert. `on conflict do nothing` is a no-op on a second pass, so a corrected value
  // would never reach staging while counts and key digests still matched. The digest below covers
  // whole-row content for exactly that reason.
  // Chunked. ops_kb_stage.records is 3,959 rows of long text and does not fit in one statement;
  // a single request that dies half way is the failure mode that made a prior import report 24 of
  // 168 rows remapped and say nothing. The ORDER BY is what makes the window deterministic — an
  // unordered LIMIT/OFFSET can repeat and skip rows without ever changing the total.
  const CHUNK = 400;
  for (let off = 0; off < nRows; off += CHUNK) {
    const part = String(one(await mgmtRead(PROD_REF,
      `select coalesce(jsonb_agg(j order by rn), '[]'::jsonb)::text from (
         select to_jsonb(z) j, row_number() over (order by to_jsonb(z)::text) rn
           from ${q(t)} z
       ) s where rn > ${off} and rn <= ${off + CHUNK}`)) ?? '[]');
    await mgmtWriteData(STAGE,
      `select set_config('app.change_reason', 'org config sync from production', true);` +
      ` insert into ${q(t)}` +
      ` select * from jsonb_populate_recordset(null::${q(t)}, '${part.replace(/'/g, "''")}'::jsonb);`,
      `copy ${t} @${off}`);
  }

  const after = Number(one(await mgmtRead(STAGE, `select count(*) from ${q(t)}`)));
  const stageDigest = one(await mgmtRead(STAGE, DIGEST(t)));
  results.push({ table: t, prod: nRows, staging_before: before, staging_after: after,
                 match: stageDigest === prodDigest });
}

if (!DRY) {
  // Resync sequences so staging's next insert cannot collide with a copied id.
  //
  // pg_get_serial_sequence ALONE IS NOT ENOUGH, and the first run said so in a line I read past:
  // it printed "sequences resynced: (none)" while six of these tables carry a
  // `nextval('x_id_seq'::regclass)` column default whose sequence is NOT OWNED by the column.
  // pg_get_serial_sequence reports only OWNED sequences, so it returned null for every one and the
  // resync did nothing at all. institutional_memory then held ids up to 40 with its sequence still
  // at 13, and the first insert after the copy died on a duplicate primary key — which is exactly
  // what happened the first time anything tried to write a task lesson.
  //
  // So the sequence is recovered from the column DEFAULT wherever it is not owned. A copy that
  // leaves every sequence behind its own data is not a copy, it is a delayed outage.
  const SEQ_EXPR = `coalesce(
      pg_get_serial_sequence(n.nspname || '.' || c.relname, a.attname),
      substring(pg_get_expr(ad.adbin, ad.adrelid) from 'nextval..([^'']+)'))`;
  const seqRows = await mgmtRead(STAGE,
    `select n.nspname || '.' || c.relname t, a.attname col, ${SEQ_EXPR} seq
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
       join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
       left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
      where n.nspname || '.' || c.relname in (${TABLES.map(t => `'${q(t)}'`).join(',')})
        and ${SEQ_EXPR} is not null`);
  for (const { t, col, seq } of seqRows) {
    await mgmtWrite(STAGE,
      `select setval('${seq}', greatest(coalesce((select max(${col}) from ${t}), 0), 1))`, `seq ${t}`);
  }
  console.log(`sequences resynced: ${seqRows.map(s => `${s.t}.${s.col}->${s.seq}`).join(', ') || '(NONE — suspicious, check the derivation)'}`);
}

console.table(results);
const bad = results.filter(r => !DRY && !r.match);
if (bad.length) { console.error('DIGEST MISMATCH:', bad.map(b => b.table).join(', ')); process.exit(1); }
console.log(DRY ? 'DRY RUN — nothing written' : `ORG CONFIG SYNCED to ${STAGE}: ${results.length}/${results.length} tables digest-identical to production`);
