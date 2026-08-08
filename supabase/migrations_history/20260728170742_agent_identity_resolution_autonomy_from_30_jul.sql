-- THE BUG: trg_action_gate calls fn_authorize(NEW.agent, ...) passing an AGENT KEY
-- ('it', 'onboarding', 'knowledge_curator') into a parameter named p_email.
-- fn_role_of() only ever looked in user_roles / admin_emails / leads / customers,
-- all keyed by email, so every employee resolved to 'guest'. Role 'guest' holds no
-- permissions, so 810 of 811 decisions in the system's life were held_for_review
-- with: role "guest" lacks permission "run_agent_action".
--
-- The authority model was never the problem. Role 'agent' already exists with a
-- deliberately conservative envelope: route_inquiry, send_message, and
-- run_agent_action capped at max_amount_aed = 0. It grants NO approve_supplier,
-- NO issue_refund, NO edit_pricing, NO publish_content. Employees simply never
-- reached it.
--
-- Two new switches, both plain rows you can flip without a deploy:
--   agent_autonomy_from    - date autonomy begins (set to 30 Jul 2026)
--   agent_autonomy_enabled - kill switch; set to false to park everything again

insert into app_secrets (key, value)
select 'agent_autonomy_from', '2026-07-30'
where not exists (select 1 from app_secrets where key = 'agent_autonomy_from');

insert into app_secrets (key, value)
select 'agent_autonomy_enabled', 'true'
where not exists (select 1 from app_secrets where key = 'agent_autonomy_enabled');

create or replace function public.fn_role_of(p_email text)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  e text := lower(trim(coalesce(p_email,'')));
  v_role text;
  v_from date;
  v_on boolean;
begin
  if e = '' then return 'guest'; end if;

  -- Human identities first: unchanged behaviour, still wins over everything.
  select ur.role into v_role from user_roles ur
   where ur.email = e
   order by array_position(array['owner','admin','ops','finance','support','agent'], ur.role)
   limit 1;
  if v_role is not null then return v_role; end if;

  if e = any (string_to_array(lower(coalesce((select value from app_secrets where key='admin_emails'),'')), ','))
    then return 'owner'; end if;

  -- AGENT IDENTITY. Only for values that are not email addresses, so a real
  -- person can never be mistaken for an employee record.
  if position('@' in e) = 0 then
    if exists (select 1 from org_agents where lower(agent_key) = e and active) then
      v_on := lower(coalesce((select value from app_secrets where key='agent_autonomy_enabled'),'true')) = 'true';
      begin
        v_from := coalesce((select value from app_secrets where key='agent_autonomy_from'),'2026-07-30')::date;
      exception when others then v_from := date '2026-07-30';
      end;
      if v_on and current_date >= v_from then
        return 'agent';
      else
        return 'guest';   -- pre-arming: behaviour identical to today
      end if;
    end if;
  end if;

  if exists (select 1 from leads where lower(coalesce(claimed_by,'')) = e) then return 'supplier'; end if;
  if exists (select 1 from customers where lower(coalesce(email,'')) = e) then return 'customer'; end if;
  return 'guest';
end
$function$;

comment on function public.fn_role_of(text) is
  'Resolves an identity to a role. Accepts an email OR an org_agents.agent_key. Agent keys resolve to role "agent" only when agent_autonomy_enabled is true AND current_date >= agent_autonomy_from; otherwise "guest", which reproduces pre-30-Jul-2026 behaviour exactly.';