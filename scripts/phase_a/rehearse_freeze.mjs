// Rehearse the freeze migration inside an aborted production transaction.
//   node scripts/phase_a/rehearse_freeze.mjs
import { readFileSync } from 'node:fs';
import { PROD_REF } from '../staging/qd_guard.mjs';

const FWD = 'supabase/migrations/20260815070000_phase_a_frozen_founder_approved.sql';
const sql = readFileSync(FWD, 'utf8');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const ABORT = `
do $$
declare v_b int; v_drift int; v_roles int; v_ovl int; v_guard int; v_fired text := 'NO';
begin
  select count(*) into v_b from public.org_phase_baseline where phase='A';
  select count(*) into v_drift from public.fn_phase_a_baseline_drift();
  select count(*) into v_roles from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  select count(*) into v_ovl from public.org_role where status='active' and runtime_mode='knowledge_overlay';
  select count(*) into v_guard from pg_trigger where tgname='z90_phase_a_freeze' and not tgisinternal;
  -- force the guard once more, here, so the rehearsal reports it rather than trusting the file
  begin
    update public.org_role set status='retired' where role_id='product_ux_designer';
  exception when others then
    if sqlerrm like 'PHASE A IS FROZEN%' then v_fired := 'YES'; else v_fired := 'WRONG ERROR: '||sqlerrm; end if;
  end;
  raise exception 'FREEZE REHEARSAL — ROLLED BACK. baseline_rows=% drift=% roles=% overlays=% guard_triggers=% guard_refused_a_shape_change=%',
    v_b, v_drift, v_roles, v_ovl, v_guard, v_fired;
end $$;`;

const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql + '\n' + ABORT }),
});
const body = await r.text();
let msg = body; try { msg = JSON.parse(body).message || body; } catch { /* raw */ }
console.log(`HTTP ${r.status}`);
console.log(String(msg).replace(/\\n/g, '\n').slice(0, 1600));
if (r.ok) { console.error('\nFAILED: the abort did not fire — the changes may have COMMITTED.'); process.exitCode = 1; }
else if (/FREEZE REHEARSAL/.test(msg)) { console.log('\nREHEARSAL PASSED.'); process.exitCode = 0; }
else { console.error('\nREHEARSAL DID NOT REACH THE ABORT. Nothing was applied.'); process.exitCode = 2; }
