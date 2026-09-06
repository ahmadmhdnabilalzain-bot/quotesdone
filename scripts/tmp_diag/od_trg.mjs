import { sql } from '../phase_b/lib/db.mjs';
const tables = ['customers','leads','inquiries','inquiry_matches','documents','quotes',
  'phase_c_workflow_run','phase_c_workflow_step_run','workflow_run','workflow_step_run',
  'org_tasks','notifications','company_event','doc_backups','phase_c_event_outbox','event_delivery'];
const list = tables.map(t=>`'${t}'`).join(',');
const r = await sql(`
select c.relname as tbl, tg.tgname as trg, tg.tgenabled as enabled,
       n2.nspname||'.'||p.proname as fn,
       pg_get_triggerdef(tg.oid) as def
  from pg_trigger tg
  join pg_class c on c.oid=tg.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_proc p on p.oid=tg.tgfoid
  join pg_namespace n2 on n2.oid=p.pronamespace
 where not tg.tgisinternal and n.nspname='public'
   and c.relname in (${list})
 order by c.relname, tg.tgname`);
for (const x of r) console.log(`${x.tbl}\t${x.trg}\tenabled=${x.enabled}\tfn=${x.fn}\n    ${x.def}`);
console.log('\n---COUNT---', r.length);
