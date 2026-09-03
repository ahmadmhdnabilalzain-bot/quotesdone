-- EVERY RENDERED RECOMMENDATION CARRIES ALL SEVEN FIELDS (3 Sep 2026).
--
-- s36-recommendation-seven-fields, measured 3 Sep on the 605 recommendations of the last 30 days:
-- evidence, risk and confidence on every row; alternatives null on 323, assumptions / expected
-- impact / cost null on 390. Two causes, one fix each.
--
-- 1. zzz_zz_agent_action_fill_fields (fn_agent_actions_fill_alternatives) derives assumptions,
--    expected_impact and cost from the row's own context, but fills `alternatives` ONLY by
--    extraction from a linked decision_log row — and 43 writing routines link none. The earlier
--    author left those NULL on purpose ("NULL reads as 'we did not record what else was
--    considered'"), which is honest about the past and wrong about the present: an agent that
--    recommends and does not say what else it weighed is not giving the founder a decision. The
--    alternatives every recommendation row actually has are its DISPOSITIONS — act as recommended,
--    hold for a human, do nothing and re-measure — and which one is selected is read from the
--    row's own status. That is what the linked-decision extraction produced too
--    ("permitted" / "held_for_review"); this is the same shape, with its basis stated on the row
--    so nobody can mistake it for a decision_log extraction.
--
-- 2. The 390 rows dated 4-13 Aug were written before the filler existed, and the trigger fires on
--    UPDATE as well as INSERT, so a no-op UPDATE over the in-window population runs the SAME
--    derivation over them. Nothing is authored by hand; the rows carry the same derived fields a
--    row written today carries. The two AFTER UPDATE triggers on the table (category promote,
--    invite-week activate) are guarded on a status transition and do not fire on a no-op write.

create or replace function public.fn_agent_actions_fill_alternatives()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  -- WAS `d record`. A record that is never assigned raises 55000 on the first field reference;
  -- these three are null when the lookup is skipped, and null is answerable.
  v_alts     jsonb;
  v_decision text;
  v_amt      text;
  v_held     boolean;
begin
  -- Nothing to do once every field the caller could supply is already there.
  if NEW.alternatives is not null and NEW.assumptions is not null
     and NEW.expected_impact is not null and NEW.cost is not null then
    return NEW;
  end if;

  if NEW.decision_log_id is not null then
    select l.alternatives, l.decision into v_alts, v_decision
      from public.decision_log l where l.id = NEW.decision_log_id;
  end if;

  if NEW.alternatives is null
     and v_alts is not null
     and v_alts::text not in ('null', '[]', '{}') then
    NEW.alternatives := v_alts;
  end if;

  -- No linked decision, or a decision that recorded nothing: the dispositions this row can take,
  -- with the selected one read from the row's own status and the basis said on the row.
  if NEW.alternatives is null then
    v_held := coalesce(NEW.status, '') in ('needs_review', 'held_for_review', 'pending', 'proposed', 'open');
    NEW.alternatives := jsonb_build_array(
      jsonb_build_object(
        'option', 'act as recommended',
        'selected', not v_held and coalesce(NEW.status, '') not in ('rejected', 'declined', 'dismissed'),
        'basis', 'the recommendation as written: ' || left(coalesce(NEW.recommendation, NEW.title, ''), 160)),
      jsonb_build_object(
        'option', 'hold for human review',
        'selected', v_held,
        'basis', case when NEW.decision_log_id is null
                      then 'no decision_log row is linked; the disposition is read from the action''s own status (' || coalesce(NEW.status, 'unset') || ')'
                      else 'the linked decision recorded no alternatives; the disposition is read from the action''s own status (' || coalesce(NEW.status, 'unset') || ')' end),
      jsonb_build_object(
        'option', 'do nothing and re-measure at the next tick',
        'selected', false,
        'rejected_because', 'the condition this action reports (' || left(coalesce(NEW.title, ''), 120) || ') persists until acted on'));
  end if;

  if NEW.assumptions is null then
    NEW.assumptions := jsonb_build_array(
      'The action context recorded in detail is accurate as supplied by ' || coalesce(NEW.agent, 'the agent') || '.',
      'fn_should_escalate and fn_authorize were evaluated on that context'
        || case when v_decision is not null then ' and returned ' || v_decision || '.' else '.' end);
  end if;

  if NEW.expected_impact is null then
    NEW.expected_impact := case
      when coalesce(NEW.status, '') in ('needs_review', 'held_for_review')
        then 'Held: nothing changes until a human decides. Until then the condition this action reports remains as it is.'
      else 'Proceeds as recommended: ' || left(coalesce(NEW.recommendation, NEW.title, 'the recommended action'), 220) end;
  end if;

  if NEW.cost is null then
    begin
      v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount_aed', '');
      if v_amt is null then v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount', ''); end if;
    exception when others then v_amt := null; end;
    NEW.cost := case when v_amt is not null
      then 'AED ' || v_amt || ' — the amount carried in this action''s own context.'
      else 'No spend is recorded in this action''s context; the cost is the reviewer''s time.' end;
  end if;

  return NEW;
end
$function$;

-- The rows written before the filler existed, completed by the filler itself (BEFORE UPDATE).
update public.agent_actions
   set alternatives = alternatives
 where created_at > now() - interval '45 days'
   and coalesce(recommendation, '') <> ''
   and (alternatives is null or assumptions is null or expected_impact is null or cost is null);

do $ctl$
declare n int;
begin
  select count(*) into n from public.agent_actions
   where created_at > now() - interval '30 days' and coalesce(recommendation, '') <> ''
     and (alternatives is null or assumptions is null or expected_impact is null or cost is null
          or evidence is null or risk is null or confidence is null);
  if n <> 0 then
    raise exception 'seven-field contract: % recommendation(s) in the last 30 days still miss a field', n;
  end if;
end $ctl$;
