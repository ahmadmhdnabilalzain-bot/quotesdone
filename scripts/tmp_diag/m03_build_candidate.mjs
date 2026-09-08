// Builds scripts/tmp_diag/m03_injected_defects_candidate.sql from the LIVE body of
// public.fn_phase_d_run_injected_defects(), by exact string replacement of the eight NOT_RUN
// branches whose blocker said they needed a committed row. Never retype a 516-line function.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const live = (await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`))[0].def;
const lines = live.split('\n');
const slice = (a, b) => lines.slice(a - 1, b).join('\n') + '\n';   // 1-based inclusive

const ARMS = readFileSync('scripts/tmp_diag/m03_arms.sql', 'utf8');

const emit = (id, cat) => `  defect_id:='${id}'; category:='${cat}';
  status   := coalesce(v_live->'${id}'->>'status','NOT_RUN');
  observed := v_live->'${id}'->>'observed';
  blocker  := coalesce(v_live->'${id}'->>'blocker',
                case when v_live->>'__stage_error' is not null
                     then 'the live arms for the eight recovered defects could not be staged in '
                       || 'this transaction: ' || (v_live->>'__stage_error') end);
  return next;
`;

let out = live;
function replace(oldText, newText, what) {
  const n = out.split(oldText).length - 1;
  if (n !== 1) { console.error(`anchor for ${what} occurs ${n} time(s); expected 1`); process.exit(1); }
  out = out.replace(oldText, newText);
}

// ---- 1. the declare block gains the arm variables --------------------------------------------
replace('  v_sup text; v_id bigint;\n',
`  v_sup text; v_id bigint;
  -- the eight recovered defects: one live run per arm, and what each arm observed
  v_live jsonb; v_hold_step text; v_rev text; v_clo_step text; v_clo_owner text;
  v_cands jsonb; v_fx jsonb; v_drive jsonb; v_o jsonb; v_d1 jsonb; v_d2 jsonb;
  v_srid bigint; v_srid2 bigint; v_run bigint; v_run2 bigint; v_psr bigint; v_tr bigint;
  v_acct text; v_task bigint; v_pk text; v_pacct text; v_pstep text;
  v_txt text; v_txt2 text; v_sk text; v_succ_kind text; v_src text;
  v_c0 int; v_c1 int; v_s0 int; v_s1 int; v_h0 int; v_h1 int;
  v_claim int; v_lost int; v_first int;
`, 'declare block');

// ---- 2. PD-IDEM-002: the arms run here, then the branch reports -------------------------------
replace(slice(75, 81),
`  -- PD-IDEM-002 duplicate workflow step completion -> the frozen kernel decides.
${ARMS}
${emit('PD-IDEM-002', 'IDEMPOTENCY')}`, 'PD-IDEM-002');

// ---- 3. PD-REV-002 / 004 / 005 ----------------------------------------------------------------
replace(slice(210, 221),
`  -- PD-REV-002/004/005 are decided by the ARM A run staged above.
${emit('PD-REV-002', 'REVIEW')}${emit('PD-REV-004', 'REVIEW')}${emit('PD-REV-005', 'REVIEW')}`,
  'PD-REV-002/004/005');

// ---- 4. PD-STATE-002 / 003 (004 keeps its blocker: it is a frozen-registry property) ----------
replace(slice(432, 439),
`  -- PD-STATE-002/003 are decided by the ARM A / ARM B runs staged above. PD-STATE-004 below is
  -- unchanged: a missing successor owner really is a frozen Phase B property.
${emit('PD-STATE-002', 'STATE')}${emit('PD-STATE-003', 'STATE')}`, 'PD-STATE-002/003');

// ---- 5. PD-TRACE-003 / 004 --------------------------------------------------------------------
replace(slice(454, 460),
`${emit('PD-TRACE-003', 'TRACE')}${emit('PD-TRACE-004', 'TRACE')}`, 'PD-TRACE-003/004');

writeFileSync('scripts/tmp_diag/m03_injected_defects_candidate.sql', out.endsWith('\n') ? out : out + '\n');
console.log(`scripts/tmp_diag/m03_injected_defects_candidate.sql  ${out.split('\n').length} lines (live was ${lines.length})`);
