-- THE COMMAND PALETTE'S ENTITY SEARCH RETURNED 500 ON EVERY QUERY (6 Sep 2026, OS walk after PR #523).
--
-- Measured in the founder's own browser: typing "fit" into the Ctrl+K palette fired os_api
-- action 'search', which answered HTTP 500 after 8.8 s with "canceling statement due to
-- statement timeout". fn_os_search searched nine corpora; eight answer in under 2 s. The ninth was
--
--     kb_chunks: title ilike '%q%' or content ilike '%q%' or category ilike '%q%'
--                order by effective_date desc nulls last limit 8
--
-- over 2,687,194 rows — a sequential scan of every chunk's content, 25 s and more, inside the 8 s
-- statement budget the authenticator role gives every PostgREST request. So the palette has never
-- shown an entity hit: the whole JSON was lost with the one corpus that timed out.
--
-- kb_chunks already carries a generated tsvector column `fts` = to_tsvector('english', title || ' '
-- || content) with a GIN index (kb_chunks_fts). This file makes the knowledge corpus use it:
-- `fts @@ plainto_tsquery('english', q)`, first eight index hits, no ORDER BY — ordering by
-- effective_date forced Postgres to collect every match first (8 s+ for a common word like "fit");
-- unordered, "fit", "fit out", "hvac", "trade licence" and a nonsense term each answer in 300–470 ms.
-- Nothing else in the function changes.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/os_search_reads_knowledge_through_its_fts_index.sql --apply --ddl
-- Prove:  Ctrl+K in the OS, type "fit" → the Entities group lists knowledge hits; os_api 'search' answers 200.

CREATE OR REPLACE FUNCTION public.fn_os_search(p_q text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with b as (select coalesce(nullif(btrim(p_q), ''), '') q,
                    '-infinity'::date lo, 'infinity'::date hi)
  select jsonb_build_object(
    'query', (select q from b),

    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'sub',emirate||' · '||coalesce(sector,''))) from (
        select l.id, l.company_name, l.emirate, l.sector from public.leads l, b
         where b.q <> '' and l.company_name ilike '%'||b.q||'%'
         order by l.capability_score desc nulls last limit 6) s),'[]'::jsonb),

    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',coalesce(summary,category),'sub',category)) from (
        select i.id, i.summary, i.category from public.inquiries i, b
         where b.q <> '' and (i.summary ilike '%'||b.q||'%' or i.category ilike '%'||b.q||'%')
           and i.created_at::date between b.lo and b.hi
         order by i.created_at desc limit 6) r),'[]'::jsonb),

    'customers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name,'sub',email)) from (
        select c.id, c.full_name, c.email from public.customers c, b
         where b.q <> '' and (c.full_name ilike '%'||b.q||'%' or c.email ilike '%'||b.q||'%') limit 6) c),'[]'::jsonb),

    -- ── WHAT THE COMPANY KNOWS ───────────────────────────────────────────────────────────────
    -- 2.69M chunks: the generated `fts` column and its GIN index are the only way through this
    -- table inside the 8 s request budget. First eight hits, unordered — an ORDER BY here makes
    -- Postgres collect every match before it can return one (measured 8 s+ for "fit").
    'knowledge', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',title,'sub',citation,'at',effective_date)) from (
        select k.id, k.title, k.citation, k.effective_date from public.kb_chunks k, b
         where b.q <> '' and k.fts @@ plainto_tsquery('english', b.q)
         limit 8) k),'[]'::jsonb),

    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',file_name,'sub',kind,'at',created_at)) from (
        select d.id, d.file_name, d.kind, d.created_at from public.documents d, b
         where b.q <> '' and (d.file_name ilike '%'||b.q||'%' or d.kind ilike '%'||b.q||'%')
           and d.created_at::date between b.lo and b.hi
         order by d.created_at desc limit 6) d),'[]'::jsonb),

    -- ── WHAT THE COMPANY REMEMBERS ───────────────────────────────────────────────────────────
    'lessons', coalesce((select jsonb_agg(jsonb_build_object(
          'id',id,'name',headline,'sub',outcome,'detail',left(detail,240),'kind',kind,
          'os_key',os_key,'confidence',confidence,'occurred_at',occurred_at)) from (
        select m.* from public.institutional_memory m, b
         where (b.q = '' or m.headline ilike '%'||b.q||'%' or m.detail ilike '%'||b.q||'%'
                or m.category_slug ilike '%'||b.q||'%')
           and coalesce(m.occurred_at, m.created_at)::date between b.lo and b.hi
         order by coalesce(m.occurred_at, m.created_at) desc limit 10) m),'[]'::jsonb),

    'org_memory', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',left(content,120),'sub',scope||' · '||coalesce(kind,''),'at',created_at)) from (
        select o.id, o.content, o.scope, o.kind, o.created_at from public.org_memory o, b
         where b.q <> '' and (o.content ilike '%'||b.q||'%' or o.scope ilike '%'||b.q||'%')
           and o.created_at::date between b.lo and b.hi
         order by o.created_at desc limit 8) o),'[]'::jsonb),

    'agent_memory', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',left(content,120),'sub',agent_key||' · '||coalesce(kind,''),'at',created_at)) from (
        select a.id, a.content, a.agent_key, a.kind, a.created_at from public.agent_memory a, b
         where b.q <> '' and (a.content ilike '%'||b.q||'%' or a.agent_key ilike '%'||b.q||'%')
           and a.created_at::date between b.lo and b.hi
         order by a.created_at desc limit 8) a),'[]'::jsonb),

    -- ── WHAT THE COMPANY DECIDED ─────────────────────────────────────────────────────────────
    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
          'id',id,'name',decision,'sub',actor||' · '||coalesce(kind,''),'reasons',reasons,
          'confidence',confidence,'route_to',route_to,'at',created_at)) from (
        select l.* from public.decision_log l, b
         where (b.q = '' or l.decision ilike '%'||b.q||'%' or l.actor ilike '%'||b.q||'%'
                or l.kind ilike '%'||b.q||'%' or l.ctx::text ilike '%'||b.q||'%')
           and l.created_at::date between b.lo and b.hi
         order by l.created_at desc limit 10) l),'[]'::jsonb)
  );
$function$;
