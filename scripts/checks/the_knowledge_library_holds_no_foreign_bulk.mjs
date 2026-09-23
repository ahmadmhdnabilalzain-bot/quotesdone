// THE KNOWLEDGE LIBRARY HOLDS NO FOREIGN BULK
//
// Seat: it_engineer. Founder instruction 520 (18 Sep 2026): unrelated knowledge is deleted
// permanently. docs/KNOWLEDGE_DOCTRINE.md §6 clause 5 names it; scripts/sql/
// the_foreign_bulk_leaves_the_knowledge_library_permanently.sql holds the rule as
// fn_kb_purge_clause; scripts/kb/purge_kb_bulk.mjs removes it. This check keeps it gone: it FAILS
// if any clause-5 row exists in public.kb_chunks that is not protected by clause 2 (cited in
// sales_decision_log). Read-only; counts by source_kind so the failure names what came back.
//
// It reads production through the same helper every DB check uses (qd_guard.mgmtRead refuses
// writes). Before the purge has run it fails by design — 2.4 M rows is the finding, not a flake —
// and the count of the `standard` kind is walked by id slice because a whole-table classification
// takes ~210 s against the platform's 2-minute statement_timeout.
import { mgmtRead, PROD_REF } from '../lib/qd_guard.mjs';

const CITED = `(select split_part(x, ':', 2)::bigint from public.sales_decision_log s, unnest(s.cited) x where x ~ '^kb_chunks:[0-9]+$')`;
// The third argument is the REASONED jurisdiction of the citation (kb_citation_jurisdiction, surface
// ceo.kb_jurisdiction), never the citation text: an undecided citation is clause 4 and kept.
const CLAUSE = `public.fn_kb_purge_clause(k.source_kind, k.category, (select j.jurisdiction from public.kb_citation_jurisdiction j where j.citation_md5 = md5(k.citation)))`;
const SLICE = 200000;

const rule = await mgmtRead(PROD_REF, `select count(*)::int as n from pg_proc where proname = 'fn_kb_purge_clause'`);
if (!rule[0].n) {
  console.error('FAIL: public.fn_kb_purge_clause is not on the database — the rule the purge and this check share has not been applied');
  process.exit(1);
}

const byKind = new Map();
const add = (rows) => { for (const r of rows) byKind.set(r.source_kind, (byKind.get(r.source_kind) || 0) + Number(r.n)); };

// Every kind but `standard` in one read (≈21 s before the purge, well under a second after it).
add(await mgmtRead(PROD_REF, `
  set statement_timeout = '10min';
  select k.source_kind, count(*) as n from public.kb_chunks k
   where k.source_kind <> 'standard' and ${CLAUSE} = 5 and k.id not in ${CITED}
   group by 1`));

const [{ lo, hi }] = await mgmtRead(PROD_REF, `select coalesce(min(id), 0)::bigint as lo, coalesce(max(id), 0)::bigint as hi from public.kb_chunks where source_kind = 'standard'`);
for (let from = Number(lo); from <= Number(hi); from += SLICE) {
  add(await mgmtRead(PROD_REF, `
    set statement_timeout = '10min';
    select k.source_kind, count(*) as n from public.kb_chunks k
     where k.source_kind = 'standard' and k.id >= ${from} and k.id < ${from + SLICE}
       and ${CLAUSE} = 5 and k.id not in ${CITED}
     group by 1`));
}

const total = [...byKind.values()].reduce((a, b) => a + b, 0);
if (total === 0) {
  console.log('OK: public.kb_chunks holds no clause-5 (foreign bulk) row');
  process.exit(0);
}
console.error(`FAIL: ${total} foreign-bulk rows (docs/KNOWLEDGE_DOCTRINE.md §6 clause 5) are in public.kb_chunks:`);
for (const [kind, n] of [...byKind].sort((a, b) => b[1] - a[1])) console.error(`  ${kind.padEnd(12)} ${n}`);
console.error('Run node scripts/kb/purge_kb_bulk.mjs --run (coordinator only) to remove them.');
process.exit(1);
