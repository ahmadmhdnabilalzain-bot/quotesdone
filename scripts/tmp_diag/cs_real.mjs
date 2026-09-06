import { sql } from '../phase_b/lib/db.mjs';
const label = process.argv[2] || 'phase-d-closing-2026-08-24';
const r1 = await sql(`select public.fn_phase_d_committed_scenario_open('{"label":${JSON.stringify(label)}}'::jsonb) as v`);
console.log('OPEN  ' + JSON.stringify(r1[0].v));
const id = r1[0].v.scenario_id;
const r2 = await sql(`select count(*) n from public.customers where email like 'zz-phase-d-cs-%'`);
console.log('COMMITTED customers matching: ' + JSON.stringify(r2));
const r3 = await sql(`select public.fn_phase_d_committed_scenario_close(${id}) as v`);
console.log('CLOSE ' + JSON.stringify(r3[0].v));
const r4 = await sql(`select * from public.phase_d_committed_scenario where scenario_id=${id}`);
console.log('REGISTER ' + JSON.stringify(r4[0].assertions));
const r5 = await sql(`select (select count(*) from public.fn_phase_d_fixture_residue()) residue,
  (select count(*) from public.customers) customers, (select count(*) from public.leads) leads,
  (select count(*) from public.doc_backups) doc_backups, (select count(*) from public.company_event) company_event,
  (select count(*) from public.inquiries) inquiries`);
console.log('AFTER ' + JSON.stringify(r5));
