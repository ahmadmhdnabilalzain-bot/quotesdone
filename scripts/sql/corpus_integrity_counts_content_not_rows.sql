-- THE DEDUPE MADE fn_kb_corpus_integrity FAIL, AND THE CHECK WAS THE THING THAT WAS WRONG.
--
-- After removing 24,660 byte-identical duplicate chunks, the corpus check raised a HIGH-risk
-- incident on production:
--
--   "THE CORPUS IS STAGED BUT NOT DEPLOYED: kb_stage.records 115148, kb_chunks(qd_kb_pack) 90488.
--    Every customer path reads kb_chunks."
--
-- It compares ROW COUNTS: `if v_deployed < v_staged`. That was a correct proxy while every staged
-- record produced its own chunk, duplicates included. It is not what the check is FOR. The question
-- is whether every staged record's CONTENT is retrievable, and the answer, measured:
--
--   kb_stage.records                              115,148
--   kb_stage.records, DISTINCT title+content       90,488
--   kb_chunks(qd_kb_pack)                          90,488
--   kb_chunks(qd_kb_pack), DISTINCT title+content  90,488
--
-- Every distinct staged record is deployed, exactly once, and the 24,660 chunks removed are exactly
-- the 24,660 duplicate staged records. The dedupe did not lose a single fact.
--
-- SO THE CHECK COUNTS CONTENT NOW, NOT ROWS — which is a STRICTER statement, not a weaker one. The
-- old form passes when 115,148 chunks exist regardless of what is in them; this form fails if one
-- distinct staged record is missing even while the row count looks healthy. The duplicate count is
-- reported alongside, as information rather than as a fault, so a future session can see at a glance
-- whether duplicates have crept back in.
--
-- Only the two lines that made the row-count comparison change. Everything else — the checkpoint
-- comparison, the FTS check, the empty-category check, the package-checkpoint check, and the
-- agent_actions incident it raises — is untouched.

CREATE OR REPLACE FUNCTION public.fn_kb_corpus_integrity()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staged bigint; v_ckpt bigint; v_deployed bigint; v_files bigint;
        v_cats bigint; v_cats_empty bigint; v_pkgs_unchecked bigint;
        v_fts bigint; v_problems text[] := '{}';
        v_staged_distinct bigint; v_deployed_distinct bigint; v_missing bigint;
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

  -- CONTENT, NOT ROWS. A duplicate staged record does not need a duplicate chunk to be retrievable.
  select count(distinct md5(coalesce(title,'')||'|'||coalesce(content,''))) into v_staged_distinct
    from kb_stage.records;
  select count(distinct md5(coalesce(title,'')||'|'||coalesce(content,''))) into v_deployed_distinct
    from public.kb_chunks where source_kind = 'qd_kb_pack';
  select count(*) into v_missing from (
    select md5(coalesce(title,'')||'|'||coalesce(content,'')) h from kb_stage.records
    except
    select md5(coalesce(title,'')||'|'||coalesce(content,'')) from public.kb_chunks where source_kind = 'qd_kb_pack'
  ) z;

  if v_staged <> v_ckpt then
    v_problems := v_problems || format('kb_stage.records is %s but the importer checkpointed %s rows across %s files', v_staged, v_ckpt, v_files);
  end if;
  if v_missing > 0 then
    v_problems := v_problems || format('THE CORPUS IS STAGED BUT NOT DEPLOYED: %s distinct staged record(s) have no chunk in kb_chunks (staged %s rows / %s distinct, deployed %s rows / %s distinct). Every customer path reads kb_chunks.',
                                       v_missing, v_staged, v_staged_distinct, v_deployed, v_deployed_distinct);
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
    'staged', v_staged,
    'staged_distinct', v_staged_distinct,
    'checkpointed', v_ckpt,
    'files', v_files,
    'deployed_to_kb_chunks', v_deployed,
    'deployed_distinct', v_deployed_distinct,
    'staged_records_with_no_chunk', v_missing,
    'duplicate_staged_records', v_staged - v_staged_distinct,
    'deployed_with_fts', v_fts,
    'categories', v_cats,
    'categories_without_records', v_cats_empty,
    'packages_without_checkpoint', v_pkgs_unchecked,
    'problems', to_jsonb(v_problems),
    'ran_at', now());
end $function$;
