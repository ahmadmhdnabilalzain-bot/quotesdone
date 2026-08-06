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
//                    reachable through os_department.
//   3. READ        — that OS's own purpose, mission, every one of its responsibilities and every
//                    one of its objectives are present, verbatim, IN THAT OS'S OWN BLOCK of the
//                    prompt fn_agent_context builds for an employee of that OS. Text in a table is
//                    not text an employee was told; this spec file is entirely about the difference.
//
// The read leg is per-OS on purpose. A single global "fn_agent_context mentions operating_system"
// probe would have passed all ten off one OS's data.
//
// TWO THINGS THIS FILE DELIBERATELY DOES NOT CLAIM.
//   (a) That fn_agent_context has a caller. Its only SQL-visible caller is fn_agent_context_capped,
//       which has zero callers and zero cron jobs of its own; the real callers are TypeScript Edge
//       Functions, which pg_proc/pg_views/cron.job structurally cannot see. Asserting SQL-visible
//       reachability here would manufacture a MISSING for a function that is in fact called, which
//       is the same error as manufacturing a MET. It is stated here rather than scored.
//   (b) That os_review is part of a per-OS requirement. "Review" is not one of the seven things
//       these ten requirements name, and an unbounded `count(os_review) > 0` is a population test
//       with no recency and no reader. It is asserted ONCE, with both, in os-all-ten-active.

// One active employee of this OS, resolved the way fn_agent_context resolves it:
// org_agents.department -> os_department -> operating_system. Deterministic only because
// os_department.dept_key is unique — which os-all-ten-active asserts, because fn_agent_context
// picks the OS with `limit 1` and no ORDER BY and would otherwise render an arbitrary one.
const AGENT = (k) => `(select a.agent_key from public.org_agents a
      join public.os_department d on d.dept_key = a.department
     where d.os_key = '${k}' and a.active order by a.agent_key limit 1)`;

// THE ANCHOR. The prompt is 26,000-30,000 characters and most of it is common to every employee,
// so an unanchored strpos over the whole string is not a test that the OS block arrived: measured,
// 'security' and 'platform' (technology), 'quotes' and 'matching' (marketplace), 'mission' and
// 'strategy' (leadership) and eleven more bare-word responsibilities are present in all nine
// prompts of OSes that do NOT own them — for 'security' because fn_agent_context emits the word in
// the POSTURE paragraph it hands every agent. Those clauses were true with or without the OS block.
//
// fn_agent_context emits the section under '# YOUR OPERATING SYSTEM — <name>' and the next '\n# '
// starts a different section, so that slice is the OS block and nothing else. Measured on
// production: 746-1060 characters per OS, and all ten still carry 100% of their responsibilities,
// objectives, purpose and mission inside it. If the block is absent the slice is '' and every
// needle fails, which is the intended verdict.
const CTX = (k) => `with ctx as materialized (
       select public.fn_agent_context(${AGENT(k)}, 22000) t),
     head as (select case when position('# YOUR OPERATING SYSTEM' in t) = 0 then ''
                     else substring(t from position('# YOUR OPERATING SYSTEM' in t)) end x from ctx),
     blk as (select substring(x from 1 for
                 coalesce(nullif(position(E'\\n# ' in x), 0) - 1, length(x))) b from head)`;

// fn_agent_context emits left(charter,300) / left(mission,240), so the needle must be truncated the
// same way or a long mission would look absent when it is in fact there. The length guards stop a
// blank column from passing trivially: strpos(anything, '') returns 1. The same guard is folded
// into the responsibility and objective clauses — a blank row must not satisfy its own read test.
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
  and (select strpos((select b from blk), left(mission,240)) > 0
            and strpos((select b from blk), left(charter,300)) > 0 from o)
  and (select count(*) from public.os_responsibility r
        where r.os_key = '${k}'
          and (length(trim(coalesce(r.responsibility,''))) < 2
               or strpos((select b from blk), r.responsibility) = 0)) = 0
  and (select count(*) from public.os_objective j
        where j.os_key = '${k}' and coalesce(j.active,true)
          and (length(trim(coalesce(j.objective,''))) < 2
               or strpos((select b from blk), j.objective) = 0)) = 0
  and ${extra}`;

// Evidence is the count that decides it: how much of this OS's declared content actually landed in
// an employee's prompt, which employee was asked, and how large the slice searched was — a reader
// who does not see the block size cannot tell an anchored match from a 28,000-character haystack.
// Both sides of the objective ratio filter on active; mixing the filters is how a check prints
// 'obj 4/5' beside a MET verdict the moment one objective is deactivated.
const osEvidence = (k, extra = `''`) => `${CTX(k)}
select (select count(*) from public.org_agents a
          join public.os_department d on d.dept_key = a.department
         where d.os_key = '${k}' and a.active) || ' staff; prompt of ' || ${AGENT(k)}
    || ' (OS block ' || (select length(b) from blk) || ' of '
    || (select length(t) from ctx) || ' chars)'
    || ': purpose+mission ' || (select case when strpos((select b from blk), left(o.mission,240)) > 0
             and strpos((select b from blk), left(o.charter,300)) > 0 then 'yes' else 'no' end
           from public.operating_system o where o.os_key = '${k}')
    || ', resp ' || (select count(*) from public.os_responsibility r where r.os_key = '${k}'
           and strpos((select b from blk), r.responsibility) > 0)
    || '/' || (select count(*) from public.os_responsibility where os_key = '${k}')
    || ', obj ' || (select count(*) from public.os_objective j where j.os_key = '${k}'
           and coalesce(j.active,true) and strpos((select b from blk), j.objective) > 0)
    || '/' || (select count(*) from public.os_objective
                where os_key = '${k}' and coalesce(active,true)) || ${extra}`;

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

// A reader of operating_system that is neither its writer nor a dead reference. READERS() counts
// three things it must not: fn_os_review, which is the only routine that WRITES the table (measured:
// it is the sole match for an update/insert against operating_system); the literal string
// 'operating_system'::text inside v_operating_manual's own definition; and v_operating_manual itself,
// the view this file's header records as having no readers. Requiring the routine to be named by an
// ACTIVE cron job is what makes it a live consumer rather than a mention. Measured on production: 5
// qualify — fn_company_snapshot, fn_exec_meeting, fn_graph_rebuild, fn_os_health_brief, fn_os_improve.
const LIVE_OS_READERS = `(select count(*) from pg_proc p
     join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and p.proname not in ('fn_os_review')
      and pg_get_functiondef(p.oid) ~* '\\yoperating_system\\y'
      and exists (select 1 from cron.job j
                   where j.active and j.command ~* ('\\y' || p.proname || '\\y')))`;

// The department -> OS resolution every read leg in this file depends on. os_department's PRIMARY
// KEY is (os_key, dept_key), which permits one department to belong to several OSes; fn_agent_context
// resolves it with `limit 1` and no ORDER BY, so a second mapping makes which OS an employee is told
// they belong to an arbitrary unordered row, and makes AGENT(k) above disagree with it. Made
// structural in scripts/sql/os_ownership_structural.sql; asserted here so it stays that way.
const DEPT_UNIQUE = `exists (select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'os_department'
      and indexdef ~* 'unique index .* \\(dept_key\\)$')`;

export default async function ({ req }) {
  for (const [id, key, label] of TEN) {
    const isOps = key === 'operations';
    await req('os-', id, `${label}: row, purpose, mission, owner, responsibilities, objectives, staff`,
      osCheck(key, isOps ? AUTOMATION : 'true'),
      osEvidence(key, isOps
        ? `'; automation owned by ' || coalesce((select os_key from public.os_responsibility
             where responsibility = 'automation'), 'NO os')`
        : `''`));
  }

  // All ten exist, are numbered 1-10, are active, have a live owner — and are read.
  //
  // The os_review leg used to compare `period = (select max(period) from os_review)` to itself,
  // which is true for any table with rows: stop the weekly cron and it reads 10/10 forever. It is
  // now bounded on created_at against a 10-day window, one weekly period plus margin, so a dead
  // os_review_weekly turns this MISSING inside ten days. Measured: 20 rows / 10 OSes in 9 days,
  // latest 2026-08-06 07:09.
  await req('os-', 'os-all-ten-active', 'All ten named Operating Systems exist and are active', `
    select (select count(*) from public.operating_system where active) = 10
       and (select count(distinct num) from public.operating_system) = 10
       and (select min(num) || '-' || max(num) from public.operating_system) = '1-10'
       and (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) = 10
       and (select count(distinct os_key) from public.os_review
             where created_at > now() - interval '10 days') = 10
       and ${LIVE_OS_READERS} > 0
       and ${DEPT_UNIQUE}`, `
    select (select count(*) from public.operating_system where active) || '/10 active, '
        || (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) || ' owners live, os_review '
        || (select count(distinct os_key) from public.os_review
             where created_at > now() - interval '10 days') || '/10 OS within 10 days (latest '
        || coalesce((select max(period) from public.os_review), 'never') || '), '
        || ${LIVE_OS_READERS} || ' cron-live non-writer reader(s): '
        || coalesce((select string_agg(p.proname, ', ' order by p.proname) from pg_proc p
              join pg_namespace ns on ns.oid = p.pronamespace
             where ns.nspname = 'public' and p.prokind in ('f','p')
               and p.proname not in ('fn_os_review')
               and pg_get_functiondef(p.oid) ~* '\\yoperating_system\\y'
               and exists (select 1 from cron.job j
                            where j.active and j.command ~* ('\\y' || p.proname || '\\y'))), 'none')
        || '; os_department.dept_key unique: ' || ${DEPT_UNIQUE}`);

  // "No duplicated ownership" has to hold for BOTH ownership tables the blueprint defines, and the
  // rule has to reach the people it binds.
  //
  // Both halves are now asserted the same way: as a constraint that makes a second owner
  // unrepresentable, not as a row count that happens to be zero today. os_responsibility already had
  // PRIMARY KEY (responsibility); os_knowledge_domain's only key was (os_key, domain_key), which
  // permits exactly the duplication the rule forbids, so scripts/sql/os_ownership_structural.sql adds
  // a partial unique index on (domain_key) where ownership='owns'. The old data clauses
  // (`group by responsibility having count(*) > 1` = 0) are gone: each was ENTAILED by the constraint
  // asserted on the next line and could never fail, and its evidence number could never be anything
  // but 0 — a measurement no reader can disagree with is not a measurement.
  //
  // The read leg was `strpos(whole 28,000-char prompt, 'no other OS may own') > 0`, which matches a
  // hard-coded label fn_agent_context emits for any OS with any responsibilities, was tested against
  // one employee, and is byte-identical to components_14_17.mjs:215. It now requires, for ALL TEN
  // active OSes, that the exclusivity sentence is followed on its own line by that OS's OWN
  // responsibilities — so the clause fails if the sentence arrives carrying nothing, or carrying
  // someone else's list. (fn_agent_context caps that line at 12 responsibilities; the largest OS
  // declares 9, so the cap is not what is being measured — if an OS ever declares a 13th, the 13th
  // genuinely does not reach the employee and this correctly fails.)
  await req('os-', 'os-exclusive-ownership',
    `No responsibility or knowledge domain is owned by two OSes`, `
    select exists (select 1 from pg_constraint
                    where conrelid = 'public.os_responsibility'::regclass
                      and contype = 'p' and pg_get_constraintdef(oid) = 'PRIMARY KEY (responsibility)')
       and exists (select 1 from pg_indexes
                    where schemaname = 'public' and tablename = 'os_knowledge_domain'
                      and indexdef ~* 'unique index' and indexdef ~* '\\(domain_key\\)'
                      and indexdef ~* 'where \\(ownership')
       and (select count(*) from public.operating_system o
              cross join lateral (select public.fn_agent_context(
                  (select a.agent_key from public.org_agents a
                     join public.os_department d on d.dept_key = a.department
                    where d.os_key = o.os_key and a.active order by a.agent_key limit 1), 22000) t) c
              cross join lateral (select case when position('no other OS may own' in c.t) = 0 then ''
                    else substring(c.t from position('no other OS may own' in c.t)) end x) h
              cross join lateral (select substring(h.x from 1 for
                    coalesce(nullif(position(E'\\n' in h.x), 0) - 1, length(h.x))) line) l
             where o.active
               and (length(l.line) < 20
                    or exists (select 1 from public.os_responsibility r
                                where r.os_key = o.os_key
                                  and strpos(l.line, r.responsibility) = 0))) = 0`, `
    select (select count(*) from public.os_responsibility) || ' responsibilities under PRIMARY KEY '
        || '(responsibility); ' || (select count(distinct domain_key) from public.os_knowledge_domain)
        || ' knowledge domains, ' || (select count(*) from public.os_knowledge_domain
              where ownership = 'owns') || ' owned, '
        || (select count(*) from (select domain_key from public.os_knowledge_domain
              group by 1 having count(*) filter (where ownership = 'owns') = 0) z)
        || ' owned by none, unique-owns index: '
        || (select count(*) from pg_indexes where schemaname = 'public'
             and tablename = 'os_knowledge_domain' and indexdef ~* 'unique index'
             and indexdef ~* '\\(domain_key\\)' and indexdef ~* 'where \\(ownership')
        || '; OSes whose exclusivity line carries their own responsibilities: '
        || (select count(*) from public.operating_system o
              cross join lateral (select public.fn_agent_context(
                  (select a.agent_key from public.org_agents a
                     join public.os_department d on d.dept_key = a.department
                    where d.os_key = o.os_key and a.active order by a.agent_key limit 1), 22000) t) c
              cross join lateral (select case when position('no other OS may own' in c.t) = 0 then ''
                    else substring(c.t from position('no other OS may own' in c.t)) end x) h
              cross join lateral (select substring(h.x from 1 for
                    coalesce(nullif(position(E'\\n' in h.x), 0) - 1, length(h.x))) line) l
             where o.active and length(l.line) >= 20
               and not exists (select 1 from public.os_responsibility r
                                where r.os_key = o.os_key
                                  and strpos(l.line, r.responsibility) = 0))
        || '/' || (select count(*) from public.operating_system where active)`);
}
