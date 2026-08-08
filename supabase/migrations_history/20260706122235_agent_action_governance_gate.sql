-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706122235   name: agent_action_governance_gate
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ O1: enforce governance gate on agent-initiated actions ============
create or replace function public.trg_action_gate() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
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
            to_jsonb(reasons), '[]'::jsonb, coalesce(esc->>'route_to','Secretary'));
  exception when others then null; end;
  return NEW;
end $$;
drop trigger if exists action_gate on public.agent_actions;
create trigger action_gate before insert on public.agent_actions
  for each row execute function public.trg_action_gate();

-- TEST: an agent trying to auto-approve a large refund must be forced to review
insert into public.agent_actions(agent,kind,status,risk,title,recommendation,detail)
values ('finance-agent','issue_refund','approved','high','Auto-refund AED 25,000','process now','{"amount_aed":25000}')
returning id, status as enforced_status;
