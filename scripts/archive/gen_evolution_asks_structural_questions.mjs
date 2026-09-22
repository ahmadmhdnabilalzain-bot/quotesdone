// ROW #3 s35 — the Evolution OS has never asked a question about the organisation.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   s35-restructure-four-questions  MISSING  0 of 4 structural question(s) appear among 32
//                                            proposal(s)/180d
//   evolution-proposes-structure    MISSING  5 of 8 domains covered; absent: organisation, …
//
// fn_evolution_scan proposes on three triggers — repeated_failure, metric_off_target and
// cost_anomaly — and every one of them is about a routine, a metric or a bill. Not one is about
// the company's own shape. Meanwhile:
//
//   57 of 66 active employees have not produced a single run in 30 days
//   4 departments hold 5+ open tasks with NO employee that has run in 30 days
//     evolution 25, legal 19, knowledge_eng 13, hr 8
//   4 operating systems carry a backlog above 5 per head, Operations OS at 18.8
//   13 departments have two or more employees who are all dormant
//
// An Evolution OS that proposes model routing changes while 57 of its 66 employees are dormant is
// not looking at the organisation. Four blocks are added, one per structural question the spec
// names, in exactly the shape of the three that are already there.
//
// ── EVERY BLOCK ONLY FIRES WHEN THE DATA SAYS SO ────────────────────────────────────────────────
// These are `insert ... select ... where`, like the three above them: no proposal is written unless
// its condition holds on live rows. If the company hires, routes work properly and the backlog
// falls, these stop proposing on their own — which is the difference between a scan and a template.
//
// The two that could be noisy are aggregated into ONE proposal each rather than one per employee:
// 57 dormant employees is a single organisational decision, not 57 of them, and a founder handed 57
// rows would read none of them. Overload and understaffing stay per-department, because each names
// a different department with a different number and they are acted on separately.
//
// Each block also refuses to re-propose the same trigger inside 30 days. Without that, a weekly
// cron restates the same four facts every Monday and the proposal queue becomes a newsletter.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/evolution_asks_structural_questions.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_evolution_scan' limit 1`);
if (!def) { console.error('fn_evolution_scan not found'); process.exit(1); }
if (/THE FOUR STRUCTURAL QUESTIONS/.test(def)) { console.error('REFUSING: fn_evolution_scan already asks the structural questions.'); process.exit(1); }

const ANCHOR = `  return (select count(*) from evolution_proposal where status='proposed');`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the return anchor did not match exactly once. Re-read fn_evolution_scan.');
  process.exit(1);
}

// A proposal about the same SUBJECT is not repeated inside a month. The scan runs weekly.
//
// Keyed on subject rather than on a trigger_kind of my own choosing, because evolution_proposal
// carries two CHECK constraints that the first draft of this file violated and staging caught:
//   trigger_kind in (repeated_failure, metric_off_target, cost_anomaly, manual, audit_gap, review_rejection)
//   change_class in (knowledge, process, code, policy, model_routing, org)
// All four questions are an audit of the organisation, so they share trigger_kind 'audit_gap' and
// change_class 'org' — which means the subject is what distinguishes them.
const FRESH = (subj) => `not exists (select 1 from evolution_proposal p
        where p.trigger_kind = 'audit_gap' and p.subject = ${subj}
          and p.created_at > now() - interval '30 days')`;

const BLOCK = `  -- ── THE FOUR STRUCTURAL QUESTIONS ─────────────────────────────────────────────────────────────
  -- The three triggers above ask about routines, metrics and bills. These ask about the company.

  -- IS ANOTHER ROLE IDLE? One proposal, not one per employee: 57 dormant employees is a single
  -- organisational decision and a founder handed 57 rows would read none of them.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', 'workforce',
         format('%s of %s active employees are dormant — no recorded run in 30 days. Longest-standing: %s.',
                d.idle, d.total, d.sample),
         jsonb_build_object('dormant', d.idle, 'active', d.total, 'sample', d.sample),
         'Decide, for each dormant role, which of two things is true: nothing routes to it, or the role is not needed. Where nothing routes to it the routing is the defect and the role is fine. Where the role is not needed it should be retired rather than carried as an employee that never works.',
         'org'
    from (select count(*) filter (where not exists (select 1 from agent_runs r
                                    where r.agent = a.agent_key and r.started_at > now() - interval '30 days')) idle,
                 count(*) total,
                 (select string_agg(x.agent_key, ', ') from (
                    select a2.agent_key from org_agents a2 where a2.active
                     and not exists (select 1 from agent_runs r2 where r2.agent = a2.agent_key
                                      and r2.started_at > now() - interval '30 days')
                     order by a2.agent_key limit 5) x) sample
            from org_agents a where a.active) d
   where d.idle > 0 and ${FRESH("'workforce'")}
  on conflict do nothing;

  -- IS ONE ROLE OVERLOADED? Per operating system, because each names a different number and they
  -- are acted on separately.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', h.name,
         format('%s carries a backlog of %s open tasks per head across %s employee(s) — the role is overloaded.',
                h.name, h.backlog_per_head, coalesce(h.employees, 0)),
         jsonb_build_object('backlog_per_head', h.backlog_per_head, 'employees', h.employees,
                            'open_tasks', h.open_tasks, 'os_key', h.os_key),
         format('Either split the work of %s across more employees, or accept that the backlog is not going to be cleared and close what is no longer worth doing. Carrying it at this level is a decision by default.', h.name),
         'org'
    from v_os_health h
   where h.backlog_per_head > 5 and ${FRESH('h.name')}
  on conflict do nothing;

  -- IS A NEW SPECIALIST NEEDED? Work exists in the department and no employee in it has run at all.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', z.dept_key,
         format('%s holds %s open task(s) and not one active employee in it has run in 30 days — the work has no one doing it.',
                z.dept_key, z.n),
         jsonb_build_object('open_tasks', z.n, 'department', z.dept_key),
         format('A new specialist is needed for %s, or the work belongs to a department that already has someone running. Decide which before hiring: staffing a queue that should have been routed elsewhere adds an employee and keeps the defect.', z.dept_key),
         'org'
    from (select t.dept_key, count(*) n from org_tasks t
           where t.status <> 'done' and t.dept_key is not null
             and not exists (select 1 from org_agents a join agent_runs r on r.agent = a.agent_key
                              and r.started_at > now() - interval '30 days'
                             where a.active and a.department = t.dept_key)
           group by t.dept_key having count(*) >= 5) z
   where ${FRESH('z.dept_key')}
  on conflict do nothing;

  -- SHOULD TWO ROLES MERGE? Aggregated for the same reason as role_idle.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', 'organisation structure',
         format('%s department(s) have two or more employees who are ALL dormant: %s.', m.depts, m.sample),
         jsonb_build_object('departments', m.depts, 'sample', m.sample),
         'Consider whether these roles should merge. Two dormant employees in one department is either duplicated scope that should be consolidated into a single role, or a department that receives no work at all — and those two answers lead to opposite actions, so establish which before combining anything.',
         'org'
    from (select count(*) depts,
                 (select string_agg(y.department||' ('||y.n||')', ', ' order by y.n desc) from (
                    select a3.department, count(*) n from org_agents a3 where a3.active
                     and not exists (select 1 from agent_runs r3 where r3.agent = a3.agent_key
                                      and r3.started_at > now() - interval '30 days')
                     group by a3.department having count(*) >= 2 order by count(*) desc limit 5) y) sample
            from (select a.department from org_agents a where a.active
                   and not exists (select 1 from agent_runs r where r.agent = a.agent_key
                                    and r.started_at > now() - interval '30 days')
                   group by a.department having count(*) >= 2) q) m
   where m.depts > 0 and ${FRESH("'organisation structure'")}
  on conflict do nothing;

${ANCHOR}`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_evolution_scan ${def.length} -> ${out.length} chars`);
