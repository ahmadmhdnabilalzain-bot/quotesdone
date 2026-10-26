// ROW #3 — the daily company snapshot records everything about the company except its customers.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   time-machine-restores-six-dimensions  MISSING  5 of 6 dimensions are non-null on ALL 12
//                                                  snapshot(s) of the last 14 days
//
// The one missing dimension is CUSTOMERS. company_snapshot.state carries 24 keys — employees,
// revenue, knowledge, decisions, KPIs, indices, os_health, departments — and not one of them
// matches customer or buyer. A time machine that restores the company as it was, minus its
// customer base, is not restoring the company.
//
// ── ZERO IS A MEASUREMENT ───────────────────────────────────────────────────────────────────────
// public.customers holds 0 rows today and all 7 inquiries carry a null customer_id. Recording that
// is not fabrication — it is the fact, and it is the single most important fact about this
// marketplace's current state. The value of writing it down daily is precisely that the day it
// stops being zero, the snapshot shows exactly when.
//
// Two keys rather than one, because they answer different questions: how many customers exist, and
// how many inquiries actually reached one. Today they are 0 and 0 and they will diverge the moment
// inquiry_intake creates its first record.
//
// ── IT DOES NOT FLIP ON DEPLOY, AND THAT IS CORRECT ─────────────────────────────────────────────
// The check is a per-dimension universal over EVERY snapshot in the last 14 days, so it turns green
// 14 days after the writer changes, not tonight. Back-filling the key into the 12 existing rows
// would be editing history to turn a gate green, and those snapshots genuinely did not record it.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/snapshot_carries_customers.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_company_snapshot' limit 1`);
if (!def) { console.error('fn_company_snapshot not found'); process.exit(1); }
if (/'customers'/.test(def)) { console.error('REFUSING: fn_company_snapshot already records customers.'); process.exit(1); }

const ANCHOR = `    'employees',        (select count(*) from org_agents where active),`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the employees anchor did not match exactly once. Re-read the routine.');
  process.exit(1);
}

const BLOCK = `${ANCHOR}
    -- THE CUSTOMER BASE, which the snapshot has never recorded. Zero is the measurement today —
    -- 0 customers and 0 inquiries carrying one — and writing it down daily is what makes the day
    -- it stops being zero visible in the replay.
    'customers',              (select count(*) from customers),
    'customers_with_inquiry', (select count(distinct customer_id) from inquiries where customer_id is not null),`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_company_snapshot ${def.length} -> ${out.length} chars`);
