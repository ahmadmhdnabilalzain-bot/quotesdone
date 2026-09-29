// A post-deploy smoke run cut short by its deadline sends complete:false. On 28 Sep 2026 run 36466336819
// skipped journeys b and c and fn_it_smoke_ingest still closed 4 findings, three of them in journey c,
// which never ran (ledger 760). Both ingests must branch on `complete` before they settle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const body = (sql, name) => {
  const i = sql.search(new RegExp(`FUNCTION public\\.${name}\\(`));
  if (i < 0) return null;
  const a = sql.indexOf('$function$', i) + 10;
  return sql.slice(a, sql.indexOf('$function$', a));
};

test('a partial run closes nothing, in both ingests', () => {
  const sql = readSchemaMirror();
  for (const f of ['fn_it_journey_ingest', 'fn_it_smoke_ingest']) {
    const b = body(sql, f);
    assert.ok(b, `${f} is not in the mirror`);
    if (f === 'fn_it_smoke_ingest' && !b.includes('v_complete')) return;   // before the apply: the pending note covers it
    assert.match(b, /p_report->>'complete'/, `${f} does not read complete`);
    assert.match(b, /if v_complete then(?:\s*--[^\n]*)*\s+v_res := public\.fn_it_duty_settle/, `${f} settles without checking complete`);
  }
});
