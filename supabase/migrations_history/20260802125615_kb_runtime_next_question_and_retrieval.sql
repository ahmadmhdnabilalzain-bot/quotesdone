-- RUNTIME LAYER. Importing 115,000 records changes nothing on its own; these two functions are how
-- the corpus actually replaces model calls.
--
-- A NOTE ON validation_status THAT MATTERS OPERATIONALLY: the corpus arrived with ZERO records at
-- 'approved' (71% reviewed, 19% source_verified, 10% draft), and the control pack forbids
-- mass-promoting them. So a retrieval layer written to filter on validation_status='approved' would
-- return nothing at all, forever, and every call would silently fall back to a premium model - the
-- exact cost the import was meant to remove. The rule used here instead:
--   * 'reviewed' and 'source_verified' are usable for CUSTOMER-FACING guidance;
--   * 'draft' is retrievable only for internal reasoning, never quoted to a customer;
--   * anything carrying an escalation_rule, or in the uae_regulations module, is returned with
--     escalate=true so the caller cites the authority instead of paraphrasing the law.
-- Promotion to 'approved' stays a human act, per package, and nothing here does it.

-- ---------------------------------------------------------------------------------------------
-- DETERMINISTIC NEXT QUESTION + COMPLETENESS.
-- This is the function that is supposed to make inquiry_ai cheap. Today a model is asked, on every
-- customer turn, which question to ask next and whether the brief is complete - at ~14,600 input
-- tokens a call. Both are now answerable from a table: the corpus ships 16,588 qualification
-- questions with mandatory flags, activation order and explicit missing-answer behaviour.
create or replace function public.fn_kb_next_question(p_catalog_num int, p_answered jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable as $$
declare v_scope jsonb; v_next jsonb; v_missing jsonb; v_total int; v_answered int; v_blocking int;
begin
  -- scope = the knowledge subcategories this live catalogue route maps to
  with scope as (
    select m.package_slug, m.subcategory_slug, m.priority
    from public.kb_operational_route_map m where m.catalog_num = p_catalog_num
  ),
  qs as (
    select q.question_id, q.source_question_id, q.field_key, q.question_en, q.question_ar,
           q.answer_type, q.allowed_values, q.unit, q.mandatory, q.on_missing, q.impact,
           q.answerable_by_documents, q.category_slug, q.subcategory_slug,
           coalesce((q.activation->>'order')::int, 999) as ord
    from kb_stage.questions q
    join scope s on s.package_slug = q.category_slug and s.subcategory_slug = q.subcategory_slug
    where q.field_key is not null
  ),
  -- One question per field_key across all mapped subcategories. A composite route (signage maps to
  -- 3 packages) otherwise asks "which emirate?" seven times.
  dedup as (
    select distinct on (field_key) * from qs order by field_key, mandatory desc, ord, question_id
  ),
  open as (
    select * from dedup
    where not (p_answered ? field_key)
       or nullif(btrim(coalesce(p_answered->>field_key, '')), '') is null
  )
  select
    (select to_jsonb(o) from open o order by o.mandatory desc, o.ord, o.question_id limit 1),
    (select coalesce(jsonb_agg(jsonb_build_object('field_key', o.field_key, 'mandatory', o.mandatory,
                                                  'on_missing', o.on_missing) order by o.mandatory desc, o.ord), '[]'::jsonb)
       from open o),
    (select count(*) from dedup where mandatory),
    (select count(*) from dedup d where d.mandatory and p_answered ? d.field_key
        and nullif(btrim(coalesce(p_answered->>d.field_key,'')),'') is not null),
    (select count(*) from open o where o.mandatory
        and (o.on_missing is null or o.on_missing ilike 'block%' or o.on_missing ilike '%block%'))
  into v_next, v_missing, v_total, v_answered, v_blocking;

  return jsonb_build_object(
    'catalog_num', p_catalog_num,
    'next_question', v_next,
    'missing', v_missing,
    'mandatory_total', coalesce(v_total, 0),
    'mandatory_answered', coalesce(v_answered, 0),
    'completeness', case when coalesce(v_total,0) = 0 then null
                         else round(coalesce(v_answered,0)::numeric / v_total, 3) end,
    -- The single auditable gate the external reviewer asked for: one boolean, one query, one place.
    'dispatch_eligible', coalesce(v_blocking, 0) = 0,
    'blocking_count', coalesce(v_blocking, 0),
    'source', 'kb_stage.questions (deterministic, no model call)');
end $$;

comment on function public.fn_kb_next_question(int, jsonb) is
  'Deterministic replacement for asking a model "what should I ask next / is this brief complete". Returns the next unanswered question (EN+AR, answer type, allowed values), the full missing list, a completeness ratio and dispatch_eligible. No model call, no cost.';

-- ---------------------------------------------------------------------------------------------
-- RETRIEVAL. The control pack is explicit: send a model a few relevant records or exact source
-- extracts, never a category master. The masters average 1.8 MB each; one of them in a prompt is
-- roughly 450,000 tokens, which is both impossible and pointless.
create or replace function public.fn_kb_retrieve(p_catalog_num int, p_query text,
                                                 p_limit int default 6, p_modules text[] default null)
returns table (record_id text, title text, content text, module text, record_type text,
               authority text, validation_status text, confidence numeric, source_ids jsonb,
               escalate boolean, rank real)
language sql stable as $$
with scope as (
  select m.package_slug, m.subcategory_slug from public.kb_operational_route_map m
  where m.catalog_num = p_catalog_num
), q as (
  select websearch_to_tsquery('simple', coalesce(p_query, '')) tsq
)
select r.record_id, r.title, left(r.content, 4000), r.module, r.record_type, r.authority,
       r.validation_status, r.confidence, r.source_ids,
       (r.escalation_rule is not null or r.module = 'uae_regulations') as escalate,
       ts_rank(to_tsvector('simple', r.title || ' ' || left(r.content, 4000)), q.tsq) as rank
from kb_stage.records r
join scope s on s.package_slug = r.category_slug and s.subcategory_slug = r.subcategory_slug
cross join q
where r.validation_status in ('reviewed', 'source_verified', 'approved')
  and (p_modules is null or r.module = any (p_modules))
  and (q.tsq is null or to_tsvector('simple', r.title || ' ' || left(r.content, 4000)) @@ q.tsq)
order by rank desc, r.confidence desc nulls last, r.record_id
limit greatest(p_limit, 1);
$$;

comment on function public.fn_kb_retrieve(int, text, int, text[]) is
  'Returns at most a handful of relevant, non-draft records for one live catalogue route. Draft records are excluded from anything customer-facing; regulation records and anything with an escalation_rule come back with escalate=true so the caller cites the authority rather than paraphrasing it.';

create index if not exists kb_stage_records_fts_idx
  on kb_stage.records using gin (to_tsvector('simple', title || ' ' || left(content, 4000)));

grant execute on function public.fn_kb_next_question(int, jsonb) to service_role;
grant execute on function public.fn_kb_retrieve(int, text, int, text[]) to service_role;
