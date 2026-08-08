-- STEP 2 (Gather Data) for the third decision_log writer, and the last 'Secretary' in the codebase.
--
-- trg_action_gate was repaired on 6 Aug (scripts/sql/action_gate_records_sources.sql) and fn_decide
-- has always built a sources array. fn_ai_gate is the writer that repair did not reach: it stores
-- `p_sources` verbatim, and p_sources DEFAULTS TO '[]'. Measured on production: all 3 ai_gate rows
-- ever written carry sources='[]', i.e. every one of them states that the decision was taken having
-- consulted nothing.
--
-- That statement is false in exactly the way the action-gate one was. The function reads
-- decision_policy.confidence_min, calls fn_authorize and calls fn_should_escalate, and decides on
-- all three. It now records the two verdicts alongside whatever the caller cited, as objects rather
-- than as a label. This is NOT a constant: if a call raises, the whole function raises and no row is
-- written at all, so the array can only ever describe retrievals that actually returned.
--
-- The 'Secretary' in the directive is the same ghost the write path just lost: no org_agent, no
-- title and no dept_key on production matches it, so "escalate to Secretary" told an employee to
-- hand the work to nobody. fn_should_escalate already resolves the party, so the directive uses its
-- answer and says plainly when there is none.
--
-- LATENT, NOT LIVE: the last ai_gate row is from 2026-07-06, so this changes no verdict today. It
-- is here because comp-10-02's population is EVERY decision_log row, and the next call from an edge
-- function would have re-opened the gap the other two writers just closed.
CREATE OR REPLACE FUNCTION public.fn_ai_gate(p_answer text, p_sources jsonb DEFAULT '[]'::jsonb, p_confidence numeric DEFAULT NULL::numeric, p_action text DEFAULT 'run_agent_action'::text, p_actor text DEFAULT 'agent'::text, p_attrs jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare g jsonb; a jsonb; esc jsonb; conf_min numeric; viol text[]:='{}'; approved boolean; route text;
        v_sources jsonb;
begin
  g := public.fn_require_grounding(p_answer, p_sources);
  if not (g->>'grounded')::boolean then viol := array_append(viol,'ungrounded: retrieve knowledge and cite a source'); end if;
  select value::numeric into conf_min from decision_policy where key='confidence_min';
  if p_confidence is not null and p_confidence < coalesce(conf_min,0.6) then
     viol := array_append(viol,'low_confidence: below '||coalesce(conf_min,0.6)||' — ask a clarifying question or escalate'); end if;
  a := public.fn_authorize(p_actor, p_action, p_attrs);
  if not (a->>'allowed')::boolean then viol := array_append(viol,'unauthorized: '||(a->>'reason')); end if;
  esc := public.fn_should_escalate(p_attrs || jsonb_build_object('confidence',p_confidence));
  route := esc->>'route_to';
  approved := (array_length(viol,1) is null) and not (esc->>'escalate')::boolean;
  -- WHAT THIS DECISION WAS TAKEN ON: the caller's citations plus the two verdicts the gate obtained
  -- for itself. Reaching this line means both calls returned, so both elements are real retrievals.
  v_sources := (case when jsonb_typeof(p_sources)='array' then p_sources else '[]'::jsonb end)
    || jsonb_build_array(
         jsonb_build_object('kind','policy_check','ref','fn_should_escalate','result',esc),
         jsonb_build_object('kind','authority_check','ref','fn_authorize','result',a));
  -- log the governance decision (immutable)
  insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,'ai_gate', jsonb_build_object('action',p_action,'attrs',p_attrs),
          case when approved then 'approved' else 'blocked' end, p_confidence,
          to_jsonb(viol || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]')))), v_sources, route);
  return jsonb_build_object('approved',approved,'violations',to_jsonb(viol),
    'grounding',g,'authorization',a,'escalation',esc,'route_to',route,'sources',v_sources,
    'directive', case when approved then 'emit'
                      when (esc->>'escalate')::boolean and route is not null then 'escalate to '||route
                      when (esc->>'escalate')::boolean then 'escalate: no party is configured to take this — '
                           ||coalesce(esc->>'route_note','decision_policy.review_owner resolves to nobody')
                      else 'revise before emitting' end);
end $function$;
