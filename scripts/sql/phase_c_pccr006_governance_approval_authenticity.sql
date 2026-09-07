-- PCCR-006 — GOVERNANCE APPROVAL AUTHENTICITY.
--
-- ================================================================================================
-- THIS FILE IS NOT TO BE APPLIED UNTIL THE FOUNDER HAS APPROVED PCCR-006 THROUGH A VERIFIED
-- SESSION. It is committed so the amendment table has an exact subject to describe, and so the
-- approval can name a digest of something that already exists.
-- ================================================================================================
--
-- THE DEFECT, MEASURED BY EXECUTION ON PRODUCTION 24 AUG 2026, IN ABORTED TRANSACTIONS.
--
--   A.  update public.phase_c_change_request set approved_by='management@quotesdone.com',
--           approved_at=now() where change_request_ref='PCCR-004';
--       -> ACCEPTED. disposition became APPROVED and the row kept the DEFERRAL's own reason text.
--          PCCR-005 behaves identically. The CHECK
--          phase_c_change_request_deferral_is_not_approval never fires, because the BEFORE trigger
--          a15_phase_c_change_request_disposition_follows_approval has already rewritten
--          disposition := 'APPROVED' by the time the CHECK is evaluated.
--
--   B.  update public.phase_c_change_request set disposition='APPROVED' ... (no approver at all)
--       -> ACCEPTED. A request reads APPROVED with approved_by null.
--
--   C.  insert into public.phase_c_freeze_amendment (..., approval_basis, approval_route,
--           approval_auth_subject, approved_amendment_table_digest)
--       values (..., 'AUTHENTICATED_FOUNDER_SESSION', 'auth.uid()',
--               '1256c7ec-…'::uuid, repeat('a',64));
--       -> ACCEPTED. Every constraint checks only the SHAPE of the claim.
--
--   D.  THE FINDING THE INDEPENDENT AUDIT DID NOT REACH, AND THE DEEPEST ONE.
--       The canonical service itself can be walked past from migration SQL:
--         perform public.fn_phase_c_founder_subject_bind('1256c7ec-…'::uuid);   -- ACCEPTED
--         select  public.fn_phase_c_freeze_amendment_approve('{…"amendment_table_digest":
--                 "aaaa…64"…}'::jsonb);                                        -- ACCEPTED
--       recording approval_basis='AUTHENTICATED_FOUNDER_SESSION',
--       approval_route='fn_phase_c_founder_subject_bind' and a forged digest.
--       fn_phase_c_founder_subject_bind refuses only current_user in ('anon','authenticated').
--       The management API connects as postgres, which is neither, so a migration can mint a
--       founder auth event with no JWT in existence.
--
-- THE LOAD-BEARING FACT THIS CORRECTION RESTS ON, MEASURED RATHER THAN ASSUMED:
--
--   session_user  application_name   what it is
--   postgres      mgmt-api           migration / management SQL (scripts/apply_sql.mjs)
--   authenticator postgrest          the ONLY connection that can carry a verified user JWT
--
--   postgres has rolsuper=false on this project, and `set session authorization` from postgres is
--   refused 42501. `set role` changes current_user and leaves session_user alone. So session_user
--   is an identity a migration cannot forge, and "session_user = 'authenticator'" is exactly the
--   set of connections through which a founder's bearer token can arrive.
--
--   BOUNDARY, STATED SO IT IS NOT READ AS LARGER THAN IT IS: supabase_admin IS a superuser on this
--   project and could set session authorization. We do not hold its credentials and no path in this
--   repository uses it. This correction closes the paths this estate actually has; it does not
--   claim the platform owner cannot write a row.
--
-- THE ARCHITECTURE, WHICH IS THE ONE THE REFUND PATH ALREADY USES (PCCR-003):
--
--   verified founder JWT
--     -> server-side verified auth subject          (auth.uid(), or os_api's verified bind)
--     -> transaction-bound, purpose-bound, single-use founder-auth event
--          carrying action class, change request, decision, amendment-table digest, nonce, txid,
--          issued/expires/consumed
--     -> ONE canonical service: fn_phase_c_governance_decide
--     -> an append-only governance-decision ledger: public.phase_c_governance_decision
--     -> phase_c_change_request's approval columns are DERIVED from that ledger and writable from
--        nowhere else.
--
-- WHAT THIS FILE DOES NOT DO. It does not populate approved_by or approved_at for any change
-- request, including PCCR-006 itself. It cannot: after this file is applied, the only way an
-- approval row exists is a call through PostgREST carrying a founder bearer token.

-- ================================================================================================
-- 1. THE AUTH EVENT BECOMES PURPOSE-BOUND, EXPIRING AND SINGLE-USE
-- ================================================================================================
-- Every column is nullable so the refund path's existing general-session events stay legal and
-- fn_phase_c_require_founder Route B keeps working unchanged for them. The CHECK below binds only
-- events that declare an action class.

ALTER TABLE public.phase_c_founder_auth_event
  ADD COLUMN IF NOT EXISTS action_class           text,
  ADD COLUMN IF NOT EXISTS object_ref             text,
  ADD COLUMN IF NOT EXISTS decision               text,
  ADD COLUMN IF NOT EXISTS amendment_table_digest text,
  ADD COLUMN IF NOT EXISTS nonce                  text,
  ADD COLUMN IF NOT EXISTS issued_at              timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS expires_at             timestamptz,
  ADD COLUMN IF NOT EXISTS consumed_at            timestamptz,
  ADD COLUMN IF NOT EXISTS consumed_by            text;

ALTER TABLE public.phase_c_founder_auth_event
  DROP CONSTRAINT IF EXISTS phase_c_founder_auth_event_purpose_is_complete;
ALTER TABLE public.phase_c_founder_auth_event
  ADD CONSTRAINT phase_c_founder_auth_event_purpose_is_complete CHECK (
    action_class IS NULL
    OR (action_class = 'GOVERNANCE_DECISION'
        AND nullif(btrim(object_ref), '')             IS NOT NULL
        AND nullif(btrim(decision), '')               IS NOT NULL
        AND amendment_table_digest ~ '^[0-9a-f]{64}$'
        AND nullif(btrim(nonce), '')                  IS NOT NULL
        AND expires_at                                IS NOT NULL
        AND expires_at > issued_at
        AND expires_at <= issued_at + interval '10 minutes'));

ALTER TABLE public.phase_c_founder_auth_event
  DROP CONSTRAINT IF EXISTS phase_c_founder_auth_event_consumption_follows_issue;
ALTER TABLE public.phase_c_founder_auth_event
  ADD CONSTRAINT phase_c_founder_auth_event_consumption_follows_issue CHECK (
    consumed_at IS NULL OR consumed_at >= issued_at);

-- SINGLE USE, at the storage layer as well as in the service.
CREATE UNIQUE INDEX IF NOT EXISTS phase_c_founder_auth_event_nonce_uk
  ON public.phase_c_founder_auth_event (nonce) WHERE nonce IS NOT NULL;

-- ------------------------------------------------------------------------------------------------
-- A FOUNDER AUTH EVENT MAY ONLY BE MINTED ON A CONNECTION THAT COULD HAVE CARRIED A JWT.
-- This is the trigger that answers finding D. It refuses the management/migration connection by
-- session_user, which SET ROLE cannot change and which postgres cannot reassign on this project.
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_auth_event_is_server_minted()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'DELETE' then
    raise exception 'phase_c_founder_auth_event is append-only: a consumed founder session may not be deleted, because deleting it is how a replay stops looking like one. (pccr_auth_event_append_only)'
      using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE' then
    -- The only legal update is the single-use consumption stamp, in the same transaction that
    -- minted the event.
    if (NEW.event_id, NEW.auth_subject, NEW.identity, NEW.route, NEW.txid, NEW.bound_by,
        NEW.bound_at, NEW.action_class, NEW.object_ref, NEW.decision, NEW.amendment_table_digest,
        NEW.nonce, NEW.issued_at, NEW.expires_at)
       is distinct from
       (OLD.event_id, OLD.auth_subject, OLD.identity, OLD.route, OLD.txid, OLD.bound_by,
        OLD.bound_at, OLD.action_class, OLD.object_ref, OLD.decision, OLD.amendment_table_digest,
        OLD.nonce, OLD.issued_at, OLD.expires_at) then
      raise exception 'phase_c_founder_auth_event: only consumed_at and consumed_by may be updated, and only once. Everything else about a verified session is a fact about the past. (pccr_auth_event_append_only)'
        using errcode = '42501';
    end if;
    if OLD.consumed_at is not null then
      raise exception 'phase_c_founder_auth_event: event % was consumed at % and a single-use session may not be spent twice. (pccr_auth_event_replayed)',
        OLD.event_id, OLD.consumed_at using errcode = '23505';
    end if;
    if OLD.txid is distinct from txid_current() then
      raise exception 'phase_c_founder_auth_event: event % belongs to transaction % and is being consumed in %. A session bound to another transaction is a value a caller typed. (pccr_auth_event_wrong_transaction)',
        OLD.event_id, OLD.txid, txid_current() using errcode = '28000';
    end if;
    return NEW;
  end if;

  -- INSERT.
  if session_user <> 'authenticator' then
    raise exception 'phase_c_founder_auth_event: a founder session may only be minted on the PostgREST connection (session_user authenticator); this call arrives as session_user %, which is the management/migration path and carries no bearer token. Knowing the founder''s auth subject is not being the founder. (pccr_auth_event_untrusted_connection)',
      session_user using errcode = '28000';
  end if;
  if NEW.txid is distinct from txid_current() then
    raise exception 'phase_c_founder_auth_event: an event must name the transaction that mints it (got %, current %) (pccr_auth_event_wrong_transaction)',
      NEW.txid, txid_current() using errcode = '28000';
  end if;
  return NEW;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_founder_auth_event_is_server_minted() FROM PUBLIC;

DROP TRIGGER IF EXISTS a00_phase_c_founder_auth_event_is_server_minted
  ON public.phase_c_founder_auth_event;
CREATE TRIGGER a00_phase_c_founder_auth_event_is_server_minted
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_c_founder_auth_event
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_founder_auth_event_is_server_minted();

-- A raising trigger makes a table enforcing, and an enforcing table must not be truncatable.
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_founder_auth_event;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_c_founder_auth_event
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
REVOKE TRUNCATE ON public.phase_c_founder_auth_event FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================================================
-- 2. THE BIND DOOR NAMES THE CONNECTION IT TRUSTS
-- ================================================================================================
-- The old body refused current_user in ('anon','authenticated') and let postgres through. It now
-- states the positive condition instead: the caller must be on the connection that verifies JWTs.

CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_subject_bind(p_subject uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id text; v_ev bigint;
begin
  -- PCCR-006. THE POSITIVE CONDITION, NOT A DENY-LIST WITH NO THIRD ANSWER.
  -- 'anon' and 'authenticated' were named and 'postgres' was not, so migration SQL bound the
  -- founder's subject with no bearer token in existence. session_user is the connection role; SET
  -- ROLE cannot change it and postgres may not SET SESSION AUTHORIZATION on this project.
  if session_user <> 'authenticator' then
    raise exception 'fn_phase_c_founder_subject_bind: this is the server path. A founder subject may only be bound on the PostgREST connection that verified the bearer token (session_user authenticator); this call arrives as session_user % / current_user %. (pccr_founder_bind_untrusted_connection)',
      session_user, current_user using errcode = '28000';
  end if;
  if current_user = 'anon' then
    raise exception 'fn_phase_c_founder_subject_bind: anon may not bind a founder subject (pd_founder_bind_untrusted_caller)'
      using errcode = '42501';
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

-- ================================================================================================
-- 3. THE FROZEN FOUNDER RESOLVER REFUSES TO SPEND A PURPOSE-BOUND SESSION
-- ================================================================================================
-- AMENDMENT TO A FROZEN PHASE C SUBJECT: founder_authentication,
-- fn_phase_c_require_founder(p_actor text). Prior digest e0f8f63e14238a83…
--
-- Without this, a governance session minted to approve PCCR-006 would also satisfy the refund door
-- in the same transaction. A session issued for one act must not pay for another. One predicate is
-- added to Route B; Route A, the message text, the signature, the return and every caller are
-- unchanged.

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
-- 4. THE APPEND-ONLY GOVERNANCE DECISION LEDGER
-- ================================================================================================

CREATE TABLE IF NOT EXISTS public.phase_c_governance_decision (
  decision_id                     bigserial   PRIMARY KEY,
  change_request_ref              text        NOT NULL REFERENCES public.phase_c_change_request(change_request_ref),
  decision                        text        NOT NULL,
  approval_reason                 text        NOT NULL,
  approved_amendment_table_path   text        NOT NULL,
  approved_amendment_table_digest text        NOT NULL,
  decided_by                      text        NOT NULL REFERENCES public.phase_c_founder_identity(identity),
  decided_at                      timestamptz NOT NULL DEFAULT now(),
  approval_basis                  text        NOT NULL DEFAULT 'AUTHENTICATED_FOUNDER_SESSION',
  approval_route                  text        NOT NULL,
  approval_auth_subject           uuid        NOT NULL,
  auth_event_id                   bigint      NOT NULL UNIQUE REFERENCES public.phase_c_founder_auth_event(event_id),
  nonce                           text        NOT NULL UNIQUE,
  txid                            bigint      NOT NULL,
  CONSTRAINT phase_c_governance_decision_values CHECK (
    decision = ANY (ARRAY['APPROVED','DEFERRED','DEFER_OR_REJECT','REJECTED','WITHDRAWN'])),
  CONSTRAINT phase_c_governance_decision_basis CHECK (
    approval_basis = 'AUTHENTICATED_FOUNDER_SESSION'),
  CONSTRAINT phase_c_governance_decision_route CHECK (
    approval_route = ANY (ARRAY['auth.uid()','fn_phase_c_founder_subject_bind'])),
  CONSTRAINT phase_c_governance_decision_digest_shape CHECK (
    approved_amendment_table_digest ~ '^[0-9a-f]{64}$'),
  CONSTRAINT phase_c_governance_decision_path_shape CHECK (
    approved_amendment_table_path ~ '^docs/phase-[a-d]/[A-Za-z0-9_.-]+\.md$'),
  CONSTRAINT phase_c_governance_decision_reason_ck CHECK (
    length(btrim(approval_reason)) >= 40),
  -- REPLAY IS IDEMPOTENT AND MAKES NO SECOND DECISION ROW.
  CONSTRAINT phase_c_governance_decision_once
    UNIQUE (change_request_ref, decision, approved_amendment_table_digest)
);

COMMENT ON TABLE public.phase_c_governance_decision IS
  'PCCR-006. The append-only ledger a Phase C governance decision is recorded in. '
  'public.phase_c_change_request''s approval columns are DERIVED from this table and are writable '
  'from nowhere else. A row may only be inserted by fn_phase_c_governance_decide, against a '
  'purpose-bound founder auth event consumed in the same transaction.';

-- ------------------------------------------------------------------------------------------------
-- The ledger's own guard. It does not trust a GUC or a route label: it re-reads the auth event and
-- checks that it is this transaction's, this change request's, this decision's and this digest's.
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_governance_decision_is_session_backed()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e public.phase_c_founder_auth_event%rowtype;
begin
  if TG_OP <> 'INSERT' then
    raise exception 'phase_c_governance_decision is append-only: a recorded governance decision is a fact about the past and may not be % (pccr_governance_decision_append_only)',
      lower(TG_OP) using errcode = '42501';
  end if;

  select * into e from public.phase_c_founder_auth_event where event_id = NEW.auth_event_id;
  if not found then
    raise exception 'phase_c_governance_decision: auth event % does not exist (pccr_governance_no_auth_event)',
      NEW.auth_event_id using errcode = '28000';
  end if;
  if e.txid is distinct from txid_current() or NEW.txid is distinct from txid_current() then
    raise exception 'phase_c_governance_decision: auth event % belongs to transaction % and this decision is being written in %. A session bound to another transaction is not a session. (pccr_governance_wrong_transaction)',
      e.event_id, e.txid, txid_current() using errcode = '28000';
  end if;
  if e.action_class is distinct from 'GOVERNANCE_DECISION' then
    raise exception 'phase_c_governance_decision: auth event % carries action class % and a governance decision requires GOVERNANCE_DECISION. A session issued for one act may not pay for another. (pccr_governance_wrong_action_class)',
      e.event_id, coalesce(e.action_class,'(none)') using errcode = '28000';
  end if;
  if e.object_ref is distinct from NEW.change_request_ref then
    raise exception 'phase_c_governance_decision: auth event % is bound to % and this decision names %. A verified session approves the request it was issued for. (pccr_governance_wrong_object)',
      e.event_id, e.object_ref, NEW.change_request_ref using errcode = '28000';
  end if;
  if e.decision is distinct from NEW.decision then
    raise exception 'phase_c_governance_decision: auth event % is bound to decision % and this row records %. (pccr_governance_wrong_decision)',
      e.event_id, e.decision, NEW.decision using errcode = '28000';
  end if;
  if e.amendment_table_digest is distinct from NEW.approved_amendment_table_digest then
    raise exception 'phase_c_governance_decision: auth event % is bound to amendment-table digest % and this row records %. The founder approves the document he read. (pccr_governance_wrong_digest)',
      e.event_id, left(e.amendment_table_digest,16)||'…', left(NEW.approved_amendment_table_digest,16)||'…'
      using errcode = '28000';
  end if;
  if e.nonce is distinct from NEW.nonce then
    raise exception 'phase_c_governance_decision: the decision names nonce % and its auth event carries % (pccr_governance_wrong_nonce)',
      NEW.nonce, e.nonce using errcode = '28000';
  end if;
  if e.identity is distinct from NEW.decided_by or e.auth_subject is distinct from NEW.approval_auth_subject then
    raise exception 'phase_c_governance_decision: the decision is attributed to %/% and the verified session resolved to %/%. (pccr_governance_wrong_identity)',
      NEW.decided_by, NEW.approval_auth_subject, e.identity, e.auth_subject using errcode = '28000';
  end if;
  if e.expires_at <= now() then
    raise exception 'phase_c_governance_decision: auth event % expired at % (pccr_governance_auth_event_expired)',
      e.event_id, e.expires_at using errcode = '28000';
  end if;
  if e.consumed_at is null then
    raise exception 'phase_c_governance_decision: auth event % has not been consumed. The session is spent before the decision is written, so a failure between the two cannot leave a reusable session behind. (pccr_governance_auth_event_unconsumed)',
      e.event_id using errcode = '28000';
  end if;
  return NEW;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_governance_decision_is_session_backed() FROM PUBLIC;

DROP TRIGGER IF EXISTS a00_phase_c_governance_decision_is_session_backed
  ON public.phase_c_governance_decision;
CREATE TRIGGER a00_phase_c_governance_decision_is_session_backed
  BEFORE INSERT OR UPDATE OR DELETE ON public.phase_c_governance_decision
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_governance_decision_is_session_backed();

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_governance_decision;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_c_governance_decision
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

REVOKE ALL ON TABLE public.phase_c_governance_decision FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.phase_c_governance_decision TO service_role;

-- ------------------------------------------------------------------------------------------------
-- THE DERIVATION. phase_c_change_request's approval columns are written HERE and only here.
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_governance_decision_applies()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform set_config('app.phase_c_governance_decision', NEW.decision_id::text, true);

  update public.phase_c_change_request
     set disposition             = NEW.decision,
         disposition_reason      = NEW.approval_reason,
         disposition_recorded_at = NEW.decided_at,
         approved_by             = case when NEW.decision = 'APPROVED' then NEW.decided_by end,
         approved_at             = case when NEW.decision = 'APPROVED' then NEW.decided_at end,
         approval_reason         = case when NEW.decision = 'APPROVED' then NEW.approval_reason end,
         approval_basis          = case when NEW.decision = 'APPROVED' then NEW.approval_basis end,
         approval_route          = case when NEW.decision = 'APPROVED' then NEW.approval_route end,
         approval_auth_subject   = case when NEW.decision = 'APPROVED' then NEW.approval_auth_subject end,
         approved_amendment_table_digest
                                 = case when NEW.decision = 'APPROVED' then NEW.approved_amendment_table_digest end,
         governance_decision_id  = case when NEW.decision = 'APPROVED' then NEW.decision_id end
   where change_request_ref = NEW.change_request_ref;

  perform set_config('app.phase_c_governance_decision', '', true);
  return NEW;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_governance_decision_applies() FROM PUBLIC;

DROP TRIGGER IF EXISTS z10_phase_c_governance_decision_applies
  ON public.phase_c_governance_decision;
CREATE TRIGGER z10_phase_c_governance_decision_applies
  AFTER INSERT ON public.phase_c_governance_decision
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_governance_decision_applies();

-- ================================================================================================
-- 5. phase_c_change_request — APPROVAL BECOMES A DERIVED, GUARDED FACT
-- ================================================================================================

ALTER TABLE public.phase_c_change_request
  ADD COLUMN IF NOT EXISTS approval_reason                 text,
  ADD COLUMN IF NOT EXISTS approval_basis                  text,
  ADD COLUMN IF NOT EXISTS approval_route                  text,
  ADD COLUMN IF NOT EXISTS approval_auth_subject           uuid,
  ADD COLUMN IF NOT EXISTS approved_amendment_table_digest text,
  ADD COLUMN IF NOT EXISTS governance_decision_id          bigint
    REFERENCES public.phase_c_governance_decision(decision_id);

-- §2.4. A DEFERRAL REASON AND AN APPROVAL REASON ARE DIFFERENT FACTS.
-- The measured defect was a row that read APPROVED while carrying the deferral's own reason text.
-- They now live in different columns and the approval one is only ever set on an approval.
ALTER TABLE public.phase_c_change_request
  DROP CONSTRAINT IF EXISTS phase_c_change_request_approval_reason_only_on_approval;
ALTER TABLE public.phase_c_change_request
  ADD CONSTRAINT phase_c_change_request_approval_reason_only_on_approval CHECK (
    (disposition = 'APPROVED') OR approval_reason IS NULL);

-- CORRECTED 2026-08-25, BEFORE APPROVAL AND BEFORE APPLICATION. This constraint was written
-- without NOT VALID, and the migration therefore DID NOT APPLY. Rehearsed on production in an
-- aborted transaction on 25 Aug:
--
--   ERROR: 23514: check constraint "phase_c_change_request_approval_is_derived" of relation
--                 "phase_c_change_request" is violated by some row
--
-- The row is PCCR-003 — the founder's real approval of 21 Aug 2026, `approved_by
-- management@quotesdone.com`, `approved_at 2026-08-21 20:20:33+00`. It has an approver and no
-- governance_decision_id because THIS MIGRATION creates that column. The predicate names a column
-- the migration itself introduces and was then checked against rows that predate it, so a genuine
-- historical approval failed a rule that could not have existed when it was given.
--
-- NOT VALID is the honest treatment and it is not a weakening. Postgres enforces a NOT VALID CHECK
-- on every INSERT and every UPDATE; what it skips is the retroactive scan. So from this migration
-- forward, an approver without a ledger row is refused — which is the whole point — and one real
-- approval taken before the ledger existed is grandfathered rather than deleted or back-filled.
--
-- BACK-FILLING WAS THE ALTERNATIVE AND IT IS REFUSED. Giving PCCR-003 a governance_decision_id
-- would mean minting a ledger row for a decision that predates the ledger — inventing the verified
-- session it never had, which is precisely the defect this change request exists to close.
--
-- THE GRANDFATHERED SET IS ASSERTED, NOT ASSUMED. The block below fails the migration if the set is
-- anything other than exactly PCCR-003, so a second unbacked approval cannot slip in under this
-- allowance between now and the day it is applied.
ALTER TABLE public.phase_c_change_request
  DROP CONSTRAINT IF EXISTS phase_c_change_request_approval_is_derived;
ALTER TABLE public.phase_c_change_request
  ADD CONSTRAINT phase_c_change_request_approval_is_derived CHECK (
    (approved_by IS NULL) = (governance_decision_id IS NULL)) NOT VALID;

DO $grandfathered$
DECLARE v_rows text;
BEGIN
  SELECT string_agg(change_request_ref || ' (' || approved_by || ', ' || approved_at::date || ')',
                    ', ' ORDER BY change_request_ref)
    INTO v_rows
    FROM public.phase_c_change_request
   WHERE (approved_by IS NULL) <> (governance_decision_id IS NULL);

  IF v_rows IS DISTINCT FROM 'PCCR-003 (management@quotesdone.com, 2026-08-21)' THEN
    RAISE EXCEPTION
      'PCCR-006: the rows grandfathered by phase_c_change_request_approval_is_derived are %L. '
      'Exactly one was measured on 2026-08-25 and it is PCCR-003, the founder approval that '
      'predates the governance ledger. Anything else is an approval that was written without a '
      'verified session AFTER this defect was known, and it may not be carried in under this '
      'allowance. (pccr_grandfathered_set_moved)', coalesce(v_rows, '(none)')
      USING errcode = '23514';
  END IF;

  RAISE NOTICE 'PCCR-006: 1 approval grandfathered by NOT VALID — %', v_rows;
END $grandfathered$;

-- ------------------------------------------------------------------------------------------------
-- THE WRITE GUARD. Fires before a10 (the identity guard) and before a15, so "this approval was not
-- given in a verified session" is answered first and is not tidied into a disposition.
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_change_request_approval_is_derived()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dec bigint := nullif(btrim(current_setting('app.phase_c_governance_decision', true)),'')::bigint;
  v_touches_approval boolean;
begin
  if TG_OP = 'INSERT' then
    v_touches_approval := NEW.approved_by is not null
                       or NEW.governance_decision_id is not null
                       or NEW.disposition = 'APPROVED';
  else
    v_touches_approval := (NEW.approved_by, NEW.approved_at, NEW.approval_basis, NEW.approval_route,
                           NEW.approval_auth_subject, NEW.approved_amendment_table_digest,
                           NEW.approval_reason, NEW.governance_decision_id, NEW.disposition)
                       is distinct from
                          (OLD.approved_by, OLD.approved_at, OLD.approval_basis, OLD.approval_route,
                           OLD.approval_auth_subject, OLD.approved_amendment_table_digest,
                           OLD.approval_reason, OLD.governance_decision_id, OLD.disposition);
  end if;

  if not v_touches_approval then
    return NEW;
  end if;

  -- The write must be THIS transaction's governance decision, for THIS change request.
  if v_dec is null
     or not exists (select 1 from public.phase_c_governance_decision d
                     where d.decision_id = v_dec
                       and d.txid = txid_current()
                       and d.change_request_ref = NEW.change_request_ref
                       and d.decision = NEW.disposition) then
    raise exception 'phase_c_change_request %: the disposition and every approval column are DERIVED from public.phase_c_governance_decision and may not be written directly. Call public.fn_phase_c_governance_decide with a founder bearer token. A migration, a service_role connection and a typed founder email are all refused here, which is the whole point of PCCR-006. (pccr_governance_decision_required)',
      NEW.change_request_ref using errcode = '42501';
  end if;

  return NEW;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_change_request_approval_is_derived() FROM PUBLIC;

DROP TRIGGER IF EXISTS a05_phase_c_change_request_approval_is_derived
  ON public.phase_c_change_request;
CREATE TRIGGER a05_phase_c_change_request_approval_is_derived
  BEFORE INSERT OR UPDATE ON public.phase_c_change_request
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_change_request_approval_is_derived();

-- ------------------------------------------------------------------------------------------------
-- §2.2. THE SILENT RE-DISPOSITION IS REMOVED.
-- O15 added a15 for a real reason: the CHECK phase_c_change_request_deferral_is_not_approval
-- refused a legitimate approval because the approver and the disposition were two statements. The
-- reason is now answered a different way — fn_phase_c_governance_decide sets BOTH in one derivation
-- — so the trigger no longer has to guess, and the guess was the defect. It keeps only the reverse
-- half, which closes the row the CHECK forbids without ever manufacturing an approval.
-- ------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_change_request_disposition_follows_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- PCCR-006. The forward half is gone. Writing an approver no longer moves the disposition:
  --   update … set approved_by='management@quotesdone.com' where change_request_ref='PCCR-004'
  -- used to come out as disposition=APPROVED carrying the DEFERRAL's own reason text. It is now
  -- refused twice over — by a05 for not being a derived write, and by the CHECK, which finally sees
  -- a deferred row because nothing rewrote it first.
  if TG_OP = 'UPDATE' and NEW.approved_by is null and OLD.approved_by is not null then
    -- The reverse still holds: an APPROVED row whose approver is cleared would be an approval
    -- nobody gave.
    NEW.disposition             := 'RAISED';
    NEW.disposition_reason      := null;
    NEW.disposition_recorded_at := null;
    NEW.approval_reason         := null;
    NEW.approval_basis          := null;
    NEW.approval_route          := null;
    NEW.approval_auth_subject   := null;
    NEW.approved_amendment_table_digest := null;
    NEW.governance_decision_id  := null;
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_change_request_disposition_follows_approval() FROM PUBLIC;

-- ================================================================================================
-- 6. phase_c_freeze_amendment — A SESSION CLAIM MUST BE BACKED BY A SESSION
-- ================================================================================================

ALTER TABLE public.phase_c_freeze_amendment
  ADD COLUMN IF NOT EXISTS approved_amendment_table_path text;

-- Existing approvals were all recorded against the one committed tables document. Naming it makes
-- scripts/checks/pccr_approval_matches_committed_tables.test.mjs able to verify a SECOND amendment
-- document without invalidating the first five — which is what would otherwise happen the moment
-- PCCR-006's own table was committed.
UPDATE public.phase_c_freeze_amendment
   SET approved_amendment_table_path = 'docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md'
 WHERE approved_amendment_table_path IS NULL
   AND approved_amendment_table_digest IS NOT NULL;

ALTER TABLE public.phase_c_freeze_amendment
  DROP CONSTRAINT IF EXISTS phase_c_freeze_amendment_approval_names_its_document;
ALTER TABLE public.phase_c_freeze_amendment
  ADD CONSTRAINT phase_c_freeze_amendment_approval_names_its_document CHECK (
    (approved_amendment_table_digest IS NULL) = (approved_amendment_table_path IS NULL));

CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_amendment_session_claim_is_verified()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

REVOKE ALL ON FUNCTION public.fn_phase_c_freeze_amendment_session_claim_is_verified() FROM PUBLIC;

DROP TRIGGER IF EXISTS a05_freeze_amendment_session_claim_is_verified
  ON public.phase_c_freeze_amendment;
CREATE TRIGGER a05_freeze_amendment_session_claim_is_verified
  BEFORE INSERT OR UPDATE ON public.phase_c_freeze_amendment
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_freeze_amendment_session_claim_is_verified();

-- ================================================================================================
-- 7. THE ONE CANONICAL GOVERNANCE APPROVAL SERVICE
-- ================================================================================================
-- fn_phase_c_freeze_amendment_approve keeps its name and its job — it approves ONE FREEZE
-- AMENDMENT. This is its sibling for the CHANGE REQUEST, which had no service at all.

CREATE OR REPLACE FUNCTION public.fn_phase_c_governance_decide(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

REVOKE ALL ON FUNCTION public.fn_phase_c_governance_decide(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_governance_decide(jsonb) TO authenticated, service_role;

-- ================================================================================================
-- 8. THE FREEZE BOARD READS THE VERIFIED DECISION
-- ================================================================================================
-- Two rows are appended to fn_phase_c_freeze_drift(). The existing EIGHT are carried verbatim: the
-- body below was produced by reading the live definition out with pg_get_functiondef, anchoring on
-- its complete final emit (`select 'raw_frozen_subjects' … from judged;`) and splicing after it.
-- The prefix is byte-identical to the deployed body; nothing in the eight checks moves.
--
-- WHY THE BOARD NEEDED A ROW AT ALL. Every governance row it carried was about
-- public.phase_c_freeze_amendment. It carried none about public.phase_c_change_request, which is
-- the table the measured defect walks past — so the board read green while PCCR-004 could be
-- flipped to APPROVED in one statement.

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_freeze_drift was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


REVOKE ALL ON FUNCTION public.fn_phase_c_freeze_drift() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_freeze_drift() TO service_role;
