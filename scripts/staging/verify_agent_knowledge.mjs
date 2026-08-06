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
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF } from './demo_factory.mjs';

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
const titles = async (key, q) => await one(REF, `
  with ctx as (select public.fn_agent_context(${lit(key)}, 24000, ${lit(q)}) t),
       sect as (select substring(t from '# LAYER 2b.*$') s from ctx),
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

// ---- 6. both projects carry the overload — verify_phase1 asserts the routine COUNT ---------------
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
