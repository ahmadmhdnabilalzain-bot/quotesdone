-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710213155   name: knowledge_quality_views
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Per-chunk confidence score (0-100 + band) from citation, title, substance, dating.
create or replace view public.v_kb_confidence as
select *, case when confidence>=75 then 'high' when confidence>=50 then 'medium' else 'low' end as band
from (
  select id, category, left(title,80) as title,
    least(100,
        (case when citation is not null and length(btrim(citation))>=8 then 40 else 0 end)
      + (case when title is not null and btrim(title)<>'' then 20 else 0 end)
      + (case when length(coalesce(content,''))>=200 then 20 else 0 end)
      + (case when effective_date is not null and effective_date>=current_date then 20
              when effective_date is not null then 10 else 0 end)
    ) as confidence,
    (citation is not null and length(btrim(coalesce(citation,'')))>=8) as has_citation,
    effective_date, created_at
  from public.kb_chunks
) s;
revoke all on public.v_kb_confidence from anon, authenticated;

-- 2) Broken/weak-citation guard.
create or replace view public.v_kb_citation_check as
select id, category, left(title,80) as title, citation, source_kind, source_id, created_at
from public.kb_chunks
where citation is null or length(btrim(coalesce(citation,''))) < 8
order by created_at desc;
revoke all on public.v_kb_citation_check from anon, authenticated;

-- 3) Review worklist: undated, expired, weak-citation, or aging chunks.
create or replace view public.v_kb_review_due as
select id, category, left(title,80) as title, effective_date, created_at,
  array_remove(array[
    case when effective_date is null then 'undated' end,
    case when effective_date is not null and effective_date < current_date then 'expired' end,
    case when citation is null or length(btrim(coalesce(citation,'')))<8 then 'weak_citation' end,
    case when created_at < now() - interval '180 days' then 'aging' end
  ], null) as reasons
from public.kb_chunks
where effective_date is null
   or (effective_date is not null and effective_date < current_date)
   or citation is null or length(btrim(coalesce(citation,'')))<8
   or created_at < now() - interval '180 days'
order by created_at desc;
revoke all on public.v_kb_review_due from anon, authenticated;
