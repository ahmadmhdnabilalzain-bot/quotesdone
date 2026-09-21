// IS THE PURGE CENSUS THE TABLE IT CLAIMS TO COUNT? — the rule purge_kb_bulk.mjs applies before any
// delete, pulled out so purge_census.test.mjs can replay the failing input.
//
// MEASURED 21 Sep 2026 (read-only, while the census ran, 15:15–15:48 UTC): kb_chunks held 589,199
// non-standard rows and the census in kb_purge_ledger already held 1,178,961 for them — more than
// twice — with two SIZE 'before the purge' rows one second apart; minutes later the ledger held no
// census at all (the run that hit the gateway's 524 had ended). Every census request went through a helper that retried any
// 5xx, and a 524 does not mean the statement did not run: it can commit behind the error, so a
// retried INSERT counts its rows again. Nothing compared the census with the table, so a census that
// survived such a run would have printed a wrong plan and nothing would have said so.
//
// The rule: per source_kind, the census rows sum to the live count EXACTLY, and there is exactly one
// SIZE row. Anything else is not an audit record, and the purge refuses to run on it.

/**
 * @param {{source_kind: string, rows: number|string}[]} census  sum(rows) per source_kind, note='census'
 * @param {{source_kind: string, n: number|string}[]} live       count(*) per source_kind in kb_chunks
 * @param {number} sizeRows  count of SIZE 'before the purge' rows
 * @returns {string[]} one line per disagreement; empty means the census is the table
 */
export function censusMismatches(census, live, sizeRows) {
  const c = new Map(census.map((r) => [r.source_kind, Number(r.rows)]));
  const l = new Map(live.map((r) => [r.source_kind, Number(r.n)]));
  const out = [];
  for (const k of new Set([...c.keys(), ...l.keys()])) {
    const a = c.get(k) ?? 0, b = l.get(k) ?? 0;
    if (a !== b) out.push(`${k}: census ${a}, live ${b} (${a > b ? 'counted twice' : 'not counted'}: ${Math.abs(a - b)})`);
  }
  if (Number(sizeRows) !== 1) out.push(`SIZE 'before the purge' rows: ${sizeRows}, expected exactly 1`);
  return out.sort();
}
