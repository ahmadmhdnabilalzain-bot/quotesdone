-- A REASONED ANSWER IS APPLIED BY ITS OWN SURFACE — the replay's effect, one routine per decision point.
-- Seat: it_engineer (shared platform). 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word
-- matching anywhere).
--
-- WHY. fn_reason_held_resolve (scripts/sql/every_seat_reasons_before_it_answers.sql) applied the effect of
-- a replayed question with one if/elsif per surface. 64 more decision points are migrated off word lists
-- (supabase/functions/_shared/decision_points.json), in batches of ~8 per PR; each batch editing that one
-- routine would make every later apply silently drop the branches the batch before it added (the highest
-- MANIFEST key wins — lessons: "applying an old file resurrects a superseded routine").
--
-- WHAT. The two built-in surfaces keep their branches. Any other surface whose effect lives in SQL defines
-- its own routine  public.fn_reason_apply_<surface with '.' -> '__'>(p_id bigint, p_result jsonb) returns jsonb
-- in its own batch file, and this resolver calls it when it exists. A surface with no such routine is
-- 'reasoned' and left to the channel delivery (_shared/reasoned_delivery.ts), exactly as before.
-- The routine name is built from the surface, which the table's CHECK already limits to ^[a-z_]+(\.[a-z_]+)*$,
-- and it is quoted with %I, so no surface string can name anything but a routine of that exact shape.
--
-- Follows every_seat_reasons_before_it_answers.sql and meaning_is_decided_by_reasoning_not_by_word_lists.sql.
-- Pending: scripts/sql/pending/a_reasoned_answer_is_applied_by_its_own_surface.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs.

create or replace function public.fn_reason_held_resolve(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_effect jsonb := null; v_fn text;
begin
  select * into r from public.reasoning_held_question where id = p_id for update;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if coalesce(p_result->>'status', '') <> 'answered' then
    update public.reasoning_held_question
       set result = p_result, status = case when attempts >= 5 then 'failed' else 'held' end
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'still_held');
  end if;
  update public.reasoning_held_question set result = p_result, status = 'reasoned', reasoned_at = now() where id = p_id;
  if r.surface = 'ceo.command_intent' and (r.subject->>'command_id') is not null then
    v_effect := public.fn_ceo_command_interpret((r.subject->>'command_id')::bigint, p_result->'decision'->>'choice',
                  left(coalesce(p_result->>'answer', ''), 1000));
  elsif r.surface = 'inquiry_intake.trade' and (r.subject->>'intake_id') is not null then
    update public.inquiry_intake i
       set category = p_result->'decision'->>'choice', status = 'needs_info', updated_at = now(),
           brief = coalesce(i.brief, '{}'::jsonb) || jsonb_build_object('category_by', 'reasoning', 'held_id', p_id)
     where i.id::text = r.subject->>'intake_id' and i.status = 'held'
       and exists (select 1 from public.category_specs cs where cs.category = p_result->'decision'->>'choice');
    v_effect := jsonb_build_object('intake_id', r.subject->>'intake_id', 'category', p_result->'decision'->>'choice', 'reopened', found);
  else
    v_fn := 'fn_reason_apply_' || replace(r.surface, '.', '__');
    if length(v_fn) <= 63 and to_regprocedure(format('public.%I(bigint,jsonb)', v_fn)) is not null then
      execute format('select public.%I($1, $2)', v_fn) into v_effect using p_id, p_result;
      v_effect := coalesce(v_effect, jsonb_build_object('applied_by', v_fn));
    end if;
  end if;
  if v_effect is not null then
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  end if;
  return jsonb_build_object('id', p_id, 'status', case when v_effect is null then 'reasoned' else 'applied' end, 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_reason_held_resolve(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_held_resolve(bigint, jsonb) to service_role;
