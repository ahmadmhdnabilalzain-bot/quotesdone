-- The two triggers on the critical path stop naming their own project — 12 Aug 2026
--
-- apply_sql now REFUSES to promote any routine carrying a literal https://<ref>.supabase.co URL,
-- because promoting one repoints the production copy at staging and nothing fails visibly. Nineteen
-- routines carried one. That guard is correct, and it makes those nineteen unpromotable until they
-- are fixed — which is the right forcing function, but it means the two on the demand and supply
-- critical path cannot be touched at all until they are converted. They are converted here.
--
--   trg_autodispatch_inquiry — the ONLY caller of dispatch_inquiry. Every RFQ the company will ever
--                              route passes through this line.
--   trg_enrich_capability    — the only thing that gives an approved supplier a capability record,
--                              without which fn_match_capability cannot see them at all.
--
-- Both now read app_secrets.project_ref with the cron.job fallback, the same lookup
-- fn_action_invoke_dispatch, fn_rfq_redispatch_sweep and fn_capability_enrich_sweep use. Their
-- definitions become identical on both projects and safe to promote.
--
-- THE FALLBACK MATTERS MORE HERE THAN ELSEWHERE. These run inside a trigger on a customer's INSERT.
-- If the ref cannot be resolved the old code would have posted to a hardcoded URL and worked; the
-- new code must not raise, or a missing app_secrets row would start REFUSING RFQ creation and
-- supplier approval. So an unresolvable ref skips the call and leaves the row untouched — exactly
-- what already happens when the HTTP post fails — and both paths now have a retry sweep behind them
-- (fn_rfq_redispatch_sweep, fn_capability_enrich_sweep) that will pick the row up within six hours.
-- That is why converting these two was safe to do only after the sweeps existed.
--
-- Trigger conditions, guards and return values are otherwise byte-identical.

create or replace function public.trg_autodispatch_inquiry()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_secret text; v_ref text;
begin
  if NEW.rfq_ready is true
     and (TG_OP='INSERT' or OLD.rfq_ready is distinct from NEW.rfq_ready)
     and (NEW.routing is null or (NEW.routing->>'dispatched_at') is null) then
    select value into v_secret from app_secrets where key='cred_db_internal';
    select value into v_ref from app_secrets where key='project_ref';
    if v_ref is null then
      select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
        from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
    end if;
    -- Never raise inside the trigger: a missing ref must not stop an RFQ being created.
    -- fn_rfq_redispatch_sweep re-offers an RFQ that reached nobody within six hours.
    if v_ref is not null then
      perform net.http_post(
        url := 'https://'||v_ref||'.supabase.co/functions/v1/dispatch_inquiry',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('__secret', v_secret, 'inquiry_id', NEW.id));
    end if;
  end if;
  return NEW;
end $function$;

create or replace function public.trg_enrich_capability()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_secret text; v_ref text;
begin
  if NEW.approval_status='approved'
     and (TG_OP='INSERT' or OLD.approval_status is distinct from NEW.approval_status)
     and NEW.capability_enriched_at is null then
    select value into v_secret from app_secrets where key='cred_db_internal';
    select value into v_ref from app_secrets where key='project_ref';
    if v_ref is null then
      select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
        from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
    end if;
    -- Never raise inside the trigger: a missing ref must not stop a supplier being approved.
    -- fn_capability_enrich_sweep retries a claimed approved supplier within six hours.
    if v_ref is not null then
      perform net.http_post(
        url := 'https://'||v_ref||'.supabase.co/functions/v1/enrich_capability',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('__secret', v_secret, 'lead_id', NEW.id));
    end if;
  end if;
  return NEW;
end $function$;
