import { sql } from '../lib/db.mjs';
import { readFileSync } from 'node:fs';
const cand = readFileSync('scripts/tmp_diag/l01_candidate.sql','utf8');
const q = `do $emit$
declare v_out text := '';
begin
  execute $cand$${cand}$cand$;
  for v_out in select '' loop end loop;
  select coalesce(string_agg(t.line, E'\n' order by t.line),'(no change)') into v_out from (
    select format('%s %s/%s %s -> %s | %s',
             case when a.applies then 'LOST ' else 'GAINED' end,
             r.rule_id, s.workflow_id, s.step_id,
             case when b.applies then 'applies' else 'exempt' end,
             left(coalesce(b.why,a.why),150)) as line
      from public.phase_b_business_rule r
      cross join public.phase_b_workflow_step s
      cross join lateral public.fn_phase_d_rule_applies(r.rule_id, s.step_id) a
      cross join lateral public.zz_cand_rule_applies(r.rule_id, s.step_id) b
     where a.applies is distinct from b.applies) t;
  raise exception 'DELTA<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('DELTA<<'); console.log(i>=0?m.slice(i+7,m.lastIndexOf('>>')).replace(/\n/g,'\n'):m.slice(0,3000)); }
