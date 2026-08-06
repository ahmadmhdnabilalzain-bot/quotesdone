// SPEC FILE #2 — "The Ten Operating Systems". 12 requirements.
//
// Ten per-OS requirements of identical shape ("<name> OS: row, purpose, mission, owner,
// responsibilities, objectives, staff"), plus the two rules that bind the set together: all ten
// are active, and nothing is owned twice.
//
// Every one of these ten assets was POPULATED and READ BY NOTHING at the start of row #2 —
// charter/mandate/mission 10/10, os_objective 50 rows, os_responsibility 71 rows, and the single
// view that exposed them (v_operating_manual) had zero readers of its own. So a check here that
// only counted rows would have scored all ten MET while no employee could name their own OS.
// Each per-OS check therefore asks all three questions in one boolean:
//
//   1. EXISTS      — the operating_system row, active, with purpose (charter+mandate) and mission,
//                    an owner_agent that resolves to a live employee.
//   2. POPULATED   — >=1 os_responsibility, all five os_objective horizons, >=1 active employee
//                    reachable through os_department, and an os_review the weekly cron wrote.
//   3. READ        — that OS's own purpose, mission, every one of its responsibilities and every
//                    one of its objectives are present, verbatim, in the prompt fn_agent_context
//                    builds for an employee of that OS. Text in a table is not text an employee
//                    was told; this spec file is entirely about the difference.
//
// The read leg is per-OS on purpose. A single global "fn_agent_context mentions operating_system"
// probe would have passed all ten off one OS's data.

// One active employee of this OS, resolved the way fn_agent_context resolves it:
// org_agents.department -> os_department -> operating_system.
const AGENT = (k) => `(select a.agent_key from public.org_agents a
      join public.os_department d on d.dept_key = a.department
     where d.os_key = '${k}' and a.active order by a.agent_key limit 1)`;

// MATERIALIZED so the prompt is assembled once per query, not once per strpos.
const CTX = (k) => `with ctx as materialized (select public.fn_agent_context(${AGENT(k)}, 22000) t)`;

// fn_agent_context emits left(charter,300) / left(mission,240), so the needle must be truncated the
// same way or a long mission would look absent when it is in fact there. The length guards stop a
// blank column from passing trivially: strpos(anything, '') returns 1.
const osCheck = (k, extra = 'true') => `${CTX(k)},
     o as (select * from public.operating_system where os_key = '${k}')
select
      (select count(*) from o where active
         and length(coalesce(charter,'')) > 10 and length(coalesce(mandate,'')) > 10
         and length(coalesce(mission,'')) > 10) = 1
  and (select count(*) from o join public.org_agents a
         on a.agent_key = o.owner_agent and a.active) = 1
  and (select count(*) from public.org_agents a
         join public.os_department d on d.dept_key = a.department
        where d.os_key = '${k}' and a.active) > 0
  and (select count(*) from public.os_responsibility where os_key = '${k}') > 0
  and (select count(distinct horizon) from public.os_objective
        where os_key = '${k}' and coalesce(active,true)) = 5
  and (select count(*) from public.os_review where os_key = '${k}') > 0
  and (select strpos((select t from ctx), left(mission,240)) > 0
            and strpos((select t from ctx), left(charter,300)) > 0 from o)
  and (select count(*) from public.os_responsibility r
        where r.os_key = '${k}' and strpos((select t from ctx), r.responsibility) = 0) = 0
  and (select count(*) from public.os_objective j
        where j.os_key = '${k}' and coalesce(j.active,true)
          and strpos((select t from ctx), j.objective) = 0) = 0
  and ${extra}`;

// Evidence is the count that decides it: how much of this OS's declared content actually landed in
// an employee's prompt, and which employee was asked.
const osEvidence = (k, extra = `''`) => `${CTX(k)}
select (select count(*) from public.org_agents a
          join public.os_department d on d.dept_key = a.department
         where d.os_key = '${k}' and a.active) || ' staff; prompt of ' || ${AGENT(k)}
    || ': purpose+mission ' || (select case when strpos((select t from ctx), left(o.mission,240)) > 0
             and strpos((select t from ctx), left(o.charter,300)) > 0 then 'yes' else 'no' end
           from public.operating_system o where o.os_key = '${k}')
    || ', resp ' || (select count(*) from public.os_responsibility r where r.os_key = '${k}'
           and strpos((select t from ctx), r.responsibility) > 0)
    || '/' || (select count(*) from public.os_responsibility where os_key = '${k}')
    || ', obj ' || (select count(*) from public.os_objective j where j.os_key = '${k}'
           and coalesce(j.active,true) and strpos((select t from ctx), j.objective) > 0)
    || '/' || (select count(*) from public.os_objective where os_key = '${k}')
    || '; os_review ' || (select count(*) from public.os_review where os_key = '${k}') || ${extra}`;

// The blueprint names Operations' responsibilities and 'automation' is one of them; it is owned by
// no OS at all today, so Operations carries one extra clause the other nine do not need. It is a
// clause that can pass — one os_responsibility row closes it.
const AUTOMATION = `(select count(*) from public.os_responsibility
   where responsibility = 'automation' and os_key = 'operations') = 1`;

const TEN = [
  ['os-leadership', 'leadership', 'Leadership OS'],
  ['os-commercial', 'commercial', 'Commercial OS'],
  ['os-marketplace', 'marketplace', 'Marketplace OS'],
  ['os-operations', 'operations', 'Operations OS'],
  ['os-technology', 'technology', 'Technology OS'],
  ['os-finance', 'finance', 'Finance OS'],
  ['os-legal-governance', 'legal_gov', 'Legal & Governance OS'],
  ['os-knowledge', 'knowledge', 'Knowledge OS'],
  ['os-intelligence', 'intelligence', 'Intelligence OS'],
  ['os-evolution', 'evolution', 'Evolution OS'],
];

export default async function ({ req, READERS }) {
  for (const [id, key, label] of TEN) {
    const isOps = key === 'operations';
    await req('os-', id, `${label}: row, purpose, mission, owner, responsibilities, objectives, staff`,
      osCheck(key, isOps ? AUTOMATION : 'true'),
      osEvidence(key, isOps
        ? `'; automation owned by ' || coalesce((select os_key from public.os_responsibility
             where responsibility = 'automation'), 'NO os')`
        : `''`));
  }

  // All ten exist, are numbered 1-10, are active, have a live owner — and are read: the weekly
  // os_review cron produced a row for every one of them in its most recent period, and
  // operating_system itself has routine/view/cron readers.
  await req('os-', 'os-all-ten-active', 'All ten named Operating Systems exist and are active', `
    select (select count(*) from public.operating_system where active) = 10
       and (select count(distinct num) from public.operating_system) = 10
       and (select min(num) || '-' || max(num) from public.operating_system) = '1-10'
       and (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) = 10
       and (select count(distinct os_key) from public.os_review
             where period = (select max(period) from public.os_review)) = 10
       and ${READERS('operating_system')} > 0`, `
    select (select count(*) from public.operating_system where active) || '/10 active, '
        || (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) || ' owners live, os_review '
        || (select max(period) from public.os_review) || ' covers '
        || (select count(distinct os_key) from public.os_review
             where period = (select max(period) from public.os_review)) || '/10, '
        || ${READERS('operating_system')} || ' readers of operating_system'`);

  // "No duplicated ownership" has to hold for BOTH ownership tables the blueprint defines, and the
  // rule has to reach the people it binds. os_responsibility is structurally safe — PRIMARY KEY
  // (responsibility) alone makes a second owner impossible — but os_knowledge_domain's key is
  // (os_key, domain_key), which permits exactly the duplication the rule forbids.
  await req('os-', 'os-exclusive-ownership',
    `No responsibility or knowledge domain is owned by two OSes`, `
    ${CTX('leadership')}
    select (select count(*) from (select responsibility from public.os_responsibility
              group by 1 having count(*) > 1) z) = 0
       and exists (select 1 from pg_constraint
                    where conrelid = 'public.os_responsibility'::regclass
                      and contype = 'p' and pg_get_constraintdef(oid) = 'PRIMARY KEY (responsibility)')
       and (select count(*) from (select domain_key from public.os_knowledge_domain
              where ownership = 'owns' group by 1 having count(*) > 1) z) = 0
       and strpos((select t from ctx), 'no other OS may own') > 0`, `
    select (select count(*) from (select responsibility from public.os_responsibility
              group by 1 having count(*) > 1) z) || ' of '
        || (select count(*) from public.os_responsibility)
        || ' responsibilities owned twice; '
        || (select count(*) from (select domain_key from public.os_knowledge_domain
              where ownership = 'owns' group by 1 having count(*) > 1) z) || ' of '
        || (select count(distinct domain_key) from public.os_knowledge_domain)
        || ' domains owned twice, '
        || (select count(*) from (select domain_key from public.os_knowledge_domain
              group by 1 having count(*) filter (where ownership = 'owns') = 0) z) || ' owned by none'`);
}
