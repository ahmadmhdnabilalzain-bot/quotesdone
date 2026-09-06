-- THE EMBEDDING PICKER CLAIMS ITS ROWS (6 Sep 2026). Sibling of the_embedding_backfill_runs_again_under_the_kernel.sql.
--
-- MEASURED three minutes after the three backfill jobs came back: 30 kb_embed responses reported 40
-- embeddings between them, five invocations died with HTTP 546, one wrote "failed to write 1 of 1
-- back ... canceling statement due to statement timeout", and the frontier (oldest unembedded chunk)
-- moved 11 seconds of created_at. Cause: every invocation picks the same five oldest unembedded rows
-- (`order by created_at limit 5`), so 13 concurrent invocations a minute embed the same rows and
-- queue on the same row locks - duplicated model work, lock waits past the 8 s wall, and no progress.
--
-- THE FIX is the claim pattern fn_workflow_step_claim already uses: fn_kb_embed_claim(limit, kinds,
-- categories, newest) takes the oldest unclaimed rows FOR UPDATE SKIP LOCKED, stamps
-- kb_chunks.embed_claimed_at, and returns them. A claim older than 3 minutes is free again, so a
-- worker that died holding five rows costs three minutes, not the rows. The column is nullable with
-- no default (instant on 2.65M rows); the vector write still keys on id.
--
--   node scripts/apply_sql.mjs scripts/sql/the_embedding_picker_claims_its_rows.sql --apply --ddl

begin;

alter table public.kb_chunks add column if not exists embed_claimed_at timestamptz;
comment on column public.kb_chunks.embed_claimed_at is 'Set by fn_kb_embed_claim when a kb_embed worker takes the row to embed; a claim older than 3 minutes is free again. Null once nobody holds it; irrelevant once embedding_gte is set.';

create or replace function public.fn_kb_embed_claim(p_limit integer default 5, p_source_kinds text[] default null, p_categories text[] default null, p_newest boolean default false)
returns table(id bigint, title text, content text)
language sql
volatile security definer
set search_path to 'public', 'pg_temp'
as $function$
  with pick as (
    select k.id
      from public.kb_chunks k
     where k.embedding_gte is null
       and (k.embed_claimed_at is null or k.embed_claimed_at < now() - interval '3 minutes')
       and (p_source_kinds is null or k.source_kind = any(p_source_kinds))
       and (p_categories is null or k.category = any(p_categories))
     order by case when p_newest then null else k.created_at end asc nulls last,
              case when p_newest then k.created_at end desc nulls last,
              k.id
     limit greatest(1, least(coalesce(p_limit, 5), 8))
       for update skip locked
  )
  update public.kb_chunks k
     set embed_claimed_at = now()
    from pick
   where k.id = pick.id
  returning k.id, k.title, k.content;
$function$;

revoke execute on function public.fn_kb_embed_claim(integer, text[], text[], boolean) from public, anon, authenticated;
grant execute on function public.fn_kb_embed_claim(integer, text[], text[], boolean) to service_role;

-- PROOF (aborted inside a savepoint): two claims in one transaction return disjoint rows, and a claim
-- is visible on the rows it took.
do $proof$
declare a bigint[]; b bigint[]; n int;
begin
  select array_agg(c.id) into a from public.fn_kb_embed_claim(5, null, null, false) c;
  select array_agg(c.id) into b from public.fn_kb_embed_claim(5, null, null, false) c;
  if coalesce(cardinality(a),0) <> 5 or coalesce(cardinality(b),0) <> 5 then raise exception 'claims returned % and % rows, expected 5 and 5', cardinality(a), cardinality(b); end if;
  if a && b then raise exception 'two claims overlapped: % vs %', a, b; end if;
  select count(*) into n from public.kb_chunks where id = any(a || b) and embed_claimed_at is not null;
  if n <> 10 then raise exception 'claim stamped % of 10 rows', n; end if;
  raise notice 'claim proof: % + % disjoint rows stamped', cardinality(a), cardinality(b);
  -- the proof's own claims are released so the first real tick is not delayed by three minutes
  update public.kb_chunks set embed_claimed_at = null where id = any(a || b);
end $proof$;

commit;
