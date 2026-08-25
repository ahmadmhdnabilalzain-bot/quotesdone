-- PCCR-006 — GOVERNANCE APPROVAL AUTHENTICITY — ROLLBACK.
--
-- TRANSACTION_NEUTRAL. This file carries NO transaction control of its own — no BEGIN, no COMMIT,
-- no ROLLBACK — so a caller who wraps it in "begin; … rollback;" gets a rehearsal and not a
-- deployment. Four Phase D down scripts did carry their own COMMIT and the independent audit of
-- 24 Aug 2026 deployed them by accident while rehearsing; that is why this is stated here.
--
-- The four routine bodies below were read out of production with pg_get_functiondef immediately
-- before PCCR-006 was written, and their sha256 digests are recorded beside them. Restoring is
-- therefore re-applying the DEPLOYED body, not a body retyped from a document.
--
--   fn_phase_c_require_founder(p_actor text)                        e0f8f63e14238a8319ea79b401c57ba4c81380a8aac6baa176e4c165eb20cabc
--   fn_phase_c_founder_subject_bind(p_subject uuid)                 e119c18c53788c0ef91352cebd4e01ececbd599239742d0bac7023ff0d4685e4
--   fn_phase_c_change_request_disposition_follows_approval()        d58329f04c9d3556d25e2a96d553ab1da24e0a4c22b4d4fcdf0a86127de75cce
--   fn_phase_c_freeze_drift()                                       44d3253af459f7e94c2e7a2bcf36e4ad6ff5a5d7c9e606e7b8acb70fed372b72
--
-- WHAT THIS ROLLBACK COSTS, STATED PLAINLY. It restores the estate to the state the independent
-- audit measured and failed on Gate 1: a migration can write an approver onto a DEFERRED change
-- request and the trigger will silently re-disposition it to APPROVED, and a migration can mint a
-- founder auth event with no bearer token in existence. Rolling back is not neutral; it is a
-- decision to reopen those paths.
--
-- WHAT IT DOES NOT DESTROY. public.phase_c_governance_decision is dropped, and with it any recorded
-- governance decision. Run the SELECT at the foot of this file FIRST and keep its output: after the
-- drop the ledger cannot be reconstructed, because the auth events that backed it are dropped with
-- their purpose columns. If any row exists, this rollback is a DATA_PURGE and needs the founder.

-- ---- 0. WHAT WOULD BE LOST. Read this before running anything below. ---------------------------
--   select * from public.phase_c_governance_decision order by decision_id;

-- ---- 1. THE DERIVED APPROVAL COLUMNS AND THEIR GUARD -------------------------------------------
DROP TRIGGER IF EXISTS a05_phase_c_change_request_approval_is_derived
  ON public.phase_c_change_request;
DROP FUNCTION IF EXISTS public.fn_phase_c_change_request_approval_is_derived();

ALTER TABLE public.phase_c_change_request
  DROP CONSTRAINT IF EXISTS phase_c_change_request_approval_is_derived,
  DROP CONSTRAINT IF EXISTS phase_c_change_request_approval_reason_only_on_approval;

ALTER TABLE public.phase_c_change_request
  DROP COLUMN IF EXISTS governance_decision_id,
  DROP COLUMN IF EXISTS approved_amendment_table_digest,
  DROP COLUMN IF EXISTS approval_auth_subject,
  DROP COLUMN IF EXISTS approval_route,
  DROP COLUMN IF EXISTS approval_basis,
  DROP COLUMN IF EXISTS approval_reason;

-- ---- 2. THE LEDGER -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS z10_phase_c_governance_decision_applies ON public.phase_c_governance_decision;
DROP TRIGGER IF EXISTS a00_phase_c_governance_decision_is_session_backed ON public.phase_c_governance_decision;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_governance_decision;
DROP FUNCTION IF EXISTS public.fn_phase_c_governance_decision_applies();
DROP FUNCTION IF EXISTS public.fn_phase_c_governance_decision_is_session_backed();
DROP FUNCTION IF EXISTS public.fn_phase_c_governance_decide(jsonb);
DROP TABLE IF EXISTS public.phase_c_governance_decision;

-- ---- 3. THE FREEZE-AMENDMENT SESSION-CLAIM GUARD -----------------------------------------------
DROP TRIGGER IF EXISTS a05_freeze_amendment_session_claim_is_verified
  ON public.phase_c_freeze_amendment;
DROP FUNCTION IF EXISTS public.fn_phase_c_freeze_amendment_session_claim_is_verified();
ALTER TABLE public.phase_c_freeze_amendment
  DROP CONSTRAINT IF EXISTS phase_c_freeze_amendment_approval_names_its_document;
ALTER TABLE public.phase_c_freeze_amendment
  DROP COLUMN IF EXISTS approved_amendment_table_path;

-- ---- 4. THE AUTH EVENT RETURNS TO A PLAIN RECORD ------------------------------------------------
DROP TRIGGER IF EXISTS a00_phase_c_founder_auth_event_is_server_minted
  ON public.phase_c_founder_auth_event;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_founder_auth_event;
DROP FUNCTION IF EXISTS public.fn_phase_c_founder_auth_event_is_server_minted();
DROP INDEX IF EXISTS public.phase_c_founder_auth_event_nonce_uk;
ALTER TABLE public.phase_c_founder_auth_event
  DROP CONSTRAINT IF EXISTS phase_c_founder_auth_event_purpose_is_complete,
  DROP CONSTRAINT IF EXISTS phase_c_founder_auth_event_consumption_follows_issue;
ALTER TABLE public.phase_c_founder_auth_event
  DROP COLUMN IF EXISTS consumed_by,
  DROP COLUMN IF EXISTS consumed_at,
  DROP COLUMN IF EXISTS expires_at,
  DROP COLUMN IF EXISTS issued_at,
  DROP COLUMN IF EXISTS nonce,
  DROP COLUMN IF EXISTS amendment_table_digest,
  DROP COLUMN IF EXISTS decision,
  DROP COLUMN IF EXISTS object_ref,
  DROP COLUMN IF EXISTS action_class;

-- ---- 5. THE FOUR ROUTINE BODIES, RESTORED VERBATIM ---------------------------------------------

-- fn_phase_c_require_founder(p_actor text)  sha256 e0f8f63e14238a8319ea79b401c57ba4c81380a8aac6baa176e4c165eb20cabc
CREATE OR REPLACE FUNCTION public.fn_phase_c_require_founder(p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sub    uuid;
  v_id     text;
  v_ev     bigint;
  v_route  text;
begin
  -- ---- ROUTE A: a bearer token PostgREST already verified -------------------------------------
  -- auth.uid() is null for a service_role connection and for anything that did not arrive with a
  -- user JWT. It cannot be set by a caller.
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

-- fn_phase_c_founder_subject_bind(p_subject uuid)  sha256 e119c18c53788c0ef91352cebd4e01ececbd599239742d0bac7023ff0d4685e4
CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_subject_bind(p_subject uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id text; v_ev bigint;
begin
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_c_founder_subject_bind: % may not bind a founder subject; this is the server path (pd_founder_bind_untrusted_caller)',
      current_user using errcode = '42501';
  end if;
  if p_subject is null then
    raise exception 'fn_phase_c_founder_subject_bind: a verified auth subject is required, and null is not one'
      using errcode = '28000';
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

-- fn_phase_c_change_request_disposition_follows_approval()  sha256 d58329f04c9d3556d25e2a96d553ab1da24e0a4c22b4d4fcdf0a86127de75cce
CREATE OR REPLACE FUNCTION public.fn_phase_c_change_request_disposition_follows_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.approved_by is not null and (TG_OP = 'INSERT' or OLD.approved_by is null) then
    NEW.disposition := 'APPROVED';
    if coalesce(NEW.disposition_reason,'') = '' then
      NEW.disposition_reason := format('Approved by %s. Disposition set by '
        || 'a15_phase_c_change_request_disposition_follows_approval: an approved request is not a '
        || 'deferred one, and the two columns may not disagree.', NEW.approved_by);
    end if;
    NEW.disposition_recorded_at := coalesce(NEW.disposition_recorded_at, NEW.approved_at, now());
  elsif TG_OP = 'UPDATE' and NEW.approved_by is null and OLD.approved_by is not null then
    -- The reverse, or the CHECK could still be walked into: an APPROVED row whose approver is
    -- cleared would be an approval nobody gave.
    NEW.disposition := 'RAISED';
    NEW.disposition_reason := null;
    NEW.disposition_recorded_at := null;
  end if;
  return NEW;
end $function$;

-- fn_phase_c_freeze_drift()  sha256 44d3253af459f7e94c2e7a2bcf36e4ad6ff5a5d7c9e606e7b8acb70fed372b72
CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_drift()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  with live as (
    select f.subject, f.object_identity, f.digest as frozen,
           case
             when f.object_kind = 'routine' then (
               select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public'
                  and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
                      = f.object_identity)
             when f.object_kind = 'table' and f.object_identity = 'public.phase_c_component' then (
               select encode(sha256(convert_to(string_agg(
                 c.component_id || '|' || coalesce(c.component_type,'') || '|' || coalesce(c.workflow_id,'')
                   || '|' || coalesce(c.step_id,'') || '|' || coalesce(c.accountable_role_id,'')
                   || '|' || coalesce(c.canonical_system_actor,'') || '|' || coalesce(c.authority_class,'')
                   || '|' || coalesce(c.trace_policy_id,'') || '|' || coalesce(c.activation_state,'')
                   || '|' || coalesce(c.classification,'') || '|' || coalesce(c.mutates_state::text,''),
                 chr(10) order by c.component_id),'UTF8')),'hex')
                 from public.phase_c_component c)
             else f.digest   -- repository_file subjects are checked in CI, not here; never silently green
           end as now_digest
      from public.phase_c_frozen_subject f
  ), judged as (
    -- D49. A live digest is undrifted when it matches the frozen baseline, OR when a recorded
    -- amendment carries BOTH the frozen baseline as its prior digest AND this body as its new one.
    -- An unrecorded edit is drift. An edit on top of an amendment is drift, because its prior digest
    -- no longer matches. Overwriting phase_c_frozen_subject.digest would have made both invisible.
    --
    -- E13 required the amendment to name a Phase C change request. E23 makes that reference a
    -- foreign key to public.phase_c_change_request, so an amendment can no longer point at a
    -- document nobody wrote.
    select l.*,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest
                      and coalesce(btrim(a.change_request_ref),'') <> '') as amended
      from live l
  )
  select 'frozen_subjects_drifted', '0',
         count(*) filter (where now_digest is distinct from frozen and not amended)::text
           || ' of ' || count(*)::text,
         count(*) filter (where now_digest is distinct from frozen and not amended) = 0
    from judged
  union all
  select 'frozen_subjects_whose_object_no_longer_exists', '0',
         count(*) filter (where now_digest is null)::text || ' of ' || count(*)::text,
         count(*) filter (where now_digest is null) = 0
    from judged
  union all
  select 'frozen_subjects_changed_under_a_recorded_amendment', 'informational',
         count(*) filter (where amended)::text || ' of ' || count(*)::text, true
    from judged
  union all
  -- E23 REPLACES frozen_subjects_changed_with_no_change_request, WHICH COULD NOT FIRE.
  -- That row tested btrim(change_request_ref) = '' on a column that is NOT NULL and shape-checked,
  -- so it read 0 of 25 whatever anyone did. The R3 acceptance named it, correctly, as a green tick
  -- measuring nothing. What is checkable is whether the MECHANISM is still in place, and this row
  -- goes red the moment any of the three constraints is dropped.
  select 'change_request_reference_is_enforced', '3',
         -- The three are counted into ONE number. An earlier draft printed the two constraints as
         -- "2 of 3" and reported the NOT NULL separately, which read as a failing check sitting
         -- next to a green tick — the precise confusion this row exists to end.
         ((select count(*) from pg_constraint
            where conrelid = 'public.phase_c_freeze_amendment'::regclass
              and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                              'phase_c_freeze_amendment_change_request_fk'))
          + (select count(*) from information_schema.columns
              where table_schema='public' and table_name='phase_c_freeze_amendment'
                and column_name='change_request_ref' and is_nullable='NO'))::text
         || ' of 3 (shape check, foreign key to phase_c_change_request, NOT NULL)',
         (select count(*) from pg_constraint
           where conrelid = 'public.phase_c_freeze_amendment'::regclass
             and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                             'phase_c_freeze_amendment_change_request_fk')) = 2
         and (select count(*) from information_schema.columns
               where table_schema='public' and table_name='phase_c_freeze_amendment'
                 and column_name='change_request_ref' and is_nullable='NO') = 1
  union all
  select 'amendments_whose_change_request_is_unregistered', '0',
         (select count(*)::text from public.phase_c_freeze_amendment a
           where not exists (select 1 from public.phase_c_change_request cr
                              where cr.change_request_ref = a.change_request_ref))
         || ' of ' || (select count(*)::text from public.phase_c_freeze_amendment),
         not exists (select 1 from public.phase_c_freeze_amendment a
                      where not exists (select 1 from public.phase_c_change_request cr
                                         where cr.change_request_ref = a.change_request_ref))
  union all
  -- E34. THIS ROW'S ok WAS THE LITERAL true, AND IT READ 4 of 4.
  --
  -- Its own comment was candid - "Reported, never used. A change request that has been WRITTEN is
  -- not one that has been APPROVED" - and the consequence stood anyway: four amendments to frozen
  -- Phase C kernel contracts are live in production, unapproved, under a fully green board. The
  -- independent acceptance named it as the same species this estate keeps finding, a board row
  -- whose ok is a constant, and scored it LOW because it was disclosed. Disclosed in a comment is
  -- not disclosed on the board.
  --
  -- It is now a REAL RED, and it goes green the moment the founder signs. That is the right colour
  -- because the condition is genuinely unmet: an amendment to a frozen contract is not complete
  -- until the person who froze it has approved the change. Nothing here can clear it and nothing
  -- here should be able to - approved_by and approved_at are constrained to move as a pair, and a
  -- builder writing his own name into them would be the whole defect this row exists to surface.
  --
  -- 'expected' is now 0 rather than the word 'informational', so a reader comparing expected with
  -- actual sees the gap instead of a label that excuses it.
  -- E38. THIS ASKED `approved_by is null`, WHICH IS A QUESTION ABOUT A STORED STRING.
  -- An acceptance auditor added itself to public.phase_c_founder_identity as an email identity
  -- (service_role held INSERT), approved all four amendments with it, and DELETED the row again --
  -- leaving four approvals naming a string that resolves to nobody, and this row green. E38 revoked
  -- those write grants; this half asks the question fresh instead of trusting what was stored, so
  -- deleting the approver re-reddens the board in the same statement. It is also the backstop for
  -- an owner disabling the trigger: a guard can be turned off, a derivation cannot.
  select 'amendments_awaiting_founder_approval', '0',
         (select count(*) from public.phase_c_freeze_amendment a
           where a.approved_by is null
              or not exists (select 1 from public.phase_c_founder_identity fi
                              where fi.active
                                and lower(btrim(fi.identity)) = lower(btrim(a.approved_by))))::text
           || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
           || ' await the founder (change requests named: '
           || (select coalesce(string_agg(distinct change_request_ref, ', '),'(none)')
                 from public.phase_c_freeze_amendment)
           -- E36. THIS SAID "Only he can clear this row." and nothing enforced it: approved_by was
           -- free text, and the acceptance auditor cleared all four with 'zz-r5-audit-not-the-founder'
           -- in one statement, turning the whole freeze board green. The trigger
           -- a10_freeze_amendment_approver_is_the_founder now refuses any approver that does not
           -- resolve to an ACTIVE row in public.phase_c_founder_identity. The row names the register
           -- rather than a person, because the register is what the database can check.
           || '). Cleared only while approved_by RESOLVES to one of the '
           || (select count(*)::text from public.phase_c_founder_identity where active)
           || ' active identities in public.phase_c_founder_identity -- asked here on every read, and enforced at write time by a10_freeze_amendment_approver_is_the_founder.',
         (select count(*) from public.phase_c_freeze_amendment a
           where a.approved_by is null
              or not exists (select 1 from public.phase_c_founder_identity fi
                              where fi.active
                                and lower(btrim(fi.identity)) = lower(btrim(a.approved_by)))) = 0
  union all
  -- F31. HOW THE APPROVAL WAS GIVEN, WHICH IS NOT THE SAME QUESTION AS WHETHER THERE IS ONE.
  --
  -- The row above asks whether approved_by resolves to an active founder identity. It cannot tell
  -- an approval the founder placed through a verified Supabase Auth session from one a migration
  -- wrote on the strength of an instruction he sent in a message. Both leave the same string in the
  -- same column. F23 wrote the second kind for PCCR-003 and said so in its own header; nothing on
  -- any board repeated it, so a reader saw "approved by the founder" and had no way to learn which.
  --
  -- This row is red while any approval rests on WRITTEN_INSTRUCTION. It is a disclosure, not an
  -- accusation: the instruction is real, quoted verbatim in the change request, and the design it
  -- approves is strictly harder to pass than the one it replaced. What is missing is his signature
  -- through the door F20 built and F21 granted, and that is his to give, not this repository's.
  select 'amendments_approved_on_written_instruction_only', '0',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'WRITTEN_INSTRUCTION')::text
         || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
         || ' (change requests: '
         || (select coalesce(string_agg(distinct change_request_ref, ', '),'(none)')
               from public.phase_c_freeze_amendment where approval_basis = 'WRITTEN_INSTRUCTION')
         || '). An approval recorded from a written instruction is not a founder session. Cleared '
         || 'only by re-approval through a verified auth subject, which no migration can perform.',
         (select count(*) from public.phase_c_freeze_amendment
           where approval_basis = 'WRITTEN_INSTRUCTION') = 0
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$function$;

-- ---- 6. THE GRANTS THE RESTORED BODIES CARRIED --------------------------------------------------
-- CREATE OR REPLACE preserves the ACL, so nothing is re-granted here. The two functions this
-- rollback DROPs and does not recreate had their grants dropped with them.
REVOKE ALL ON FUNCTION public.fn_phase_c_require_founder(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_c_change_request_disposition_follows_approval() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_c_freeze_drift() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_require_founder(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_freeze_drift() TO service_role;
