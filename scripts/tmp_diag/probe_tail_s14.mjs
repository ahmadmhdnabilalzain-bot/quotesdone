import { sql } from '../lib/db.mjs';
const J = (x) => JSON.stringify(x);
// static facts
console.log('reveal_invoices pkey', J(await sql(`select conname, pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.reveal_invoices'::regclass and contype in ('p','u')`)));
console.log('W12-S06 effect', J(await sql(`select step_id, expected_effect_type, effect_object_id, effect_relation from public.phase_d_step_effect where step_id='W12-S06'`)));
console.log('W16 effects', J(await sql(`select step_id, expected_effect_type, effect_object_id from public.phase_d_step_effect where workflow_id='W16' order by step_id`)));
console.log('W01-S07 effect', J(await sql(`select step_id, effect_object_id from public.phase_d_step_effect where step_id='W01-S07'`)));
console.log('W05 founder-gated steps', J(await sql(`select step_id, founder_gate from public.phase_b_workflow_step where workflow_id='W05' and lower(coalesce(btrim(founder_gate),'none'))<>'none'`)));
console.log('supplier_assignment map', J(await sql(`select object_id, target_relation, key_column, column_map from public.phase_d_object_write_map where object_id in ('supplier_assignment','dispatch_batch','notification_attempt')`)));
console.log('inquiry_matches cols', J(await sql(`select column_name, data_type from information_schema.columns where table_name='inquiry_matches' and table_schema='public' order by ordinal_position`)).slice(0,900));
