import fs from 'node:fs';

const HDR = `-- ---------------------------------------------------------------------------------------------
-- "SMART ENGINE SHOWS 234 AGENTS." THE COMPANY HAS 90.
--
-- Three surfaces, three different numbers, one company:
--   Smart Engine header pill   234   fn_ws_agents()->kpis->agents
--   Smart Engine tab body       95   fn_agents_board() total
--   Governance                  88   active_agents
--
-- 234 is not a stale count and not a stand-down miss. fn_ws_agents builds a temp table by UNIONing
-- FOUR DIFFERENT KEY-SPACES and counting the result:
--   1. org_agents where active            - the actual AI employees
--   2. 'cat:'||slug from category_agents  - category brains, prefixed
--   3. slug from category_agents          - the SAME category brains, unprefixed
--   4. agent_key from agent_knowledge     - anything that has ever had a knowledge row
-- then tries to collapse (2) and (3) back together with a case expression. Whatever that count
-- means, it is not "how many AI employees does this company have", and it is the number sitting
-- under the word "agents" on the founder's screen.
--
-- This is the instrument-measuring-the-wrong-subject defect again, and the same one that once
-- counted cron jobs as colleagues: agent_runs is a job log, category brains are knowledge scopes,
-- and an agent_knowledge row is not a member of staff.
--
-- The employee count is org_agents where active. It is 90. The category brains keep their own
-- count under their own name rather than being added to the workforce.
-- ---------------------------------------------------------------------------------------------
`;

let s = fs.readFileSync('.fresh/fn_ws_agents.sql', 'utf8');
const OLD = `      'agents', (select count(distinct case when m.k like 'cat:%' then m.k
                                            when exists (select 1 from _minds m2 where m2.k='cat:'||m.k) then 'cat:'||m.k
                                            else m.k end) from _minds m),`;
const NEW = `      -- THE WORKFORCE, and nothing else. Was a distinct count over a union of org_agents,
      -- category brains under two spellings, and every agent_key that ever had a knowledge row.
      'agents', (select count(*) from public.org_agents where active),
      -- The category brains still counted, under their own name, because they are real and useful
      -- - they are simply not employees.
      'category_brains', (select count(*) from public.category_agents where active),`;
if (!s.includes(OLD)) { console.error('NO MATCH'); process.exit(1); }
s = s.replace(OLD, NEW);
fs.writeFileSync('scripts/sql/smart_engine_counts_the_workforce.sql', HDR + s.trimEnd() + ';\n');
console.log('written');
