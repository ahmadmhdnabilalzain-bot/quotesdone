-- STEP 2 (Gather Data), for the writer that produces 80% of the company's decisions.
--
-- MEASURED DEFECT, production, 6 Aug 2026: of the 39 decision_log rows written in 24 hours, 31 are
-- kind='action_gate' and every one of them carries sources = '[]'. trg_action_gate is the busiest
-- decision writer in the database and its ledger row states, on every single row, that the decision
-- was taken having consulted nothing.
--
-- That statement is FALSE, and demonstrably so: the trigger calls fn_should_escalate(attrs) and
-- fn_authorize(agent, action, attrs) and decides entirely on what they return — the 31 rows above
-- are all 'held_for_review' with reasons taken verbatim out of fn_authorize's verdict. The gate
-- retrieves; it simply threw the retrieval away and hard-coded '[]'::jsonb in its place.
--
-- So sources now carries the two verdicts the gate actually obtained, as objects rather than as a
-- label. This is deliberately NOT a constant: the two calls sit inside `exception when others then
-- blocked := true`, and on that path esc and authz stay NULL, no source element is appended, and
-- the row records honestly that this decision was taken on nothing retrieved. A silently broken
-- fn_should_escalate — which round 3 showed is invisible everywhere else, because route_to is
-- written by a coalesce that survives the exception — now shows up as an unsourced decision.
--
-- agent_actions.decision_log_id is the other half. Every agent action passes this gate and the gate
-- writes a decision_log row about it, and until now nothing connected the two: 2,296 actions and
-- 1,114 ledger rows with no join between them, so "which decision authorised this action?" had no
-- answer in the schema. The FK makes the link resolvable rather than merely present.
alter table public.agent_actions
  add column if not exists decision_log_id bigint references public.decision_log(id);

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
  attrs := attrs || jsonb_build_object('amount_aed', amt, 'text', lower(coalesce(NEW.title,'')||' '||coalesce(NEW.recommendation,'')),
                                       'category', coalesce(attrs->>'category',''), 'moves_money', (lower(coalesce(NEW.kind,'')) ~ '(refund|payout|charge|payment|transfer)'));
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
            case when blocked then 'held_for_review' else 'permitted' end, null,
            to_jsonb(reasons), v_sources, coalesce(esc->>'route_to','Secretary'))
    returning id into v_dl_id;
  exception when others then v_dl_id := null; end;

  NEW.decision_log_id := v_dl_id;
  return NEW;
end $function$;
