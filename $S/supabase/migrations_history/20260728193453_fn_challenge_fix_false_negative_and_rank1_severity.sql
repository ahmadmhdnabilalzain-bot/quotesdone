-- Test caught a bad miss: "Cut the security budget by half" returned SUPPORT, because the
-- pattern required budget-then-security and the sentence says security-then-budget. A control
-- cut is exactly what must be challenged, so order-independence matters. Also: a rank-1
-- compliance conflict should reach recommend_against on its own, not need to accumulate.

update challenge_heuristic
   set pattern = '(cut|reduce|lower|halve|slash).*(security|compliance|backup|audit|test|control)|(security|compliance|backup|audit|test|control).*(budget|spend|cost).*(cut|reduce|lower|halve|slash)|(cut|reduce|lower|halve|slash).*(budget|spend|cost)'
 where principle = 'Protect legal and regulatory compliance'
   and concern like 'Cutting spend on controls%';

insert into challenge_heuristic (pattern, rank_touched, principle, concern, alternative) values
 ('(expand|enter|launch).*(saudi|ksa|qatar|oman|kuwait|bahrain|new market|abu dhabi)', 4,'Support sustainable revenue growth',
  'Expanding to a new market before the home market has onboarded supply spreads a thin pool thinner, and the category knowledge is UAE-specific.',
  'Reach the 10-supplier target in the UAE first; or pilot one category in the new market with dedicated sourcing.'),
 ('(remove|drop|stop).*(anonymity|blind|masking|scrub)', 2,'Protect customer trust and data security',
  'Anonymity before reveal is the product promise buyers pay the reveal fee for. Removing it removes the reason the fee exists.',
  'Keep the gate and widen what is shown pre-reveal in banded form, which preserves the promise while adding signal.')
on conflict do nothing;

create or replace function public.fn_challenge(
  p_proposal text, p_proposed_by text default 'founder', p_challenger text default 'brief'
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_challenge(text,text,text) from public, anon, authenticated;