// THE KNOWLEDGE ESTATE, RE-LEVELLED. verify_prod_parity check 8 compares agent_knowledge and
// kb_chunks row for row. They were identical at session 12's close and diverged again because
// PRODUCTION RUNS CRONS AND STAGING RUNS NONE: kb_deepen and kb_fill_gap wrote 7 agent_knowledge
// rows and 18 kb_chunks rows on production during this session alone. That is legitimate growth of
// the live corpus, not corruption — and it means this gate will go amber again on its own. It is
// re-runnable for exactly that reason.
//
// DELTA, NOT REPLACE. These tables are large (1,876 and 4,956 rows) and kb_chunks carries a
// vector(384) embedding that cost real money to compute; re-inserting everything would churn it for
// no reason. Rows are matched on a CONTENT DIGEST rather than on `id`, because both tables are
// keyed on a surrogate id that the two projects assign independently — matching on id would call
// every row different.
//
// Generated columns are excluded from the insert: kb_chunks.fts and kb_chunks.category_norm are
// STORED GENERATED and Postgres refuses an explicit value for them. embedding_gte is NOT generated —
// it is computed by an embedding call — so it is copied.
//
//   node scripts/sync_knowledge_delta_to_staging.mjs [--dry-run]
import { mgmtRead, mgmtWrite, mgmtWriteData, PROD_REF } from './lib/qd_guard.mjs';
import { REF as STAGE } from './lib/demo_factory.mjs';

const DRY = process.argv.includes('--dry-run');
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;

const TABLES = [
  { name: 'agent_knowledge',
    key: `md5(coalesce(agent_key,'')||'|'||coalesce(topic,'')||'|'||coalesce(content,''))` },
  { name: 'kb_chunks',
    key: `md5(coalesce(source_kind,'')||'|'||coalesce(source_id::text,'')||'|'||coalesce(title,'')||'|'||coalesce(content,''))` },
];

const results = [];
for (const t of TABLES) {
  // Columns to carry: everything except generated ones. `id` is carried too — the projects have
  // been kept in step on it since the original import, and dropping it would renumber staging.
  const cols = (await mgmtRead(PROD_REF,
    `select a.attname c from pg_attribute a
       join pg_class rel on rel.oid = a.attrelid
       join pg_namespace n on n.oid = rel.relnamespace and n.nspname='public'
      where rel.relname = '${t.name}' and a.attnum > 0 and not a.attisdropped
        and a.attgenerated = '' order by a.attnum`)).map(r => r.c);
  const colList = cols.map(c => `"${c}"`).join(', ');

  const stageKeys = (await mgmtRead(STAGE, `select ${t.key} k from public.${t.name}`)).map(r => r.k);
  const prodCount = Number(one(await mgmtRead(PROD_REF, `select count(*) from public.${t.name}`)));
  const stageCount = stageKeys.length;

  // The missing set is computed ON PRODUCTION against the staging key list, so the comparison is a
  // set difference rather than a count difference — a table can be short by 7 and wrong by 30.
  const keyLiteral = stageKeys.length
    ? `array[${stageKeys.map(k => `'${k}'`).join(',')}]::text[]`
    : `array[]::text[]`;
  const missingJson = String(one(await mgmtRead(PROD_REF,
    `select coalesce(jsonb_agg(to_jsonb(z) - ${cols.length ? '' : ''}'') , '[]'::jsonb)::text
       from (select ${colList} from public.${t.name} where ${t.key} <> all(${keyLiteral})) z`)) ?? '[]');
  const missing = JSON.parse(missingJson);

  // AND THE OTHER DIRECTION. The count gap was 7 and 18; the set difference is 8 and 76 — staging
  // holds rows production does not, because kb_deepen REWROTE the content of existing chunks on
  // production and a rewritten row is a different row by digest. Inserting the missing set alone
  // would take kb_chunks to 5,014 against production's 4,956 and fail the count check the other
  // way. This is exactly why a count is the wrong instrument: a table can be short by 18 and wrong
  // by 76. So the reconciliation runs both ways — drop what production no longer has, add what it
  // gained — which touches only the differences and leaves 4,880 untouched rows and their paid-for
  // embeddings alone.
  const prodKeys = (await mgmtRead(PROD_REF, `select ${t.key} k from public.${t.name}`)).map(r => r.k);
  const prodSet = new Set(prodKeys);
  const stale = stageKeys.filter(k => !prodSet.has(k));

  results.push({ table: t.name, production: prodCount, staging_before: stageCount,
                 to_add: missing.length, to_drop: stale.length });
  if (DRY || (!missing.length && !stale.length)) continue;

  for (let i = 0; i < stale.length; i += 400) {
    const batch = stale.slice(i, i + 400).map(k => `'${k}'`).join(',');
    await mgmtWrite(STAGE,
      `delete from public.${t.name} where ${t.key} in (${batch})`, `stale ${t.name} @${i}`);
  }

  for (let i = 0; i < missing.length; i += 200) {
    const part = JSON.stringify(missing.slice(i, i + 200)).replace(/'/g, "''");
    // OVERRIDING SYSTEM VALUE: `id` is GENERATED ALWAYS AS IDENTITY on both projects. The ids are
    // preserved rather than reassigned because agent_knowledge.supersedes_id points at them —
    // letting staging renumber would silently repoint a supersession chain at a different row.
    await mgmtWriteData(STAGE,
      `insert into public.${t.name} (${colList}) overriding system value` +
      ` select ${colList} from jsonb_populate_recordset(null::public.${t.name}, '${part}'::jsonb)`,
      `knowledge delta ${t.name} @${i}`);
  }
  const after = Number(one(await mgmtRead(STAGE, `select count(*) from public.${t.name}`)));
  results[results.length - 1].staging_after = after;
  results[results.length - 1].level = after === prodCount;
}

console.table(results);
const bad = results.filter(r => !DRY && (r.to_add || r.to_drop) && !r.level);
if (bad.length) { console.error('NOT LEVEL: ' + bad.map(b => b.table).join(', ')); process.exit(1); }
console.log(DRY ? 'DRY RUN — nothing written' : 'KNOWLEDGE ESTATE RE-LEVELLED with production');
