import { sql } from '../lib/db.mjs';
const out = {};
out.safe_view_cols = await sql(`select column_name, data_type from information_schema.columns
  where table_schema='public' and table_name='inquiries_supplier_safe' order by ordinal_position`);
out.safe_view_def = await sql(`select pg_get_viewdef('public.inquiries_supplier_safe'::regclass, true) as def`);
out.populations = await sql(`select
  (select count(*) from public.inquiries) inquiries,
  (select count(*) from public.inquiry_matches) matches,
  (select count(*) from public.customers) customers,
  (select count(*) from public.quotes) quotes,
  (select count(*) from public.leads) leads,
  (select count(*) from public.documents) documents,
  (select count(*) from public.notifications) notifications`);
out.probe_result_grants = await sql(`select grantee, privilege_type from information_schema.role_table_grants
  where table_schema='public' and table_name in ('phase_d_section8_probe_result','phase_d_section8_defect_map') order by 1,2`);
out.probe_pk = await sql(`select conname, pg_get_constraintdef(oid) as def from pg_constraint
  where conrelid in ('public.phase_d_section8_probe_result'::regclass,'public.phase_d_section8_defect_map'::regclass)`);
console.log(JSON.stringify(out, null, 1));
