import fs from 'node:fs';

const HDR = `-- ---------------------------------------------------------------------------------------------
-- THE READING SITES THE FIRST PASS MISSED ON OPERATIONS AND COMPANY.
--
-- Fixing the task predicates cleared the tiles the founder pointed at and left four lists beside
-- them still showing the old company:
--
--   Operations · decisions_24h        44, of which 1 is after the reset - a wall-clock 24h window
--                                     straddling the watermark
--   Operations · decisions list       20 rows, no filter of any kind
--   Operations · security events      10 rows, none of them after the reset
--   Company    · departments bar      2,839 LIFETIME actions across 20 departments
--   Company    · recent agent runs    12 rows
--   Company    · missing legal docs   5
--
-- Every one is a count over history with no bound. They take the same fresh-start watermark as the
-- rest; none of the rows is deleted or altered.
--
-- TWO THINGS ARE DELIBERATELY LEFT ALONE, because clearing them would be hiding rather than
-- resetting:
--
--   Company · missing legal documents (5). These are not events that happened, they are documents
--   that DO NOT EXIST - legal_checklist rows where present = false. A watermark cannot make a
--   missing document present, and dating it out of view would tell him the company is compliant
--   when it is not. It stays.
--
--   Company · recent agent runs. Nine of the twelve are AFTER the reset: they are the watcher crons
--   the stand-down deliberately left running - backup, uptime, health. Showing them is correct.
--   The list is watermarked anyway so the three older rows drop, and what remains is true.
-- ---------------------------------------------------------------------------------------------
`;

let out = HDR;

let ops = fs.readFileSync('.fresh/fn_ws_operations2.sql', 'utf8');
const opsEdits = [
  ["from (select * from security_events order by created_at desc limit 10) e",
   "from (select * from security_events where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 10) e"],
  ["'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours')",
   "'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours' and created_at >= public.fn_os_fresh_start_at())"],
  ["from (select * from decision_log order by created_at desc limit 20) d",
   "from (select * from decision_log where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 20) d"],
];
for (const [a, b] of opsEdits) {
  if (!ops.includes(a)) { console.error('OPS NO MATCH: ' + a.slice(0, 60)); process.exit(1); }
  ops = ops.replace(a, b);
}
out += '\n' + ops.trimEnd() + ';\n';

let co = fs.readFileSync('.fresh/fn_ws_company2.sql', 'utf8');
const coEdits = [
  ["from agent_actions group by 1 order by 2 desc limit 20) d",
   "from agent_actions where created_at >= public.fn_os_fresh_start_at() group by 1 order by 2 desc limit 20) d"],
  ["from (select * from agent_runs order by started_at desc limit 12) r",
   "from (select * from agent_runs where started_at >= public.fn_os_fresh_start_at() order by started_at desc limit 12) r"],
];
for (const [a, b] of coEdits) {
  if (!co.includes(a)) { console.error('CO NO MATCH: ' + a.slice(0, 60)); process.exit(1); }
  co = co.replace(a, b);
}
out += '\n' + co.trimEnd() + ';\n';

fs.writeFileSync('scripts/sql/operations_company_remaining_lists.sql', out);
console.log('written');
