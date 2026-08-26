-- THE AMENDMENT GUARD ONLY WATCHED ONE BASIS, AND auth.uid() IS A SETTING.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and one assertion block; rehearsable.
--
-- ================================================================================================
-- WHAT WAS MEASURED, ON PRODUCTION, IN ABORTED TRANSACTIONS
-- ================================================================================================
--
-- public.fn_phase_c_freeze_amendment_session_claim_is_verified opened with:
--
--     if NEW.approval_basis is distinct from 'AUTHENTICATED_FOUNDER_SESSION' then return NEW; end if;
--
-- so every other value of that column walked straight through. From the management connection,
-- session_user = postgres, carrying no bearer token of any kind:
--
--   INSERT an amendment approved on WRITTEN_INSTRUCTION                        -> ACCEPTED
--   INSERT a SECOND AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP amendment          -> ACCEPTED
--   UPDATE approved_by / approved_at onto amendment 51 as WRITTEN_INSTRUCTION  -> ACCEPTED
--   UPDATE approved_amendment_table_digest on amendment 51 to repeat('a',64)   -> ACCEPTED
--
-- The last one is the sharp one: it rewrites the record of WHICH DOCUMENT THE FOUNDER APPROVED, on
-- the row carrying his only PCCR-006 approval, and no check on fn_phase_c_freeze_drift moves.
--
-- And the arm that did fire was not sound either. Its Route A fallback is:
--
--     if coalesce(auth.uid(), '000…0') is distinct from NEW.approval_auth_subject then raise …
--
-- auth.uid() reads current_setting('request.jwt.claims'). A management connection can set it:
--
--     select set_config('request.jwt.claims','{"sub":"1256c7ec-…","role":"authenticated"}',true);
--     select auth.uid();                                    -> 1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14
--     insert … approval_basis='AUTHENTICATED_FOUNDER_SESSION' …   -> ACCEPTED
--
-- The identical INSERT is REFUSED 28000 without that one line. So the guard did not test whether a
-- session existed; it tested whether a string had been set.
--
-- ================================================================================================
-- WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT
-- ================================================================================================
--
-- Three additions, all on the same trigger function, none of them touching a frozen subject
-- (public.phase_c_frozen_subject does not name this routine):
--
--   1. THE CONNECTION, not the claim. Any write that sets or moves an approval column must arrive
--      on the PostgREST connection that verified a bearer token — session_user = 'authenticator'.
--      This is the same predicate PCCR-006 already put on fn_phase_c_governance_decide and on
--      fn_phase_c_founder_auth_event, and it is the only one a `set_config` cannot forge, because
--      session_user is the connected role and SET SESSION AUTHORIZATION is refused to postgres on
--      this deployment (measured: 42501, is_superuser = off).
--
--   2. EVERY BASIS, not one. WRITTEN_INSTRUCTION is refused at write time rather than merely
--      reported afterwards by fn_phase_c_freeze_drift. A board that reports a forged row is a
--      detection; this is the refusal the gate asked for.
--
--   3. AN APPROVAL IS A FACT ABOUT THE PAST. Once approved_by is set, none of approved_by,
--      approved_at, approval_basis, approval_route, approval_auth_subject,
--      approved_amendment_table_path or approved_amendment_table_digest may move again.
--
-- THE LEGITIMATE WRITER IS NOT BROKEN, and this was checked before the predicate was chosen.
-- scripts/phase_d/approve_pccr_amendments.mjs posts to ${BASE}/rest/v1/rpc/… with a GoTrue bearer
-- issued for the active founder identity — its own header says so — so it arrives as session_user
-- 'authenticator' and passes. The five amendments recorded AUTHENTICATED_FOUNDER_SESSION
-- (1, 2, 4, 5, 36) were written that way and are undisturbed.
--
-- THE BOOTSTRAP IS PINNED WHERE IT ALREADY WAS. Amendment 51 carries
-- AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP and fn_phase_c_freeze_drift already expects "exactly 1 --
-- PCCR-006 itself". That expectation was enforced by nothing. It is now: a new row on that basis is
-- refused, and the existing one is left exactly as it is. This is not a widening; a value that
-- could be written freely can now be written never.
--
-- WHAT THIS DOES NOT FIX, STATED SO ITS SILENCE IS NOT READ AS COVERAGE.
-- public.fn_phase_c_require_founder(p_actor text) has the same auth.uid() weakness and it IS a
-- frozen subject (founder_authentication). It gates the refund decision service, fn_kernel_cancel
-- and the Chief of Staff command path, and with request.jwt.claims set a management connection
-- passes it — measured: fn_kernel_refund_decision_record got past the founder gate and stopped on
-- a missing request_id, which is argument validation AFTER the gate. That is raised as PCCR-007,
-- docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md, and needs the founder. This file does not touch
-- it and does not pretend to.

create or replace function public.fn_phase_c_freeze_amendment_session_claim_is_verified()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_ev      bigint;
  e         public.phase_c_founder_auth_event%rowtype;
  v_moved   boolean;
begin
  -- ---- 0. AN APPROVAL ALREADY GIVEN MAY NOT MOVE ------------------------------------------------
  if TG_OP = 'UPDATE' and OLD.approved_by is not null then
    if (NEW.approved_by, NEW.approved_at, NEW.approval_basis, NEW.approval_route,
        NEW.approval_auth_subject, NEW.approved_amendment_table_path,
        NEW.approved_amendment_table_digest)
       is distinct from
       (OLD.approved_by, OLD.approved_at, OLD.approval_basis, OLD.approval_route,
        OLD.approval_auth_subject, OLD.approved_amendment_table_path,
        OLD.approved_amendment_table_digest) then
      raise exception 'phase_c_freeze_amendment %: the approval columns are a fact about the past and may not be changed once given. Rewriting approved_amendment_table_digest changes which document the founder is recorded as having read. (pccr007_amendment_approval_immutable)',
        OLD.amendment_id using errcode = '42501';
    end if;
    return NEW;   -- an unrelated column moved on an already-approved row
  end if;

  -- ---- 1. IS THIS WRITE MAKING AN APPROVAL CLAIM AT ALL? ----------------------------------------
  v_moved := NEW.approved_by is not null or NEW.approval_basis is not null;
  if TG_OP = 'UPDATE' then
    v_moved := v_moved and
      (NEW.approved_by, NEW.approval_basis) is distinct from (OLD.approved_by, OLD.approval_basis);
  end if;
  if not v_moved then
    return NEW;
  end if;

  -- ---- 2. A WRITTEN INSTRUCTION IS NOT AN APPROVAL, AND IS NOW REFUSED RATHER THAN REPORTED -----
  if NEW.approval_basis = 'WRITTEN_INSTRUCTION' then
    raise exception 'phase_c_freeze_amendment %: WRITTEN_INSTRUCTION may not be written. An approval recorded from a written instruction is not a founder session, and fn_phase_c_freeze_drift has reported that for as long as this column has existed. It is refused here instead. (pccr007_amendment_written_instruction_refused)',
      coalesce(NEW.amendment_id::text,'(new)') using errcode = '28000';
  end if;

  -- ---- 3. THE ONE-TIME COMMAND BOOTSTRAP WAS SPENT BY PCCR-006 ----------------------------------
  if NEW.approval_basis = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP' then
    raise exception 'phase_c_freeze_amendment %: AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP was used exactly once, by PCCR-006, to approve the change request that created the governance ledger. fn_phase_c_freeze_drift expects exactly one and nothing enforced it. Every approval after that one goes through a verified session. (pccr007_amendment_bootstrap_already_spent)',
      coalesce(NEW.amendment_id::text,'(new)') using errcode = '28000';
  end if;

  -- ---- 4. THE CONNECTION. This is the predicate a set_config cannot forge. ----------------------
  if session_user <> 'authenticator' then
    raise exception 'phase_c_freeze_amendment %: an approval may only be recorded on the PostgREST connection that verified a founder bearer token (session_user authenticator); this call arrives as session_user %. auth.uid() reads request.jwt.claims, which a management or migration connection can set for itself, so the claim is not evidence and the connection is. (pccr007_amendment_untrusted_connection)',
      coalesce(NEW.amendment_id::text,'(new)'), session_user using errcode = '28000';
  end if;

  -- ---- 5. THE VERIFIED SUBJECT, unchanged from PCCR-006 -----------------------------------------
  v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
  select * into e from public.phase_c_founder_auth_event
   where event_id = v_ev and txid = txid_current();
  if not found then
    if coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
       is distinct from NEW.approval_auth_subject then
      raise exception 'phase_c_freeze_amendment %: a row may not claim % without a verified session. There is no founder auth event bound to this transaction and auth.uid() does not resolve to the subject the row names. (pccr_amendment_session_claim_unverified)',
        coalesce(NEW.amendment_id::text,'(new)'), NEW.approval_basis using errcode = '28000';
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

-- ================================================================================================
-- SELF-VERIFICATION.
--
-- Every case runs inside its own plpgsql BEGIN/EXCEPTION block, which is a SUBTRANSACTION: a probe
-- that raises rolls back its own write and nothing else. The one probe expected to SUCCEED raises a
-- sentinel of its own afterwards so that it too rolls back. Nothing here may abort the file, because
-- the file has no transaction control and an abort would take the CREATE OR REPLACE with it — so
-- the only unconditional raise is the one that fires when a case behaves WRONGLY, which is exactly
-- when the apply should fail.
-- ================================================================================================
do $verify$
declare
  log text := '';
  ok  boolean := true;
  fn  text;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14","role":"authenticated"}', true);

  for fn in select unnest(array['WRITTEN_INSTRUCTION',
                               'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP',
                               'AUTHENTICATED_FOUNDER_SESSION'])
  loop
    begin
      insert into public.phase_c_freeze_amendment
        (subject, object_identity, prior_digest, new_digest, reason, evidence, amended_at,
         change_request_ref, approved_by, approved_at, approval_basis, approval_route,
         approval_auth_subject, approved_amendment_table_path, approved_amendment_table_digest,
         original_deployment_at, deployed_before_approval)
      values ('founder_authentication', 'fn_pccr007_verify_'||lower(fn)||'(text)',
              repeat('c',64), repeat('d',64),
              'self-verification block of phase_c_the_amendment_guard_only_watched_one_basis.sql, proving that the migration connection is refused on every approval basis including a forged request.jwt.claims',
              'self-verification evidence string long enough to satisfy the forty character minimum',
              now(), 'PCCR-004', 'management@quotesdone.com', now(), fn,
              case when fn = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP' then null else 'auth.uid()' end,
              case when fn = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP' then null
                   else '1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14'::uuid end,
              'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-004.md', repeat('a',64), now(), false);
      log := log || fn || '=ACCEPTED(WRONG) ';
      ok := false;
    exception when others then
      log := log || fn || '=REFUSED(' || sqlstate || ') ';
    end;
  end loop;

  begin
    update public.phase_c_freeze_amendment
       set approved_amendment_table_digest = repeat('a',64)
     where amendment_id = 51;
    log := log || 'DIGEST_REWRITE=ACCEPTED(WRONG) ';
    ok := false;
  exception when others then
    log := log || 'DIGEST_REWRITE=REFUSED(' || sqlstate || ') ';
  end;

  begin
    update public.phase_c_freeze_amendment
       set approved_by = 'management@quotesdone.com', approved_at = now(),
           approval_basis = 'WRITTEN_INSTRUCTION', approval_route = 'written_instruction'
     where amendment_id = 51;
    log := log || 'APPROVER_REWRITE=ACCEPTED(WRONG) ';
    ok := false;
  exception when others then
    log := log || 'APPROVER_REWRITE=REFUSED(' || sqlstate || ') ';
  end;

  -- An UNRELATED column on an approved row must still be writable, or this guard would freeze the
  -- table rather than the approval. The sentinel raise rolls the touch back with its subtransaction.
  begin
    update public.phase_c_freeze_amendment
       set evidence = evidence || ' (self-verification touch)'
     where amendment_id = 51;
    raise exception 'PCCR007_SELFTEST_ROLLBACK';
  exception when others then
    if sqlerrm = 'PCCR007_SELFTEST_ROLLBACK' then
      log := log || 'UNRELATED_COLUMN=ACCEPTED(correct) ';
    else
      log := log || 'UNRELATED_COLUMN=REFUSED(' || sqlstate || ')(WRONG) ';
      ok := false;
    end if;
  end;

  perform set_config('request.jwt.claims', '', true);

  if not ok then
    raise exception 'PCCR007_AMENDMENT_GUARD_FAILED | %', log using errcode = '23514';
  end if;
  raise notice 'PCCR007_AMENDMENT_GUARD_VERIFIED | %', log;
end
$verify$;
