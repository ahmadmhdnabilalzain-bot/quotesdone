-- fn_challenge can refuse a proposal and not say why.
-- 
-- ── HOW IT SURFACED ─────────────────────────────────────────────────────────────────────────────
-- The weekly executive meeting now puts its top three priorities to a second officer through
-- fn_challenge (scripts/gen_exec_meeting_agenda_debate_priorities.mjs). Verifying that on staging
-- produced a challenge with stance `recommend_against`, confidence 0.75 — and `reasoning` empty.
-- 
-- ── THE DEFECT ──────────────────────────────────────────────────────────────────────────────────
-- fn_challenge accumulates `v_weight` from two independent places and writes `v_reason` from only
-- one of them:
-- 
--   challenge_heuristic  → v_weight += rank, AND v_reason := h.concern
--   institutional_memory → v_weight += 3 for each prior outcome of 'worse', v_reason UNCHANGED
-- 
-- So a proposal that matches no heuristic but has two prior attempts on record that ended worse
-- reaches v_weight 6, crosses the `>= 3` threshold into recommend_against, and is written to
-- challenge_record with an empty reasoning. The `else` branch that supplies default prose only runs
-- for `support`, which is precisely the stance that does not need explaining.
-- 
-- Production has not hit it yet — 0 of 47 challenge_record rows have a blank reasoning, measured
-- 9 Aug 2026 — because every recorded challenge so far matched a heuristic. The meeting calling
-- fn_challenge three times a week is what makes it a matter of time.
-- 
-- ── THE FIX ─────────────────────────────────────────────────────────────────────────────────────
-- State the basis that actually drove the weight. The prior outcomes are already collected in
-- `v_evidence` by the time the stance is decided, so the reason is written from the evidence that
-- produced it rather than from a second query — and an unexplained refusal becomes an explained one.
-- 
-- Read from the live definition and patched at one asserted anchor, so the rest of the routine
-- stays byte-identical.

CREATE OR REPLACE FUNCTION public.fn_challenge(p_proposal text, p_proposed_by text DEFAULT 'founder'::text, p_challenger text DEFAULT 'brief'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h record; v_id bigint; v_stance text := 'support'; v_conf numeric := 0.5;
  v_reason text := ''; v_alts jsonb := '[]'::jsonb; v_evidence jsonb := '[]'::jsonb;
  v_rank int; v_principle text; v_weight int := 0;
  v_prior record; v_supply int; v_rev numeric;
begin
  for h in select * from challenge_heuristic where active and p_proposal ~* pattern order by rank_touched limit 3
  loop
    -- a rank-1 conflict is severe on its own; lower ranks accumulate
    v_weight := v_weight + case h.rank_touched when 1 then 3 when 2 then 2 else 1 end;
    if v_rank is null or h.rank_touched < v_rank then v_rank := h.rank_touched; v_principle := h.principle; end if;
    v_reason := v_reason || case when v_reason='' then '' else ' ' end || h.concern;
    if h.alternative is not null then v_alts := v_alts || jsonb_build_array(h.alternative); end if;
  end loop;

  for v_prior in
    select headline, detail, outcome from institutional_memory
     where outcome in ('worse','improved')
       and p_proposal ~* coalesce(substring(headline from '\w+'),'zzzz')
     order by created_at desc limit 3
  loop
    v_evidence := v_evidence || jsonb_build_array(jsonb_build_object(
      'type','prior_outcome','verdict',v_prior.outcome,'lesson',left(v_prior.detail,240)));
    if v_prior.outcome='worse' then v_weight := v_weight + 3; end if;
  end loop;

  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev
    from transactions where revealed_at > now()-interval '30 days';
  v_evidence := v_evidence || jsonb_build_array(jsonb_build_object(
    'type','current_state','onboarded_suppliers',v_supply,'revenue_30d_aed',v_rev,
    'note', case when v_supply=0
      then 'The marketplace has no onboarded supply, so any demand-side or pricing change cannot be validated against real behaviour yet.'
      else 'Supply exists; effects are measurable.' end));

  if v_supply=0 and p_proposal ~* '(fee|price|commission|campaign|customer|demand)' then
    v_weight := v_weight + 1;
    v_reason := v_reason || ' There is also no onboarded supply to measure the effect against, so the change would be unfalsifiable at the moment it is made.';
  end if;

  if v_weight >= 3 then v_stance := 'recommend_against'; v_conf := least(0.95, 0.60 + v_weight*0.05);
  elsif v_weight >= 1 then v_stance := 'concern'; v_conf := 0.65;
  else v_stance := 'support'; v_conf := 0.6;
       v_reason := 'No conflict with the priority hierarchy, no contrary prior outcome on record, and current state does not argue against it.';
  end if;

  -- A REFUSAL WITH NO REASON IS NOT A CHALLENGE. v_weight can cross the recommend_against
  -- threshold from institutional_memory alone, and only the heuristic loop above writes v_reason —
  -- so a proposal with two prior attempts that ended worse and no matching heuristic was recorded
  -- as recommend_against with an empty reasoning. Write the basis that actually drove the weight.
  if v_reason = '' and v_stance <> 'support' then
    v_reason := 'No principle in the priority hierarchy is touched by this, but '
      ||(select count(*) from jsonb_array_elements(v_evidence) e
          where e->>'type'='prior_outcome' and e->>'verdict'='worse')
      ||' prior attempt(s) on record ended worse: '
      ||coalesce((select string_agg(left(e->>'lesson',200), ' | ')
                    from jsonb_array_elements(v_evidence) e
                   where e->>'type'='prior_outcome' and e->>'verdict'='worse'),
                 'the outcome was recorded without a lesson')||'.';
  end if;

  if v_alts='[]'::jsonb and v_stance<>'support' then
    v_alts := jsonb_build_array('Run it as a bounded test with a named metric and a captured baseline, so it can be graded and reversed.');
  end if;

  insert into challenge_record (proposal,proposed_by,challenged_by,stance,confidence,reasoning,
                                violates_rank,violates_principle,evidence,alternatives)
  values (p_proposal,p_proposed_by,p_challenger,v_stance,v_conf,v_reason,v_rank,v_principle,v_evidence,v_alts)
  returning id into v_id;

  return jsonb_build_object('id',v_id,'stance',v_stance,'confidence',v_conf,
    'conflicts_with', case when v_principle is null then null else 'Rank '||v_rank||' — '||v_principle end,
    'reasoning',v_reason,'evidence',v_evidence,'alternatives',v_alts);
end $function$
;
