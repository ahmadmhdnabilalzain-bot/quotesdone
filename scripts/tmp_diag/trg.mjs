import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t)).slice(0,1800));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,250)}`)}};
await q('self_reg trigger', `select c.relname, tg.tgname, p.proname, pg_get_triggerdef(tg.oid) def from pg_trigger tg join pg_proc p on p.oid=tg.tgfoid join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and tg.tgname like '%self_reg%'`);
await q('poster set', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~* 'net[.]http_(post|get)' and p.proname like '%provision%'`);
await q('trg body', `select left(prosrc,400) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='trg_self_reg_category'`);
