-- ROLLBACK for scripts/sql/phase_c_the_amendment_guard_only_watched_one_basis.sql
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE; rehearsable.
--
-- Restores public.fn_phase_c_freeze_amendment_session_claim_is_verified to the body PCCR-006
-- deployed on 2026-08-25, read out of production with pg_get_functiondef before the change and
-- reproduced here verbatim.
--
-- APPLYING THIS REOPENS FOUR MEASURED HOLES, and they are named rather than left to be discovered:
-- from a management connection carrying no bearer token, an amendment approved on
-- WRITTEN_INSTRUCTION becomes writable, a second AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP becomes
-- writable, approved_amendment_table_digest on an already-approved row becomes rewritable, and a
-- forged `set_config('request.jwt.claims', …)` makes auth.uid() resolve to the founder so an
-- AUTHENTICATED_FOUNDER_SESSION row becomes writable too.

create or replace function public.fn_phase_c_freeze_amendment_session_claim_is_verified()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_ev bigint; e public.phase_c_founder_auth_event%rowtype;
begin
  if NEW.approval_basis is distinct from 'AUTHENTICATED_FOUNDER_SESSION' then
    return NEW;
  end if;
  if TG_OP = 'UPDATE' and OLD.approval_basis = 'AUTHENTICATED_FOUNDER_SESSION'
     and (NEW.approved_by, NEW.approval_route, NEW.approval_auth_subject,
          NEW.approved_amendment_table_digest)
         is not distinct from
         (OLD.approved_by, OLD.approval_route, OLD.approval_auth_subject,
          OLD.approved_amendment_table_digest) then
    return NEW;   -- an unrelated column moved on an already-verified approval
  end if;

  v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
  select * into e from public.phase_c_founder_auth_event
   where event_id = v_ev and txid = txid_current();
  if not found then
    -- Route A carries no bound event; the subject must then be a live auth.uid().
    if coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
       is distinct from NEW.approval_auth_subject then
      raise exception 'phase_c_freeze_amendment %: a row may not claim AUTHENTICATED_FOUNDER_SESSION without a verified session. There is no founder auth event bound to this transaction and auth.uid() does not resolve to the subject the row names. Every constraint on this table checks the SHAPE of the claim; this checks the claim. (pccr_amendment_session_claim_unverified)',
        coalesce(NEW.amendment_id::text,'(new)') using errcode = '28000';
    end if;
    return NEW;
  end if;
  if e.identity is distinct from NEW.approved_by or e.auth_subject is distinct from NEW.approval_auth_subject then
    raise exception 'phase_c_freeze_amendment %: the row is attributed to %/% and the verified session resolved to %/%. (pccr_amendment_session_claim_mismatched)',
      coalesce(NEW.amendment_id::text,'(new)'), NEW.approved_by, NEW.approval_auth_subject,
      e.identity, e.auth_subject using errcode = '28000';
  end if;
  return NEW;
end
$function$;
