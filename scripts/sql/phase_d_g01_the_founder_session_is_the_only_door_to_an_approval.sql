-- G01 — an approval that no migration can write, and that names the document it approves
--
-- THE BOARD ALREADY SAYS WHAT IS MISSING, and says it exactly:
--
--   amendments_awaiting_founder_approval             4 of 5 (PCCR-001, PCCR-002, PCCR-003)
--   amendments_approved_on_written_instruction_only  1 of 5 (PCCR-003)
--       "Cleared only by re-approval through a verified auth subject, which no migration can
--        perform."
--
-- That last clause is the whole design and it is already half true: public.phase_c_freeze_amendment
-- carries a10_freeze_amendment_approver_is_the_founder, and approval_basis is constrained to
-- AUTHENTICATED_FOUNDER_SESSION or WRITTEN_INSTRUCTION. What is missing is a DOOR: a routine that
-- can only run inside a verified founder session, so that the approval is produced by
-- authentication rather than asserted by whoever holds a database connection.
--
-- WHAT THIS FILE ADDS, AND WHY EACH PIECE IS HERE.
--
-- 1. Five columns, all nullable, all additive:
--      deployed_before_approval          section 1 requires this stated, not implied
--      original_deployment_at            when the code actually reached production
--      approval_route                    auth.uid() or the server bind path — which one authenticated
--      approval_auth_subject             the auth.users id that was verified
--      approved_amendment_table_digest   sha256 of the amendment tables the approval is based on
--    DOWN: one `alter table public.phase_c_freeze_amendment drop column ...` per column plus the two
--    constraints below. No data loss beyond the approval metadata itself. Recorded in the Phase D
--    rollback classification as ADDITIVE_WITH_EXPLICIT_DOWN.
--
-- 2. fn_phase_c_freeze_amendment_approve(jsonb). Its FIRST statement is
--    fn_phase_c_require_founder(null), which raises 28000 unless auth.uid() resolves to an active
--    founder identity or os_api bound a subject it verified in this same transaction. A migration
--    running as the owner has neither, so a migration cannot call it — which is what the board
--    already promised.
--
--    approved_by is taken from the VERIFIED identity the resolver returns and never from the input.
--    A caller may not name an approver; that is E39's vector and it stays closed.
--
-- 3. ONE AMENDMENT PER CALL. The founder's instruction is "Do not combine or rewrite the
--    amendments" and "Do not bundle four amendments into one approval sentence". The routine takes
--    a scalar amendment_id and refuses any plural key, and it makes the caller restate the change
--    request, the subject and the new digest of the row being approved — so an approval aimed at
--    amendment 1 cannot land on amendment 2 because the id was mistyped.
--
-- 4. THE DOCUMENT IS PART OF THE APPROVAL. "Approval is based on the exact amendment tables
--    committed in PHASE_D_PCCR_AMENDMENT_TABLES.md." The digest of that file is recorded on the
--    row. It is NOT hard-coded here: a constant typed into the routine that checks it proves
--    nothing about the file. scripts/checks/pccr_approval_matches_committed_tables.test.mjs hashes
--    the committed file and compares, so drift is caught by the repository against the database
--    rather than by the database against itself.
--
-- 5. WRITTEN_INSTRUCTION MAY BE UPGRADED, NEVER THE REVERSE. Amendment 36 (PCCR-003) carries a
--    written-instruction approval from 21 Aug 2026. Re-approval through this door replaces the
--    basis and records what it was before; this routine never writes WRITTEN_INSTRUCTION at all,
--    so the movement is one-way by construction rather than by a rule someone must remember.

alter table public.phase_c_freeze_amendment
  add column if not exists deployed_before_approval        boolean,
  add column if not exists original_deployment_at          timestamptz,
  add column if not exists approval_route                  text,
  add column if not exists approval_auth_subject           uuid,
  add column if not exists approved_amendment_table_digest text;

comment on column public.phase_c_freeze_amendment.deployed_before_approval is
  'G01: true when the amended object was already live on production when the founder approved it. Stated, never inferred: the founder asked for retrospective ratification to be recorded as what it is.';
comment on column public.phase_c_freeze_amendment.original_deployment_at is
  'G01: when the amended body actually reached production, which is not when it was approved.';
comment on column public.phase_c_freeze_amendment.approval_route is
  'G01: which of the two founder-authentication routes carried this approval — auth.uid() for a bearer PostgREST verified, or fn_phase_c_founder_subject_bind for a subject os_api verified.';
comment on column public.phase_c_freeze_amendment.approval_auth_subject is
  'G01: the auth.users id that was verified. A record of WHO authenticated, not of who was named.';
comment on column public.phase_c_freeze_amendment.approved_amendment_table_digest is
  'G01: sha256 of docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md as the approval was given against it. Compared with the committed file by scripts/checks/pccr_approval_matches_committed_tables.test.mjs.';

alter table public.phase_c_freeze_amendment
  drop constraint if exists phase_c_freeze_amendment_approval_route_values;
alter table public.phase_c_freeze_amendment
  add constraint phase_c_freeze_amendment_approval_route_values
  check (approval_route is null
         or approval_route in ('auth.uid()', 'fn_phase_c_founder_subject_bind', 'written_instruction'));

alter table public.phase_c_freeze_amendment
  drop constraint if exists phase_c_freeze_amendment_session_approval_names_its_route;
alter table public.phase_c_freeze_amendment
  add constraint phase_c_freeze_amendment_session_approval_names_its_route
  check (approval_basis is distinct from 'AUTHENTICATED_FOUNDER_SESSION'
         or (approval_route in ('auth.uid()','fn_phase_c_founder_subject_bind')
             and approval_auth_subject is not null
             and approved_amendment_table_digest ~ '^[0-9a-f]{64}$'));

CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_amendment_approve(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a          public.phase_c_freeze_amendment%rowtype;
  v_identity text;
  v_sub      uuid;
  v_route    text;
  v_ev       bigint;
  v_id       bigint;
  v_prior    text;
begin
  -- THE DOOR. Nothing below runs without a verified founder on this transaction: the resolver
  -- raises 28000 for a service_role connection, for a typed email, and for a bound event that
  -- belongs to some other transaction.
  v_identity := public.fn_phase_c_require_founder(null);

  -- Which route carried it. Re-derived here rather than returned by the resolver, because the row
  -- must record HOW the founder was authenticated and not merely that something said he was.
  begin v_sub := auth.uid(); exception when others then v_sub := null; end;
  if v_sub is not null then
    v_route := 'auth.uid()';
  else
    v_ev := nullif(btrim(current_setting('app.phase_c_founder_auth_event', true)),'')::bigint;
    select e.auth_subject into v_sub from public.phase_c_founder_auth_event e
     where e.event_id = v_ev and e.txid = txid_current();
    v_route := 'fn_phase_c_founder_subject_bind';
  end if;
  if v_sub is null then
    raise exception 'fn_phase_c_freeze_amendment_approve: the founder resolved to % and no auth subject can be named for the call. An approval that cannot say who authenticated is not a session approval. (pccr_approval_subject_unnameable)',
      v_identity using errcode = '28000';
  end if;

  -- ONE AMENDMENT PER CALL. The founder's instruction is that these are approved individually.
  if p_input ?| array['amendment_ids','amendments','change_request_refs'] then
    raise exception 'fn_phase_c_freeze_amendment_approve: this routine approves exactly one amendment per call. Bundling is what the founder refused: "Do not combine or rewrite the amendments." (pccr_approval_bundled)'
      using errcode = '22023';
  end if;
  v_id := nullif(btrim(coalesce(p_input->>'amendment_id','')),'')::bigint;
  if v_id is null then
    raise exception 'fn_phase_c_freeze_amendment_approve: amendment_id is required (pccr_approval_no_amendment)'
      using errcode = '22023';
  end if;

  select * into a from public.phase_c_freeze_amendment where amendment_id = v_id;
  if not found then
    raise exception 'fn_phase_c_freeze_amendment_approve: no amendment % (pccr_approval_unknown_amendment)', v_id
      using errcode = '23503';
  end if;

  -- THE APPROVAL NAMES WHAT IT APPROVES. A mistyped id lands on a different amendment silently
  -- unless the call also restates the change request, the subject and the digest being adopted.
  if coalesce(nullif(btrim(p_input->>'change_request_ref'),''),'') is distinct from a.change_request_ref
     or coalesce(nullif(btrim(p_input->>'subject'),''),'')          is distinct from a.subject
     or coalesce(nullif(btrim(p_input->>'new_digest'),''),'')       is distinct from a.new_digest then
    raise exception 'fn_phase_c_freeze_amendment_approve: amendment % is (%, %, new_digest %) and the call names (%, %, %). An approval must name the exact amendment it approves. (pccr_approval_names_a_different_amendment)',
      v_id, a.change_request_ref, a.subject, a.new_digest,
      coalesce(p_input->>'change_request_ref','(none)'), coalesce(p_input->>'subject','(none)'),
      coalesce(p_input->>'new_digest','(none)') using errcode = '22023';
  end if;

  if coalesce(p_input->>'amendment_table_digest','') !~ '^[0-9a-f]{64}$' then
    raise exception 'fn_phase_c_freeze_amendment_approve: amendment_table_digest must be the sha256 of the amendment tables the approval is based on; got %. (pccr_approval_no_document_digest)',
      coalesce(nullif(p_input->>'amendment_table_digest',''),'(none)') using errcode = '22023';
  end if;

  if (p_input->>'deployed_before_approval') is null then
    raise exception 'fn_phase_c_freeze_amendment_approve: deployed_before_approval must be stated true or false. Whether the code was already live when it was approved is a fact about this approval, not a detail to leave blank. (pccr_approval_deployment_order_unstated)'
      using errcode = '22023';
  end if;
  if (p_input->>'deployed_before_approval')::boolean
     and nullif(btrim(p_input->>'original_deployment_at'),'') is null then
    raise exception 'fn_phase_c_freeze_amendment_approve: amendment % is recorded as deployed before approval and the call names no original_deployment_at. A retrospective ratification that cannot say when the code shipped is not a record of anything. (pccr_approval_deployment_time_missing)',
      v_id using errcode = '22023';
  end if;

  -- ALREADY APPROVED THROUGH THIS DOOR: idempotent, and it does not restamp the time.
  if a.approval_basis = 'AUTHENTICATED_FOUNDER_SESSION' then
    if lower(a.approved_by) is distinct from lower(v_identity) then
      raise exception 'fn_phase_c_freeze_amendment_approve: amendment % is already approved in a verified session by % and % may not overwrite that record. (pccr_approval_would_overwrite_another_founder)',
        v_id, a.approved_by, v_identity using errcode = '23514';
    end if;
    return jsonb_build_object('ok', true, 'amendment_id', v_id, 'outcome','ALREADY_APPROVED',
      'approved_by', a.approved_by, 'approved_at', a.approved_at, 'approval_basis', a.approval_basis,
      'note','this door is idempotent and does not restamp an approval it has already recorded');
  end if;

  v_prior := coalesce(a.approval_basis, '(unapproved)');

  update public.phase_c_freeze_amendment
     set approved_by                      = v_identity,     -- THE VERIFIED IDENTITY, never the input
         approved_at                      = now(),
         approval_basis                   = 'AUTHENTICATED_FOUNDER_SESSION',
         approval_route                   = v_route,
         approval_auth_subject            = v_sub,
         approved_amendment_table_digest  = lower(btrim(p_input->>'amendment_table_digest')),
         deployed_before_approval         = (p_input->>'deployed_before_approval')::boolean,
         original_deployment_at           = nullif(btrim(p_input->>'original_deployment_at'),'')::timestamptz
   where amendment_id = v_id;

  return jsonb_build_object(
    'ok', true, 'amendment_id', v_id,
    'outcome', case when v_prior = 'WRITTEN_INSTRUCTION' then 'REAFFIRMED_IN_VERIFIED_SESSION'
                    else 'APPROVED_IN_VERIFIED_SESSION' end,
    'prior_approval_basis', v_prior,
    'change_request_ref', a.change_request_ref, 'subject', a.subject,
    'approved_by', v_identity, 'approval_route', v_route, 'approval_auth_subject', v_sub,
    'approval_type', case when (p_input->>'deployed_before_approval')::boolean
                          then 'retrospective founder ratification' else 'prospective approval' end,
    'original_deployment_at', nullif(btrim(p_input->>'original_deployment_at'),'')::timestamptz,
    'amendment_table_digest', lower(btrim(p_input->>'amendment_table_digest')));
end
$function$;

revoke all on function public.fn_phase_c_freeze_amendment_approve(jsonb) from public;
revoke all on function public.fn_phase_c_freeze_amendment_approve(jsonb) from anon;
-- The founder's own bearer arrives as `authenticated`. That grant is the point of the routine: the
-- resolver inside it refuses every authenticated caller who is not the founder, which is a narrower
-- door than any table grant would be.
grant execute on function public.fn_phase_c_freeze_amendment_approve(jsonb) to authenticated;
grant execute on function public.fn_phase_c_freeze_amendment_approve(jsonb) to service_role;
