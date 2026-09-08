import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,4000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('sysexec cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_c_system_execution' order by ordinal_position limit 8`);
await q('sysexec triggers', `select tgname, tgfoid::regproc::text f, pg_get_triggerdef(oid) d from pg_trigger where tgrelid='public.phase_c_system_execution'::regclass and not tgisinternal order by tgname`);
await q('trace triggers', `select tgname, tgfoid::regproc::text f from pg_trigger where tgrelid='public.phase_c_trace'::regclass and not tgisinternal order by tgname`);
await q('wa counts', `select table_name, count(*) from public.kernel_write_authority where table_name in ('phase_c_refund_decision','refunds','founder_approval_request','phase_c_trace','phase_c_system_execution','quotes') group by 1`);
await q('frozen subject', `select * from public.phase_c_frozen_subject limit 40`);
