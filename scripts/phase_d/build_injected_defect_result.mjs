// PHASE D DELIVERABLE — PHASE_D_INJECTED_DEFECT_RESULT.csv
//
// One row per catalogue defect, produced BY INJECTING IT and observing what the machine did. The
// runner executes inside a transaction that aborts, so nothing survives; the counts come out in the
// raised message. The catalogue supplies defect_id, category, injected_defect and
// expected_machine_result; this script supplies status, observed and blocker from the live run and
// refuses to write if the two disagree on the population.
import { writeFileSync, readFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
import { outPath, provenance } from './lib/deliverable.mjs';

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

// THE SOURCE IS THE REPORT WRAPPER, NOT THE RUNNER. fn_phase_d_injected_defect_report() is
// fn_phase_d_run_injected_defects() with the recorded §8 probe verdicts LEFT JOINed on: the runner
// still decides all 75 rows, and a row is overridden only where a named HTTP probe assertion in
// public.phase_d_section8_probe_result actually executed. See D34 for the mapping and for the nine
// section 8 defects that are deliberately NOT mapped.
//
// ONE PROBE, ABORTED. Separators are control characters so a comma in a blocker cannot split a row.
const RUN = `
do $emit$
declare v_out text := ''; r record;
begin
  -- F01. THIS SET A GUC ANY CALLER COULD SET. app.phase_d_test_context = 'on' was a string the
  -- caller supplied about itself, which is the shape E38 and E39 removed twice elsewhere. The
  -- context is now an hmac over txid_current(), keyed by a secret no role can SELECT, minted only
  -- against an approved audited operation.
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build', 'label','injected-defect-deliverable'));
  for r in select * from public.fn_phase_d_injected_defect_report() where category = '__CAT__' order by defect_id loop
    -- BOUNDED, AND THE BOUND IS VISIBLE. The transport truncates a message at 2000 characters, and
    -- D44 lengthened one PD-PRIV observed string enough to push the PRIVACY category over it -- the
    -- guard below caught a 4-row export where 5 were expected rather than writing the four. Each
    -- free-text field is now capped at 240 characters with the cut marked in the value, so a reader
    -- of the deliverable can see that a reason was shortened. A silent cut is the defect; a marked
    -- one is a measurement with its boundary stated.
    v_out := v_out || chr(30) || concat_ws(chr(31), r.defect_id, r.category, r.status,
             public.fn_phase_d_bounded(replace(replace(coalesce(r.observed,''), chr(10),' '), chr(13),' '), 240),
             public.fn_phase_d_bounded(replace(replace(coalesce(r.blocker,''),  chr(10),' '), chr(13),' '), 240));
  end loop;
  -- AND IF THE BOUND IS EVER NOT ENOUGH, SAY SO RATHER THAN LOSE A ROW.
  if length(v_out) > 1800 then
    raise exception 'PHASE_D_DEFECTS_OVERFLOW category __CAT__ produced % characters, over the 1800 this transport carries. Lower the per-field bound or emit one probe per defect; do not let a row fall off the end.', length(v_out);
  end if;
  raise exception 'PHASE_D_DEFECTS%', v_out;
end $emit$;`;

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

writeFileSync(outPath('PHASE_D_INJECTED_DEFECT_RESULT.csv'),
  provenance({
    command: 'node scripts/phase_d/build_injected_defect_result.mjs',
    numerator: rows.length,
    denominator: byId.size,
    of: 'catalogued defects (PHASE_D_INJECTED_DEFECT_CATALOG.csv)',
    attribution: 'one row per catalogue defect, produced by injecting it inside a transaction that '
      + 'is aborted; status NOT_RUN carries a named blocker and is never a default',
  }) + out);

const exec = rows.filter(r => r[2] === 'REFUSED_AS_REQUIRED').length;
const notrun = rows.filter(r => r[2] === 'NOT_RUN').length;
const notref = rows.filter(r => r[2] === 'NOT_REFUSED');
// NOT_DISCRIMINATED (D44): the assertion executed and could not separate a refusal from an ignored
// parameter or an empty estate. It is neither a pass nor a failure and must not be counted as
// either. The total below is asserted because a status this summary does not name would otherwise
// vanish from the console without changing any of the three figures above it.
const notdisc = rows.filter(r => r[2] === 'NOT_DISCRIMINATED').length;
const residue = await sql('select count(*)::int as n from public.phase_d_external_attempt');
console.log(`PHASE_D_INJECTED_DEFECT_RESULT.csv  ${rows.length} rows`);
console.log(`  executed and refused as required   ${exec}`);
console.log(`  NOT_RUN with a named blocker       ${notrun}`);
console.log(`  executed but NOT_DISCRIMINATED     ${notdisc}`);
console.log(`  FAILED TO REFUSE                   ${notref.length}   (must be 0)`);
console.log(`  attempt rows left behind           ${residue?.[0]?.n ?? -1}   (must be 0)`);
if (exec + notrun + notdisc + notref.length !== rows.length) {
  const named = new Set(['REFUSED_AS_REQUIRED', 'NOT_RUN', 'NOT_DISCRIMINATED', 'NOT_REFUSED']);
  const other = [...new Set(rows.map(r => r[2]).filter(s => !named.has(s)))];
  console.error(`  the run produced status value(s) this summary does not count: ${other.join(', ')}`);
  process.exit(1);
}
if (notref.length) { console.error('  ' + notref.map(r => r[0]).join(', ')); process.exit(1); }
if ((residue?.[0]?.n ?? -1) !== 0) process.exit(1);

// EVERY CASE THAT DID NOT RUN IS NAMED IN THE REGISTER, OR THIS BUILD FAILS.
//
// The founder's ruling of 23 Aug 2026, section 4: "every remaining case named in the register with
// a reason a reader can check". Until this line the reason a case did not run lived in a text
// literal inside the injection function, which is where a stale reason hides best — PD-PRIV-004
// carried "SECTION 8 NOT BUILT" for days after section 8 had been built and had overridden it.
// public.phase_d_injected_defect_disposition is the register; this is what makes it owed rather
// than optional. A case that stops running and gains no row turns this red on the next build.
const open = rows.filter(r => r[2] !== 'REFUSED_AS_REQUIRED').map(r => r[0]);
const decided = new Set((await sql(
  'select defect_id from public.phase_d_injected_defect_disposition')).map(r => r.defect_id));
const undecided = open.filter(id => !decided.has(id));
const stale = [...decided].filter(id => !open.includes(id));
console.log(`  named in the disposition register  ${open.length - undecided.length} of ${open.length}`);
if (undecided.length) {
  console.error(`  NOT IN THE REGISTER: ${undecided.join(', ')}`);
  console.error('  a case that did not run and that nobody decided is not a case anyone can check.');
  process.exit(1);
}
if (stale.length) {
  console.error(`  REGISTER ROWS FOR CASES THAT NOW RUN: ${stale.join(', ')}`);
  console.error('  an exemption for a case that has since been closed is a reason nobody re-read.');
  process.exit(1);
}
