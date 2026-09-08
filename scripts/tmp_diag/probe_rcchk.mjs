import { sql } from '../lib/db.mjs';
console.log('CHK', JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.review_chain'::regclass and contype='c'`)));
console.log('STAGES', JSON.stringify(await sql(`select distinct stage from public.review_chain limit 20`)));
console.log('SUBJTYPES', JSON.stringify(await sql(`select distinct subject_type from public.review_chain limit 20`)));
