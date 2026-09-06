// O12. The fixture file revision O11 added is a row a COMMITTED scenario would leave behind.
// Adds public.phase_d_file_revision to the committed-scenario watch list and its removal to
// fn_phase_d_committed_scenario_close, keyed on the fxrev: prefix the fixture factory mints.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

let src = (await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  and n.nspname='public' and p.proname='fn_phase_d_committed_scenario_close'`))[0].prosrc;

const FIND = `  delete from public.phase_d_effect_ledger where run_id = any(v_runs);`;
const REPL = `  -- O12. THE FIXTURE FILE REVISIONS. O11 gave the scenario's supplier_safe_package the file set
  -- BR-012 now requires, and public.phase_d_file_revision was NOT on the watch list -- so a
  -- COMMITTED scenario would have left one 'fxrev:' row per package behind while every watched
  -- relation returned to its watermark and the close reported success. A cleanup that stops at the
  -- tables somebody remembered is the shape this estate has already been caught by.
  -- The metadata scan rows are NOT deleted: they are measurements of committed fixture bytes, they
  -- are keyed on a digest rather than on a scenario, and they are shared by every revision naming
  -- those bytes.
  delete from public.phase_d_file_revision
   where revision_ref like 'fxrev:%'
     and package_ref in (select business_key from public.phase_d_object_record
                          where object_id = 'supplier_safe_package'
                            and fixture_run_id = v_fx);

  delete from public.phase_d_effect_ledger where run_id = any(v_runs);`;

const n = src.split(FIND).length - 1;
if (n !== 1) { console.error(`ANCHOR effect_ledger delete: matched ${n}`); process.exit(1); }

// which variable holds the fixture run id in this routine?
const decl = src.slice(0, src.indexOf('begin'));
console.log('declares:', decl.replace(/\s+/g, ' ').slice(0, 600));
writeFileSync(process.argv[2] || 'C:/Users/Opera/AppData/Local/Temp/claude/'
  + 'C--Users-Opera-quotesdone/051dbf76-3315-4c3b-9c5c-69c40409fdcc/scratchpad/csc_head.txt', decl);
