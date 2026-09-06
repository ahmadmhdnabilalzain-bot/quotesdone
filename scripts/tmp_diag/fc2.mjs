import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select data_type from information_schema.columns where table_schema='public' and table_name='founder_command' and column_name='message_id'`)));
console.log(JSON.stringify(await sql(`select message_id from public.founder_command order by command_id desc limit 3`)));
console.log(JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.founder_command'::regclass and contype in ('u','c')`)).slice(0,600));
