import { sql } from '../lib/db.mjs';
console.log('--- constraints on phase_d_outbound_door ---');
console.log(JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) as def from pg_constraint where conrelid='public.phase_d_outbound_door'::regclass order by 1`), null, 1));
console.log('--- grants ---');
console.log(JSON.stringify(await sql(`select grantee, privilege_type from information_schema.role_table_grants where table_schema='public' and table_name='phase_d_outbound_door' order by 1,2`)));
console.log('--- triggers on phase_d_outbound_door ---');
console.log(JSON.stringify(await sql(`select tg.tgname, pg_get_triggerdef(tg.oid) as def from pg_trigger tg where tg.tgrelid='public.phase_d_outbound_door'::regclass and not tg.tgisinternal`), null, 1));
