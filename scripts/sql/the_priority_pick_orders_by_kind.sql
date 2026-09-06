-- THE PRIORITY PICK ORDERS BY KIND (6 Sep 2026). Follows the_priority_pick_reads_its_own_index.sql.
--
-- MEASURED after that index was built (valid, 18 MB): the planner still chose kb_chunks_unembedded_created_idx
-- for the kind-filtered pick (Rows Removed by Filter 2,561,738; 459,780 pages read) because its
-- estimate for "these four kinds among the un-embedded rows" is ~3,000 while the truth is 4, so a
-- date-ordered walk looks like it will find five rows at once. The function now has a third branch
-- for a kind-filtered pick that orders by (source_kind, created_at), which the new index serves
-- directly with the array key; the plain and newest-first branches are unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/the_priority_pick_orders_by_kind.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_kb_embed_claim(p_limit integer DEFAULT 5, p_source_kinds text[] DEFAULT NULL::text[], p_categories text[] DEFAULT NULL::text[], p_newest boolean DEFAULT false)
 RETURNS TABLE(id bigint, title text, content text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lim int := greatest(1, least(coalesce(p_limit, 5), 8));
begin
  if coalesce(p_newest, false) then
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_source_kinds is null or k.source_kind = any(p_source_kinds))
           and (p_categories is null or k.category = any(p_categories))
         order by k.created_at desc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  elsif p_source_kinds is not null then
    -- 6 SEP 2026: a kind-filtered pick reads kb_chunks_unembedded_kind_created_idx (source_kind, created_at)
    -- where embedding_gte is null. Ordered by kind first so the index serves the order and the array
    -- key: the planner otherwise walks the whole un-embedded set in date order (2.56M rows, 370k pages
    -- read from disk, 23 s) because it cannot see that only a handful of these kinds remain.
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and k.source_kind = any(p_source_kinds)
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_categories is null or k.category = any(p_categories))
         order by k.source_kind asc, k.created_at asc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  else
    return query
      with pick as (
        select k.id
          from public.kb_chunks k
         where k.embedding_gte is null
           and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
           and (p_source_kinds is null or k.source_kind = any(p_source_kinds))
           and (p_categories is null or k.category = any(p_categories))
         order by k.created_at asc
         limit v_lim
           for update skip locked)
      update public.kb_chunks k set embed_claimed_at = now()
        from pick where k.id = pick.id
      returning k.id, k.title, k.content;
  end if;
end $function$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_priority_pick_orders_by_kind.sql',
       evidence = 'kind-filtered pick reads its own partial index (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_kb_embed_claim';
