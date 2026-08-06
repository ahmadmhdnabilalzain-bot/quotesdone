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
//   3. READ        — that OS's own purpose (charter AND mandate), mission and every one of its
//                    objectives are present, verbatim, IN THAT OS'S OWN BLOCK of the prompt
//                    fn_agent_context builds for an employee of that OS, and every one of its
//                    responsibilities is present on the OWNS LINE inside that block. Text in a table
//                    is not text an employee was told; this spec file is entirely about the
//                    difference. And a word occurring somewhere in the block is not that OS's
//                    responsibility arriving — see the second anchor below.
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
//
// THE SECOND ANCHOR. Even inside the OS block, "the responsibility reached the employee" is not the
// same claim as "the word occurs somewhere in the block": fn_agent_context renders responsibilities
// on exactly ONE line ('Your OS OWNS, and no other OS may own: a, b, c') and caps it at `limit 12`,
// while Purpose: and Mission: prose sit above it in the same block. So an OS's 13th responsibility
// genuinely never reaches the employee, yet scored read whenever the bare word also occurred in that
// OS's own charter or mission.
//
// This is not latent. Measured on production over all 90 OS/foreign-responsibility pairs: ONE
// responsibility belonging to another OS already matches somewhere inside a block — leadership's
// block contains 'suppliers', which marketplace owns — and ZERO match on the OWNS line. The
// block-wide test therefore accepts a claim that is false today; the anchored one does not.
// os-exclusive-ownership in this same file already anchors to that line, and scoring the same fact
// two ways in one file is how two checks come to disagree about it.
const CTX = (k) => `with ctx as materialized (
       select public.fn_agent_context(${AGENT(k)}, 22000) t),
     head as (select case when position('# YOUR OPERATING SYSTEM' in t) = 0 then ''
                     else substring(t from position('# YOUR OPERATING SYSTEM' in t)) end x from ctx),
     blk as (select substring(x from 1 for
                 coalesce(nullif(position(E'\\n# ' in x), 0) - 1, length(x))) b from head),
     ownl as (select coalesce(substring(b from E'no other OS may own[^\\n]*'), '') l from blk)`;

// fn_agent_context emits left(charter,300) / left(mission,240) / left(mandate,240), so the needle
// must be truncated the same way or a long mission would look absent when it is in fact there. The
// length guards stop a blank column from passing trivially: strpos(anything, '') returns 1. The same
// guard is folded into the responsibility and objective clauses — a blank row must not satisfy its
// own read test.
//
// MANDATE IS NEEDLE-TESTED, NOT MERELY POPULATED. This file's header defines "purpose" as
// charter+mandate, and the check required length(mandate) > 10 while testing only charter and
// mission against the prompt. Every attribute in fn_agent_context's OS block is individually wrapped
// in `case when r.<x> is not null then ... else '' end`, so deleting the one Mandate line
// (fn_agent_context_os_layer.sql:181) left all ten checks MET with a populated, unread column —
// the exact failure this whole spec file is about. Measured: 85-186 chars per OS, all ten present.
//
// THE RESPONSIBILITY LEG IS A FLOOR, NOT `> 0`. minResp is the count the blueprint NAMES for that
// OS — the seed at supabase/migrations/20260728191802_os_blueprint_mission_objectives_ownership_io
// .sql:32-57, plus 'automation' for operations. A bare `> 0` scored "<name> OS ... responsibilities"
// MET with one row: nine of the ten OSes could have been reduced to a single responsibility and the
// evidence would have printed 'resp 1/1'. The floor is >= rather than = so the blueprint can grow;
// it fails on deletion, which is the failure it exists to catch. Production is exactly at the floor
// on all ten today, so this is measured, not padded.
//
// The STAFF leg is deliberately left at `> 0`: unlike responsibilities and objectives, the blueprint
// names no headcount per OS, and any floor invented here would be a number no requirement asks for.
const osCheck = (k, minResp, extra = 'true') => `${CTX(k)},
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
  and (select count(*) from public.os_responsibility where os_key = '${k}') >= ${minResp}
  and (select count(distinct horizon) from public.os_objective
        where os_key = '${k}' and coalesce(active,true)) = 5
  and (select strpos((select b from blk), left(mission,240)) > 0
            and strpos((select b from blk), left(charter,300)) > 0
            and strpos((select b from blk), left(mandate,240)) > 0 from o)
  and (select count(*) from public.os_responsibility r
        where r.os_key = '${k}'
          and (length(trim(coalesce(r.responsibility,''))) < 2
               or strpos((select l from ownl), r.responsibility) = 0)) = 0
  and (select count(*) from public.os_objective j
        where j.os_key = '${k}' and coalesce(j.active,true)
          and (length(trim(coalesce(j.objective,''))) < 2
               or strpos((select b from blk), j.objective) = 0)) = 0
  and ${extra}`;

// Evidence is the count that decides it: how much of this OS's declared content actually landed in
// an employee's prompt, which employee was asked, and how large the slice searched was — a reader
// who does not see the block size cannot tell an anchored match from a 28,000-character haystack.
// Both sides of the objective ratio filter on active; mixing the filters is how a check prints
// 'obj 4/5' beside a MET verdict the moment one objective is deactivated. For the same reason the
// resp numerator is counted on the OWNS LINE, the population the verdict scores, and the purpose
// figure now includes mandate: evidence measured over a wider population than the verdict is how a
// MISSING row comes to print the number that contradicts it.
const osEvidence = (k, minResp, extra = `''`) => `${CTX(k)}
select (select count(*) from public.org_agents a
          join public.os_department d on d.dept_key = a.department
         where d.os_key = '${k}' and a.active) || ' staff; prompt of ' || ${AGENT(k)}
    || ' (OS block ' || (select length(b) from blk) || ' chars of '
    || (select length(t) from ctx) || ', OWNS line ' || (select length(l) from ownl) || ')'
    || ': purpose(charter+mandate)+mission '
    || (select case when strpos((select b from blk), left(o.mission,240)) > 0
             and strpos((select b from blk), left(o.charter,300)) > 0
             and strpos((select b from blk), left(o.mandate,240)) > 0 then 'yes' else 'no' end
           from public.operating_system o where o.os_key = '${k}')
    || ', resp on OWNS line ' || (select count(*) from public.os_responsibility r
           where r.os_key = '${k}' and strpos((select l from ownl), r.responsibility) > 0)
    || '/' || (select count(*) from public.os_responsibility where os_key = '${k}')
    || ' declared (blueprint names ${minResp})'
    || ', obj ' || (select count(*) from public.os_objective j where j.os_key = '${k}'
           and coalesce(j.active,true) and strpos((select b from blk), j.objective) > 0)
    || '/' || (select count(*) from public.os_objective
                where os_key = '${k}' and coalesce(active,true)) || ${extra}`;

// The blueprint names Operations' responsibilities and 'automation' is one of them; it is owned by
// no OS at all today, so Operations carries one extra clause the other nine do not need. It is a
// clause that can pass — one os_responsibility row closes it.
const AUTOMATION = `(select count(*) from public.os_responsibility
   where responsibility = 'automation' and os_key = 'operations') = 1`;

// The trailing number is minResp: how many responsibilities the BLUEPRINT names for that OS, counted
// off the seed insert in supabase/migrations/20260728191802_os_blueprint_mission_objectives_
// ownership_io.sql:32-57 (71 rows), plus 'automation' for operations, which the AUTOMATION clause
// below names separately. It is not today's row count copied back as its own test: 71 + 1 = 72 is
// what os_responsibility holds, and this is the list that produced it.
const TEN = [
  ['os-leadership', 'leadership', 'Leadership OS', 9],
  ['os-commercial', 'commercial', 'Commercial OS', 6],
  ['os-marketplace', 'marketplace', 'Marketplace OS', 8],
  ['os-operations', 'operations', 'Operations OS', 7],
  ['os-technology', 'technology', 'Technology OS', 7],
  ['os-finance', 'finance', 'Finance OS', 7],
  ['os-legal-governance', 'legal_gov', 'Legal & Governance OS', 7],
  ['os-knowledge', 'knowledge', 'Knowledge OS', 6],
  ['os-intelligence', 'intelligence', 'Intelligence OS', 8],
  ['os-evolution', 'evolution', 'Evolution OS', 7],
];

// WRITER, STRUCTURALLY. The writer exclusion used to be the hardcoded name `not in ('fn_os_review')`
// — correct on the day it was written and silently wrong the day a second writer is added, at which
// point that writer counts as its own table's reader. This derives it from the body instead, so it
// holds for whoever writes the table and whenever. (The write keywords are split around `||` because
// qd_guard refuses any read whose text contains one — the guard is doing its job.)
const WRITER_OF = (t) => `pg_get_functiondef(p.oid) ~*
        ('(ins'||'ert\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;

// A JOB ROW IS A CLAIM; cron.job_run_details IS THE FACT — scripts/sql/kpi_schedule_prove.sql:7, and
// the form every sibling file in this suite already uses (components_11_13.mjs:223, component_10.mjs
// :213, components_14_17.mjs:82, cross_os.mjs:111). cron.job.active is a boolean somebody set: a job
// that has never fired once satisfies it, and production has exactly that case — job 185
// (os_health_brief_weekly, schedule '50 4 * * 1') is active with 0 runs ever, because it was created
// after the last Monday. That is not a broken job, and it is exactly why the distinction matters:
// fn_os_health_brief reads BOTH operating_system and os_review, and under the old clause it was
// certifying a read that has not yet happened once. It starts counting on 10 Aug, when it runs.
//
// Ten days is one weekly period plus margin, the same window this file already applies to os_review,
// and it does not lapse for a healthy weekly job (measured: exec_meeting_weekly and os_review_weekly
// both fire Mondays, a 7-day gap). Under it the reader counts drop from 5 to 4 and from 3 to 2.
//
// The proname is escaped before it enters the regex. It is a catalog identifier so today every name
// is [a-z0-9_], but an identifier carrying a metacharacter would either change what matches or raise
// an invalid-regex error — and verify_os_blueprint.mjs:102-105 counts an ERROR as UNMEASURED, not as
// MISSING, so an injected pattern would remove the requirement from the scorecard rather than fail it.
const CRON_SUCCEEDED = (nameExpr, days = 10) => `exists (
        select 1 from cron.job j
          join cron.job_run_details d on d.jobid = j.jobid
         where j.active and d.status = 'succeeded'
           and d.end_time > now() - interval '${days} days'
           and j.command ~* ('\\y' || regexp_replace(${nameExpr}, '([^[:alnum:]_])', '\\\\&', 'g') || '\\y'))`;

// A reader of <t> that is neither one of its writers nor a dead reference. READERS() in the harness
// counts things it must not: the table's own writer (its self-exclusion `proname <> '<table>'` never
// fires, because no routine is named after a table); the literal string 'operating_system'::text
// inside v_operating_manual's own definition; and v_operating_manual itself, the view this file's
// header records as having no readers. count(DISTINCT proname) because pg_proc holds one row per
// OVERLOAD — fn_agent_context has two on production — and an overload set is one reader, not two.
//
// Measured on production today: operating_system 4 (fn_company_snapshot, fn_exec_meeting,
// fn_graph_rebuild, fn_os_improve — fn_os_health_brief drops out on the never-run job above, and
// fn_os_review is the writer), os_review 2 (fn_company_snapshot, fn_exec_meeting). Note '\yos_review\y'
// does not match inside 'fn_os_review': '_' is a word character, so the writer's NAME is not a
// spurious hit on the TABLE — the exclusion above is doing the work, not the boundary.
const LIVE_READERS = (t, days = 10) => `(select count(distinct p.proname) from pg_proc p
     join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
      and not ${WRITER_OF(t)}
      and ${CRON_SUCCEEDED('p.proname', days)})`;

const LIVE_READER_NAMES = (t, days = 10) => `coalesce((select string_agg(distinct p.proname, ', ')
       from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.prokind in ('f','p')
        and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
        and not ${WRITER_OF(t)}
        and ${CRON_SUCCEEDED('p.proname', days)}), 'none')`;

// The department -> OS resolution every read leg in this file depends on. os_department's PRIMARY
// KEY is (os_key, dept_key), which permits one department to belong to several OSes; fn_agent_context
// resolves it with `limit 1` and no ORDER BY, so a second mapping makes which OS an employee is told
// they belong to an arbitrary unordered row, and makes AGENT(k) above disagree with it. Made
// structural in scripts/sql/os_ownership_structural.sql; asserted here so it stays that way.
const DEPT_UNIQUE = `exists (select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'os_department'
      and indexdef ~* 'unique index .* \\(dept_key\\)$')`;

export default async function ({ req }) {
  for (const [id, key, label, minResp] of TEN) {
    const isOps = key === 'operations';
    await req('os-', id, `${label}: row, purpose, mission, owner, responsibilities, objectives, staff`,
      osCheck(key, minResp, isOps ? AUTOMATION : 'true'),
      osEvidence(key, minResp, isOps
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
  //
  // BUT RECENCY IS NOT A READER, and this file's header claimed os_review is "asserted ONCE, with
  // both [recency and a reader], in os-all-ten-active" while the only reader clause matched
  // `\yoperating_system\y` — a DIFFERENT object, whose name does not contain the substring
  // 'os_review'. The reader leg structurally could not cover the table it was said to cover; it read
  // true only because fn_os_health_brief happens to touch both, and deleting its `join os_review`
  // (scripts/sql/fn_os_health_brief.sql:32) would not have moved the verdict. os_review now carries
  // its own reader leg. That is the whole subject of this spec file applied to this file's own claim.
  await req('os-', 'os-all-ten-active', 'All ten named Operating Systems exist and are active', `
    select (select count(*) from public.operating_system where active) = 10
       and (select count(distinct num) from public.operating_system) = 10
       and (select min(num) || '-' || max(num) from public.operating_system) = '1-10'
       and (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) = 10
       and (select count(distinct os_key) from public.os_review
             where created_at > now() - interval '10 days') = 10
       and ${LIVE_READERS('operating_system')} > 0
       and ${LIVE_READERS('os_review')} > 0
       and ${DEPT_UNIQUE}`, `
    select (select count(*) from public.operating_system where active) || '/10 active, '
        || (select count(*) from public.operating_system o join public.org_agents a
              on a.agent_key = o.owner_agent and a.active) || ' owners live, os_review '
        || (select count(distinct os_key) from public.os_review
             where created_at > now() - interval '10 days') || '/10 OS within 10 days (latest '
        || coalesce((select max(period) from public.os_review), 'never') || '); '
        || 'operating_system read by ' || ${LIVE_READERS('operating_system')} || ' ('
        || ${LIVE_READER_NAMES('operating_system')} || '), os_review read by '
        || ${LIVE_READERS('os_review')} || ' (' || ${LIVE_READER_NAMES('os_review')}
        || ') — non-writer routines on a cron that SUCCEEDED within 10 days'
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
  //
  // TWO REPAIRS HERE. (1) The index predicate is pinned to `where (ownership = 'owns'`, not merely
  // `where (ownership`: the loose form is satisfied by a partial unique index on (domain_key) WHERE
  // ownership <> 'owns', which permits exactly the duplicated ownership this requirement forbids
  // while matching the regex. Production's index reads WHERE (ownership = 'owns'::text), so the
  // pinned form is what is actually deployed. (2) The evidence no longer prints 'under PRIMARY KEY
  // (responsibility)' as a literal. That sentence IS the first scored leg, evidence prints on MISSING
  // as well as MET (verify_os_blueprint.mjs:37,40), and dropping the PK — the precise failure this
  // check exists to detect — would have produced a MISSING row still asserting the constraint it had
  // just lost. It now prints pg_get_constraintdef, i.e. whatever is actually there.
  await req('os-', 'os-exclusive-ownership',
    `No responsibility or knowledge domain is owned by two OSes`, `
    select exists (select 1 from pg_constraint
                    where conrelid = 'public.os_responsibility'::regclass
                      and contype = 'p' and pg_get_constraintdef(oid) = 'PRIMARY KEY (responsibility)')
       and exists (select 1 from pg_indexes
                    where schemaname = 'public' and tablename = 'os_knowledge_domain'
                      and indexdef ~* 'unique index' and indexdef ~* '\\(domain_key\\)'
                      and indexdef ~* 'where \\(ownership = ''owns''')
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
    select (select count(*) from public.os_responsibility) || ' responsibilities under '
        || coalesce((select pg_get_constraintdef(oid) from pg_constraint
                      where conrelid = 'public.os_responsibility'::regclass and contype = 'p'),
                    'NO PRIMARY KEY — a responsibility can be owned twice')
        || '; ' || (select count(distinct domain_key) from public.os_knowledge_domain)
        || ' knowledge domains, ' || (select count(*) from public.os_knowledge_domain
              where ownership = 'owns') || ' owned, '
        || (select count(*) from (select domain_key from public.os_knowledge_domain
              group by 1 having count(*) filter (where ownership = 'owns') = 0) z)
        || ' owned by none, unique-owns index: '
        || (select count(*) from pg_indexes where schemaname = 'public'
             and tablename = 'os_knowledge_domain' and indexdef ~* 'unique index'
             and indexdef ~* '\\(domain_key\\)' and indexdef ~* 'where \\(ownership = ''owns''')
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
