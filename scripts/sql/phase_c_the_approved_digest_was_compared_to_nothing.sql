-- THE APPROVED DIGEST WAS COMPARED TO NOTHING.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and one assertion block; rehearsable.
--
-- ================================================================================================
-- WHAT WAS MEASURED
-- ================================================================================================
--
-- PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 §B, FD-01 lines 5 and 9:
--
--     5 | no arbitrary amendment digest | any 64-hex string that is not the real
--       |                               | amendment-table digest → refused
--     9 | exact amendment digest        | the recorded digest equals the sha256 of the
--       |                               | amendment table the row names
--
-- Measured on the authenticated path with a verified founder bearer, against a change request that
-- does not exist so the call could not write:
--
--     approved_amendment_digest = repeat('a',64)  -> 23503 "no change request PCCR-999"
--     the real committed digest                   -> 23503 "no change request PCCR-999"
--
-- The identical refusal. The digest was checked for SHAPE in three places — `^[0-9a-f]{64}$` in
-- fn_phase_c_governance_decide §2, CHECK phase_c_governance_decision_digest_shape, and CHECK
-- phase_c_founder_auth_event_purpose_is_complete — and compared to nothing in any of them.
--
-- ================================================================================================
-- WHY THERE WAS NOTHING TO COMPARE IT TO, AND WHAT THERE IS
-- ================================================================================================
--
-- The obvious control is unavailable: the database cannot read the repository, so it cannot compute
-- the sha256 of docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-nnn.md and check the caller's claim
-- against it. That is why the only control that does compare them —
-- scripts/checks/pccr_approval_matches_committed_tables.test.mjs — is a repository check, and under
-- production-direct deployment a repository check does not run until the PR merges.
--
-- A new digest table would not help, because whatever can write the decision can write the table.
--
-- WHAT THE ESTATE ALREADY HOLDS IS BETTER THAN EITHER. public.founder_command_message stores the
-- founder's own words verbatim, with raw_text_hash = sha256(raw_text) recomputed on production,
-- z10_founder_command_message_immutable raising on UPDATE and DELETE, and no anon or authenticated
-- grant of any kind. When he approves a change request he types the digest into it — message 40674
-- reads:
--
--     "I approve PCCR-006 — governance_approval_authenticity — as set out in
--      docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md, sha256 c787bfcf…561ceb."
--
-- So the question "is this the digest of the document he approved?" has an answer inside the
-- database after all: **did he type this change request reference and this digest in the same
-- immutable message?** That is a stronger control than comparing to a file, because a file can be
-- edited after he read it — which PR #471 does, moving PCCR-006 from c787bfcf to 098f15d0 — while
-- his message cannot.
--
-- This file adds that comparison to public.fn_phase_c_governance_decide, which is NOT a frozen
-- subject (public.phase_c_frozen_subject does not name it).
--
-- ORDER MATTERS AND IS DELIBERATE. The unknown-change-request lookup stays FIRST, so an unknown ref
-- still reports as unknown rather than as an unquoted digest; the new check runs immediately after
-- it, before any event is minted, so a refused call leaves no session behind.
--
-- WHAT THIS DOES NOT COVER, STATED SO ITS SILENCE IS NOT READ AS COVERAGE.
-- public.phase_c_freeze_amendment.approved_amendment_table_digest is NOT given this check. The five
-- amendments recorded AUTHENTICATED_FOUNDER_SESSION carry 969830f0… — the digest of
-- docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md — and were approved on 22 Aug 2026 through
-- scripts/phase_d/approve_pccr_amendments.mjs, before the Command Center convention of quoting a
-- digest existed. Requiring a quoting message there would refuse writes that match five genuine
-- historical approvals. Those rows are instead protected by the immutability added in
-- phase_c_the_amendment_guard_only_watched_one_basis.sql, and by the repository check.

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
  v_msg     bigint;
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

  -- ---- 2b. THE DIGEST IS THE ONE HE QUOTED, NOT MERELY SIXTY-FOUR HEX CHARACTERS.
  -- public.founder_command_message is append-only, holds his words verbatim, recomputes its own
  -- sha256, and carries no anon or authenticated grant. A digest he never typed against this
  -- change request is a value a caller chose.
  select m.message_id into v_msg
    from public.founder_command_message m
    join public.phase_c_founder_identity f
      on f.identity = m.founder_identity and f.active and f.kind = 'email'
   where position(v_digest in lower(m.raw_text)) > 0
     and position(lower(v_ref) in lower(m.raw_text)) > 0
   order by m.received_at
   limit 1;
  if v_msg is null then
    raise exception 'fn_phase_c_governance_decide: no founder command message names both % and the digest %…. The founder approves the document he read, and public.founder_command_message is where his words are recorded immutably. A sixty-four character hex string that appears in none of them is a value this call chose, not a document he approved. (pccr007_governance_digest_never_quoted)',
      v_ref, left(v_digest,16) using errcode = '22023';
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
    'founder_message_id', v_msg,
    'prior_disposition', cr.disposition);
end
$function$;

-- ================================================================================================
-- SELF-VERIFICATION. Runs from this connection, which is session_user postgres, so §0 refuses every
-- call before §2b is reached — the connection guard is checked here and the digest guard is checked
-- by an independent authenticated probe recorded in the audit artifacts. What CAN be proved from
-- here without a bearer is the fact the new check rests on: that the founder's quoting message for
-- PCCR-006 exists, is attributable to an active founder identity, and recomputes its own hash.
-- ================================================================================================
do $verify$
declare n int; h boolean; log text := '';
begin
  select count(*) into n
    from public.founder_command_message m
    join public.phase_c_founder_identity f
      on f.identity = m.founder_identity and f.active and f.kind = 'email'
   where position('c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb' in lower(m.raw_text)) > 0
     and position('pccr-006' in lower(m.raw_text)) > 0;
  log := log || 'quoting_messages_for_PCCR-006=' || n || '; ';
  if n < 1 then
    raise exception 'PCCR007_DIGEST_GUARD_FAILED | the founder message quoting PCCR-006 and its digest was not found, so this check would refuse the approval that has already been given | %', log
      using errcode = '23514';
  end if;

  select bool_and(encode(sha256(convert_to(m.raw_text,'UTF8')),'hex') = m.raw_text_hash) into h
    from public.founder_command_message m;
  log := log || 'all_raw_text_hashes_recompute=' || h || '; ';
  if not h then
    raise exception 'PCCR007_DIGEST_GUARD_FAILED | a founder_command_message row does not recompute its own hash, so it is not the authority this check assumes | %', log
      using errcode = '23514';
  end if;

  select count(*) into n
    from public.founder_command_message m
   where position(repeat('a',64) in lower(m.raw_text)) > 0;
  log := log || 'messages_quoting_the_forged_digest=' || n || '; ';
  if n <> 0 then
    raise exception 'PCCR007_DIGEST_GUARD_FAILED | the sentinel digest used by the audit probes appears in a founder message | %', log
      using errcode = '23514';
  end if;

  raise notice 'PCCR007_DIGEST_GUARD_VERIFIED | %', log;
end
$verify$;
