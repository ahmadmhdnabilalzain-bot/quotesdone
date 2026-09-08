import { sql } from '../lib/db.mjs';
console.log('--- net tables ---');
console.log(JSON.stringify(await sql(`select table_name from information_schema.tables where table_schema='net' order by 1`)));
for (const t of ['http_request_queue', '_http_response']) {
  console.log('\n--- net.' + t + ' columns ---');
  console.log(JSON.stringify(await sql(`select column_name, data_type, is_nullable, column_default from information_schema.columns where table_schema='net' and table_name='${t}' order by ordinal_position`), null, 1));
}
console.log('\n--- watermark ---');
console.log(JSON.stringify(await sql(`select coalesce(max(id),0) as max_id, count(*) as depth from net.http_request_queue`)));
console.log('\n--- net._http_response watermark ---');
try { console.log(JSON.stringify(await sql(`select coalesce(max(id),0) as max_id, count(*) as n from net._http_response`))); } catch (e) { console.log('ERR ' + e.message.slice(0, 300)); }
console.log('\n--- grants on net.http_request_queue ---');
console.log(JSON.stringify(await sql(`select grantee, privilege_type from information_schema.role_table_grants where table_schema='net' and table_name='http_request_queue' order by 1,2`)));
console.log('\n--- write map for leads / inquiries / customers ---');
console.log(JSON.stringify(await sql(`select object_id, target_relation, operation, key_column, column_map from public.phase_d_object_write_map where target_relation in ('public.leads','public.inquiries','public.customers') order by 1`), null, 1));
