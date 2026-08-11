-- STEP 2 (Assign a Confidence), for the same writer that produces 80% of the company's decisions.
--
-- MEASURED DEFECT, production, 11 Aug 2026:
--   decision_log carries a confidence on 12 of 1,390 rows in 30 days.
--   agent_actions  carries a confidence on 1,337 of 1,337 rows in the same window.
--   Every one of the 415 'action_gate' decision_log rows written in 7 days has confidence NULL.
--
-- The number is not missing. It is discarded. trg_action_gate fires BEFORE INSERT on agent_actions,
-- so NEW.confidence — the confidence the acting agent reported for this very action — is in scope
-- on the line above the insert, and the insert writes a literal `null` into the column it belongs
-- in. The same value is already projected to three of the four action surfaces THROUGH the action
-- row (operations 30/30, assistant 8/8, governance 15/15 all show 0.9); only the escalations
-- surface reads decision_log directly, and it therefore shows nothing on 8 of 8.
--
-- OS 2.txt §15 "Explainability Everywhere" asks of any action: "What confidence score was
-- assigned?" For a gated action that score exists, was computed by the agent that proposed it, and
-- was thrown away by this one token.
--
-- THIS IS NOT A BACKFILL. Only rows written from now on carry it. The 1,378 historical rows keep
-- their NULL, because the confidence that applied at the time was not recorded and inventing one
-- now would be indistinguishable from a measured one the moment it landed in the column. At the
-- observed rate of 109 gated actions a day the surfaced window (8 most recent) refreshes in under
-- two hours, which is the honest way for this to go green.
--
-- CREATE OR REPLACE preserves the ACL, so there is no grant to revoke here.
create or replace function public.trg_action_gate()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
        v_sources jsonb := '[]'::jsonb; v_dl_id bigint;
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

  -- immutable audit
  begin
    insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
    values (coalesce(NEW.agent,'agent'),'action_gate',
            jsonb_build_object('action',action,'kind',NEW.kind,'risk',NEW.risk,'attrs',attrs),
            case when blocked then 'held_for_review' else 'permitted' end,
            -- THE ONE CHANGED TOKEN. Was a literal `null`. NEW.confidence is the confidence the
            -- acting agent assigned to this action; it stays NULL when the agent did not report one,
            -- so an unmeasured decision still reads as unmeasured rather than as a default.
            NEW.confidence,
            to_jsonb(reasons), v_sources, esc->>'route_to')
    returning id into v_dl_id;
  exception when others then v_dl_id := null; end;

  NEW.decision_log_id := v_dl_id;
  return NEW;
end $function$;
