// Persist one row per blueprint check, so "which check moved" is a query and not a memory.
//
// 14 Aug 2026: Row #3 read 136/152 at the start of a session and 135/152 at the end. Both
// numbers were true; the difference between them was unrecoverable, because the scorer printed
// its verdicts and kept none of them. Writing is best-effort by design — a scorer that fails
// because it could not save its own history would be worse than one with no history.
import { mgmtWriteData, PROD_REF } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';

const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

async function prodPost(sql) {
  const token = (process.env.SUPABASE_ACCESS_TOKEN
    || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 160)}`);
  return r.json();
}

/**
 * @param {string} specFile   'row3_executive_ui' | 'row4_customer_portal'
 * @param {string} ref        the project the run measured
 * @param {Array<{id:string, name:string, ok:boolean, ev:unknown}>} rows
 */
export async function recordBlueprintRun(specFile, ref, rows) {
  if (!rows?.length) return { recorded: 0, note: 'no rows to record' };
  try {
    const values = rows.map((r) => `(gen_random_uuid(), ${q(specFile)}, ${q(ref)}, ${q(r.id)}, ` +
      `${r.ok ? 'true' : 'false'}, ${q(r.name)}, ${q(String(r.ev ?? '').slice(0, 2000))})`).join(',\n');
    // One run_id for the whole run: the diff compares runs, not individual checks.
    const sql = `with run as (select gen_random_uuid() id)
      insert into os_blueprint_result (run_id, spec_file, ref, check_id, ok, name, evidence)
      select (select id from run), v.spec, v.ref, v.check_id, v.ok, v.name, v.evidence
        from (values ${values}) as v(_x, spec, ref, check_id, ok, name, evidence)`;
    if (ref === PROD_REF) await prodPost(sql); else await mgmtWriteData(ref, sql, 'blueprint history');
    return { recorded: rows.length };
  } catch (e) {
    // Loud, and never fatal.
    console.log(`  !! blueprint history not saved: ${String(e.message).slice(0, 160)}`);
    return { recorded: 0, error: String(e.message).slice(0, 160) };
  }
}

/** Print what changed since the previous run of this spec on this project. */
export async function printBlueprintDiff(specFile, ref, read) {
  try {
    const d = await read(ref, `select * from fn_blueprint_regressions(${q(specFile)}, ${q(ref)})`);
    if (!d.length) { console.log('\n  No verdict changed since the previous recorded run (or this is the first).'); return; }
    console.log('\n  CHANGED SINCE THE PREVIOUS RUN:');
    for (const r of d) console.log(`    ${String(r.direction).padEnd(10)} ${String(r.check_id).padEnd(34)} ${r.name || ''}`);
  } catch (e) { console.log(`  !! could not diff against the previous run: ${String(e.message).slice(0, 140)}`); }
}
