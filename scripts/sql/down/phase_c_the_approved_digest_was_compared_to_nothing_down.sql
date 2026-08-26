-- ROLLBACK for scripts/sql/phase_c_the_approved_digest_was_compared_to_nothing.sql
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE; rehearsable.
--
-- Restores public.fn_phase_c_governance_decide to the body PCCR-006 deployed on 2026-08-25, by
-- removing section 2b and the v_msg it uses. Everything else in the routine is unchanged, which is
-- why this file is generated from the forward file rather than retyped: the two differ only by the
-- block being reverted.
--
-- APPLYING THIS REOPENS ONE MEASURED HOLE. FD-01 lines 5 and 9 of
-- PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 require that a 64-hex string which is not the real
-- amendment digest be refused. Without section 2b the digest is checked for shape in three places
-- and compared to nothing, and repeat('a',64) reaches the same refusal as the real digest.

create or replace function public.fn_phase_c_governance_decide(p_input jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  cr        public.phase_c_change_request%rowtype;
  v_ref     text := nullif(btrim(coalesce(p_input->>'change_request_ref','')),'');
  v_dec     text := upper(nullif(btrim(coalesce(p_input->>'decision','')),''));
  v_digest  text := lower(nullif(btrim(coalesce(p_input->>'approved_amendment_digest','')),''));
  v_path    text := nullif(btrim(coalesce(p_input->>'amendment_table_path','')),'');
  v_reason  text := nullif(btrim(coalesce(p_input->>'reason','')),'');
  v_sub     uuid;
  v_id      text;
  v_route   text;
  v_nonce   text;
  v_ev      bigint;
  v_did     bigint;
  v_prior   public.phase_c_governance_decision%rowtype;
begin
  -- ---- 0. THE CONNECTION. A governance decision arrives on the connection that verifies tokens.
  if session_user <> 'authenticator' then
    raise exception 'fn_phase_c_governance_decide: a governance decision may only be recorded on the PostgREST connection that verified a founder bearer token (session_user authenticator); this call arrives as session_user %. Migration and management SQL cannot approve a Phase C change request, which is the defect PCCR-006 exists to close. (pccr_governance_untrusted_connection)',
      session_user using errcode = '28000';
  end if;

  -- ---- 1. THE VERIFIED FOUNDER. Nothing here is read from p_input.
  begin v_sub := auth.uid(); exception when others then v_sub := null; end;
  if v_sub is not null then
    v_route := 'auth.uid()';
  else
    v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
    select e.auth_subject into v_sub from public.phase_c_founder_auth_event e
     where e.event_id = v_ev and e.txid = txid_current() and e.action_class is null;
    v_route := 'fn_phase_c_founder_subject_bind';
  end if;
  if v_sub is null then
    raise exception 'fn_phase_c_governance_decide: no verified auth subject on this call. A caller-supplied email, auth subject or route label is not authentication, and neither is a written instruction. (pccr_governance_no_verified_session)'
      using errcode = '28000',
            hint = 'Call /rest/v1/rpc/fn_phase_c_governance_decide with the founder''s bearer token.';
  end if;
  select f.identity into v_id from public.phase_c_founder_identity f
   where f.auth_user_id = v_sub and f.active and f.kind = 'email';
  if v_id is null then
    raise exception 'not the founder: auth subject % does not resolve to an enabled founder identity (pccr_governance_not_the_founder)',
      v_sub using errcode = '28000';
  end if;

  -- ---- 2. THE CALL NAMES EXACTLY WHAT IT DECIDES.
  if v_ref is null or v_dec is null or v_digest is null or v_path is null or v_reason is null then
    raise exception 'fn_phase_c_governance_decide: change_request_ref, decision, approved_amendment_digest, amendment_table_path and reason are all required (got %, %, %, %, %) (pccr_governance_incomplete_call)',
      coalesce(v_ref,'(none)'), coalesce(v_dec,'(none)'),
      coalesce(left(v_digest,12),'(none)'), coalesce(v_path,'(none)'),
      case when v_reason is null then '(none)' else '(given)' end using errcode = '22023';
  end if;
  if p_input ?| array['approved_by','approved_at','approval_basis','approval_route',
                      'approval_auth_subject','disposition','decided_by'] then
    raise exception 'fn_phase_c_governance_decide: approved_by, approved_at, the approval basis, the route, the auth subject and the disposition are DERIVED from the verified session and may not be supplied. A call that states who approved it is stating a conclusion. (pccr_governance_caller_supplied_approval)'
      using errcode = '22023';
  end if;
  if v_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'fn_phase_c_governance_decide: approved_amendment_digest must be the sha256 of the committed amendment table; got % (pccr_governance_bad_digest)',
      left(coalesce(v_digest,'(none)'),20) using errcode = '22023';
  end if;

  select * into cr from public.phase_c_change_request where change_request_ref = v_ref;
  if not found then
    raise exception 'fn_phase_c_governance_decide: no change request % (pccr_governance_unknown_change_request)', v_ref
      using errcode = '23503';
  end if;


  -- ---- 3. REPLAY IS IDEMPOTENT AND MAKES NO SECOND ROW.
  select * into v_prior from public.phase_c_governance_decision
   where change_request_ref = v_ref and decision = v_dec
     and approved_amendment_table_digest = v_digest;
  if found then
    return jsonb_build_object('ok', true, 'outcome','ALREADY_DECIDED',
      'decision_id', v_prior.decision_id, 'change_request_ref', v_ref, 'decision', v_dec,
      'decided_by', v_prior.decided_by, 'decided_at', v_prior.decided_at,
      'note','this door is idempotent and does not restamp a decision it has already recorded');
  end if;

  -- ---- 4. THE PURPOSE-BOUND, SINGLE-USE SESSION. Minted and spent inside this transaction, so a
  -- failure between minting and writing cannot leave a reusable session behind.
  v_nonce := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.phase_c_founder_auth_event
    (auth_subject, identity, route, txid, bound_by,
     action_class, object_ref, decision, amendment_table_digest, nonce, issued_at, expires_at)
  values (v_sub, v_id, 'server_verified_subject', txid_current(), current_user,
          'GOVERNANCE_DECISION', v_ref, v_dec, v_digest, v_nonce, now(), now() + interval '5 minutes')
  returning event_id into v_ev;

  update public.phase_c_founder_auth_event
     set consumed_at = now(), consumed_by = 'fn_phase_c_governance_decide'
   where event_id = v_ev;

  -- ---- 5. THE APPEND-ONLY DECISION. Its own trigger re-reads the event and refuses a mismatch.
  insert into public.phase_c_governance_decision
    (change_request_ref, decision, approval_reason, approved_amendment_table_path,
     approved_amendment_table_digest, decided_by, approval_basis, approval_route,
     approval_auth_subject, auth_event_id, nonce, txid)
  values (v_ref, v_dec, v_reason, v_path, v_digest, v_id, 'AUTHENTICATED_FOUNDER_SESSION',
          v_route, v_sub, v_ev, v_nonce, txid_current())
  returning decision_id into v_did;

  return jsonb_build_object('ok', true, 'outcome','DECIDED_IN_VERIFIED_SESSION',
    'decision_id', v_did, 'change_request_ref', v_ref, 'decision', v_dec,
    'decided_by', v_id, 'approval_route', v_route, 'approval_auth_subject', v_sub,
    'approved_amendment_table_path', v_path,
    'approved_amendment_table_digest', v_digest,
    'auth_event_id', v_ev,
    'prior_disposition', cr.disposition);
end
$function$;
