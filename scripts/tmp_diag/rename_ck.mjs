import { sql } from '../phase_b/lib/db.mjs';
await sql(`alter table public.phase_d_injected_defect_disposition
  drop constraint if exists phase_d_injected_defect_disposition_disposition_check,
  drop constraint if exists phase_d_injected_defect_disp_what_would_make_it_executabl_check,
  drop constraint if exists phase_d_injected_defect_disposition_reason_check,
  add constraint phase_d_disposition_value_ck check (disposition in ('PERMANENT_EXEMPTION','DEFERRED_TO_A_BUILT_PATH')),
  add constraint phase_d_disposition_reason_ck check (length(btrim(reason)) > 40),
  add constraint phase_d_disposition_next_ck check (length(btrim(what_would_make_it_executable)) > 20)`);
console.log(JSON.stringify(await sql(`select conname from pg_constraint where conrelid='public.phase_d_injected_defect_disposition'::regclass and contype='c' order by 1`)));
