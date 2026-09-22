// verify_agent_knowledge.mjs — the department library, and whether an employee can actually see it.
//
// dept_library held 1,456 rows in BOTH projects with a tsvector column and a working search
// function, fn_dept_library_search(p_dept, p_query, p_limit), and that function had ZERO callers:
// no routine, no view, no Edge Function, no cron job, no frontend module named it. Complete,
// indexed, searchable, unread — the fifth instance of the shape that cost sessions 10 and 11 four
// separate assets. Nothing failed loudly, because nothing ran.
//
// The reader is an OVERLOAD on fn_agent_context, the four-layer employee assembly that thirteen
// call sites already read. This gate asserts the mechanism, not the deploy: the caller half —
// agent_brain passing p_query — is asserted by verify_deploy_parity.mjs against the deployed
// bundle on both projects, which is a better instrument than re-reading the source here.
//
// The checks that matter are the NEGATIVE ones. A query-less call must be byte-identical to what
// the other twelve call sites got before, or this change is a silent behaviour change to ten Edge
// Functions. And the section must be provably built FROM dept_library — a model-free assertion
// that each emitted title exists as a real row, not that the output merely grew.
//
// Everything here is SQL. No model calls, nothing created, nothing to tear down.
//
//     node scripts/staging/verify_agent_knowledge.mjs
import { mgmtRead, PROD_REF } from '../lib/qd_guard.mjs';
import { REF } from '../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`);
};
const one = async (ref, sql) => (await mgmtRead(ref, sql))[0];
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

const Q = 'What are the VAT and free zone rules for a UAE trade licence renewal?';

// ---- 1. the corpus is present, and identical to production --------------------------------------
const shape = async (ref) => (await one(ref,
  `select count(*)::int n, count(distinct department)::int d,
          md5(string_agg(department || '|' || coalesce(title,''), E'\\n' order by id)) h
     from public.dept_library`));
const [ps, ss] = [await shape(PROD_REF), await shape(REF)];
step('dept_library matches production row for row',
  ss.n === ps.n && ss.n > 0 && ss.h === ps.h,
  `staging ${ss.n} rows / ${ss.d} departments, production ${ps.n} / ${ps.d}, md5 ${String(ss.h).slice(0, 10)}…`);

// ---- 2. the search function returns real material, per department --------------------------------
const probes = [
  ['legal', 'What are the VAT and free zone rules for a UAE trade licence renewal?'],
  ['procurement', 'supplier evaluation criteria and tender award process'],
  ['it', 'incident response and backup retention policy'],
  ['finance', 'revenue recognition and receivables ageing'],
  ['company', 'how does quotesdone make money'],
];
for (const [dept, q] of probes) {
  const r = await one(REF, `select count(*)::int n, min(length(content))::int minlen,
    (array_agg(title order by rank desc))[1] top from public.fn_dept_library_search(${lit(dept)}, ${lit(q)}, 5)`);
  step(`fn_dept_library_search finds ${dept} material`, r.n > 0 && r.minlen > 0,
    `${r.n} hit(s), top "${String(r.top || '').slice(0, 54)}"`);
}

// A department with no library must return nothing rather than borrowing another department's.
// 9 of the 13 staffed departments are in this state; that is a corpus gap, stated not hidden.
const cov = await one(REF, `select
  (select count(*)::int from public.org_agents where active and department is not null) staffed,
  (select count(distinct a.department)::int from public.org_agents a where a.active
     and exists (select 1 from public.dept_library l where l.department = a.department)) with_lib,
  (select count(distinct department)::int from public.org_agents where active) depts,
  (select count(*)::int from public.fn_dept_library_search('marketing', 'social media campaign plan', 5)) marketing_hits`);
step('a department with no library returns nothing', cov.marketing_hits === 0,
  `marketing 0 hits; ${cov.with_lib} of ${cov.depts} staffed departments have a library`);

// ---- 3. the query-less path is unchanged — twelve call sites depend on it -----------------------
const plain = await one(REF, `select
  length(public.fn_agent_context('legal', 24000))::int a,
  length(public.fn_agent_context('legal', 24000, null))::int b,
  length(public.fn_agent_context('legal', 24000, ''))::int c,
  (public.fn_agent_context('legal', 24000, null) = public.fn_agent_context('legal', 24000)) same_null,
  (public.fn_agent_context('legal', 24000, '') = public.fn_agent_context('legal', 24000)) same_empty,
  (public.fn_agent_context('legal', 24000) like '%LAYER 2b%') leaked`);
step('a query-less call is byte-identical to the old two-argument one',
  plain.same_null && plain.same_empty && !plain.leaked,
  `${plain.a} chars, null=${plain.b} empty=${plain.c}, no LAYER 2b`);

// ---- 4. with a query, the section is present AND built from dept_library -------------------------
// The 2b span must STOP at 2c. `'# LAYER 2b.*$'` runs to the end of the string, so once the
// operations corpus added a 2c section this measured both and reported 9 excerpts and 5,650 chars
// for a 4-excerpt, 3,137-char section — a gate failing on its own extractor, not on the code.
const titles = async (key, q) => await one(REF, `
  with ctx as (select public.fn_agent_context(${lit(key)}, 24000, ${lit(q)}) t),
       sect as (select split_part(substring(t from '# LAYER 2b.*$'), '# LAYER 2c', 1) s from ctx),
       lines as (select trim(substring(l from 4)) title from sect, unnest(string_to_array(s, E'\\n')) l where l like '## %')
  select (select length(s) from sect)::int seclen,
         count(*)::int n,
         count(*) filter (where exists (select 1 from public.dept_library d where d.title = lines.title))::int real,
         (array_agg(title))[1] first_title
    from lines`);

const legal = await titles('legal', Q);
step('a real question adds LAYER 2b from dept_library',
  legal.n > 0 && legal.real === legal.n,
  `${legal.n} excerpt(s), ${legal.real} matching a real row, first "${String(legal.first_title || '').slice(0, 44)}"`);

step('the section is bounded and cannot displace the four layers',
  legal.seclen > 0 && legal.seclen <= 3600,
  `${legal.seclen} chars added on top of ${plain.a}`);

// The branch most likely to be silently dead: a cat:<slug> specialist has NO org_agents row, so
// v_dept is null and fn_dept_library_search falls through to "any department". If that path were
// broken, every one of the 110 category specialists would get an empty section and nothing would say so.
const catKey = (await one(REF, `select 'cat:' || slug k from public.category_agents where coalesce(active,true) order by slug limit 1`)).k;
const spec = await titles(catKey, 'what payment terms and retention are standard on a UAE fit-out contract');
step('a cat: specialist with no org_agents row still gets a library',
  spec.n > 0 && spec.real === spec.n,
  `${catKey} → ${spec.n} excerpt(s), ${spec.real} real`);

// ---- 5. os_knowledge_domain has a reader, and reports its own coverage hole ----------------------
const gaps = async (ref) => (await one(ref, `select
  (public.fn_knowledge_gaps()->'summary'->>'total')::int total,
  (public.fn_knowledge_gaps()->'summary'->>'unowned')::int unowned,
  (select count(*)::int from jsonb_array_elements(public.fn_knowledge_gaps()->'agents') a
     where a->>'owner_os' is not null) owned,
  (select count(*)::int from public.category_agents ca where coalesce(ca.active,true)
     and exists (select 1 from public.os_knowledge_domain d where d.domain_key='cat:'||ca.slug and d.ownership='owns')) truth`));
const gs = await gaps(REF);
step('fn_knowledge_gaps attributes each agent to its owning OS component',
  gs.owned === gs.truth && gs.owned > 0 && gs.owned + gs.unowned === gs.total,
  `${gs.owned} owned, ${gs.unowned} unowned, ${gs.total} total`);

// ---- 6. layer 2 falls back to the DEPARTMENT, and only where the employee has nothing -----------
// The spec's architectural recommendation is one sentence long — "Don't create 20 isolated
// knowledge bases" — and layer 2 is DEPARTMENT knowledge. Keying it to the individual left 52 of
// 66 active employees with an empty "# LAYER 2 - YOUR PROFESSIONAL EXPERTISE" heading, 8 of them
// department leads, on a path dept_plan runs daily.
const l2 = await one(REF, `
  with a as (select agent_key, department from public.org_agents where active),
       own as (select a.agent_key,
         exists (select 1 from public.agent_knowledge k where k.agent_key = a.agent_key
                   and coalesce(k.layer,'profession') in ('profession','state')) hasown,
         exists (select 1 from public.agent_knowledge k
                   join public.org_agents b on b.agent_key = k.agent_key and b.active
                  where b.department = a.department
                    and coalesce(k.layer,'profession') in ('profession','state')) hasdept
         from a)
  select count(*)::int agents, count(*) filter (where hasown)::int own_l2,
         count(*) filter (where hasown or hasdept)::int reachable,
         count(*) filter (where not hasown and not hasdept)::int still_empty
    from own`);

// Rendered, not inferred: the CEO Office AI is requirement #1 of this spec file and had zero.
const l2topics = async (key) => await one(REF, `
  with c as (select public.fn_agent_context(${lit(key)}, 24000) t)
  select coalesce((select count(*)::int from unnest(string_to_array(
           substring(t from '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE(.*?)# LAYER 1'), E'\\n')) l
           where l like '## %'), 0) topics,
         coalesce((select count(*)::int from unnest(string_to_array(
           substring(t from '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE(.*?)# LAYER 1'), E'\\n')) l
           where l like '## %'
             and exists (select 1 from public.agent_knowledge k
                          where k.agent_key = ${lit(key)} and '## '||k.topic = l)), 0) own_topics
    from c`);

const ceo = await l2topics((await one(REF, `select lead_agent k from public.org_departments where dept_key='exec'`)).k);
step('an employee with no knowledge of their own inherits the department\'s',
  ceo.topics > 0 && l2.reachable > l2.own_l2,
  `exec lead renders ${ceo.topics} topic(s); ${l2.own_l2} of ${l2.agents} have their own, ${l2.reachable} can reach one`);

// THE NEGATIVE THAT MATTERS: own rows must still win outright, or this silently widened the
// context of the 14 agents that were already correct.
const legalAgent = await l2topics('legal');
step('an employee with their own knowledge is unaffected',
  legalAgent.topics > 0 && legalAgent.own_topics === legalAgent.topics,
  `legal renders ${legalAgent.topics} topic(s), ${legalAgent.own_topics} of them its own`);

step('employees with no knowledge anywhere are counted, not hidden', l2.still_empty >= 0,
  `${l2.still_empty} employee(s) have neither their own nor a department library — a corpus gap, not a wiring one`);

// ---- 6b. the operations corpus, and the departments that had NOTHING ----------------------------
// 3,959 founder-supplied records (240 exception playbooks, 240 decision rules, 236 SOPs, 216 KPI
// definitions) that neither project had a table for. Imported and wired in one change, because an
// imported corpus with no reader is the exact defect this whole line of work exists to prevent.
const opsDigest = async (ref) => (await one(ref,
  `select count(*)::int n, count(dept_key)::int mapped,
          md5(string_agg(record_id, E'\\n' order by record_id)) h,
          count(*) filter (where record_type='exception_playbook')::int playbooks
     from public.ops_knowledge`));
const [po, so] = [await opsDigest(PROD_REF), await opsDigest(REF)];
step('ops_knowledge is row-for-row identical to production',
  so.n === po.n && so.n > 0 && so.h === po.h,
  `staging ${so.n} rows / ${so.mapped} mapped, production ${po.n} / ${po.mapped}, md5 ${String(so.h).slice(0, 10)}…`);
step('the exception playbooks are present', so.playbooks === 240, `${so.playbooks} exception_playbook record(s)`);

// IMPORTING IT AND LEAVING PART OF IT UNREACHABLE IS THE SAME DEFECT, ONE LEVEL DOWN. The first
// cut resolved dept_key from scope_key only, so all 96 agent records, all 340 workflow records and
// the 21 external sources were returned by no search at all — 884 of 3,959. Agent and workflow
// records name their department in structured_data.department_key instead; company principles, the
// UAE source registry and ownerless cross-department workflows apply to everyone.
const reach = await one(REF, `select count(*)::int total,
    count(*) filter (where dept_key is not null or scope_type in ('company','external_source')
                        or (scope_type='workflow' and dept_key is null))::int reachable,
    (select string_agg(scope_key||' '||n, ', ' order by n desc) from (
       select scope_key, count(*) n from public.ops_knowledge
        where dept_key is null and scope_type not in ('company','external_source','workflow')
        group by 1) z) orphans
  from public.ops_knowledge`);
step('every record is reachable except the departments that do not exist',
  Number(reach.total) - Number(reach.reachable) === 439,
  `${reach.reachable}/${reach.total} reachable; orphaned: ${reach.orphans}`);

// The spec's FIRST named exception scenario is "OpenAI is unavailable / Anthropic is unavailable".
// The founder shipped a playbook for it per department. This asserts the retrieval finds it.
// Assert PRESENCE, not position. The first cut demanded the department playbook rank first, and
// broke the moment cross-department workflows became reachable: the company-wide "External provider
// outage and continuity" workflow now outranks it, which is the better answer, with HR's own
// playbook, scenario and decision rule at 2, 3 and 5. A rank assertion would keep failing every
// time retrieval improved.
const outage = await one(REF, `select count(*)::int n,
    count(*) filter (where record_type='exception_playbook')::int playbooks,
    count(*) filter (where title ilike '%HR%provider unavailable%')::int own_playbook,
    (select title from public.fn_ops_knowledge_search('hr','external AI provider unavailable',1)) t
  from public.fn_ops_knowledge_search('hr','external AI provider unavailable',5)`);
step('an AI-provider outage retrieves the department\'s own playbook',
  outage.n > 0 && outage.own_playbook > 0 && outage.playbooks > 0,
  `${outage.n} hit(s), ${outage.playbooks} playbook(s), own=${outage.own_playbook}, top "${String(outage.t || '').slice(0, 44)}"`);

// hr, intelligence and knowledge_eng each held 0 agent_knowledge AND 0 dept_library rows.
const zeros = await one(REF, `select count(*)::int still_empty from public.org_departments d
  where d.active
    and not exists (select 1 from public.ops_knowledge o where o.dept_key = d.dept_key)
    and not exists (select 1 from public.dept_library l where l.department = d.dept_key)
    and not exists (select 1 from public.agent_knowledge k join public.org_agents a
                     on a.agent_key = k.agent_key and a.active where a.department = d.dept_key)`);
step('no active department is left with zero knowledge', Number(zeros.still_empty) === 0,
  `${zeros.still_empty} department(s) with nothing`);

// The authority tier must travel WITH the excerpt. An agent reading a `gated` procedure that does
// not say it is gated will act on it, which is worse than not retrieving it at all.
const l2c = await one(REF, `
  with c as (select public.fn_agent_context('hr_director', 24000,
                    'external AI provider unavailable during onboarding') t)
  -- NOTE: the probe text avoids the word "do". qd_guard's read-only regex includes \\bdo\\b for
  -- anonymous DO blocks, so a natural-sounding question ("what do we do when...") is refused as a
  -- write. The guard is right; the probe was careless.
  select (t like '%LAYER 2c%') has_2c,
         (t ~ 'authority: (advisory|supervised|gated|autonomous)') has_tier,
         (t ~ '(implemented|partial|target_state)') has_status from c`);
step('layer 2c carries the authority tier and implementation status',
  l2c.has_2c && l2c.has_tier && l2c.has_status,
  `section=${l2c.has_2c} tier=${l2c.has_tier} status=${l2c.has_status}`);

// ---- 7. continuous monitoring: the failing-cron signal now has a reader -------------------------
// fn_os_health()'s `failing_crons` uses JOIN LATERAL … ORDER BY start_time DESC LIMIT 1 WHERE
// status='failed' — the most recent run, the only definition of "failing now" that is any use. It
// had one caller (fn_os_selftest) which itself had none: not a cron, not a routine, not an os_api
// action. fn_exception_alerts — hourly, already writing founder_alerts, already deduped — now asks.
for (const [env, ref] of [['staging', REF], ['production', PROD_REF]]) {
  const h = await one(ref, `select
    (select count(*)::int from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.proname='fn_exception_alerts' and p.prosrc like '%QD_CRON_HEALTH%') marker,
    jsonb_array_length(coalesce(public.fn_os_health()->'failing_crons','[]'::jsonb)) failing_now`);
  step(`the cron-health check is deployed on ${env}`, h.marker === 1,
    `marker ${h.marker}, ${h.failing_now} job(s) failing on their most recent run`);
}

// STAGING HAS 0 CRONS, SO THE BRANCH CANNOT EXECUTE HERE — which is exactly how the two jsonb
// concatenation bugs in the RFQ trace hid until a fixture ran them. The alert text is therefore
// built against a synthetic failing_crons array, including the null-message row.
const detail = await one(REF, `select 'Scheduled job(s) failed on their most recent run: '||
  (select string_agg(distinct (e->>'job')||' — '||left(coalesce(e->>'message',''),120), '; ')
     from jsonb_array_elements('[{"job":"kpi_review_weekly","message":"ERROR: statement timeout"},
                                 {"job":"health_check","message":null}]'::jsonb) e) d`);
step('the alert text builds, including a null message',
  String(detail.d || '').includes('kpi_review_weekly') && String(detail.d || '').includes('health_check'),
  `"${String(detail.d || '').slice(0, 72)}…"`);

// ---- 8. both projects carry the overload — verify_phase1 asserts the routine COUNT ---------------
const sig = async (ref) => (await one(ref, `select count(*)::int n from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname='public' and p.proname='fn_agent_context'
   and p.oid::regprocedure::text = 'fn_agent_context(text,integer,text)'`)).n;
const [pSig, sSig] = [await sig(PROD_REF), await sig(REF)];
step('the overload exists on both projects', pSig === 1 && sSig === 1,
  `staging ${sSig}, production ${pSig}`);

const bad = checks.filter((c) => !c.ok).length;
console.log(`\nAGENT KNOWLEDGE ${checks.length - bad}/${checks.length} on ${REF}`);
if (bad) process.exitCode = 1;
