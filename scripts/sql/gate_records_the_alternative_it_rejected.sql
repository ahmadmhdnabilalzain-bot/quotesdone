-- OS 2.txt §15 "Explainability Everywhere" asks of any action: "What alternatives were considered?"
--
-- MEASURED, production 11 Aug 2026: `explain-alternatives-considered` is 0 of 61. All four action
-- surfaces deliver `confidence`; none delivers `alternatives`, and `decision_log` has no column to
-- put one in.
--
-- WHAT AN HONEST ALTERNATIVE IS HERE. trg_action_gate does not pick from a menu — it evaluates two
-- outcomes and takes one. fn_should_escalate says whether the action must be escalated, fn_authorize
-- says whether the actor may take it, and between them the gate lands on `permitted` or
-- `held_for_review`. The other verdict is a real option that was genuinely available and genuinely
-- rejected, and the reasons it lost are already computed and already stored in `reasons`/`sources`.
--
-- So this records the two options with the one that won marked selected, which is the exact shape
-- fn_decide already ships as v_options and the founder has already accepted as honest:
--   [{option, selected: true, ...}, {option, selected: false, rejected_because}]
--
-- It invents nothing. When the gate raised inside its own exception block, `reasons` says so and the
-- rejected_because says so with it.
--
-- WHAT THIS DOES NOT DO, AND WHY THE CHECK STAYS RED FOR NOW. The three agent_actions-based surfaces
-- reach this through agent_actions.decision_log_id, and that column only exists from 6 Aug:
--   operations (30 pending)           29 rows,  9 carry a decision_log_id
--   assistant  (pending+needs_review) 42 rows, 22 carry one
--   governance (escalated)            15 rows, 15 carry one
-- Two thirds of the surfaced approvals predate it and have NO recorded evaluation to cite. A value
-- synthesised for those would be an evaluation that never happened — the same objection that keeps
-- the reputation dimensions empty. They are left null and the check goes MET as the older rows leave
-- the queue, exactly as the confidence half is doing.
--
-- CREATE OR REPLACE preserves the ACL, so there is no grant to revoke.
alter table public.decision_log add column if not exists alternatives jsonb;

comment on column public.decision_log.alternatives is
  'The options this decision actually chose between, in fn_decide''s v_options shape: one object per option, the taken one marked selected=true and the rejected one carrying rejected_because. Null on rows written before 11 Aug 2026 — those decisions recorded no evaluation and one must not be invented for them.';

create or replace function public.trg_action_gate()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
        v_sources jsonb := '[]'::jsonb; v_dl_id bigint;
        v_taken text; v_other text; v_why text; v_alts jsonb;
begin
  -- build context defensively (detail may be jsonb or text)
  begin
    attrs := case when jsonb_typeof(to_jsonb(NEW.detail)) = 'object' then to_jsonb(NEW.detail) else '{}'::jsonb end;
  exception when others then attrs := '{}'::jsonb; end;
  begin amt := nullif(attrs->>'amount_aed','')::numeric; if amt is null then amt := nullif(attrs->>'amount','')::numeric; end if; exception when others then amt := null; end;
  -- 'actor' IS PART OF THE CONTEXT, NOT JUST OF THE LEDGER ROW. NEW.agent was written to
  -- decision_log.actor and withheld from fn_should_escalate, so the router had nobody to route
  -- FROM and every one of these rows carried the same company-wide addressee. With it the
  -- escalation travels up the escalating employee's own reporting line.
  attrs := attrs || jsonb_build_object('amount_aed', amt, 'text', lower(coalesce(NEW.title,'')||' '||coalesce(NEW.recommendation,'')),
                                       'category', coalesce(attrs->>'category',''), 'moves_money', (lower(coalesce(NEW.kind,'')) ~ '(refund|payout|charge|payment|transfer)'),
                                       'actor', coalesce(NEW.agent,'agent'));
  -- map action kind to an RBAC action
  action := case
    when lower(coalesce(NEW.kind,'')) ~ 'refund' then 'issue_refund'
    when lower(coalesce(NEW.kind,'')) ~ 'approve.*suppl|suppl.*approve|kyc' then 'approve_supplier'
    when lower(coalesce(NEW.kind,'')) ~ 'price|fee|commission' then 'edit_pricing'
    when lower(coalesce(NEW.kind,'')) ~ 'publish|post|content|blog|campaign' then 'publish_content'
    when lower(coalesce(NEW.kind,'')) ~ 'message|email|notify|send' then 'send_message'
    else 'run_agent_action' end;

  begin
    esc  := public.fn_should_escalate(attrs);
    authz:= public.fn_authorize(coalesce(NEW.agent,'agent'), action, attrs);
    if (esc->>'escalate')::boolean then blocked:=true; reasons := reasons || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]'))); end if;
    if not (authz->>'allowed')::boolean then blocked:=true; reasons := array_append(reasons, authz->>'reason'); end if;
  exception when others then blocked:=true; reasons := array_append(reasons,'gate error — held for review: '||sqlerrm); end;

  -- WHAT THIS DECISION WAS TAKEN ON. Each element is a retrieval that actually returned: if the
  -- call above raised, the variable is still NULL, nothing is appended, and the ledger row says so.
  if esc is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'policy_check', 'ref', 'fn_should_escalate', 'result', esc));
  end if;
  if authz is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'authority_check', 'ref', 'fn_authorize', 'result', authz));
  end if;

  -- enforce: a gated action can never be auto-approved; force human review
  if blocked and coalesce(NEW.status,'pending') in ('approved','auto','auto_approved','executed','done') then
    NEW.status := 'needs_review';
  elsif blocked and coalesce(NEW.status,'pending')='pending' then
    NEW.status := 'needs_review';
  end if;

  -- THE OPTION THAT WAS NOT TAKEN. Two outcomes were genuinely available and one was genuinely
  -- rejected; the reasons it lost are the ones already computed above, not a new narrative.
  v_taken := case when blocked then 'held_for_review' else 'permitted' end;
  v_other := case when blocked then 'permitted' else 'held_for_review' end;
  v_why := case when blocked
    then case when array_length(reasons,1) is null
              then 'the gate blocked without recording a reason, which is itself the finding'
              else array_to_string(reasons, ' | ') end
    else 'fn_should_escalate did not fire and fn_authorize allowed it, so there was no ground to hold it' end;
  v_alts := jsonb_build_array(
    jsonb_build_object('option', v_taken, 'selected', true,
                       'basis', 'fn_should_escalate + fn_authorize on this action''s own context'),
    jsonb_build_object('option', v_other, 'selected', false, 'rejected_because', v_why));

  -- immutable audit
  begin
    insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to,alternatives)
    values (coalesce(NEW.agent,'agent'),'action_gate',
            jsonb_build_object('action',action,'kind',NEW.kind,'risk',NEW.risk,'attrs',attrs),
            case when blocked then 'held_for_review' else 'permitted' end,
            -- NEW.confidence, not a literal null. This trigger is named zzz_action_gate so it fires
            -- AFTER trg_governance_stamp, which is what stamps the 0.9 — see
            -- action_gate_runs_after_the_stamp.sql. Reading it any earlier reads a NULL.
            NEW.confidence,
            to_jsonb(reasons), v_sources, esc->>'route_to', v_alts)
    returning id into v_dl_id;
  exception when others then v_dl_id := null; end;

  NEW.decision_log_id := v_dl_id;
  return NEW;
end $function$;
