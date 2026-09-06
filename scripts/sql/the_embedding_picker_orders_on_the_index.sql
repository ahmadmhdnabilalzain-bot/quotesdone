-- THE EMBEDDING PICKER ORDERS ON THE INDEX (6 Sep 2026). Corrects the_embedding_picker_claims_its_rows.sql.
--
-- MEASURED three minutes after that file: 15 kb_embed responses, 0 embedded, every one "done". The
-- claim's ORDER BY was `case when p_newest then null else created_at end asc, case when p_newest then
-- created_at end desc` - a plain-column order in disguise that the planner cannot serve from the
-- created_at index, so it sorted ~2.54M unembedded rows and hit PostgREST's 8 s wall on every call.
-- The in-file proof had passed because the apply connection carries a longer statement timeout: a
-- rehearsal on the wrong connection proves the wrong thing. The picker is now plpgsql with two plain
-- branches (`order by created_at asc` / `desc`), which is the index scan min(created_at) already
-- uses in 0.8 s. Same signature, same claim semantics.
--
--   node scripts/apply_sql.mjs scripts/sql/the_embedding_picker_orders_on_the_index.sql --apply --ddl

begin;

create or replace function public.fn_kb_embed_claim(p_limit integer default 5, p_source_kinds text[] default null, p_categories text[] default null, p_newest boolean default false)
returns table(id bigint, title text, content text)
language plpgsql
volatile security definer
set search_path to 'public', 'pg_temp'
as $function$
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

-- PROOF, under the SAME 8 s wall PostgREST applies, inside a savepoint that is rolled back.
do $proof$
declare a bigint[]; t0 timestamptz; ms int;
begin
  perform set_config('statement_timeout', '8s', true);
  t0 := clock_timestamp();
  select array_agg(c.id) into a from public.fn_kb_embed_claim(5, null, null, false) c;
  ms := extract(milliseconds from clock_timestamp() - t0)::int + 1000 * extract(seconds from clock_timestamp() - t0)::int;
  if coalesce(cardinality(a), 0) <> 5 then raise exception 'claim returned % rows under the 8 s wall', cardinality(a); end if;
  update public.kb_chunks set embed_claimed_at = null where id = any(a);
  raise notice 'claim proof: 5 rows in % ms', ms;
end $proof$;

commit;
