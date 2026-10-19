-- A FIXTURE SUPPLIER REGISTRATION FILES NO TASK, NO HANDOFF AND NO supplier_registered NOTICE
-- (13 Oct 2026, seat: customer_support; coordinator-approved defect fix).
--
-- MEASURED on production 13 Oct 2026: 23 org_tasks '[founder_mail:supplier_registered] ...', every one a ZZ DEMO
-- supplier (most recent 580607, "ZZ DEMO Walk 79399dc7 en mobile 0"), and a customer_support delivery.request
-- handoff (agent_actions kind 'handoff', target_table 'notifications') for each notice — about one of each per walk.
-- The chain: supplier_api save_profile -> requestDelivery (fn_customer_support_takes_delivery files the handoff and
-- queues the notice to management) -> BEFORE INSERT a10_notifications_founder_mail_policy -> fn_founder_mail_route
-- inserts the org_task (kind not allowed_to_email, so it is routed to a seat instead of mailed).
--
-- Fence 1 (the source): supplier_api no longer files the supplier_registered notice for a fixture lead
--   (_shared/demo_identity.ts isFixtureLead), so no handoff and no notice exist to route.
-- Fence 2 (this file): fn_notifications_founder_mail_policy drops a supplier_registered admin notice whose lead is a
--   fixture (public.fn_seat_clock_lead_is_fixture, or a qd_run:<tag> on leads.tags) before it can be routed, so any
--   other path that queues one still files no org_task.
--
-- The body below is the LIVE definition read 13 Oct 2026 with only the fence block added. CREATE OR REPLACE keeps the
-- existing ACL; the revoke is restated anyway. Proved by a_fixture_supplier_registration_files_no_task_handoff_or_notice_probe.sql.

create or replace function public.fn_notifications_founder_mail_policy()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_admin text; v_phone text; v_kind text; v_allowed boolean; v_level text;
begin
  if coalesce(NEW.channel, 'email') not in ('email', 'whatsapp') then return NEW; end if;
  -- a format guard on OUR OWN fixture addresses (the reserved .invalid domain), not a reading of meaning
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_admin from public.app_secrets where key = 'admin_emails';
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(NEW.to_role, '') in ('founder', 'admin', 'owner')
          or (NEW.to_email is not null and lower(NEW.to_email) = coalesce(v_admin, 'management@quotesdone.com'))
          or (NEW.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(NEW.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return NEW;
  end if;

  v_kind := coalesce(nullif(btrim(NEW.kind), ''), nullif(btrim(NEW.type), ''), 'unregistered');

  -- THE FIXTURE FENCE (13 Oct 2026): a walk's registration is not a record anyone keeps. Dropped, never routed.
  if v_kind = 'supplier_registered' and NEW.lead_id is not null and exists (
       select 1 from public.leads l
        where l.id = NEW.lead_id
          and (public.fn_seat_clock_lead_is_fixture(l)
               or exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%'))) then
    return null;
  end if;

  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;
  if coalesce(v_allowed, false) then
    NEW.kind := v_kind;
    return NEW;
  end if;

  -- The routed task's level is what the producer STATED; unstated is filed at the normal level.
  NEW.severity := public.fn_notification_severity(NEW.severity, NEW.type);
  v_level := coalesce(NEW.severity, case when NEW.type = 'founder_alert' then 'high' end, 'warn');
  begin
    perform public.fn_founder_mail_route(v_kind, NEW.subject, NEW.body, v_level);
  exception when others then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high', 'founder_mail:route_failed', left('kind ' || v_kind || ' / ' || coalesce(NEW.subject, '') || ' — ' || sqlerrm, 1000), 'os');
  end;
  return null;
end $function$;

revoke execute on function public.fn_notifications_founder_mail_policy() from public, anon, authenticated;
