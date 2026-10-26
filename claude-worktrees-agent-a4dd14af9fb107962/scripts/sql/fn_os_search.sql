-- fn_os_search — one search box over everything the company knows.
--
-- Screen 12 of the executive-UI spec: "one search box that searches everything the company knows."
-- The routine searched three operational tables — suppliers, RFQs and customers — and none of the
-- company's actual memory. Everything the company has learned, decided or written down was
-- unreachable from the search box:
--
--   kb_chunks              5,109 knowledge chunks
--   org_memory               362 organisational memories
--   agent_memory             355 employee memories
--   institutional_memory     269 lessons, each with an outcome
--   decision_log           1,278 decisions across 49 actors
--   documents                 16 indexed documents
--
-- THE SIGNATURE IS UNCHANGED ON PURPOSE. Adding `p_from date default null` would not replace this
-- routine — it would create a second overload beside it, and anything reading pg_get_functiondef
-- with `limit 1` could then pick either body. Period scoping lives in fn_os_memory below, which is
-- a new routine rather than a new overload of this one.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_os_search.sql --promote
create or replace function public.fn_os_search(p_q text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
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
    'knowledge', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',title,'sub',citation,'at',effective_date)) from (
        select k.id, k.title, k.citation, k.effective_date from public.kb_chunks k, b
         where b.q <> '' and (k.title ilike '%'||b.q||'%' or k.content ilike '%'||b.q||'%'
                              or k.category ilike '%'||b.q||'%')
         order by k.effective_date desc nulls last limit 8) k),'[]'::jsonb),

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

-- fn_os_memory — the company's memory, asked about a SUBJECT and scoped to a PERIOD.
--
-- "Show every decision about Marketing." "Why did we reject Supplier X?" "When did AI change
-- pricing?" "Find lessons from February." Four questions the console could not ask, because every
-- reachable reader of decision_log took no arguments and returned the last ten by recency.
--
-- This is a separate routine rather than an overload of fn_os_search: see the note above.
create or replace function public.fn_os_memory(p_q text default null, p_from date default null, p_to date default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
  with b as (select coalesce(nullif(btrim(p_q), ''), '') q,
                    coalesce(p_from, '-infinity'::date) lo,
                    coalesce(p_to, 'infinity'::date) hi)
  select jsonb_build_object(
    'subject', (select q from b), 'from', p_from, 'to', p_to,

    -- Every decision about a subject, over a period.
    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
          'id', l.id, 'actor', l.actor, 'kind', l.kind, 'decision', l.decision,
          'confidence', l.confidence, 'reasons', l.reasons, 'route_to', l.route_to, 'at', l.created_at)
        order by l.created_at desc)
      from (select l.* from public.decision_log l, b
             where (b.q = '' or l.decision ilike '%'||b.q||'%' or l.actor ilike '%'||b.q||'%'
                    or l.kind ilike '%'||b.q||'%' or l.ctx::text ilike '%'||b.q||'%')
               and l.created_at::date between b.lo and b.hi
             order by l.created_at desc limit 25) l), '[]'::jsonb),

    -- Why something was rejected: the recorded reasoning behind a past decision.
    'rejection_reason', coalesce((select jsonb_agg(jsonb_build_object(
          'id', d.id, 'problem', d.problem, 'recommendation', d.recommendation,
          'risks', d.risks, 'options', d.options, 'status', d.status,
          'decided_by', d.decided_by, 'actual_outcome', d.actual_outcome, 'at', d.created_at)
        order by d.created_at desc)
      from (select d.* from public.decision_record d, b
             where (b.q = '' or d.problem ilike '%'||b.q||'%' or d.recommendation ilike '%'||b.q||'%'
                    or d.context ilike '%'||b.q||'%')
               and d.created_at::date between b.lo and b.hi
             order by d.created_at desc limit 15) d), '[]'::jsonb),

    -- When something changed, and who changed it. undo_log is the row-level change history.
    'changes', coalesce((select jsonb_agg(jsonb_build_object(
          'id', u.id, 'table_name', u.table_name, 'row_id', u.row_id, 'op', u.op,
          'actor', u.actor, 'reverted', u.reverted, 'at', u.created_at)
        order by u.created_at desc)
      from (select u.* from public.undo_log u, b
             where (b.q = '' or u.table_name ilike '%'||b.q||'%' or u.actor ilike '%'||b.q||'%')
               and u.created_at::date between b.lo and b.hi
             order by u.created_at desc limit 25) u), '[]'::jsonb),
    'change_subjects', coalesce((select jsonb_agg(jsonb_build_object('table_name', t.table_name, 'n', t.n) order by t.n desc)
      from (select table_name, count(*) n from public.undo_log group by 1) t), '[]'::jsonb),

    -- Lessons, scoped to a period.
    'lessons', coalesce((select jsonb_agg(jsonb_build_object(
          'id', m.id, 'headline', m.headline, 'detail', left(m.detail, 300), 'outcome', m.outcome,
          'kind', m.kind, 'os_key', m.os_key, 'confidence', m.confidence, 'occurred_at', m.occurred_at)
        order by coalesce(m.occurred_at, m.created_at) desc)
      from (select m.* from public.institutional_memory m, b
             where (b.q = '' or m.headline ilike '%'||b.q||'%' or m.detail ilike '%'||b.q||'%'
                    or m.category_slug ilike '%'||b.q||'%')
               and coalesce(m.occurred_at, m.created_at)::date between b.lo and b.hi
             order by coalesce(m.occurred_at, m.created_at) desc limit 20) m), '[]'::jsonb)
  );
$function$;
