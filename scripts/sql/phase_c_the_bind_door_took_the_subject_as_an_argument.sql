-- THE BIND DOOR TOOK THE SUBJECT AS AN ARGUMENT, AND THE GOVERNANCE DOOR COULD NOT WRITE.
--
-- NO TRANSACTION CONTROL. Two CREATE OR REPLACE-equivalents, one registry row, four grant
-- statements and one assertion block; rehearsable with a bare `node scripts/apply_sql.mjs <file>`.
--
-- Neither routine touched here is a frozen Phase C subject. public.phase_c_frozen_subject lists 25
-- objects; fn_phase_c_founder_subject_bind, fn_phase_c_governance_decide and
-- public.kernel_write_authority are not among them, so no PCCR amendment is raised by this file.
-- fn_phase_c_require_founder IS frozen and is NOT touched.
--
-- ================================================================================================
-- FINDING 1. THE GOVERNANCE DOOR HAS NEVER OPERATED.
-- ================================================================================================
--
-- public.phase_c_governance_decision holds 0 rows and public.phase_c_founder_auth_event holds 0,
-- measured 2026-08-27 11:44 UTC. PCCR-006 built fn_phase_c_governance_decide as the one canonical
-- governance-decision door and gave it, in step 4, an INSERT into public.phase_c_founder_auth_event.
-- That table carries z10_kernel_write_guard, and public.kernel_write_authority named exactly one
-- routine for it:
--
--     fn_phase_c_founder_subject_bind -> phase_c_founder_auth_event      (added 2026-08-21)
--
-- fn_kernel_write_guard reads the PL/pgSQL call stack and refuses any writer not on that register,
-- SQLSTATE 42501. So every call of fn_phase_c_governance_decide that got as far as minting its
-- purpose-bound session was refused by the estate's own write guard — which is why the ledger it
-- writes has never held a row, and why fn_phase_c_freeze_drift's
-- `approved_change_requests_with_no_verified_governance_decision` could never clear.
--
-- The fix is the registry row, not a grant of direct DML. Nothing is granted INSERT, UPDATE or
-- DELETE on phase_c_founder_auth_event by this file; the only change is that one more named routine
-- is recognised on the call stack, and that routine is the one PCCR-006 built for the purpose.
--
-- ================================================================================================
-- FINDING 2. THE BIND DOOR TOOK THE SUBJECT AS AN ARGUMENT.
-- ================================================================================================
--
-- The frozen-in-practice body of fn_phase_c_founder_subject_bind asked three questions:
--
--     session_user = 'authenticator'        -- closes management and migration connections
--     current_user <> 'anon'                -- closes the unauthenticated PostgREST role
--     p_subject resolves to an active row in public.phase_c_founder_identity
--
-- and never compared p_subject to the caller's OWN auth.uid(). proacl showed
-- `service_role=X/postgres`. PostgREST connects as `authenticator` and SET ROLEs, so a service_role
-- call to /rest/v1/rpc/fn_phase_c_founder_subject_bind carrying the founder's auth_user_id — a
-- value readable from the same table it validates against — bound his subject with no founder
-- bearer token in existence, and from there fn_kernel_refund_decision_record and
-- fn_phase_c_freeze_amendment_approve accepted it.
--
-- That is the shape PCCR-003, PCCR-006 and PCCR-007 each closed one connection at a time:
-- "resolves to a registered identity" is a spelling test, not authentication. The register is an
-- answer key, and service_role could read it.
--
-- It was raised as an open finding on 2026-08-26 and deliberately NOT USED, because driving a
-- founder-authority control by handing the door his own uuid is the impersonation the door exists
-- to stop.
--
-- CALLERS, MEASURED BEFORE THE CHANGE, not assumed:
--
--     grep -rn "founder_subject_bind" supabase/ scripts/ src/ docs/
--
-- returns supabase/schema/full_schema.sql (the mirror), three CHECK constraints that name the
-- string 'fn_phase_c_founder_subject_bind' as a permitted approval_route VALUE, six
-- scripts/checks/*.test.mjs files that call it from a management connection and ASSERT THAT IT
-- REFUSES, and scripts/phase_d/prove_founder_authentication.mjs which does the same. There is no
-- caller in supabase/functions and none in src/. os_api does not bind: it verifies the bearer token
-- with admin.auth.getUser and then builds asCaller(authHeader) — an anon-key client carrying the
-- verified user's own Authorization header — so PostgREST hands the database the subject IT
-- verified and auth.uid() resolves without any bind at all. Active production callers of the bind
-- door: 0. Nothing in his OS closes when service_role loses this grant.
--
-- THE FIX, four predicates and a grant change:
--
--   1. session_user must still be 'authenticator'      (unchanged; closes migration/management)
--   2. auth.uid() must be non-null                     (closes service_role and anon, both null)
--   3. the verified JWT role must be 'authenticated'   (closes service_role by name, with its own code)
--   4. p_subject must equal auth.uid()                 (THE ONE THAT WAS MISSING)
--   5. EXECUTE revoked from service_role, anon and PUBLIC; granted to authenticated only
--
-- The signature is kept. Predicate 4 makes the argument redundant rather than dangerous, and seven
-- committed check files plus three CHECK constraints name this exact identity; changing the
-- signature would rewrite them all to close a hole that predicate 4 already closes.
--
-- ================================================================================================

-- ---- 1. THE BIND DOOR ---------------------------------------------------------------------------
create or replace function public.fn_phase_c_founder_subject_bind(p_subject uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_id text; v_ev bigint; v_uid uuid; v_role text;
begin
  -- PCCR-006. THE POSITIVE CONDITION, NOT A DENY-LIST WITH NO THIRD ANSWER.
  -- 'anon' and 'authenticated' were named and 'postgres' was not, so migration SQL bound the
  -- founder's subject with no bearer token in existence. session_user is the connection role; SET
  -- ROLE cannot change it and postgres may not SET SESSION AUTHORIZATION on this project.
  if session_user <> 'authenticator' then
    raise exception 'fn_phase_c_founder_subject_bind: this is the server path. A founder subject may only be bound on the PostgREST connection that verified the bearer token (session_user authenticator); this call arrives as session_user % / current_user %. (pccr_founder_bind_untrusted_connection)',
      session_user, current_user using errcode = '28000';
  end if;

  -- 27 Aug 2026. THE CALLER MAY ONLY BIND ITSELF.
  -- The role check that stood here named 'anon' and stopped. service_role holds EXECUTE through
  -- PostgREST, arrives as session_user 'authenticator', and could hand this door the founder's own
  -- auth_user_id -- which is readable from public.phase_c_founder_identity, the very table this
  -- routine validates against. Knowing a uuid is not holding a session.
  -- AND IT IS NOT current_user THAT SAYS WHO THE CALLER IS. This routine is SECURITY DEFINER, so
  -- current_user is the OWNER — `postgres` — on every call, including anon's. The line that stood
  -- here, `if current_user = 'anon'`, could therefore never be true and had never refused anything;
  -- it was a guard on a condition that cannot occur. The role PostgREST switched to is in the JWT
  -- it verified, and that is what is read.
  v_role := coalesce(
    nullif(btrim(current_setting('request.jwt.claim.role', true)), ''),
    (nullif(btrim(current_setting('request.jwt.claims', true)), '')::jsonb ->> 'role'));
  if coalesce(v_role,'') <> 'authenticated' then
    raise exception 'fn_phase_c_founder_subject_bind: a founder subject is bound by an authenticated user session and by nothing else; this call presents JWT role %. service_role is a server key, not a person, and a key that can name any subject can name his. (pd_founder_bind_not_a_user_session)',
      coalesce(v_role,'(none)') using errcode = '42501';
  end if;

  begin v_uid := auth.uid(); exception when others then v_uid := null; end;
  if v_uid is null then
    raise exception 'fn_phase_c_founder_subject_bind: no verified auth subject on this call. The bind door records a session that already exists; it does not create one. (pd_founder_bind_no_verified_subject)'
      using errcode = '28000';
  end if;

  if p_subject is null then
    raise exception 'fn_phase_c_founder_subject_bind: a verified auth subject is required, and null is not one'
      using errcode = '28000';
  end if;

  -- THE PREDICATE THAT WAS MISSING. p_subject is now an ASSERTION about who the caller is, checked
  -- against the subject PostgREST verified, exactly as p_actor became an assertion in PCCR-003.
  if p_subject <> v_uid then
    raise exception 'fn_phase_c_founder_subject_bind: this call asks to bind subject % and the verified session belongs to %. A caller may bind itself and no one else. (pd_founder_bind_subject_is_not_the_caller)',
      p_subject, v_uid using errcode = '28000';
  end if;

  select f.identity into v_id
    from public.phase_c_founder_identity f
   where f.auth_user_id = p_subject and f.active and f.kind = 'email';
  if v_id is null then
    raise exception 'not the founder: auth subject % does not resolve to an enabled founder identity', p_subject
      using errcode = '28000';
  end if;

  insert into public.phase_c_founder_auth_event
    (auth_subject, identity, route, txid, bound_by)
  values (p_subject, v_id, 'server_verified_subject', txid_current(), current_user)
  returning event_id into v_ev;

  perform set_config('app.phase_c_founder_auth_event', v_ev::text, true);
  return jsonb_build_object('ok', true, 'identity', v_id, 'event_id', v_ev,
    'note','transaction-local; the verifier requires this event to name the current txid');
end
$function$;

-- CREATE OR REPLACE preserves the ACL, so these are not no-ops and the revokes mean what they say.
-- There is no PUBLIC grant on this routine today; the PUBLIC revoke is stated anyway because a
-- revoke from a named role is a silent no-op while the same privilege is held through PUBLIC, and
-- this file should not depend on that being true tomorrow.
revoke execute on function public.fn_phase_c_founder_subject_bind(uuid) from public;
revoke execute on function public.fn_phase_c_founder_subject_bind(uuid) from anon;
revoke execute on function public.fn_phase_c_founder_subject_bind(uuid) from service_role;
grant  execute on function public.fn_phase_c_founder_subject_bind(uuid) to authenticated;

-- ---- 2. THE GOVERNANCE DOOR'S WRITE AUTHORITY ---------------------------------------------------
insert into public.kernel_write_authority (routine_name, table_name, why)
values ('fn_phase_c_governance_decide', 'phase_c_founder_auth_event',
        'PCCR-006 made this the one canonical governance-decision door. It mints a purpose-bound, '
     || 'single-use founder auth event (action_class GOVERNANCE_DECISION, bound to the change '
     || 'request, the decision and the amendment-table digest), consumes it, and writes the '
     || 'immutable decision, all in one transaction. Without this row fn_kernel_write_guard refused '
     || 'the mint with 42501 and the door could never operate: phase_c_governance_decision held 0 '
     || 'rows from the day it was created until 2026-08-27. The authority is the registry row and '
     || 'not a grant -- no role holds INSERT, UPDATE or DELETE on phase_c_founder_auth_event, and '
     || 'a00_phase_c_founder_auth_event_is_server_minted still refuses any mint whose session_user '
     || 'is not authenticator and any event that does not name its own transaction.')
on conflict (routine_name, table_name) do nothing;

-- The governance door refuses service_role on its own terms already (auth.uid() is null there, and
-- the bind route it falls back to now requires an authenticated user session), but a server key
-- should not hold EXECUTE on a founder-authority control at all.
revoke execute on function public.fn_phase_c_governance_decide(jsonb) from public;
revoke execute on function public.fn_phase_c_governance_decide(jsonb) from anon;
revoke execute on function public.fn_phase_c_governance_decide(jsonb) from service_role;
grant  execute on function public.fn_phase_c_governance_decide(jsonb) to authenticated;

-- ---- 3. THE ASSERTIONS --------------------------------------------------------------------------
do $assert$
declare
  v_acl_bind text;
  v_acl_gov  text;
  v_auth     int;
  v_body     text;
begin
  select coalesce(array_to_string(proacl,' | '),'(default: PUBLIC)') into v_acl_bind
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='fn_phase_c_founder_subject_bind';
  select coalesce(array_to_string(proacl,' | '),'(default: PUBLIC)') into v_acl_gov
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='fn_phase_c_governance_decide';

  if v_acl_bind like '%service_role=X%' or v_acl_bind like '%anon=X%' then
    raise exception 'the bind door still grants a server or anonymous role: %', v_acl_bind;
  end if;
  if v_acl_bind not like '%authenticated=X%' then
    raise exception 'the bind door is not callable by an authenticated user session: %', v_acl_bind;
  end if;
  if v_acl_gov like '%service_role=X%' or v_acl_gov like '%anon=X%' then
    raise exception 'the governance door still grants a server or anonymous role: %', v_acl_gov;
  end if;
  if v_acl_gov not like '%authenticated=X%' then
    raise exception 'the governance door is not callable by an authenticated user session: %', v_acl_gov;
  end if;

  select count(*) into v_auth from public.kernel_write_authority
   where routine_name = 'fn_phase_c_governance_decide'
     and table_name   = 'phase_c_founder_auth_event';
  if v_auth <> 1 then
    raise exception 'fn_phase_c_governance_decide is not registered as a writer of phase_c_founder_auth_event (rows=%)', v_auth;
  end if;

  -- No role acquired direct DML on the protected table as a side effect of any of the above.
  if exists (select 1 from information_schema.role_table_grants
              where table_schema='public' and table_name='phase_c_founder_auth_event'
                and privilege_type in ('INSERT','UPDATE','DELETE')
                and grantee in ('anon','authenticated','service_role','PUBLIC')) then
    raise exception 'a role holds direct DML on phase_c_founder_auth_event; the authority is the registry row, not a grant';
  end if;

  select pg_get_functiondef(p.oid) into v_body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='fn_phase_c_founder_subject_bind';
  if position('pd_founder_bind_subject_is_not_the_caller' in v_body) = 0
     or position('pd_founder_bind_not_a_user_session' in v_body) = 0
     or position('pd_founder_bind_no_verified_subject' in v_body) = 0 then
    raise exception 'the live bind door does not carry the three new refusal codes';
  end if;

  raise notice 'OK  bind acl=%  governance acl=%  write_authority rows=%', v_acl_bind, v_acl_gov, v_auth;
end
$assert$;
