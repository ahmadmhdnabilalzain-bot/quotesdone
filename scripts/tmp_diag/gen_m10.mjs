// M10 — the probe that reached a kernel-internal primitive.
// Returns PD-AUTH-005 and PD-LEGAL-005 to exemptions and states why.
import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';

let live = (await sql(`select pg_get_functiondef('public.fn_phase_d_run_injected_defects()'::regprocedure) def`))[0].def;

const branch = (src, id) => {
  const at = src.indexOf(`defect_id:='${id}'`);
  if (at < 0) throw new Error(`${id} not found`);
  const prev = src.lastIndexOf('return next;', at);
  const start = prev < 0 ? 0 : prev + 'return next;'.length;
  const end = src.indexOf('return next;', at);
  return src.slice(start, end + 'return next;'.length);
};

const BLOCK = 'closing this needs public.fn_phase_c_task_create, which public.kernel_retired_path '
  + 'classifies KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. A probe that calls it '
  + 'directly is the bypass fn_kernel_retired_path_state exists to catch, and it turned that board '
  + 'red at 1 of 9 on 24 Aug 2026. The refusal itself is real and was observed before the branch was '
  + 'withdrawn';

for (const [id, cat, tail] of [
  ['PD-AUTH-005', 'AUTH',
   'z10_phase_c_overlay_not_accountable refused a category overlay presented as the accountable task '
   + 'owner, and the canonical owner was accepted. ' + BLOCK + '.'],
  ['PD-LEGAL-005', 'LEGAL',
   'z20_phase_c_task_state_guard refused the owner of W28-S04 as its own reviewer, and general_counsel '
   + 'was accepted. ' + BLOCK + '.'],
]) {
  const old = branch(live, id);
  const neu = `
  -- ${id} — WITHDRAWN, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.
  defect_id:='${id}'; category:='${cat}'; status:='NOT_RUN'; observed:=null;
  blocker := '${tail.replace(/'/g, "''")}';
  return next;`;
  live = live.replace(old, neu);
  console.log(`${id}: ${old.length} -> ${neu.length}`);
}
writeFileSync('scripts/tmp_diag/m10_body.sql', live);
console.log('len ' + live.length);
