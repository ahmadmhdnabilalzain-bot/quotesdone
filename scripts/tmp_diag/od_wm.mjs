import { sql } from '../phase_b/lib/db.mjs';
console.log('WRITE MAP RELATIONS:');
console.log(JSON.stringify(await sql(`select distinct target_relation from public.phase_d_object_write_map order by 1`)));
console.log('\nTABLES matching outbox/notification/queue/event:');
console.log(JSON.stringify(await sql(`select table_schema, table_name from information_schema.tables where table_name ~ 'outbox|notif|queue|event|backup|org_task' order by 1,2`)));
