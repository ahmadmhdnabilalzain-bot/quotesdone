import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select column_name from information_schema.columns where table_schema='public' and table_name='ai_cost_log' order by ordinal_position`)));
console.log(JSON.stringify(await sql(`select count(*) n from public.llm_attempt`)));
