-- A NEAREST NEIGHBOUR IS ALWAYS FOUND — THAT IS NOT A MATCH (4 Sep 2026).
--
-- The first steps the deterministic branch closed on production looked like this:
--   "Evidence: KPI scoreboard, OS health, goal periods"  -> applied metric_definition "Rework rate"  (0.887)
--   "Generate options with cost and risk for each"       -> applied scenario "07 — Repeated failure" (0.879)
--   "Decide and record rationale"                        -> applied failure_mode_case fm04            (0.897)
-- and their candidate lists were FLAT: 0.887, 0.886, 0.880, 0.879, 0.878. MEASURED on the embedded
-- substrate itself (3,600 random in-scope pairs of runtime-eligible ops_knowledge rows, gte-small
-- cosine): p05 0.788, p50 0.837, p90 0.872, p99 0.939. A "match 0.887" is a coin-toss above the random
-- median. The apply floor of 0.42 accepted everything; cosine alone cannot separate a determination
-- from noise at this model's resolution (the genuine reveal-fee matches proven on 2 Sep scored
-- 0.886–0.904 — the same band).
--
-- §4.2 asks for a STRONG, SELF-CONTAINED match for a ROUTINE KIND. Encoded here, all deterministic:
--   1. only ACTIONABLE kinds can be applied as a determination — decision_playbook, decision_rule,
--      standard_operating_procedure, exception_playbook (the four the plan names) — never a metric
--      definition, a failure-mode case or a scenario narrative;
--   2. the cosine floor is 0.85 (the noise band's upper half) AND
--   3. the candidate must be CORROBORATED BY KEYWORD: at least 2 of the step's own lexemes, and at
--      least 30% of them, appear in the record's tsv. The lexeme overlap is the signal the packet asks
--      for as the tsv fallback, used here as the second key rather than as a fallback.
-- Among corroborated candidates the highest cosine wins; the determination renders the record's content
-- and, when present, its structured_data. Everything else returns matched=false with the numbers.
--
-- Every step closed before this calibration is RE-OPENED below (its run steps back to where it was)
-- and its review row rejected with this reason; the sealed traces keep their evidence and are graded.
--
--   node scripts/apply_sql.mjs scripts/sql/apply_playbook_needs_corroboration.sql --apply --ddl

begin;

drop function if exists public.fn_apply_playbook(text, vector, real, integer);

create or replace function public.fn_apply_playbook(
  p_agent_key       text,
  p_query_embedding vector(384),
  p_query_text      text,
  p_min_similarity  real default 0.85,
  p_k               integer default 20
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lexemes    text[];
  v_total      int;
  v_row        record;
  -- scalars, not a record compared to null: an unassigned plpgsql record RAISES on `is null`
  v_found      boolean := false;
  v_b_id text; v_b_title text; v_b_content text; v_b_layer text; v_b_type text; v_b_tier text;
  v_b_sim real := -1; v_b_terms int := 0; v_b_sd jsonb;
  v_n_seen     boolean := false;
  v_n_type text; v_n_title text; v_n_sim real; v_n_terms int;
  v_candidates jsonb := '[]'::jsonb;
  v_terms      int;
  v_pass       boolean;
  v_reason     text;
  v_det        text;
  v_key        text;
  v_dept       text;
  v_scope      text[];
  v_role_ids   text[];
begin
  if p_query_embedding is null then
    return jsonb_build_object('matched', false, 'reason', 'no query embedding supplied');
  end if;

  -- The step's own vocabulary, normalised the same way ops_knowledge.tsv is (english stemming).
  select array_agg(distinct lexeme) into v_lexemes
    from unnest(to_tsvector('english', coalesce(p_query_text, '')))
   where length(lexeme) >= 3;
  v_total := coalesce(array_length(v_lexemes, 1), 0);

  -- HYBRID, ACTIONABLE-ONLY RETRIEVAL. fn_ops_knowledge_match's top-20 by cosine is dominated by metric
  -- definitions, failure cases and scenarios (measured: the actionable SOP that DOES corroborate
  -- "Detect from health, drift or a failed gate" — SOP 04 Security Alert Triage — never reached the
  -- top 20). So the candidate set is: in-scope rows of the four actionable kinds, ranked by cosine.
  -- The scope predicate MIRRORS fn_ops_knowledge_match exactly (agent -> department -> fn_dept_scope,
  -- packaged roles via org_role_identity, company/external); change both or neither.
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select a.department into v_dept from public.org_agents a where a.agent_key = v_key;
  if v_dept is null then
    return jsonb_build_object('matched', false, 'reason', 'agent ' || coalesce(p_agent_key,'?') || ' resolves to no department; no scope');
  end if;
  v_scope := public.fn_dept_scope(v_dept);
  select array_agg(packaged_role_id) into v_role_ids from public.org_role_identity where agent_key = v_key;

  for v_row in
    select k.record_id, k.title, k.content, k.layer, k.record_type, k.authority_tier,
           (1 - (k.embedding_gte <=> p_query_embedding))::real as similarity,
           k.structured_data,
           (select count(*) from unnest(tsvector_to_array(k.tsv)) t where t = any(coalesce(v_lexemes, '{}'))) as terms_matched
      from public.ops_knowledge k
     where k.embedding_gte is not null
       and k.runtime_eligible
       and k.supersession_state = 'current'
       and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
       and (
             k.scope_type in ('company','external_source')
          or (k.scope_type = 'department' and k.dept_key = any(v_scope))
          or (k.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by k.embedding_gte <=> p_query_embedding
     limit greatest(coalesce(p_k, 20), 1)
  loop
    v_terms := coalesce(v_row.terms_matched, 0);
    if not v_n_seen then
      v_n_seen := true; v_n_type := v_row.record_type; v_n_title := v_row.title;
      v_n_sim := v_row.similarity; v_n_terms := v_terms;
    end if;
    v_pass := v_row.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')
              and v_row.similarity >= p_min_similarity
              and v_terms >= 2
              and v_total > 0 and v_terms::numeric / v_total >= 0.30
              and length(coalesce(v_row.content, '')) >= 300;
    v_candidates := v_candidates || jsonb_build_object(
      'record_id', v_row.record_id, 'title', v_row.title, 'layer', v_row.layer,
      'record_type', v_row.record_type, 'similarity', round(v_row.similarity::numeric, 4),
      'terms_matched', v_terms, 'terms_total', v_total, 'corroborated', v_pass);
    if v_pass and (not v_found or v_row.similarity > v_b_sim) then
      v_found := true; v_b_id := v_row.record_id; v_b_title := v_row.title; v_b_content := v_row.content;
      v_b_layer := v_row.layer; v_b_type := v_row.record_type; v_b_tier := v_row.authority_tier;
      v_b_sim := v_row.similarity; v_b_terms := v_terms; v_b_sd := v_row.structured_data;
    end if;
  end loop;

  if not v_found then
    v_reason := case when not v_n_seen then 'no in-scope knowledge for this agent'
                     else 'no corroborated actionable match: nearest is ' || coalesce(v_n_type,'?')
                          || ' "' || coalesce(v_n_title,'') || '" at ' || round(v_n_sim::numeric, 3)
                          || ' (floor ' || p_min_similarity || ', noise median 0.837) sharing '
                          || coalesce(v_n_terms, 0) || ' of ' || v_total || ' step terms'
                end;
    return jsonb_build_object('matched', false, 'reason', v_reason, 'candidates', v_candidates,
                              'terms_total', v_total);
  end if;

  v_det := coalesce(v_b_content, '');
  if v_b_sd is not null and v_b_sd <> '{}'::jsonb then
    v_det := v_det || E'\n\nSTRUCTURED DETERMINATION (from the record''s structured_data):\n'
             || jsonb_pretty(v_b_sd);
  end if;

  return jsonb_build_object(
    'matched',        true,
    'record_id',      v_b_id,
    'title',          v_b_title,
    'layer',          v_b_layer,
    'record_type',    v_b_type,
    'authority_tier', v_b_tier,
    'similarity',     round(v_b_sim::numeric, 4),
    'terms_matched',  v_b_terms,
    'terms_total',    v_total,
    'confidence',     round(v_b_sim::numeric, 3),
    'determination',  v_det,
    'outcome',        'Applied the company ' || v_b_type || ' "' || v_b_title
                      || '" to this step (cosine ' || round(v_b_sim::numeric, 3)
                      || ', corroborated by ' || v_b_terms || ' of ' || v_total || ' step terms).',
    'candidates',     v_candidates,
    'basis',          'deterministic: nearest ACTIONABLE company knowledge by meaning, corroborated by the step''s own terms; no model call'
  );
end
$function$;

revoke execute on function public.fn_apply_playbook(text, vector, text, real, integer) from public;

-- ---------------------------------------------------------------------------------------------------
-- Re-open every step closed deterministically BEFORE this calibration (its output carries no
-- terms_matched — the corroboration key this file introduces), step its run back, reject the review
-- rows and grade the sealed traces. Idempotent: a corroborated close is never touched, and a reverted
-- step no longer matches the predicate.
-- ---------------------------------------------------------------------------------------------------
do $$
declare v_run uuid; v_min int; v_n int := 0; v_traces uuid[];
begin
  select array_agg((s.output->>'decision_trace_id')::uuid) into v_traces
    from public.workflow_step_run s
   where s.status = 'done' and s.output->>'disposition' = 'deterministic_low_confidence'
     and not (s.output ? 'terms_matched')
     and s.finished_at < '2026-09-04 06:00:00+00';   -- the uncalibrated applier's closes (05:41-05:56 UTC)

  for v_run, v_min in
    select s.workflow_run_id, min(s.step_no)
      from public.workflow_step_run s
     where s.status = 'done' and s.output->>'disposition' = 'deterministic_low_confidence'
       and not (s.output ? 'terms_matched')
       and s.finished_at < '2026-09-04 06:00:00+00'
     group by s.workflow_run_id
  loop
    update public.workflow_step_run
       set status = case when step_no = v_min then 'ready' else 'queued' end,
           finished_at = null,
           output = jsonb_build_object('reverted_at', now(), 'reverted_by', 'apply_playbook_needs_corroboration.sql',
                      'reason', 'closed on a noise-level nearest neighbour (candidate list flat at 0.88-0.90 against a random-pair median of 0.837); re-opened for a corroborated determination',
                      'previous_output', output),
           error = null
     where workflow_run_id = v_run and step_no >= v_min and status in ('done','ready');
    get diagnostics v_n = row_count;
    update public.workflow_run
       set current_step = v_min, status = 'running', finished_at = null, updated_at = now()
     where id = v_run;
    raise notice 'reverted % step(s) of run % back to step %', v_n, v_run, v_min;
  end loop;

  if v_traces is not null then
    update public.review_queue
       set status = 'rejected', decided_at = now(), decided_by = 'apply_playbook_needs_corroboration.sql',
           founder_comment = 'rejected by calibration: the applied record was the nearest neighbour in a flat candidate list, not a corroborated actionable playbook; the step was re-opened'
     where kind = 'deterministic_step' and status = 'pending'
       and (payload->>'decision_trace_id')::uuid = any(v_traces);

    update public.decision_trace
       set outcome_status = 'rejected', evaluated_at = now(),
           outcome = jsonb_build_object('graded_by', 'apply_playbook_needs_corroboration.sql', 'at', now(),
                       'reason', 'nearest-neighbour noise (flat candidates ~0.88 vs random-pair median 0.837); step re-opened')
     where id = any(v_traces) and coalesce(outcome_status, '') <> 'rejected';
  end if;

  -- The one run already stepped back by the first apply of this file: its status was left 'done'.
  update public.workflow_run r
     set status = 'running', finished_at = null, updated_at = now()
   where r.status = 'done'
     and exists (select 1 from public.workflow_step_run s
                  where s.workflow_run_id = r.id and s.finished_at is null
                    and s.output->>'reverted_by' = 'apply_playbook_needs_corroboration.sql');
  update public.review_queue q
     set status = 'rejected', decided_at = now(), decided_by = 'apply_playbook_needs_corroboration.sql',
         founder_comment = 'rejected by calibration: the applied record was the nearest neighbour in a flat candidate list, not a corroborated actionable playbook; the step was re-opened'
   where q.kind = 'deterministic_step' and q.status = 'pending'
     and exists (select 1 from public.workflow_step_run s
                  where s.id = (q.payload->>'step_run_id')::bigint and s.finished_at is null
                    and s.output->>'reverted_by' = 'apply_playbook_needs_corroboration.sql');
  update public.decision_trace t
     set outcome_status = 'rejected', evaluated_at = now(),
         outcome = jsonb_build_object('graded_by', 'apply_playbook_needs_corroboration.sql', 'at', now(),
                     'reason', 'nearest-neighbour noise (flat candidates ~0.88 vs random-pair median 0.837); step re-opened')
   where t.decision_type = 'deterministic_playbook_application' and coalesce(t.outcome_status,'') <> 'rejected'
     and exists (select 1 from public.workflow_step_run s
                  where s.id = t.entity_id::bigint and s.finished_at is null
                    and s.output->>'reverted_by' = 'apply_playbook_needs_corroboration.sql');
end $$;

commit;
