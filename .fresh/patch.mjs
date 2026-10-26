import fs from 'node:fs';

const HDR = `-- ---------------------------------------------------------------------------------------------
-- OPERATIONS, ASSISTANCE, COMPANY AND REPORTS.
--
-- Operations and Assistance were never showing STALE rows. They were showing the SAME six
-- crm_tasks the stand-down had just cancelled, because both routines ask for
--   where coalesce(status,'') <> 'done'
-- which was correct while 'done' was the only terminal state and became wrong the moment
-- 'cancelled' existed. A cancelled task is not open work. Fixed in the predicate, not in the data,
-- because the data was already right - the same shape of defect as fn_ws_governance filtering on
-- "escalated" with no status filter at all.
--
-- Operations' task LIST had no status filter whatsoever: it ordered by "is it done" and printed
-- everything else, so a cancelled task sorted to the top and read as live work.
--
-- Company and Reports are different. They read history on purpose - 30-day escalation counts, the
-- report registry, evaluation snapshots - so they take the fresh-start watermark rather than a
-- status filter. Nothing is wrong with those rows. The founder does not want the old company on
-- the screen while the new chain of command is designed; he did not ask for its records to be
-- destroyed, and they are not.
-- ---------------------------------------------------------------------------------------------
`;

let out = HDR;
for (const n of ['fn_ws_operations', 'fn_ea_agenda', 'fn_ws_company', 'fn_ws_reports']) {
  let s = fs.readFileSync('.fresh/' + n + '.sql', 'utf8');
  s = s.split("coalesce(status,'')<>'done'").join("coalesce(status,'open') not in ('done','cancelled')");
  s = s.replace(
    "from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 20) t",
    "from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by created_at desc limit 20) t");
  s = s.replace(
    'from (select * from agent_evals order by snapshot_at desc limit 4) e',
    'from (select * from agent_evals where snapshot_at >= public.fn_os_fresh_start_at() order by snapshot_at desc limit 4) e');
  s = s.split('from public.report_registry order by created_at desc limit 25')
       .join('from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 25');
  s = s.split('from public.report_registry order by report_type, created_at desc')
       .join('from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by report_type, created_at desc');
  s = s.replace(
    "from public.exec_reports r where r.officer='ceo' order by r.created_at desc limit 1",
    "from public.exec_reports r where r.officer='ceo' and r.created_at >= public.fn_os_fresh_start_at() order by r.created_at desc limit 1");
  out += '\n' + s.trimEnd() + ';\n';
}
fs.writeFileSync('scripts/sql/operations_assistance_company_reports.sql', out);
console.log('written');
