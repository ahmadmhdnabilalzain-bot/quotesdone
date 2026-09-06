import { sql } from '../phase_b/lib/db.mjs';
const p = (t, r) => { console.log('=== ' + t + ' (' + (r ? r.length : 0) + ') ==='); console.log(JSON.stringify(r, null, 1)); };
p('gate enforcement tables', await sql(`select table_name from information_schema.tables where table_schema='public' and table_name like '%gate%' order by 1`));
p('gates bound to W09 steps + their required context', await sql(`
select g.* from public.phase_d_gate_enforcement g
 where g.gate_id in (select distinct unnest(gate_ids) from public.phase_d_handler_binding where step_id like 'W09-%')
 order by g.gate_id`).catch(e=>[{err:String(e.message).slice(0,200)}]));
p('BR-026 applies on W09 steps', await sql(`select s.step_id, a.applies, a.why from public.phase_b_workflow_step s cross join lateral public.fn_phase_d_rule_applies('BR-026', s.step_id) a where s.workflow_id='W09' order by s.step_id limit 3`));
