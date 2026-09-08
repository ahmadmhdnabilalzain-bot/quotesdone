import { sql } from '../lib/db.mjs';
const q=async(l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('run states', `select state, count(*) n, max(opened_at) last from public.phase_c_workflow_run group by 1 order by 2 desc`);
await q('step run states', `select state, count(*) n, max(started_at) last from public.phase_c_workflow_step_run group by 1 order by 2 desc`);
await q('task states + trace status', `select (select jsonb_agg(x) from (select state, count(*) n from public.phase_c_task group by 1) x) tasks, (select jsonb_agg(y) from (select status, count(*) n from public.phase_c_trace group by 1) y) traces`);
await q('open (unsealed) traces', `select count(*) n_unsealed from public.phase_c_trace where sealed_at is null`);
await q('handoff run statuses', `select status, count(*) n from public.phase_c_handoff_run group by 1`);
