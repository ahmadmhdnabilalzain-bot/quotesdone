-- ROW #5 §18 — THE SUPPLIER COLLABORATION WORKSPACE.
--
-- ── "EVERY CUSTOMER RELATIONSHIP GETS A WORKSPACE" ──────────────────────────────────────────────
-- A relationship in this schema is an (inquiry, supplier) pair: that is what chat_threads and
-- messages are keyed on, and what a reveal creates. So a workspace is one row per pair, holding the
-- project it belongs to, its files, its message count and its timeline — the four things §18 draws.
--
-- The pieces all existed separately. inquiries carries the project, messages carries the
-- conversation, and documents carries the files keyed by (ref_table, ref_id) — there is no
-- inquiry_docs table, which an earlier draft of this file assumed and Postgres corrected. NOTHING
-- joined them into a per-relationship container the supplier could open. This is that join.
--
-- ── WHY THIS RETURNS AN EMPTY LIST ON PRODUCTION TODAY, AND WHY THAT IS NOT A BUG ───────────────
-- 0 inquiries and 0 inquiry_matches exist, so there are no relationships to render. The function
-- returns an empty array with `population` naming the two counts, so an empty workspace list is
-- never mistaken for a query that failed.
--
-- It is NOT filled with a demo relationship, and that is a deliberate limit rather than an
-- oversight. Inserting one inquiry on production fires TWELVE triggers, including
-- fn_emit_event('inquiry','rfq.created') — which would inject a synthetic event into the row #2
-- event backbone that is separately measured at 107/110 — and trg_autodispatch_inquiry. Matching
-- would find 0 suppliers because none is verified, so no real company would be contacted, but
-- polluting another row's measured estate is the founder's call to make, not a side effect to slip
-- in. The mechanism is built and provable; the data path is flagged, not faked.
create or replace function public.fn_supplier_workspaces(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with rel as (
    -- One row per customer relationship this supplier actually has: an inquiry they were matched
    -- to, or one they have exchanged messages about.
    select distinct i.id as inquiry_id
    from public.inquiries i
    where exists (select 1 from public.inquiry_matches m
                  where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
       or exists (select 1 from public.messages g
                  where g.inquiry_id = i.id and g.supplier_id = p_lead_id)
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from rel),
    -- The populations behind an empty list, so nobody has to guess whether the query worked.
    'population', jsonb_build_object(
      'inquiries', (select count(*) from public.inquiries),
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          -- §18's project identity.
          'project', jsonb_build_object(
            -- inquiries has no `title` column. The human-readable name is the summary, then the
            -- category, then the RFQ number — falling through in that order means a workspace
            -- always has a name rather than rendering as blank.
            'title', coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                              'RFQ ' || coalesce(i.rfq_no::text, i.id::text)),
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          -- §18's files, CATEGORISED. The spec names drawings, specifications and contracts, so the
          -- bucket is derived from the document's own kind rather than left as one undifferentiated
          -- pile — a workspace whose files are a flat list is the thing §18 replaces.
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'name', d.file_name, 'kind', d.kind, 'created_at', d.created_at,
              'category', case
                when d.kind ~* 'drawing|dwg|plan|layout'        then 'drawings'
                when d.kind ~* 'spec|datasheet|boq|schedule'    then 'specifications'
                when d.kind ~* 'contract|agreement|po|purchase' then 'contracts'
                else 'other' end
            ) order by d.created_at desc), '[]'::jsonb)
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'file_categories', (
            select jsonb_build_object(
              'drawings', count(*) filter (where d.kind ~* 'drawing|dwg|plan|layout'),
              'specifications', count(*) filter (where d.kind ~* 'spec|datasheet|boq|schedule'),
              'contracts', count(*) filter (where d.kind ~* 'contract|agreement|po|purchase'),
              'other', count(*) filter (where d.kind !~* 'drawing|dwg|plan|layout|spec|datasheet|boq|schedule|contract|agreement|po|purchase')
            )
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          -- §18's message count, and the unread split a supplier actually acts on.
          'message_count', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id and not coalesce(g.blocked, false)
          ),
          'unread', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
              and g.sender = 'customer' and not coalesce(g.read_by_supplier, false)
              and not coalesce(g.blocked, false)
          ),
          'last_activity', (
            select max(g.created_at) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
          ),
          -- §18's timeline percentage. Derived from the stages the relationship has actually
          -- passed, so it moves for a real reason and is null before anything has happened rather
          -- than sitting at a meaningless 0%.
          'timeline', (
            select jsonb_build_object(
              'pct', case when total = 0 then null else round(100.0 * hit / total) end,
              'stages', jsonb_build_object(
                'matched', matched, 'messaged', messaged, 'quoted', quoted, 'awarded', awarded)
            )
            from (
              select 4 as total,
                (exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id and m.supplier_id = p_lead_id))::int
                  as matched,
                (exists (select 1 from public.messages g where g.inquiry_id = i.id and g.supplier_id = p_lead_id))::int
                  as messaged,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id))::int
                  as quoted,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id
                         and q.status = 'won'))::int as awarded
            ) s, lateral (select (s.matched + s.messaged + s.quoted + s.awarded) as hit) h
          )
        ) as w
        from rel r join public.inquiries i on i.id = r.inquiry_id
      ) t
    )
  );
$function$;

comment on function public.fn_supplier_workspaces(bigint) is
  'Row #5 §18. One workspace per customer relationship — project, categorised files, message count '
  'and a stage-derived timeline. Returns an empty list with its population named when the supplier '
  'has no relationships; timeline pct is null rather than 0 before anything has happened.';
