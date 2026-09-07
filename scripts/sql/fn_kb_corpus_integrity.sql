-- fn_kb_corpus_integrity — the standing guard against the defect that hid this whole corpus.
--
-- WHAT WENT WRONG, AND WHY THIS EXISTS. On 2026-08-10 all six packs measured 100% INGESTED while
-- 115,148 knowledge records sat in kb_stage.records read by one function, and every customer path
-- — kb_search, agent_brain, inquiry_intake — read kb_chunks, which held ZERO of them. Nothing in
-- the company could tell the difference between "imported" and "delivered", so nothing raised it.
-- This function is that difference, written down and run on a schedule.
--
-- It also gives kb_stage.file_hashes and kb_stage.categories their first runtime reader.
-- file_hashes is not "ingestion bookkeeping" once something checks it: sum(rows_seen) is the
-- corpus size the importer believes it wrote, and a corpus that shrinks under it is silent
-- data loss.
--
-- Four assertions, each one a number against another number, never against a constant:
--   1. staged        = sum(file_hashes.rows_seen)   the importer's own checkpoint
--   2. deployed     >= staged                       every staged record reached kb_chunks
--   3. every category in the index has records
--   4. every package in the index has file checkpoints
create or replace function public.fn_kb_corpus_integrity()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_staged bigint; v_ckpt bigint; v_deployed bigint; v_files bigint;
        v_cats bigint; v_cats_empty bigint; v_pkgs_unchecked bigint;
        v_fts bigint; v_problems text[] := '{}';
begin
  select count(*) into v_staged   from kb_stage.records;
  select coalesce(sum(rows_seen),0), count(*) into v_ckpt, v_files from kb_stage.file_hashes;
  select count(*) into v_deployed from public.kb_chunks where source_kind = 'qd_kb_pack';
  select count(*) into v_fts      from public.kb_chunks where source_kind = 'qd_kb_pack' and fts is not null;
  select count(*) into v_cats     from kb_stage.categories;
  select count(*) into v_cats_empty from kb_stage.categories c
   where not exists (select 1 from kb_stage.records r where r.category_slug = c.category_slug);
  select count(*) into v_pkgs_unchecked from kb_stage.categories c
   where not exists (select 1 from kb_stage.file_hashes f where f.package_id = c.package_id);

  if v_staged <> v_ckpt then
    v_problems := v_problems || format('kb_stage.records is %s but the importer checkpointed %s rows across %s files', v_staged, v_ckpt, v_files);
  end if;
  if v_deployed < v_staged then
    v_problems := v_problems || format('THE CORPUS IS STAGED BUT NOT DEPLOYED: kb_stage.records %s, kb_chunks(qd_kb_pack) %s. Every customer path reads kb_chunks.', v_staged, v_deployed);
  end if;
  if v_fts < v_deployed then
    v_problems := v_problems || format('%s deployed chunks have no full-text vector, and full text is the fallback retrieval path', v_deployed - v_fts);
  end if;
  if v_cats_empty > 0 then
    v_problems := v_problems || format('%s of %s categories in the index have no records', v_cats_empty, v_cats);
  end if;
  if v_pkgs_unchecked > 0 then
    v_problems := v_problems || format('%s packages in the index have no file checkpoint', v_pkgs_unchecked);
  end if;

  if array_length(v_problems,1) is not null then
    insert into public.agent_actions(agent, kind, title, recommendation, detail, risk, status)
    values ('knowledge_eng', 'incident',
            'Knowledge corpus integrity check failed',
            'The staged corpus and the corpus customers can actually retrieve have diverged. Re-run scripts/sql/deploy_corpus_into_kb_chunks.sql after establishing which side moved.',
            jsonb_build_object('problems', to_jsonb(v_problems), 'source', 'fn_kb_corpus_integrity'),
            'high', 'pending');
  end if;

  return jsonb_build_object(
    'ok', array_length(v_problems,1) is null,
    'staged', v_staged, 'checkpointed', v_ckpt, 'files', v_files,
    'deployed_to_kb_chunks', v_deployed, 'deployed_with_fts', v_fts,
    'categories', v_cats, 'categories_without_records', v_cats_empty,
    'packages_without_checkpoint', v_pkgs_unchecked,
    'problems', to_jsonb(v_problems), 'ran_at', now());
end $function$;

revoke execute on function public.fn_kb_corpus_integrity() from public;
revoke execute on function public.fn_kb_corpus_integrity() from anon;
revoke execute on function public.fn_kb_corpus_integrity() from authenticated;

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
