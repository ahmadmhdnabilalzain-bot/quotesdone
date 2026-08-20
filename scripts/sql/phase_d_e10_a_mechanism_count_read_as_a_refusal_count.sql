-- =================================================================================================
-- Phase D — E10. Two green numbers that answer an easier question than the one they are read as.
--
-- The independent acceptance of 2026-08-20 named both. Re-measured here rather than taken on trust:
--
--   fn_phase_d_rule_state.rules_with_outstanding_enforcement = 0 of 54
--     counts phase_d_rule_enforcement.status, which reads ENFORCED on all 54. That is a MECHANISM
--     count. Driving every rule against three probe contexts, fn_phase_d_rule_can_refuse() answers a
--     harder question and has never been on the board:
--         40  produce ENFORCED_FAIL on at least one context — they can refuse
--         11  delegated: the kernel guard decides and this predicate cannot invoke it
--              BR-006..010, BR-045..047, BR-050..052
--          2  constant while the founder's provider hold stands — BR-053, BR-054
--          1  enforced at fn_phase_d_handler_execute section 3, the capability boundary — BR-028
--         --
--         54
--     "54 of 54 enforced" and "40 of 54 can refuse" are both true and are not the same sentence.
--
--   fn_phase_d_handler_state.handlers_not_writing_a_business_object = 0 of 257
--     is derived from the handler's declared call to fn_phase_d_effect_produce plus a stored
--     boolean. It says the PATH EXISTS. It does not say any handler has ever written a business
--     object, and the number that does — steps_with_no_effect_ever_produced — reads 257 on a
--     different board. Two numbers about one subject, one green and one red, on two screens.
--
-- WHAT THIS FILE DOES NOT DO. Neither existing check is renamed, re-derived or lowered. Both measure
-- exactly what they measured yesterday and both stay green, because both are correct about the thing
-- they measure. What is added is the harder question, on the same board, so the easier answer cannot
-- be mistaken for it — the same shape as E5 and E7, and for the same reason.
--
-- Both bodies were produced by reading the live definition out with pg_get_functiondef and splicing;
-- the generator asserts each anchor and refuses if it has moved. Every other line is byte-identical.
-- Both are CREATE OR REPLACE, which preserves the ACL, so there is deliberately no revoke.
--
-- A DEFECT THIS FILE INTRODUCED AND THE BOARD CAUGHT, recorded because the next person splicing a
-- `return next` routine will make it. The generator's anchor was a regex over ONE check_name line
-- plus the line after it, and `handlers_not_writing_a_business_object` emits over TWO lines —
-- `expected := …; actual := …;` and then `ok := …; return next;`. The new block was therefore
-- inserted BETWEEN a check's assignment and its own `return next`, so the reassigned check_name was
-- emitted twice and the original vanished. Reading the board immediately after the apply showed
-- `handlers_that_have_actually_produced_an_effect` twice and
-- `handlers_not_writing_a_business_object` not at all. Corrected here by closing the original's
-- emit before the insertion. **A routine that emits rows must be verified by reading its rows, not
-- by the apply tool printing success** — the read-back compares the body to the file, and the file
-- was wrong.
-- =================================================================================================

CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_rules int; n_reg int; n_out int; n_unres int; n_alwaystrue int;
        n_can int; n_deleg int; n_held int; n_exec int;
begin
  select count(*) into n_rules from public.phase_b_business_rule;
  select count(*) into n_reg   from public.phase_d_rule_enforcement;

  check_name := 'every_frozen_rule_has_an_enforcement_row';
  expected := n_rules::text; actual := n_reg::text; ok := (n_reg = n_rules); return next;

  -- A named mechanism that does not exist is prose. Every enforcement_point naming a public
  -- routine is resolved in pg_proc; the two naming a table are resolved in pg_class.
  select count(*) into n_unres from public.phase_d_rule_enforcement e
   where e.enforcement_point like 'public.fn_%'
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public'
                        and p.proname = split_part(split_part(e.enforcement_point,'.',2),'(',1));
  check_name := 'every_named_enforcement_routine_resolves';
  expected := '0'; actual := n_unres::text; ok := (n_unres = 0); return next;

  select count(*) into n_out from public.phase_d_rule_enforcement where status = 'OUTSTANDING';
  check_name := 'rules_with_outstanding_enforcement';
  expected := '0'; actual := n_out::text; ok := (n_out = 0); return next;

  -- The regression guard: the routine this replaced ended with an unconditional ok := true.
  select count(*) into n_alwaystrue
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_d_rule_check'
     and pg_get_functiondef(p.oid) !~ 'rule_unregistered';
  check_name := 'rule_check_refuses_an_unregistered_rule';
  expected := '0'; actual := n_alwaystrue::text; ok := (n_alwaystrue = 0); return next;

  -- ---- E10. WHAT "ENFORCED" MEANS ON THIS BOARD, SAID BESIDE THE NUMBER ----------------------
  -- rules_with_outstanding_enforcement counts phase_d_rule_enforcement.status, which is ENFORCED on
  -- all 54. That is a statement about a declared MECHANISM. It is not a statement about whether the
  -- predicate can produce a refusal, and the two were being read as one.
  -- fn_phase_d_rule_can_refuse() already answers the harder question by driving each rule against
  -- three probe contexts. Its answer has never been on this board. It is now, as disclosure rows:
  -- the mechanism count does not move, and a reader can no longer take 54/54 for 54 that refuse.
  select count(*) into n_can from public.fn_phase_d_rule_can_refuse() where can_refuse;
  check_name := 'rules_whose_predicate_can_actually_refuse';
  expected := 'informational — 54/54 ENFORCED is a mechanism count, not this';
  actual := n_can::text || ' of ' || n_reg::text
         || ' produce ENFORCED_FAIL on at least one of the three probe contexts';
  ok := true; return next;

  select count(*) into n_deleg from public.fn_phase_d_rule_can_refuse()
   where not can_refuse and note like 'delegated%';
  check_name := 'rules_the_kernel_guard_decides_not_the_predicate';
  expected := 'informational — enforced, and not by anything this predicate can invoke';
  actual := n_deleg::text || ' rule(s) delegated to a kernel guard';
  ok := true; return next;

  select count(*) into n_held from public.fn_phase_d_rule_can_refuse()
   where not can_refuse and note like 'constant%';
  check_name := 'rules_constant_while_a_founder_hold_stands';
  expected := 'informational — the founder''s to lift, not a defect';
  actual := n_held::text || ' rule(s) cannot vary while the provider hold stands';
  ok := true; return next;

  select count(*) into n_exec from public.fn_phase_d_rule_can_refuse()
   where not can_refuse and note not like 'delegated%' and note not like 'constant%';
  check_name := 'rules_enforced_somewhere_other_than_the_predicate';
  expected := 'informational';
  actual := n_exec::text || ' rule(s) enforced at the executor''s capability boundary';
  ok := true; return next;

  -- The four groups must still account for every registered rule. A decomposition that stops
  -- covering its subject is worse than none: the parts would sum to fewer than the whole and
  -- nothing would say so.
  check_name := 'every_registered_rule_carries_a_refusal_class';
  expected := n_reg::text; actual := (n_can + n_deleg + n_held + n_exec)::text;
  ok := (n_can + n_deleg + n_held + n_exec = n_reg); return next;
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_steps int; n_bound int; n_amb int; n_sch int; n_drift int; n_blocked int; n_def int;
        n_produced int;
        n_wired int; n_needwrite int;
begin
  select count(*) into n_steps from public.phase_b_workflow_step;
  select count(*) into n_bound from public.phase_d_handler_binding;

  check_name := 'every_frozen_step_has_a_handler_binding';
  expected := n_steps::text; actual := n_bound::text; ok := (n_bound = n_steps); return next;

  select count(*) into n_amb from public.phase_d_handler_binding b
   where not exists (select 1 from public.phase_b_workflow_step s where s.step_id = b.step_id);
  check_name := 'no_binding_for_an_unfrozen_step';
  expected := '0'; actual := n_amb::text; ok := (n_amb = 0); return next;

  select count(*) into n_sch from public.phase_d_handler_schema;
  check_name := 'two_schemas_per_step';
  expected := (n_steps * 2)::text; actual := n_sch::text; ok := (n_sch = n_steps * 2); return next;

  select count(*) into n_drift from public.phase_d_handler_schema sc
    join public.phase_b_workflow_step s on s.step_id = sc.step_id
   where sc.source_digest <> encode(sha256(convert_to(
           case sc.schema_kind
             when 'input' then coalesce(s.required_inputs,'')
             else coalesce(s.required_output,'') || ' || ' || coalesce(s.acceptance_criteria,'')
           end, 'UTF8')), 'hex');
  check_name := 'no_schema_drift_against_frozen_phase_b';
  expected := '0'; actual := n_drift::text; ok := (n_drift = 0); return next;

  select count(*) into n_blocked from public.phase_d_handler_binding
   where phase_d_status = 'BLOCKED_DEFECT';
  check_name := 'blocked_defects';
  expected := '0'; actual := n_blocked::text; ok := (n_blocked = 0); return next;

  select count(*) into n_def
    from public.phase_d_handler_binding b
    join public.kernel_retired_path rp
      on b.handler_routine like '%' || rp.path_name || '%'
   where rp.disposition = 'DISABLED';
  check_name := 'no_binding_names_a_retired_routine';
  expected := '0'; actual := n_def::text; ok := (n_def = 0); return next;

  -- THE HONEST ONE. Red until a handler actually writes its business object. This check exists
  -- so the 236 NEW_DETERMINISTIC_HANDLER rows cannot be read as 236 steps with a business effect.
  --
  -- Counted as the GAP, not as the coverage, so the number FALLS as the work lands and the
  -- kernel-boards ratchet can cap it. A check reading "0 of 257 wired" would have to be ratcheted
  -- at a number that must grow, which the ratchet cannot express and which would invert its
  -- meaning: it asserts disclosed debt does not get worse.
  select count(*) into n_wired from public.phase_d_handler_binding where business_write_wired;
  select count(*) into n_needwrite from public.phase_d_handler_binding;
  check_name := 'handlers_not_writing_a_business_object';
  expected := '0'; actual := (n_needwrite - n_wired)::text;
  ok := (n_needwrite - n_wired = 0); return next;

  -- E10. WHAT THAT ZERO IS, AND WHAT IT IS NOT. It is derived from the handler's declared call to
  -- fn_phase_d_effect_produce plus a stored boolean — a statement that the PATH EXISTS. It is not a
  -- statement that any handler has ever written a business object, and the two read identically at
  -- a glance because both are the number 0 beside a green tick.
  -- The question it does not answer is on fn_phase_d_effect_state as
  -- steps_with_no_effect_ever_produced, which reads 257 and is this phase's only red. Both numbers
  -- are quoted here so a reader of this board cannot take the green one for the other.
  select count(distinct step_id) into n_produced from public.phase_d_effect_ledger;

  check_name := 'handlers_that_have_actually_produced_an_effect';
  expected := 'informational — the green above says the path EXISTS, this says whether it has RUN';
  actual := n_produced::text || ' of ' || n_steps::text
         || ' steps have ever produced an effect; see fn_phase_d_effect_state.'
         || 'steps_with_no_effect_ever_produced for what holds the remainder';
  ok := true; return next;
end $function$
;
