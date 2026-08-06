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

if (process.argv.includes('--print-sql')) {
  console.log(SQL_CONTEXT);
  console.log(SQL_GAPS);
  process.exit(0);
}

const REF = resolveStagingRef(process.argv[2]);
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

console.log(`dept_library ${m.lib_rows} rows, ${m.hits} hits for the legal probe`);
console.log(`fn_agent_context(${m.lead_agent}) ${m.plain_len} chars without a query -> ${m.with_lib_len} with one, LAYER 2b ${m.has_section ? 'present' : 'ABSENT'}`);
console.log(`fn_knowledge_gaps: ${g.total} category agents, ${g.owned} with an owning OS component, ${g.unowned} unowned`);

const ok = m.hits > 0 && m.has_section && m.with_lib_len > m.plain_len && g.owned > 0;
if (!ok) { console.log('INCOMPLETE — the library is still not reaching the employee context'); process.exitCode = 1; }
else console.log('OK — dept_library and os_knowledge_domain both have a reader on a path that runs');
