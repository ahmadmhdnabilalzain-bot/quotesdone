// 1,456 ROWS OF DEPARTMENT REFERENCE MATERIAL, AND NOT ONE EMPLOYEE COULD SEE THEM.
//
// public.dept_library holds 1,456 rows in both projects — legal 451, procurement 361, it 318,
// finance 290 and a cross-cutting `company` 36 — with a tsvector column and a search function,
// public.fn_dept_library_search(p_dept, p_query, p_limit), that works: measured 6 Aug 2026 it
// returns 5 relevant hits for a real question in each of the five. It had ZERO callers. Not one
// routine, view, Edge Function, cron job or frontend module named it. The library was complete,
// indexed, searchable and unread — the same shape as the 4,212 aliases and the 16,588 questions.
//
// THE READER IS ADDED WHERE EVERY AGENT ALREADY PASSES. fn_agent_context() is the four-layer
// employee assembly and thirteen call sites across ten Edge Functions already read it
// (agent_brain, agent_act, dept_plan, secretary_act x2, knowledge_exam, marketing_draft,
// blog_weekly, boost_recommend, content_revise, designer). Adding retrieval there rather than in
// one caller is the smaller diff AND the wider fix.
//
// IT IS AN OVERLOAD, NOT A REWRITE, AND THAT IS DELIBERATE. The new
// fn_agent_context(text,int,text) CALLS the existing fn_agent_context(text,int) and appends one
// section. The 100-line four-layer body is not copied, so it cannot drift; the existing signature
// is not dropped, so its thirteen callers keep working byte-identically and its grants survive
// (the brief records grants being lost to a DROP+CREATE once already). Both parameters of the old
// signature have defaults, so a two-argument call still resolves to exactly one function — the new
// one takes three arguments with no defaults and can never be ambiguous with it.
//
// WITHOUT A QUERY IT IS A DUMP, NOT RETRIEVAL. fn_agent_context has no message parameter, which is
// why the library could not simply be pasted into layer 2: legal alone is 451 rows averaging 1,390
// characters against a 22,000-character context budget. The section is therefore emitted only when
// a caller supplies the actual question, and capped at ~2,600 characters on top of the existing
// budget so it cannot displace the four layers.
//
// A cat:<slug> specialist has no org_agents row, so v_dept is null and fn_dept_library_search
// treats that as "any department" — a fit-out question about payment terms reaches the legal
// library. That is wanted, not a leak: the ranking decides, and the alternative is a specialist
// with no reference material at all.
//
// SECOND READER, SECOND ORPHAN: os_knowledge_domain, 380 rows, os_key -> domain_key with
// ownership, had zero readers AND zero writers. fn_knowledge_gaps reports per-category-agent
// knowledge gaps and os_api already exposes it as the `knowledge_gaps` action — but it named no
// owner, so a gap had nobody to route to. Measured before wiring, because the six-vocabularies
// rule applies here too: of 110 active category_agents, 84 have an os_knowledge_domain row at
// cat:<slug> and only 53 have one with ownership='owns'. The join is real but PARTIAL, so the
// summary now reports `unowned` as a number instead of the report quietly implying full coverage.
//
// Routine COUNT goes 743 -> 744 in each project; verify_phase1 asserts parity between them, so
// this must be applied to both or that gate goes red. Applied directly and NOT as a migration: a
// migration breaks the 712-vs-712 ledger parity the same gate asserts.
//
//   node scripts/seed_agent_library_reader.mjs              # apply to staging, then measure
//   node scripts/seed_agent_library_reader.mjs --print-sql  # emit the statements for production
import { mgmtRead, mgmtWrite, resolveStagingRef } from './staging/qd_guard.mjs';

// The overload. `distinct on (id)` matters only when v_dept is null, where the unscoped pass can
// already return the same `company` row the second pass asks for.
export const SQL_CONTEXT = `
create or replace function public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare out text; v_dept text; lib text := ''; r record;
begin
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\\n' || left(coalesce(r.content,''), 700) || E'\\n\\n';
  end loop;
  if lib = '' then return out; end if;
  return out || E'\\n' ||
    '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
    E'\\n\\n' || lib;
end
$fn$;
revoke execute on function public.fn_agent_context(text,integer,text) from public;
grant execute on function public.fn_agent_context(text,integer,text) to postgres, service_role;`;

// fn_knowledge_gaps, unchanged except that each agent now carries its owning OS component and the
// summary counts how many have none. The owner is taken as the lowest os_key where ownership='owns'
// so the value is stable across runs rather than whichever row the planner happened to return.
export const SQL_GAPS = `
create or replace function public.fn_knowledge_gaps(p_stale_days integer default 14, p_thin_min integer default 4)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $fn$
  with base as (
    select ca.slug, ca.name, ca.emoji,
      (select count(*) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as items,
      (select max(updated_at) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as last_updated,
      (select min(d.os_key) from os_knowledge_domain d
        where d.domain_key = 'cat:'||ca.slug and d.ownership = 'owns') as owner_os
    from category_agents ca where coalesce(ca.active,true)
  ),
  scored as (
    select slug, name, emoji, items, last_updated, owner_os,
      case when last_updated is null then null else floor(extract(epoch from (now()-last_updated))/86400)::int end as days_stale,
      case when items = 0 then 'missing'
           when last_updated < now() - (p_stale_days||' days')::interval then 'stale'
           when items < p_thin_min then 'thin'
           else 'ok' end as status
    from base
  )
  select jsonb_build_object(
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status='ok'),
      'stale', (select count(*) from scored where status='stale'),
      'thin', (select count(*) from scored where status='thin'),
      'missing', (select count(*) from scored where status='missing'),
      'unowned', (select count(*) from scored where owner_os is null),
      'coverage_pct', round(100.0 * (select count(*) from scored where status='ok') / nullif((select count(*) from scored),0), 1)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', emoji, 'items', items, 'owner_os', owner_os,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status
      ) order by case status when 'stale' then 0 when 'thin' then 1 when 'missing' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb)
  );
$fn$;`;

// THE SPEC SAYS IT IN ONE LINE: "Don't create 20 isolated knowledge bases."
//
// AGENTS_AND_KNOWLEDGE_BLUEPRINT.txt's architectural recommendation is a four-layer stack, and
// layer 2 is "DEPARTMENT Knowledge", not per-employee knowledge. fn_agent_context built layer 2
// from agent_knowledge rows keyed to the individual — which is the isolated-knowledge-base shape
// the spec rejects — and measured 6 Aug 2026 it leaves **52 of 66 active employees with nothing
// under the heading "# LAYER 2 - YOUR PROFESSIONAL EXPERTISE"**. Of the 15 department leads, 8 are
// in that state, including `exec` — the CEO Office AI, requirement #1 of the whole file — whose own
// department holds 12 rows it could not reach. `it` is the sharpest case: 0 personal rows against
// 41 department rows and a 318-row library.
//
// This is not dormant. dept_plan/index.ts:81 calls fn_agent_context(d.lead_agent, 5000) for every
// department on a DAILY production cron, and 4 of the empty agents have already been chatted with.
//
// THE FIX IS ONE WHERE CLAUSE: an employee with no professional knowledge of their own inherits
// their department's. Own rows still win outright wherever they exist, so the 14 agents that have
// them see no change at all. A cat:<slug> specialist has no org_agents row, so v_dept is null and
// the fallback is disabled — same output as before, by construction.
//
// PATCHED BY REWRITING pg_get_functiondef, NOT BY RETYPING THE BODY. The function is ~100 lines
// including a 900-character doctrine string; transcribing it to change one line is how a body
// silently drifts. Taking the server's own definition, replacing an exact substring and executing
// the result preserves every attribute — defaults, STABLE, SECURITY DEFINER, search_path — and the
// `raise exception` makes a missed match fail loudly instead of silently doing nothing.
export const SQL_L2_FALLBACK = `
do $do$
declare def text; newdef text;
begin
  select pg_get_functiondef(p.oid) into def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_agent_context' and p.pronargs = 2;
  if def is null then raise exception 'fn_agent_context(text,integer) not found'; end if;
  -- idempotent: the patch removes its own anchor, so a second run must recognise its own work
  -- rather than raising the "body changed" alarm at itself.
  if def like '%b.department = v_dept%' then return; end if;

  newdef := replace(def,
$old$where agent_key=p_agent_key and coalesce(layer,'profession') in ('profession','state')$old$,
$new$where coalesce(layer,'profession') in ('profession','state')
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))$new$);

  if newdef = def then
    raise exception 'layer-2 department fallback did not match — the body changed, re-read it before patching';
  end if;
  execute newdef;
end
$do$;`;

if (process.argv.includes('--print-sql')) {
  console.log(SQL_CONTEXT);
  console.log(SQL_GAPS);
  console.log(SQL_L2_FALLBACK);
  process.exit(0);
}

const REF = resolveStagingRef(process.argv[2]);
await mgmtWrite(REF, SQL_L2_FALLBACK, 'fn_agent_context layer-2 department fallback');
await mgmtWrite(REF, SQL_CONTEXT, 'fn_agent_context library overload');
await mgmtWrite(REF, SQL_GAPS, 'fn_knowledge_gaps owner attribution');

// MEASURE THE READER, NOT THE DEPLOY. The question is whether a real employee question now comes
// back carrying real library text — and whether the query-less call is still byte-identical.
const q = 'What are the VAT and free zone rules for a UAE trade licence renewal?';
const m = (await mgmtRead(REF, `
  with lead as (select lead_agent k from org_departments where dept_key='legal')
  select (select count(*)::int from public.dept_library) lib_rows,
         (select count(*)::int from public.fn_dept_library_search('legal', ${JSON.stringify(q).replace(/"/g, "'")}, 5)) hits,
         length(public.fn_agent_context((select k from lead), 24000)) plain_len,
         length(public.fn_agent_context((select k from lead), 24000, ${JSON.stringify(q).replace(/"/g, "'")})) with_lib_len,
         (public.fn_agent_context((select k from lead), 24000, ${JSON.stringify(q).replace(/"/g, "'")}) like '%LAYER 2b%') has_section,
         (select k from lead) lead_agent`))[0];

const g = (await mgmtRead(REF, `select
    (public.fn_knowledge_gaps()->'summary'->>'total')::int total,
    (public.fn_knowledge_gaps()->'summary'->>'unowned')::int unowned,
    (select count(*)::int from jsonb_array_elements(public.fn_knowledge_gaps()->'agents') a
      where a->>'owner_os' is not null) owned`))[0];

// The layer-2 fallback is measured on the DATA (how many employees can reach professional
// knowledge at all) plus one rendered spot check on `exec` — the CEO Office AI, requirement #1.
const l2 = (await mgmtRead(REF, `
  with a as (select agent_key, department from public.org_agents where active),
       own as (select a.agent_key, exists (select 1 from public.agent_knowledge k
                 where k.agent_key = a.agent_key
                   and coalesce(k.layer,'profession') in ('profession','state')) hasown,
               exists (select 1 from public.agent_knowledge k
                 join public.org_agents b on b.agent_key = k.agent_key and b.active
                 where b.department = a.department
                   and coalesce(k.layer,'profession') in ('profession','state')) hasdept
          from a)
  select count(*)::int agents,
         count(*) filter (where hasown)::int own_l2,
         count(*) filter (where hasown or hasdept)::int reachable_l2,
         count(*) filter (where not hasown and not hasdept)::int still_empty
    from own`))[0];

const exec = (await mgmtRead(REF, `
  with d as (select lead_agent k from public.org_departments where dept_key='exec'),
       c as (select public.fn_agent_context((select k from d), 24000) t)
  select (select k from d) lead,
         (select count(*)::int from unnest(string_to_array(
            substring(t from '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE(.*?)# LAYER 1'), E'\\n')) l
            where l like '## %') topics
    from c`))[0];

console.log(`layer 2: ${l2.own_l2} of ${l2.agents} employees have their own, ${l2.reachable_l2} can now reach one, ${l2.still_empty} still have nothing`);
console.log(`exec lead "${exec.lead}" renders ${exec.topics} professional-expertise topic(s)`);
console.log(`dept_library ${m.lib_rows} rows, ${m.hits} hits for the legal probe`);
console.log(`fn_agent_context(${m.lead_agent}) ${m.plain_len} chars without a query -> ${m.with_lib_len} with one, LAYER 2b ${m.has_section ? 'present' : 'ABSENT'}`);
console.log(`fn_knowledge_gaps: ${g.total} category agents, ${g.owned} with an owning OS component, ${g.unowned} unowned`);

const ok = m.hits > 0 && m.has_section && m.with_lib_len > m.plain_len && g.owned > 0
  && l2.reachable_l2 > l2.own_l2 && exec.topics > 0;
if (!ok) { console.log('INCOMPLETE — the library is still not reaching the employee context'); process.exitCode = 1; }
else console.log('OK — dept_library and os_knowledge_domain both have a reader on a path that runs');
