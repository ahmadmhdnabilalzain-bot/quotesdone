-- PCCR-007 — THE FOUNDER DOOR READ A SETTING.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and one assertion block; rehearsable.
--
-- FOUNDER APPROVAL, in his own words, recorded immutably before this file was written:
--   founder_command_message 46779, channel command_center, received 2026-08-26 12:35:30.387938+00,
--   founder_identity management@quotesdone.com (active, kind email),
--   raw_text_hash 357c4c0ef59d7ad65672e6b0ffcbf969614562d7cd643831bd8c8ccbe464a0bd,
--   recomputed on production with encode(sha256(convert_to(raw_text,'UTF8')),'hex') and equal,
--   quoting docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md sha256
--   f2a89bebcdf115c73d837f4457bddc5375ac4c3ffe7bb25e100bd7b5a0e17ad1, which is the digest of that
--   file as committed at origin/main 872d333.
--
-- ================================================================================================
-- THE SENTENCE THIS FILE DELETES
-- ================================================================================================
--
-- The frozen body carried this, immediately above Route A:
--
--     -- auth.uid() is null for a service_role connection and for anything that did not arrive with
--     -- a user JWT. It cannot be set by a caller.
--
-- The last five words are false. auth.uid() reads current_setting('request.jwt.claims'), and any
-- connection may set that for itself. Measured on production, in a transaction that aborted:
--
--     select set_config('request.jwt.claims',
--            '{"sub":"1256c7ec-…","role":"authenticated"}', true);
--     select auth.uid();                                  -> 1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14
--     select public.fn_phase_c_require_founder('management@quotesdone.com');
--                                                         -> management@quotesdone.com   ACCEPTED
--
-- Without that one set_config the identical call is REFUSED 28000. The door was not asking whether
-- a session existed; it was asking whether a string had been set.
--
-- CARRIED THROUGH TO THE MONEY, end to end, in a transaction that aborted:
--
--     insert founder_approval_request (action_class 'refund_decision', AED 10.00, state 'pending')
--     select fn_kernel_refund_decision_record('{"op":"record","request_id":…,"decision":"approved"}')
--     -> {"ok": true, "decision": "approved", "decided_by": "management@quotesdone.com",
--         "decision_id": 2597,
--         "note": "decided_by is the identity fn_phase_c_require_founder verified, not the
--                  identity the call named"}
--
-- A refund approval attributed to the founder, from a connection that never logged in, with the
-- routine's own note asserting it had verified him. Rolled back; phase_c_refund_decision returned
-- to 0 rows. His standing rule is that every refund at any amount reaches him and is approved on
-- the OS. That rule was written down and was not enforced.
--
-- ================================================================================================
-- THE FIX: ONE PREDICATE, AND WHY IT IS THIS ONE
-- ================================================================================================
--
-- session_user is the role the connection authenticated as. PostgREST connects as 'authenticator'
-- and SETs ROLE to anon / authenticated / service_role, which leaves session_user alone. Nothing a
-- caller can do changes it, and the two things that look like they might were measured:
--
--     SET SESSION AUTHORIZATION authenticator   -> REFUSED 42501 (postgres is not superuser here)
--     SET ROLE authenticator                    -> accepted, and session_user stays 'postgres'
--
-- So the predicate is exactly the one PCCR-006 already put on fn_phase_c_governance_decide and on
-- fn_phase_c_founder_auth_event. This file finishes that job on the door PCCR-003 built.
--
-- IT GUARDS BOTH ROUTES, deliberately. Route B consumes an event bound by e.txid = txid_current(),
-- so it is always the same connection that minted it, and minting already requires 'authenticator'.
-- Putting the check at the top costs nothing and removes the question.
--
-- WHAT STILL WORKS, checked before the predicate was chosen rather than after:
--   · os_api and every Edge Function reach PostgREST with the service_role key, so session_user is
--     'authenticator' and both routes are unaffected.
--   · scripts/phase_d/approve_pccr_amendments.mjs posts to /rest/v1/rpc/… with a GoTrue bearer.
--   · The refund decision service, fn_kernel_cancel and the Chief of Staff command path are all
--     reached through os_api and are unaffected.
-- What stops working is the management and migration connection, which is the change.
--
-- WHAT THIS DOES NOT CLAIM. It does not make the founder's approval unforgeable by everyone. A
-- holder of the service_role key can still mint a GoTrue bearer for his identity through
-- admin/generate_link — that is how scripts/phase_d/discharge_d0_auth_debt.mjs and
-- approve_pccr_amendments.mjs have always worked, and it is how the five AUTHENTICATED_FOUNDER_SESSION
-- amendments were recorded. This file closes the migration path, which is the hole that was
-- measured. The key-holder path is a separate subject and is not addressed here.

create or replace function public.fn_phase_c_require_founder(p_actor text)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_sub    uuid;
  v_id     text;
  v_ev     bigint;
  v_route  text;
begin
  -- ---- PCCR-007. THE CONNECTION, BEFORE ANY CLAIM IS READ ---------------------------------------
  -- session_user is the role this connection authenticated as. A caller cannot change it: SET ROLE
  -- leaves it alone and SET SESSION AUTHORIZATION is refused to postgres on this deployment. Every
  -- claim examined below — auth.uid(), the bound event — is read from session state that a
  -- management or migration connection can write for itself, so the connection is checked first.
  if session_user <> 'authenticator' then
    raise exception 'not the founder: the founder is resolved from a bearer token verified by PostgREST (session_user authenticator); this call arrives as session_user %. auth.uid() reads request.jwt.claims, which a management or migration connection can set for itself, so a resolved subject on this connection is a value the caller wrote rather than a session anyone opened. (pccr007_founder_untrusted_connection)',
      session_user using errcode = '28000',
            hint = 'Approve on the OS. A migration cannot approve a refund, cancel a workflow or answer a founder command.';
  end if;

  -- ---- ROUTE A: a bearer token PostgREST already verified -------------------------------------
  -- auth.uid() is null for a service_role connection and for anything that did not arrive with a
  -- user JWT. It CAN be set by a caller — that was PCCR-007's finding, and it is why the connection
  -- is checked above before this value is trusted.
  begin
    v_sub := auth.uid();
  exception when others then
    v_sub := null;
  end;
  if v_sub is not null then
    select f.identity into v_id
      from public.phase_c_founder_identity f
     where f.auth_user_id = v_sub and f.active and f.kind = 'email';
    v_route := 'auth.uid()';
  end if;

  -- ---- ROUTE B: the server path bound a subject it verified ------------------------------------
  if v_id is null then
    v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
    if v_ev is not null then
      select e.identity, e.auth_subject into v_id, v_sub
        from public.phase_c_founder_auth_event e
        join public.phase_c_founder_identity f on f.identity = e.identity
       where e.event_id = v_ev
         -- BOUND TO THIS TRANSACTION. A GUC pointing at an event from another transaction is not a
         -- session: it is a value a caller typed.
         and e.txid = txid_current()
         -- PCCR-006. A PURPOSE-BOUND SESSION IS NOT A GENERAL ONE. An event minted to carry one
         -- governance decision may not also open the refund door in the same transaction.
         -- fn_phase_c_governance_decide reads its own event directly and does not come through here.
         and e.action_class is null
         and f.active and f.kind = 'email';
      v_route := 'fn_phase_c_founder_subject_bind';
    end if;
  end if;

  if v_id is null then
    -- E39's vector, refused: knowing the email is no longer being the founder.
    raise exception 'not the founder: no verified auth subject on this call. The founder is resolved from auth.uid() or from a subject os_api verified and bound with fn_phase_c_founder_subject_bind; a caller-supplied identity is not authentication. (PCCR-003)'
      using errcode = '28000',
            hint = 'Call with the founder''s bearer token so auth.uid() resolves, or verify the JWT in os_api and bind the verified subject first.';
  end if;

  -- p_actor is now an ASSERTION, not a source. Supplying one that disagrees with the verified
  -- identity is a caller claiming to be someone else and is refused; supplying none is fine.
  if coalesce(btrim(p_actor),'') <> '' and lower(btrim(p_actor)) <> lower(v_id) then
    raise exception 'not the founder: the call asserts identity % and the verified auth subject resolves to %',
      lower(btrim(p_actor)), v_id using errcode = '28000';
  end if;

  return v_id;
end $function$;

-- ================================================================================================
-- SELF-VERIFICATION. Runs from the management connection — session_user 'postgres' — which is
-- exactly the caller this change is about. Each case is its own subtransaction so a refusal rolls
-- back only itself, and the file raises only when a case behaves WRONGLY, because an abort would
-- take the CREATE OR REPLACE with it.
-- ================================================================================================
do $verify$
declare log text := ''; ok boolean := true; r text; d jsonb; v_req bigint;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14","role":"authenticated"}', true);

  -- 1. The door itself, with the forged claim that used to work.
  begin
    r := public.fn_phase_c_require_founder('management@quotesdone.com');
    log := log || 'FORGED_CLAIM=ACCEPTED(' || coalesce(r,'null') || ')(WRONG) ';
    ok := false;
  exception when others then
    log := log || 'FORGED_CLAIM=REFUSED(' || sqlstate || ') ';
  end;

  -- 2. The whole money path, end to end, exactly as it was proved open.
  begin
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state, decision_note, created_at)
    values ('refund_decision', 'refund:pccr007-self-verification', 'payments_and_billing_manager',
            'AED 10.00', jsonb_build_object('note','PCCR-007 self-verification, rolled back'),
            'pending', 'PCCR-007 self-verification', now())
    returning request_id into v_req;
    d := public.fn_kernel_refund_decision_record(jsonb_build_object(
           'op','record','request_id',v_req,'decision','approved',
           'reason','PCCR-007 self-verification: a refund approved by a connection that never logged in'));
    log := log || 'FORGED_REFUND_APPROVAL=ACCEPTED(' || left(d::text,80) || ')(WRONG) ';
    ok := false;
  exception when others then
    log := log || 'FORGED_REFUND_APPROVAL=REFUSED(' || sqlstate || ') ';
  end;

  -- 3. Nothing survived either attempt.
  log := log || '| refund_decisions=' || (select count(*) from public.phase_c_refund_decision)
             || ' approval_requests=' || (select count(*) from public.founder_approval_request)
             || ' refunds=' || (select count(*) from public.refunds) || ' ';
  if (select count(*) from public.phase_c_refund_decision) <> 0
     or (select count(*) from public.refunds) <> 0 then
    ok := false;
    log := log || '(RESIDUE)(WRONG) ';
  end if;

  perform set_config('request.jwt.claims', '', true);

  if not ok then
    raise exception 'PCCR007_FOUNDER_DOOR_FAILED | %', log using errcode = '23514';
  end if;
  raise notice 'PCCR007_FOUNDER_DOOR_VERIFIED | %', log;
end
$verify$;
