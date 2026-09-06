import { sql } from '../phase_c/lib/db.mjs';
console.log(JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.legal_reviews'::regclass and contype='c'`)));
console.log(JSON.stringify(await sql(`select column_name, data_type, is_nullable, column_default from information_schema.columns where table_name='phase_d_fixture_catalogue' order by ordinal_position`)));
console.log(JSON.stringify(await sql(`select fixture_id, workflow_id, step_id, scope, field_key, value, value_kind from public.phase_d_fixture_catalogue where fixture_id >= 'PDF-3000' or scope='EFFECT_PAYLOAD' order by fixture_id`)).slice(0, 4000));
console.log(JSON.stringify(await sql(`select tgname from pg_trigger where tgrelid='public.phase_d_fixture_catalogue'::regclass and not tgisinternal`)));
console.log(JSON.stringify(await sql(`select conname, pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.phase_d_fixture_catalogue'::regclass`)));
