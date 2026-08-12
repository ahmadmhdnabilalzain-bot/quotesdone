-- The two signing triggers must never refuse a signature — 12 Aug 2026
--
-- CORRECTION TO MY OWN MIGRATION. sixteen_routines_stop_naming_their_own_project.sql says of the
-- sixteen it rewrote: "none of which is a trigger — every one is a scheduled or internally-called
-- routine." That is wrong. Two of them are live, attached triggers:
--
--   qd_sign_customer  -> fires when a CUSTOMER accepts the Terms
--   qd_sign_supplier  -> fires when a SUPPLIER accepts the Terms
--
-- and qd_project_ref() RAISES when it cannot resolve a ref. Raising inside those two would make
-- accepting the Terms fail — the single step the founder still has to complete before the first
-- inquiry can exist, and the step that gates create_inquiry for every customer after him. A
-- misconfiguration in app_secrets would have turned into "you cannot sign up".
--
-- The rule I applied to trg_autodispatch_inquiry and trg_enrich_capability applies here for the same
-- reason and was simply not applied to these two, because I had asserted they were not triggers
-- instead of checking: a trigger must not raise on an infrastructure lookup. It skips the
-- notification and lets the write through.
--
-- What is lost when it skips is a compliance_archive call that renders and mirrors the signed T&C
-- PDF. That is already treated as best-effort elsewhere by design — customer_api's create_inquiry
-- deliberately does NOT block on signed_terms_path, with the comment that "a transient failure there
-- is not the buyer's fault... blocking would take a customer's ability to trade away for an
-- operational fault of ours." Skipping here is the same judgement, applied at the same boundary.
--
-- Everything else about both triggers is byte-identical, including the 8-second timeout.

create or replace function public.qd_sign_customer()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_secret text; v_ref text;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  -- Resolved defensively: a trigger on the Terms-acceptance path must never refuse the signature.
  begin
    v_ref := public.qd_project_ref();
  exception when others then
    v_ref := null;
  end;
  if v_ref is not null then
    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action','sign','kind','customer','email', NEW.email),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 8000);
  end if;
  return NEW;
end $function$;

create or replace function public.qd_sign_supplier()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_secret text; v_ref text;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  -- Resolved defensively: a trigger on the Terms-acceptance path must never refuse the signature.
  begin
    v_ref := public.qd_project_ref();
  exception when others then
    v_ref := null;
  end;
  if v_ref is not null then
    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action','sign','kind','supplier','email', NEW.claimed_by),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 8000);
  end if;
  return NEW;
end $function$;
