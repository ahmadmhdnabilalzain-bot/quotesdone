import { sql } from '../phase_b/lib/db.mjs';
console.log(JSON.stringify(await sql(`select column_name, is_nullable, column_default from information_schema.columns where table_schema='public' and table_name='founder_command' and column_name in ('message_id','command_id','channel')`)));
console.log(JSON.stringify(await sql(`select count(*) n, max(created_at) newest from public.founder_command`)));
