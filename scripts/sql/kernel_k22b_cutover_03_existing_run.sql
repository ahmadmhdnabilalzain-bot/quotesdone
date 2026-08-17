-- K22b — cutover increment 3 of 8: signals about runs that already exist.
--
-- The first two increments cut over class-A sources, which start a workflow. These are class B:
-- they attach to a run that is already open, and must never start a second one.
--
--   dbtrigger:public.quote_items:quote_items_roll     -> supplier.quote_revision on the W14 run
--   dbtrigger:public.transactions:trg_refund_resolved -> provider.callback on the W17 run
--
-- Each finds its run with public.fn_kernel_run_for (K22), which returns the ONE live run for a
-- business object, or NULL when there is none AND when there is more than one. NULL is a real
-- answer here: no live run means there is nothing to attach to, and the source stays quiet rather
-- than opening a workflow to have somewhere to put its signal.
--
-- TWO SOURCES ARE RECLASSIFIED RATHER THAN CUT OVER, and this is the substance of the increment.
--
-- Three triggers sit on quote_items and all three fire on every insert, update and delete. The
-- register had all three as class B. If all three emitted, one edit to one line of a quotation
-- would deliver THREE signals — the source_type is part of the idempotency key, so they would not
-- collapse into one. Three signals for one revision is duplicate delivery, which is precisely
-- what this cutover exists to end.
--
-- Only one of them is a revision. Read for what each writes:
--
--   trg_quote_items_roll            recomputes fn_quote_structured_score and writes
--                                   quotes.structured and quotes.submittable. This IS the revision.
--   trg_quote_items_rescore         `update public.quotes set status = status` — a no-op touch
--                                   whose only purpose is to fire the quotes triggers.
--   fn_quote_recompute_submittable  recomputes and writes quotes.submittable on the same row.
--
-- The last two normalise one record. That is not the creation of business work, and it is exactly
-- the boundary class C draws. They move to C with the measurement written into their register row.
--
-- ACTIVATION: none. Both cut-over triggers were already enabled and firing.
--
-- Rollback: scripts/sql/rollback/kernel_k22b_cutover_03_existing_run.rollback.sql

begin;

-- dbtrigger:public.quote_items:quote_items_roll
--   A revision to a quotation already inside a W14 run. This is the ONE of the three quote_items triggers that emits: it recomputes the structured score, which is what a revision actually changes. Its two siblings only touch the quotes row and are reclassified to C in this file.
CREATE OR REPLACE FUNCTION public.trg_quote_items_roll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare qid text; s jsonb;
begin
  qid := coalesce(NEW.quote_id, OLD.quote_id);
  s := public.fn_quote_structured_score(qid);
  update quotes set structured=s, submittable=(s->>'submittable')::boolean where id=qid::uuid;
  -- Kernel cutover. A revision to a quotation already inside a W14 run. This is the ONE of the three quote_items triggers that emits: it recomputes the structured score, which is what a revision actually changes. Its two siblings only touch the quotes row and are reclassified to C in this file.
  perform public.fn_kernel_source_emit('dbtrigger:public.quote_items:quote_items_roll', jsonb_build_object(
    'source_ref',  qid,
    'workflow_run_id', public.fn_kernel_run_for('quotation:' || qid),
    'raw_payload', jsonb_build_object('quotation_id', qid, 'structured', s)));

  return null;
end $function$
;

-- dbtrigger:public.transactions:trg_refund_resolved
--   Resolution of a refund already inside a W17 run. Routing it as new work would open a second W17 for the same transaction.
CREATE OR REPLACE FUNCTION public.qd_on_refund_resolved()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fee numeric; v_admin numeric;
begin
  if NEW.refund_status in ('refunded','approved') and (OLD.refund_status is distinct from NEW.refund_status) then
    v_fee   := coalesce(NEW.reveal_fee, NEW.app_fee, 0);
    v_admin := coalesce((select num_value from public.gl_settings where key='clawback_admin_fee_aed'), 250);
  -- Kernel cutover. Resolution of a refund already inside a W17 run. Routing it as new work would open a second W17 for the same transaction.
  perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_refund_resolved', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'workflow_run_id', public.fn_kernel_run_for('refund_dispute_case:' || NEW.id::text),
    'raw_payload', jsonb_build_object('transaction_id', NEW.id::text, 'refund_status', NEW.refund_status, 'reveal_fee', v_fee)));


    if not exists (select 1 from public.supplier_dues where transaction_id=NEW.id and coalesce(status,'')<>'cancelled') then
      insert into public.supplier_dues(
        transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
        amount_due, admin_fee, interest_amount, currency,
        reveal_date, due_date, due_date_30, status, created_at)
      values(
        NEW.id, NEW.supplier_id, NEW.quote_id, NEW.quote_amount, 3,
        v_fee,          -- the 3% reveal fee QuotesDone already refunded to the customer
        v_admin,        -- flat administration fee, charged immediately per the supplier terms
        0,              -- interest starts accruing only once the due date passes
        'AED',
        NEW.revealed_at, (now()+interval '7 days'), (now()+interval '30 days'), 'due', now());
    end if;

    update public.leads
      set matching_blocked = true,
          matching_block_reason = 'Unsettled non-response charge (customer refunded due to no response)',
          rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds,0)+1
    where id = NEW.supplier_id;

    if NEW.refund_resolved_at is null then NEW.refund_resolved_at := now(); end if;
  end if;
  return NEW;
end;
$function$
;

-- The other two quote_items triggers are RECLASSIFIED, and the reason is what they were measured
-- to do rather than what their names suggest.
--
-- All three fire on every insert, update and delete of a quote item. If all three emitted, one
-- edit to one line of a quotation would deliver three signals with three different idempotency
-- keys — the source_type is part of the key, so they would not collapse. Three signals for one
-- revision is duplicate delivery, which is the thing this cutover exists to end.
--
-- Only one of them is a revision. Read for what they write:
--
--   trg_quote_items_roll         recomputes fn_quote_structured_score and writes quotes.structured
--                                and quotes.submittable. This IS the revision.
--   trg_quote_items_rescore      `update public.quotes set status = status` — a no-op touch whose
--                                only purpose is to fire the quotes triggers. It changes nothing.
--   fn_quote_recompute_submittable recomputes and writes quotes.submittable on the same row.
--
-- The last two write only the quotes row their own item belongs to. That is normalisation of one
-- record, not the creation of business work, and it is exactly the boundary class C draws.
update public.phase_c_source_cutover
   set source_class = 'C READ_ONLY_MONITOR',
       target_kernel_adapter = 'none — this class may not create business work',
       target_workflow = 'none',
       target_step_or_signal = 'none',
       idempotency_key = 'n/a — creates nothing to deduplicate',
       trace_policy = 'TRACE-MONITORING',
       status = 'RECLASSIFIED_INTERNAL_RECOMPUTATION',
       cutover_action = 'No adapter. It recomputes a field on the quotes row its own item belongs '
                     || 'to; dbtrigger:public.quote_items:quote_items_roll carries the revision '
                     || 'signal for all three.',
       classification_reason = classification_reason
         || ' | K22 2026-08-17: RECLASSIFIED B -> C. All three quote_items triggers fire on every '
         || 'item change, and the source_type is part of the idempotency key, so three emitters '
         || 'would deliver three signals for one revision rather than collapsing to one. Read for '
         || 'what it writes, this one only normalises the quotes row its own item belongs to — '
         || 'quote_items_rescore is literally `update quotes set status = status`, a no-op touch '
         || 'to fire other triggers. quote_items_roll recomputes the structured score and is the '
         || 'only one of the three that represents a revision.'
 where source_component_id in ('dbtrigger:public.quote_items:quote_items_rescore',
                              'dbtrigger:public.quote_items:trg_items_submittable');


-- ---- the wrapper corrected, see the note inside ----------------------------------------
create or replace function public.fn_kernel_source_emit(p_source_key text, p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k19_emit$
declare
  v_class   text;
  v_vocab   text;
  v_wf      text;
  v_actor   text;
  v_active  text;
  v_ref     text := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_run     bigint := nullif(p_input->>'workflow_run_id','')::bigint;
  v_out     jsonb;
  v_ctx     text;
begin
  select c.source_class, c.target_step_or_signal, c.target_workflow, c.system_actor,
         c.current_activation
    into v_class, v_vocab, v_wf, v_actor, v_active
    from public.phase_c_source_cutover c where c.source_component_id = p_source_key;

  if v_class is null then
    raise exception 'fn_kernel_source_emit: % is not in the source cutover register', p_source_key
      using errcode = '23503',
            hint = 'Every autonomous source is classified in public.phase_c_source_cutover. A '
                || 'source with no row has no route, and routing it on a guess is how one arrival '
                || 'lands on two workflows. Classify it in scripts/phase_c/source_classification.mjs '
                || 'and regenerate.';
  end if;

  if v_class = 'C READ_ONLY_MONITOR' then
    raise exception 'fn_kernel_source_emit: % is a READ_ONLY_MONITOR and may not create business work',
      p_source_key using errcode = '42501',
        hint = 'A monitor collects status and may update approved operational state. When a '
            || 'threshold is crossed it raises a SEPARATE class-A request under its own source '
            || 'key, with its own dedupe key and its own evidence — a different call, which looks '
            || 'like one.';
  end if;

  if v_class = 'D RETIRE_OR_HISTORICAL' then
    raise exception 'fn_kernel_source_emit: % is retired', p_source_key
      using errcode = '42501',
            hint = 'Retired means retired. If this source must live again it needs a row saying so, '
                || 'not a call.';
  end if;

  if v_ref is null then
    raise exception 'fn_kernel_source_emit: % supplied no source_ref', p_source_key
      using errcode = '22023',
            hint = 'source_ref is the external identity of the thing this is about — the inquiry '
                || 'id, the quote id, the transaction id. The idempotency key is built from it, '
                || 'and a key that is different every time is not a key.';
  end if;

  begin
    if v_class = 'A NEW_WORK_REQUEST' then
      v_out := public.fn_kernel_trigger_submit(jsonb_build_object(
        'source_class',    (select source_class from public.kernel_trigger_type
                             where trigger_type = v_vocab),
        'source_system',   p_source_key,
        'source_ref',      v_ref,
        'external_ref',    p_input->>'external_ref',
        'trigger_type',    v_vocab,
        'raw_payload',     coalesce(p_input->'raw_payload', '{}'::jsonb),
        'requested_by',    coalesce(nullif(btrim(p_input->>'requested_by'),''), v_actor),
        'object_version',  p_input->>'object_version',
        'priority',        p_input->>'priority',
        'idempotency_key', p_input->>'idempotency_key',
        'correlation_id',  p_input->>'correlation_id',
        'causation_id',    p_input->>'causation_id'));
    else
      -- K22b. There WAS a raise here for a NULL workflow_run_id, and it was wrong. A class-B
      -- source is a database trigger that fires on every row change; "this object has no live run
      -- right now" is the ordinary case, not a developer error, and raising turned it into a
      -- failed insert on quote_items and transactions. It is also not a silence to swallow:
      -- fn_kernel_signal_submit inserts the ledger row BEFORE it validates, so a signal with no
      -- run is recorded as a refused row carrying its reason — which is exactly what that table
      -- exists for. The check is deleted rather than moved: the door below already does it, and
      -- does it better.
      v_out := public.fn_kernel_signal_submit(jsonb_build_object(
        'source_type',     p_source_key,
        'source_id',       v_ref,
        'workflow_run_id', v_run,
        'signal_type',     v_vocab,
        'payload',         coalesce(p_input->'raw_payload', '{}'::jsonb),
        'requested_by',    coalesce(nullif(btrim(p_input->>'requested_by'),''), v_actor),
        'idempotency_key', p_input->>'idempotency_key',
        'correlation_id',  p_input->>'correlation_id',
        'causation_id',    p_input->>'causation_id'));
    end if;
  exception
    -- Deliberately narrow: the four raises above are the wrapper's own contract violations and
    -- must reach the developer, not be filed as a runtime fault. Everything else is a kernel
    -- fault, and a kernel fault must not stop a customer inserting an inquiry.
    when sqlstate '23503' or sqlstate '42501' or sqlstate '22023' then
      raise;
    when others then
      get diagnostics v_ctx = pg_context;
      insert into public.kernel_adapter_failure (source_key, input, sqlstate, message, call_stack)
      values (p_source_key, p_input, sqlstate, sqlerrm, v_ctx);
      return jsonb_build_object('ok', false, 'recorded_failure', true, 'source_key', p_source_key,
        'sqlstate', sqlstate, 'error', sqlerrm,
        'note', 'the kernel raised; the business row was not blocked and the fault is recorded in '
             || 'kernel_adapter_failure, where fn_kernel_source_emit_state fails while it is unresolved');
  end;

  return coalesce(v_out, '{}'::jsonb) || jsonb_build_object('source_key', p_source_key,
    'source_class', v_class, 'vocabulary', v_vocab, 'activation', v_active);
end
$k19_emit$;



-- ---- supplier.quote_revision becomes ATTACH_ONLY -----------------------------------------------
--
-- K16 registered it as COMPLETE_STEP, on the reasoning that W14-S03 "Receive quotation revision"
-- exists for exactly this. The rehearsal showed why that is wrong in practice:
--
--   refused [signal type 'supplier.quote_revision' completes step W14-S01 and the payload
--            carries no output object]
--
-- and the refusal is right. A database trigger on quote_items knows a quote id and a recomputed
-- score. It does not know the step's required output, and COMPLETE_STEP would only ever succeed if
-- something synthesised one — which is the fabrication fn_kernel_step_complete refuses on purpose.
--
-- So the revision ATTACHES: the fact that the supplier revised the quotation lands on the run and
-- its trace, at the moment it happened, and the step is completed later by whoever actually
-- produces the output. Recording that a revision arrived is true; recording that a step finished
-- because a revision arrived would not be.
update public.kernel_signal_type
   set disposition = 'ATTACH_ONLY',
       meaning = 'A supplier has revised a quotation inside a live W14 run. This is NOT a new '
              || 'quotation: W14-S03 Receive quotation revision is the step that exists for it, '
              || 'and starting a second W14 for the same quote would double the evaluation. '
              || 'ATTACH_ONLY since K22b: the trigger that detects a revision knows a quote id and '
              || 'a recomputed score, not the step''s required output, and completing a step '
              || 'without one would certify work nobody did.'
 where signal_type = 'supplier.quote_revision';

commit;
