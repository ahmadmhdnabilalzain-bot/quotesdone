import { sql } from '../lib/db.mjs';
console.log('--- fn security/volatility ---');
console.log(JSON.stringify(await sql(`
select p.proname, p.prosecdef, p.provolatile, pg_get_userbyid(p.proowner) as owner
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in
 ('fn_phase_d_object_write','fn_phase_d_outbound_requests_by_this_transaction','fn_phase_d_fixture_residue','fn_phase_d_outbound_state','fn_enqueue_doc_backups','trg_self_reg_category','fn_provision_category_call')
 order by 1`)));
console.log('\n--- outbound state board ---');
console.log(JSON.stringify(await sql(`select * from public.fn_phase_d_outbound_state()`), null, 1));
console.log('\n--- triggers on doc_backups / documents (all) ---');
console.log(JSON.stringify(await sql(`
select c.relname, tg.tgname, pg_get_triggerdef(tg.oid) as def
 from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('doc_backups','documents') and not tg.tgisinternal order by 1,2`), null, 1));
console.log('\n--- fn_enqueue_doc_backups callers (pg_proc) ---');
console.log(JSON.stringify(await sql(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%fn_enqueue_doc_backups%' order by 1`)));
console.log('\n--- current residue ---');
console.log(JSON.stringify(await sql(`select * from public.fn_phase_d_fixture_residue()`)));
