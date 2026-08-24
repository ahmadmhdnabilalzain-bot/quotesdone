-- O02. AN APPEND-ONLY LEDGER THAT NO ROUTINE MAY WRITE, AND A REFUND PATH THAT NEVER READ IT.
--
-- PD-FIN-004 asks whether a founder refund decision can be updated, deleted or silently replaced.
--
-- WHAT ALREADY EXISTS AND IS CORRECT. public.fn_phase_c_refund_decision_immutable, on trigger
-- a00_phase_c_refund_decision_immutable BEFORE DELETE OR UPDATE, refuses both. Driven on
-- production 24 Aug 2026 inside an aborted transaction, with the maintenance door opened so the
-- write guard was not the thing answering:
--
--   update  ... set decision='rejected'  -> 23514 "the decision is append-only; supersede it, do not edit it"
--   delete  ...                          -> 23514 "a founder refund decision cannot be deleted"
--   insert  ... supersedes_decision_id=<prior>, supersession_reason='...' -> ACCEPTED
--
-- That routine is a FROZEN Phase C subject (refund_only_founder_approval) and is not touched here.
-- Neither is fn_phase_c_refund_decision_guard. There is nothing to fix in either.
--
-- THE ACTUAL GAP IS ONE ROW EARLIER, AND IT IS TWO GAPS.
--
--   (1) public.kernel_write_authority holds ZERO rows for phase_c_refund_decision. Door 1 of
--       fn_kernel_write_guard matches the call stack against that register, so with no rows it can
--       never open: NO ROUTINE ANYWHERE MAY CREATE A FOUNDER REFUND DECISION. The table holds 0
--       rows, the append-only trigger has never had a subject, and the only way a row can exist at
--       all is Door 2 -- a hand-run maintenance write by the table owner with a stated reason,
--       which is an audited exception and not a service. An append-only ledger with no producer is
--       a control that has never been asked a question.
--
--   (2) public.refunds -- where the money actually is -- never reads the ledger. There is no column
--       binding a refund to a decision and no predicate requiring one. public.fn_refund_decide
--       gates on `exists (select 1 from phase_c_founder_identity where lower(identity) =
--       lower(btrim(p_decided_by)))`: a CALLER-SUPPLIED STRING compared against a register, which
--       is the shape PCCR-003 removed from fn_phase_c_require_founder and which survives here.
--       z00_refund_founder_decision_only returns NEW untouched unless status = 'approved', and
--       public.refund_status_transition ALLOWS requested -> succeeded ("Fast settlement; Stripe
--       confirmed before we saw the pending event"). So a refund can reach succeeded -- money moved
--       -- having passed no founder check of any strength. The founder's standing ruling of
--       17 Aug 2026 is that every refund needs him, at any amount, even AED 10.
--
-- THIS FILE BUILDS THE PRODUCER AND THE BINDING.
--
--   * public.fn_kernel_refund_decision_record -- the canonical founder refund decision service. It
--     resolves the founder through fn_phase_c_require_founder, which raises 28000 for anyone
--     without a verified auth subject, and writes decided_by FROM THE VERIFIED IDENTITY, never
--     from the call. It supports the supersession path the frozen trigger already sanctions, and
--     it refuses an attempt to edit or delete through the service with pd_refund_decision_append_only
--     rather than letting a caller discover the table trigger by accident.
--     It is named fn_kernel_* deliberately: it is a kernel entry door, and the name is what keeps
--     public.fn_kernel_retired_path_state green when it reaches a kernel-internal primitive.
--
--   * public.refunds.refund_decision_id, a FK onto the ledger, and
--     public.fn_phase_c_refund_execution_requires_decision on trigger
--     z05_refund_execution_requires_decision BEFORE INSERT OR UPDATE. A PLATFORM-ORIGINATED refund
--     may not arrive at, or move into, a money-moved status (approved, processing, succeeded)
--     without an approved, non-superseded decision on the ledger.
--     Refusal code: pd_refund_execution_without_founder_decision.
--
-- WHY THE EXTERNAL PATH IS NOT REFUSED, said out loud because refusing it is the shorter diff and
-- it is wrong. fn_refund_settle's outside-the-platform branch inserts a refunds row for money
-- STRIPE ALREADY MOVED, with requested_by='stripe_webhook'. Refusing that insert does not stop the
-- refund -- it already happened -- it only destroys our record of it, which is strictly worse than
-- recording it. Those rows are admitted and marked: the guard requires the external originator to
-- be named, and public.fn_kernel_refund_ledger_state() counts them separately so an externally
-- settled refund can never be read as one the founder approved.
--
-- MEASURED BEFORE THE GUARD, so it cannot break work in flight: public.refunds holds 0 rows and
-- public.phase_c_refund_decision holds 0 rows. The guard refuses nothing that exists.
--
-- WHAT THIS FILE DOES NOT DO. It does not touch fn_refund_decide, fn_refund_settle or
-- public.refund_status_transition. requested -> succeeded stays allowed because it is a real Stripe
-- ordering, and the transition table is not the place to express "the founder approved this" --
-- the new guard is, and it now sits on every write to the table whatever ordered it.

-- ---------------------------------------------------------------------------------------------
-- 1. THE MISSING PRODUCER.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_kernel_refund_decision_record(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_op        text   := lower(coalesce(nullif(btrim(p_input->>'op'),''), 'record'));
  v_request   bigint := nullif(btrim(coalesce(p_input->>'request_id','')), '')::bigint;
  v_decision  text   := lower(coalesce(btrim(p_input->>'decision'), ''));
  v_reason    text   := coalesce(btrim(p_input->>'reason'), '');
  v_super     bigint := nullif(btrim(coalesce(p_input->>'supersedes_decision_id','')), '')::bigint;
  v_super_why text   := coalesce(btrim(p_input->>'supersession_reason'), '');
  v_exec_role text   := nullif(btrim(coalesce(p_input->>'executor_role_id','')), '');
  v_rec_role  text   := nullif(btrim(coalesce(p_input->>'reconciler_role_id','')), '');
  v_target    bigint := nullif(btrim(coalesce(p_input->>'decision_id','')), '')::bigint;
  v_founder   text;
  v_id        bigint;
  d           public.phase_c_refund_decision%rowtype;
begin
  -- THE IDENTITY IS RESOLVED, NEVER ACCEPTED. fn_phase_c_require_founder raises 28000 when the
  -- call carries no verified auth subject; a caller-supplied identity string is an assertion it
  -- checks against the verified one, and never a source.
  v_founder := public.fn_phase_c_require_founder(nullif(btrim(p_input->>'decided_by'),''));

  if v_op not in ('record','execute','reconcile') then
    raise exception 'fn_kernel_refund_decision_record: op must be record, execute or reconcile, got % (pd_refund_decision_op_unknown)',
      v_op using errcode = '22023';
  end if;

  -- ---- THE TWO THINGS THIS SERVICE WILL NOT DO -------------------------------------------------
  -- Stated here rather than left for a caller to discover from the table trigger, because a
  -- service that quietly forwards an edit to a guard is a service that taught its callers the
  -- edit was worth trying.
  if coalesce((p_input->>'edit')::boolean, false) or coalesce((p_input->>'delete')::boolean, false) then
    raise exception 'fn_kernel_refund_decision_record: a founder refund decision is append-only. Record a NEW decision citing the prior one in supersedes_decision_id with a supersession_reason. (pd_refund_decision_append_only)'
      using errcode = '23514';
  end if;

  if v_op = 'record' then
    if v_request is null then
      raise exception 'fn_kernel_refund_decision_record: request_id is required and names the founder_approval_request this decision answers (pd_refund_decision_request_absent)'
        using errcode = '22023';
    end if;
    if v_decision not in ('approved','rejected') then
      raise exception 'fn_kernel_refund_decision_record: decision must be approved or rejected, got % (pd_refund_decision_verdict_unknown)',
        v_decision using errcode = '22023';
    end if;
    if v_reason = '' then
      raise exception 'fn_kernel_refund_decision_record: a refund decision with no stated reason is not a decision (pd_refund_decision_reason_absent)'
        using errcode = '23514';
    end if;
    -- The supersession pair is all-or-nothing at the table too
    -- (phase_c_refund_decision_supersession_ck); refusing it here names which half is missing.
    if (v_super is null) <> (v_super_why = '') then
      raise exception 'fn_kernel_refund_decision_record: supersedes_decision_id and supersession_reason are given together or not at all (pd_refund_decision_supersession_incomplete)'
        using errcode = '23514';
    end if;
    if v_super is not null and not exists (
         select 1 from public.phase_c_refund_decision x where x.decision_id = v_super) then
      raise exception 'fn_kernel_refund_decision_record: decision % does not exist, so nothing can supersede it (pd_refund_decision_supersedes_unknown)',
        v_super using errcode = '23503';
    end if;

    insert into public.phase_c_refund_decision
      (request_id, decided_by, decision, reason, supersedes_decision_id, supersession_reason,
       executor_role_id, reconciler_role_id)
    values (v_request, v_founder, v_decision, v_reason, v_super, nullif(v_super_why,''),
            coalesce(v_exec_role, 'payments_and_billing_manager'),
            coalesce(v_rec_role,  'financial_controller'))
    returning decision_id into v_id;

    select * into d from public.phase_c_refund_decision where decision_id = v_id;
    return jsonb_build_object('ok', true, 'op','record', 'decision_id', v_id,
      'decided_by', d.decided_by, 'decision', d.decision,
      'supersedes_decision_id', d.supersedes_decision_id,
      'note','decided_by is the identity fn_phase_c_require_founder verified, not the identity the call named');
  end if;

  -- ---- execute / reconcile: the only two columns the frozen trigger lets an UPDATE fill ---------
  if v_target is null then
    raise exception 'fn_kernel_refund_decision_record: decision_id is required for op % (pd_refund_decision_target_absent)',
      v_op using errcode = '22023';
  end if;
  select * into d from public.phase_c_refund_decision where decision_id = v_target;
  if not found then
    raise exception 'fn_kernel_refund_decision_record: no decision % (pd_refund_decision_unknown)',
      v_target using errcode = '23503';
  end if;
  if d.decision <> 'approved' then
    raise exception 'fn_kernel_refund_decision_record: decision % is %, so no refund may be executed against it (pd_refund_execution_without_founder_decision)',
      v_target, d.decision using errcode = '23514';
  end if;
  if exists (select 1 from public.phase_c_refund_decision s where s.supersedes_decision_id = v_target) then
    raise exception 'fn_kernel_refund_decision_record: decision % has been superseded and is no longer the founder''s decision (pd_refund_execution_without_founder_decision)',
      v_target using errcode = '23514';
  end if;

  if v_op = 'execute' then
    update public.phase_c_refund_decision set executed_at = now() where decision_id = v_target;
  else
    update public.phase_c_refund_decision set reconciled_at = now() where decision_id = v_target;
  end if;
  select * into d from public.phase_c_refund_decision where decision_id = v_target;
  return jsonb_build_object('ok', true, 'op', v_op, 'decision_id', v_target,
    'executed_at', d.executed_at, 'reconciled_at', d.reconciled_at);
end $function$;

REVOKE ALL ON FUNCTION public.fn_kernel_refund_decision_record(jsonb) FROM PUBLIC;

INSERT INTO public.kernel_write_authority (routine_name, table_name, why)
VALUES ('fn_kernel_refund_decision_record', 'phase_c_refund_decision',
        'O02. The canonical founder refund decision service, and the first writer this table has '
     || 'ever had. It resolves the founder through fn_phase_c_require_founder and writes decided_by '
     || 'from the verified identity, never from the call. The append-only and supersession rules '
     || 'stay where they are, on a00_phase_c_refund_decision_immutable.')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- 2. THE BINDING BETWEEN THE LEDGER AND THE MONEY.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.refunds
  ADD COLUMN IF NOT EXISTS refund_decision_id bigint
    REFERENCES public.phase_c_refund_decision(decision_id);

COMMENT ON COLUMN public.refunds.refund_decision_id IS
  'O02. The immutable founder decision this refund executes. Required by '
  'z05_refund_execution_requires_decision for any platform-originated refund reaching a '
  'money-moved status. Null is legitimate only for an externally originated settlement record.';

CREATE OR REPLACE FUNCTION public.fn_phase_c_refund_execution_requires_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_money_moved constant text[] := array['approved','processing','succeeded'];
  -- Named originators of money this platform did not move. A refund Stripe already issued is a
  -- FACT to be recorded, not a request to be approved; refusing the row would delete our only
  -- record of real money leaving, which is worse than admitting it.
  v_external    constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
  d public.phase_c_refund_decision%rowtype;
begin
  if not (NEW.status = any(v_money_moved)) then return NEW; end if;
  if tg_op = 'UPDATE' and OLD.status = any(v_money_moved)
     and NEW.refund_decision_id is not distinct from OLD.refund_decision_id then
    -- already past this boundary and not changing which decision it cites
    return NEW;
  end if;

  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;   -- counted separately by fn_kernel_refund_ledger_state, never as founder-approved
  end if;

  if NEW.refund_decision_id is null then
    raise exception 'refunds %: a platform-originated refund may not reach status % without naming the founder decision that authorised it. His ruling of 17 Aug 2026 is that every refund needs him, at any amount. Record one with fn_kernel_refund_decision_record. (pd_refund_execution_without_founder_decision)',
      coalesce(NEW.id::text,'(new)'), NEW.status using errcode = '23514';
  end if;

  select * into d from public.phase_c_refund_decision where decision_id = NEW.refund_decision_id;
  if not found or d.decision <> 'approved' then
    raise exception 'refunds %: decision % is %, which does not authorise a refund. (pd_refund_execution_without_founder_decision)',
      coalesce(NEW.id::text,'(new)'), NEW.refund_decision_id,
      coalesce(d.decision,'absent') using errcode = '23514';
  end if;
  if exists (select 1 from public.phase_c_refund_decision s
              where s.supersedes_decision_id = NEW.refund_decision_id) then
    raise exception 'refunds %: decision % has been superseded and is no longer his decision. (pd_refund_execution_without_founder_decision)',
      coalesce(NEW.id::text,'(new)'), NEW.refund_decision_id using errcode = '23514';
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_refund_execution_requires_decision() FROM PUBLIC;

-- z05_, before z00_refund_founder_decision_only fires? No: Postgres orders BEFORE triggers by NAME,
-- so z00_ runs first and keeps its existing answer for status='approved'. z05_ then adds the arm
-- z00_ never had -- every other money-moved status.
DROP TRIGGER IF EXISTS z05_refund_execution_requires_decision ON public.refunds;
CREATE TRIGGER z05_refund_execution_requires_decision
  BEFORE INSERT OR UPDATE ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_refund_execution_requires_decision();

-- ---------------------------------------------------------------------------------------------
-- 3. THE BOARD. Counts what is true, per class, never in aggregate: a refund the founder approved
--    and one Stripe settled without him are different facts and are never added together.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_kernel_refund_ledger_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'the_ledger_has_a_registered_writer', '1',
         (select count(*)::text from public.kernel_write_authority
           where table_name = 'phase_c_refund_decision'),
         (select count(*) from public.kernel_write_authority
           where table_name = 'phase_c_refund_decision') >= 1
  union all
  select 'platform_refunds_at_a_money_moved_status_with_no_approved_decision', '0',
         count(*)::text || ' of ' || (select count(*) from public.refunds)::text, count(*) = 0
    from public.refunds r
   where r.status in ('approved','processing','succeeded')
     and lower(coalesce(r.requested_by,'')) not in ('stripe_webhook','stripe_dashboard','stripe')
     and not exists (select 1 from public.phase_c_refund_decision d
                      where d.decision_id = r.refund_decision_id and d.decision = 'approved'
                        and not exists (select 1 from public.phase_c_refund_decision s
                                         where s.supersedes_decision_id = d.decision_id))
  union all
  select 'externally_settled_refunds_recorded_not_counted_as_approved', 'informational',
         count(*)::text || ' of ' || (select count(*) from public.refunds)::text, true
    from public.refunds r
   where lower(coalesce(r.requested_by,'')) in ('stripe_webhook','stripe_dashboard','stripe')
  union all
  select 'decisions_whose_decided_by_is_not_an_active_founder_identity', '0',
         count(*)::text || ' of ' || (select count(*) from public.phase_c_refund_decision)::text,
         count(*) = 0
    from public.phase_c_refund_decision d
   where not exists (select 1 from public.phase_c_founder_identity f
                      where f.active and lower(f.identity) = lower(d.decided_by));
$function$;

REVOKE ALL ON FUNCTION public.fn_kernel_refund_ledger_state() FROM PUBLIC;
