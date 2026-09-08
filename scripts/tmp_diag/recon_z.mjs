import { sql } from '../lib/db.mjs';
const q=async(l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('freeze triggers on phase_b tables', `select c.relname, t.tgname, p.proname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid where not t.tgisinternal and n.nspname='public' and p.proname='fn_phase_b_freeze_guard' order by 1`);
await q('steps with an independent reviewer', `select count(*) n_with_reviewer, count(*) filter (where is_closure_step) n_closure from public.phase_b_workflow_step where nullif(btrim(independent_reviewer_role_id),'') is not null`);
await q('closure flag consistency in frozen registry', `select count(*) filter (where (next_step_if_pass='WORKFLOW_COMPLETE') <> is_closure_step) n_disagree, count(*) total from public.phase_b_workflow_step`);
