-- THE SIGNATURE TRIGGER WAITS AS LONG AS SIGNING ACTUALLY TAKES (22 Sep 2026, it_engineer, CONN-09).
--
-- WHAT WAS MEASURED, in net._http_response on 22 Sep 2026 (the table is short-retention, so this is the
-- retained window and not a lifetime count):
--     http 200                                                            47
--     http 409                                                             5
--     "Timeout of 8000 ms reached. Total time: 8000.293000 ms ..."          1
-- 8,000 ms is the timeout these two triggers pass, and nothing else in the estate passes it. So the one
-- timed-out request is a Terms acceptance whose signed archive was never made.
--
-- WHY 8 s WAS NEVER ENOUGH. qd_sign_customer and qd_sign_supplier post to compliance_archive, which
-- renders the signed Terms through pdf_native (letterhead, signature, stamp) and then uploads it to
-- Dropbox. Two network hops and a PDF render. For comparison, measured over 14 days of agent_runs,
-- send_outbox — a comparable chain of one hop plus provider calls — has a p50 of 9.5 s and a p99 of
-- 31.2 s. An 8 s budget is below even the median of that shape of work.
--
-- WHY THE FAILURE IS SILENT. net.http_post is asynchronous: the trigger queues the request and returns,
-- so the Terms acceptance commits either way. The timeout lands in net._http_response minutes later,
-- where nothing reads it. The customer accepted, the row says they accepted, and the signed copy that
-- proves it does not exist.
--
-- 60_000 ms: the callee's own inner call to pdf_native is bounded at 45 s
-- (supabase/functions/compliance_archive/index.ts, CONN-04), so 60 s is that plus the upload, and it
-- costs nothing when the call is fast — a timeout is a ceiling, not a wait. THERE IS NO ORDERING
-- REQUIREMENT between this apply and that deploy (corrected 22 Sep 2026 after independent review, which
-- was right that the earlier note claimed one): the two timeouts bound two different hops and neither
-- reads the other. 60 s is chosen so that after both land this is not the binding constraint.
--
-- Everything else in both triggers is unchanged, including the defensive qd_project_ref() resolution:
-- a trigger on the Terms path must never refuse the signature.

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
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
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
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  end if;
  return NEW;
end $function$;

-- A trigger function takes no arguments and is only ever called by the trigger, but EXECUTE on it is
-- still EXECUTE on a SECURITY DEFINER routine.
revoke execute on function public.qd_sign_customer() from public, anon, authenticated;
revoke execute on function public.qd_sign_supplier() from public, anon, authenticated;

-- fn_action_invoke_dispatch was checked in the same pass and is NOT changed: it already passes
-- `timeout_milliseconds := r.timeout_seconds * 1000` with coalesce(e.timeout_seconds, 60), so its
-- deadline is explicit and per-executor. It is named here so the next reader does not have to re-check
-- whether it was missed.
