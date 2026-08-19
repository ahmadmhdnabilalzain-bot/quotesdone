// PHASE D DELIVERABLE — PHASE_D_INJECTED_DEFECT_RESULT.csv
//
// One row per catalogue defect, produced BY INJECTING IT and observing what the machine did. The
// runner executes inside a transaction that aborts, so nothing survives; the counts come out in the
// raised message. The catalogue supplies defect_id, category, injected_defect and
// expected_machine_result; this script supplies status, observed and blocker from the live run and
// refuses to write if the two disagree on the population.
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const CAT = 'QuotesDone_PHASE_D_DETERMINISTIC_BUSINESS_HANDLER_IMPLEMENTATION_PRODUCTION_DIRECT_v2026.08.17/registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv';

function parseCsv(text) {
  const rows = []; let row = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"' && text[i+1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  return rows.filter(r => r.length > 1);
}

const cat = parseCsv(readFileSync(CAT, 'utf8'));
const head = cat[0];
const byId = new Map(cat.slice(1).map(r => [r[0], r]));

// ONE PROBE, ABORTED. Separators are control characters so a comma in a blocker cannot split a row.
const RUN = `
do $emit$
declare v_out text := ''; r record;
begin
  perform set_config('app.phase_d_test_context','on', true);
  for r in select * from public.fn_phase_d_run_injected_defects() where category = '__CAT__' order by defect_id loop
    v_out := v_out || chr(30) || concat_ws(chr(31), r.defect_id, r.category, r.status,
             replace(replace(coalesce(r.observed,''), chr(10),' '), chr(13),' '),
             replace(replace(coalesce(r.blocker,''),  chr(10),' '), chr(13),' '));
  end loop;
  raise exception 'PHASE_D_DEFECTS%', v_out;
end $emit$;`;

// ONE PROBE PER CATEGORY. A single message carrying all 75 rows is truncated by the transport at
// 2000 characters — the same defect the workflow builder hit — and the guard below caught it again
// by refusing a partial export rather than writing 11 rows as if they were 75.
const cats = [...new Set([...byId.values()].map(r => r[1]))].sort();
const rows = [];
for (const cat of cats) {
  // ONE PROBE PER CATEGORY. A single message carrying all 75 rows is truncated by the transport at
// 2000 characters — the same defect the workflow builder hit — and the guard below caught it again
// by refusing a partial export rather than writing 11 rows as if they were 75.
const cats = [...new Set([...byId.values()].map(r => r[1]))].sort();
const rows = [];
for (const cat of cats) {
  let payload = null;
  try {
    await sql(RUN.replace('__CAT__', cat));
    console.error(`the probe did not raise for ${cat}`);
    process.exit(1);
  } catch (err) {
    const msg = String(err?.message ?? err);
    const at = msg.indexOf('PHASE_D_DEFECTS');
    if (at < 0) { console.error(`the probe for ${cat} failed:\n` + msg); process.exit(1); }
    payload = msg.slice(at + 'PHASE_D_DEFECTS'.length)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/\\"/g, '"')
      .replace(/\\n/g, '\n');
    const ctx = payload.indexOf('\nCONTEXT:');
    if (ctx >= 0) payload = payload.slice(0, ctx);
  }
  const got = payload.split(String.fromCharCode(30)).filter(r => r.trim() !== '')
    .map(r => r.split(String.fromCharCode(31)));
  if (got.length !== 5) { console.error(`${cat} produced ${got.length} row(s); 5 are expected`); process.exit(1); }
  rows.push(...got);
}
if (rows.length !== byId.size) {
  console.error(`the run produced ${rows.length} row(s) and the catalogue holds ${byId.size}. Refusing a partial export.`);
  process.exit(1);
}
const missing = rows.filter(r => !byId.has(r[0])).map(r => r[0]);
if (missing.length) {
  console.error('the run named defect(s) the catalogue does not contain: ' + missing.join(', '));
  process.exit(1);
}

const cell = v => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const COLS = ['defect_id','category','injected_defect','expected_machine_result','status','observed','blocker'];
const out = [COLS.join(',')].concat(rows.map(r => {
  const c = byId.get(r[0]);
  return [r[0], r[1], c[2], c[3], r[2], r[3], r[4]].map(cell).join(',');
})).join('\n') + '\n';

mkdirSync('docs/phase-d', { recursive: true });
writeFileSync('docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv', out);

const exec = rows.filter(r => r[2] === 'REFUSED_AS_REQUIRED').length;
const notrun = rows.filter(r => r[2] === 'NOT_RUN').length;
const notref = rows.filter(r => r[2] === 'NOT_REFUSED');
const residue = await sql('select count(*)::int as n from public.phase_d_external_attempt');
console.log(`PHASE_D_INJECTED_DEFECT_RESULT.csv  ${rows.length} rows`);
console.log(`  executed and refused as required   ${exec}`);
console.log(`  NOT_RUN with a named blocker       ${notrun}`);
console.log(`  FAILED TO REFUSE                   ${notref.length}   (must be 0)`);
console.log(`  attempt rows left behind           ${residue?.[0]?.n ?? -1}   (must be 0)`);
if (notref.length) { console.error('  ' + notref.map(r => r[0]).join(', ')); process.exit(1); }
if ((residue?.[0]?.n ?? -1) !== 0) process.exit(1);
