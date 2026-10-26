-- DETERMINISTIC DECISION ENGINE — core applier (build 1 of the ~200-function reasoning layer).
--
-- Founder doctrine: internal company operation is ~95% deterministic CODE + linked knowledge, ~5% model
-- (only marketing reading live Meta data, and content generation). Today every workflow step's ENTRY
-- is a paid-model call (held by the founder), so the loop is dead. This flips it: a step is worked by
-- APPLYING the nearest company playbook/rule/authority to it — by MEANING, over the embedded
-- ops_knowledge substrate (197 decision playbooks + 240 rules + 240 exception playbooks + authority/
-- policy/kpi, all embedded and runtime-eligible) — with NO model. The caller (the step executor) embeds
-- the step text once for free (in-region gte-small) and passes the vector; Postgres does the rest.
--
-- Output shape mirrors what the kernel already accepts from the model path: a determination, an OUTCOME
-- sentence, and a confidence (here = the cosine similarity of the applied playbook — honest, not invented).
-- When nothing in the agent's scope matches above the floor, it returns matched=false with the reason and
-- the candidates, so the executor can escalate up the org hierarchy rather than fabricate a determination.
--
--   node scripts/apply_sql.mjs scripts/sql/deterministic_decision_engine.sql --apply --ddl

begin;

create or replace function public.fn_apply_playbook(
  p_agent_key       text,
  p_query_embedding vector(384),
  p_min_similarity  real default 0.35,
  p_k               integer default 5
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_row        record;
  v_top        record := null;
  v_candidates jsonb := '[]'::jsonb;
  v_outcome    text;
begin
  if p_query_embedding is null then
    return jsonb_build_object('matched', false, 'reason', 'no query embedding supplied');
  end if;

  -- Nearest in-scope company knowledge, by meaning (fn_ops_knowledge_match already scopes to exactly
  -- what this agent may see: company + department-through-merge + its packaged roles).
  for v_row in
    select * from public.fn_ops_knowledge_match(p_query_embedding, p_agent_key, greatest(coalesce(p_k,5), 1))
  loop
    if v_top is null then v_top := v_row; end if;
    v_candidates := v_candidates || jsonb_build_object(
      'record_id', v_row.record_id, 'title', v_row.title, 'layer', v_row.layer,
      'record_type', v_row.record_type, 'similarity', round(v_row.similarity::numeric, 4));
  end loop;

  -- No confident match: do NOT invent a determination. Report the gap so the executor escalates.
  if v_top is null or v_top.similarity < p_min_similarity then
    return jsonb_build_object(
      'matched', false,
      'reason', case when v_top is null then 'no in-scope knowledge for this agent'
                     else 'best match ' || round(v_top.similarity::numeric, 3)
                          || ' is below the apply floor ' || p_min_similarity end,
      'candidates', v_candidates);
  end if;

  -- APPLY the top playbook/rule as this step's determination — deterministic, no model.
  v_outcome := 'Applied the company '
             || coalesce(nullif(v_top.record_type, ''), 'playbook')
             || ' "' || v_top.title || '" to this step (match '
             || round(v_top.similarity::numeric, 3) || ').';

  return jsonb_build_object(
    'matched',       true,
    'record_id',     v_top.record_id,
    'title',         v_top.title,
    'layer',         v_top.layer,
    'record_type',   v_top.record_type,
    'authority_tier',v_top.authority_tier,
    'similarity',    round(v_top.similarity::numeric, 4),
    'confidence',    round(v_top.similarity::numeric, 3),
    'determination', v_top.content,
    'outcome',       v_outcome,
    'candidates',    v_candidates,
    'basis',         'deterministic: nearest company knowledge by meaning, no model call'
  );
end
$function$;

-- SECURITY DEFINER + fresh CREATE grants EXECUTE to PUBLIC; revoke (runtime calls it as service_role).
revoke execute on function public.fn_apply_playbook(text, vector, real, integer) from public;

commit;
