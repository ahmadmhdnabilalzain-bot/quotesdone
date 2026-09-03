-- fn_supersede_lesson: refuse a missing or self-referential lesson, keep the old lesson's own
-- lineage, and report ok truthfully.
--
-- The previous body (1) returned `found` from its LAST statement (the update of the NEW row), so
-- superseding a lesson that does not exist reported ok=true and superseding by a lesson that does
-- not exist reported ok=false even though the old row had just been marked; (2) set the OLD row's
-- supersedes_id to null, erasing its pointer to ITS predecessor — a lineage of three lessons lost its
-- middle link every time the chain grew; (3) accepted p_old = p_new. Now both rows must exist, they
-- must differ, the old row's own supersedes_id is preserved, and ok reflects what happened.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_supersede_lesson_keeps_the_chain.sql --apply --ddl

create or replace function public.fn_supersede_lesson(p_old bigint, p_new bigint, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_old_exists boolean; v_new_exists boolean;
begin
  if p_old is null or p_new is null then
    return jsonb_build_object('ok', false, 'error', 'both lesson ids are required', 'old', p_old, 'new', p_new);
  end if;
  if p_old = p_new then
    return jsonb_build_object('ok', false, 'error', 'a lesson cannot supersede itself', 'old', p_old, 'new', p_new);
  end if;
  select exists(select 1 from agent_knowledge where id = p_old), exists(select 1 from agent_knowledge where id = p_new)
    into v_old_exists, v_new_exists;
  if not v_old_exists or not v_new_exists then
    return jsonb_build_object('ok', false, 'error', 'lesson not found', 'old', p_old, 'old_exists', v_old_exists,
                              'new', p_new, 'new_exists', v_new_exists);
  end if;

  -- Mark the old lesson superseded. Its own supersedes_id (what IT replaced) is left as it was.
  update agent_knowledge
     set validation_status = 'superseded',
         supporting_evidence = coalesce(supporting_evidence,'') || E'\n[superseded by ' || p_new || '] ' || coalesce(p_reason,''),
         updated_at = now()
   where id = p_old;
  update agent_knowledge set supersedes_id = p_old, updated_at = now() where id = p_new;

  return jsonb_build_object('ok', true, 'old', p_old, 'new', p_new);
end $function$;
