-- THE ML EMBED WRITE READS A KB CHUNK BY ITS KEY (platform audit 30 Sep 2026, findings M5 and L7).
--
-- ml-embed-backfill failed on main in runs 36400612179 (28 Sep) and 36228514668 (26 Sep) with
--   57014 canceling statement due to statement timeout
--   CONTEXT: select md5(...) from public.v_knowledge_ml_source s where s.src = p_src and s.row_id = p_row_id
--            PL/pgSQL function fn_ml_embed_write(text,text,text,vector,vector) line 8
--
-- v_knowledge_ml_source exposes kb_chunks.id as (id)::text. Measured with EXPLAIN on 30 Sep:
--   where s.src = 'kb_chunks' and s.row_id = '1047'
--   -> Seq Scan on kb_chunks k (cost 0..530,476)  Filter: ((id)::text = '1047'::text)
-- A full pass of the 8 GB table for every kb_chunks row written, up to 16 per runner statement.
--
-- The fix: for src 'kb_chunks' the hash is read from kb_chunks by its bigint primary key. The hashed text
-- is the same expression the view gives (title, newline, content), so a hash computed by the runner from
-- the view still matches. Every other source still reads the view; they are small tables, and their
-- UNION branches are skipped by the src filter. A row_id that is not an integer finds no row, so
-- v_now_hash stays null and the write returns false exactly as the view lookup did.
--
-- Body otherwise byte-identical to an_arabic_question_finds_the_same_knowledge_as_an_english_one.sql.
-- CREATE OR REPLACE keeps the existing ACL (service_role only), so no grant or revoke is repeated here.
create or replace function public.fn_ml_embed_write(p_src text, p_row_id text, p_hash text, p_embedding vector(384),
  p_embedding_gte vector(384) default null)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare v_now_hash text;
begin
  if p_embedding is null then raise exception 'fn_ml_embed_write: no vector for %/%', p_src, p_row_id; end if;
  if p_src in ('support_knowledge', 'ceo_knowledge') and p_embedding_gte is null then
    raise exception 'fn_ml_embed_write: % rows carry their gte-small vector too', p_src;
  end if;
  if p_src = 'kb_chunks' then
    if p_row_id ~ '^[0-9]{1,18}$' then
      select md5(coalesce(k.title, '') || E'\n' || coalesce(k.content, '')) into v_now_hash
        from public.kb_chunks k where k.id = p_row_id::bigint;
    end if;
  else
    select md5(coalesce(s.title, '') || E'\n' || coalesce(s.body, '')) into v_now_hash
      from public.v_knowledge_ml_source s where s.src = p_src and s.row_id = p_row_id;
  end if;
  delete from public.knowledge_ml_claim where src = p_src and row_id = p_row_id;
  if v_now_hash is distinct from p_hash then return false; end if;
  insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values (p_src, p_row_id, p_hash, p_embedding)
  on conflict (src, row_id) do update set text_hash = excluded.text_hash, embedding = excluded.embedding, embedded_at = now();
  if p_src = 'support_knowledge' then
    update public.support_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  elsif p_src = 'ceo_knowledge' then
    update public.ceo_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  end if;
  return true;
end $fn$;

-- VERDICT, read-only. It does not call the view for kb_chunks itself: that is the 26 s scan being removed.
-- The hash equivalence was proved before commit by an aborted-transaction probe on 30 Sep (a real row,
-- the key read and the view read gave the same md5, and a stale hash returned false).
select case when (select prosrc from pg_proc
                   where oid = 'public.fn_ml_embed_write(text,text,text,vector,vector)'::regprocedure)
                 like '%from public.kb_chunks k where k.id = p_row_id::bigint%'
            then 'PROBE OK'
            else 'PROBE FAILED: fn_ml_embed_write still reads kb_chunks through the view' end as verdict;
