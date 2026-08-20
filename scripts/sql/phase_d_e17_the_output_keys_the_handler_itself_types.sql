-- E17 — the output keys the handler itself types
--
-- After E16 the input side declares a type for every key and closes every contract. The output side
-- still carried 1,216 `unconstrained` required-key declarations across its 257 schemas, with only
-- `status`, `output`, `denominator` and `numerator` typed. The output contracts were already CLOSED,
-- so an invented key was already refused; what was missing was the type of the declared ones.
--
-- WHERE THE TYPES COME FROM. Not from prose and not from a naming convention. There are 29 distinct
-- output keys in the whole registry, and every one of them is constructed by a single expression in
-- `public.fn_phase_d_handler_execute` — the routine whose output these schemas validate. The type is
-- whatever that expression builds, and it cannot build anything else:
--
--   jsonb_build_array(...)            -> array   acceptance_assertions, evidence_refs, findings,
--                                                assumptions, blockers_resolved
--   v_inputs (the resolved input obj) -> object  captured_verbatim, inputs_used, packet
--   jsonb_build_object(...)           -> object  business_effect
--   format(...) / coalesce(text,...)  -> string  output, source_ref, method, state_change,
--                                                target_object, authorization_ref, decision,
--                                                rationale, authority_ref, receiving_role_id,
--                                                acceptance_criteria, metric, formula, window,
--                                                closure_evidence, verdict, reviewer_role_id
--   a literal                         -> string  status  (already typed, and domain-constrained)
--   p_input->'denominator' / numerator-> number  (already typed)
--
-- `verdict`, `reviewer_role_id`, `denominator`, `numerator`, `formula` and `window` reach the output
-- through `jsonb_strip_nulls`, so they are absent rather than null when unset. A declared type
-- constrains them when present, which is what the validator already does for optional keys.
--
-- This is the same derivation E16 used on the input side and it is checkable the same way: a reader
-- can open fn_phase_d_handler_execute and match each key to the expression that builds it. It is
-- also enforced, not just asserted — `fn_phase_d_handler_execute` validates its own output against
-- these schemas before handing anything to the kernel, so a handler that produced a different type
-- would now refuse itself, and `scripts/checks/phase_d_dispatch_reaches_executed.test.mjs` drives
-- every workflow and would go red.
--
-- No routine is created or replaced here, so there is no grant to revoke.

update public.phase_d_handler_schema s
   set field_types = coalesce(s.field_types,'{}'::jsonb) || (
         select jsonb_object_agg(k, t.declared)
           from unnest(s.required_keys || coalesce(s.optional_keys,'{}')) k
           join (values
                   ('status','string'), ('output','string'),
                   ('acceptance_assertions','array'), ('evidence_refs','array'),
                   ('business_effect','object'),
                   ('source_ref','string'), ('captured_verbatim','object'),
                   ('method','string'), ('inputs_used','object'),
                   ('findings','array'), ('assumptions','array'),
                   ('state_change','string'), ('target_object','string'),
                   ('authorization_ref','string'),
                   ('verdict','string'), ('reviewer_role_id','string'),
                   ('decision','string'), ('rationale','string'), ('authority_ref','string'),
                   ('packet','object'), ('receiving_role_id','string'),
                   ('acceptance_criteria','string'),
                   ('metric','string'), ('denominator','number'), ('numerator','number'),
                   ('formula','string'), ('window','string'),
                   ('blockers_resolved','array'), ('closure_evidence','string')
                ) as t(key, declared) on t.key = k),
       schema_version = 2,
       type_source =
         'E17, 2026-08-20: every output key is typed from the expression in '
         || 'public.fn_phase_d_handler_execute that builds it — jsonb_build_array for the five '
         || 'array keys, the resolved input object for captured_verbatim / inputs_used / packet, '
         || 'jsonb_build_object for business_effect, and format()/coalesce() over text for the rest. '
         || 'The handler validates its own output against this schema before handing anything to '
         || 'fn_kernel_step_complete, so a mismatch refuses the step rather than being recorded. '
         || 'Prior type_source: ' || left(coalesce(s.type_source,'(none)'), 260)
 where s.schema_kind = 'output';

do $$
declare v_unconstrained int; v_open int; v_untyped_keys text;
begin
  select count(*), coalesce(string_agg(distinct k, ', '),'')
    into v_unconstrained, v_untyped_keys
    from public.phase_d_handler_schema s, lateral unnest(s.required_keys || coalesce(s.optional_keys,'{}')) k
   where s.schema_kind = 'output'
     and coalesce(s.field_types->>k, 'unconstrained') = 'unconstrained';
  select count(*) into v_open from public.phase_d_handler_schema
   where coalesce(additional_properties, true);

  if v_unconstrained > 0 then
    raise exception 'E17 did not finish: % output key declarations still unconstrained (%). A key the mapping missed must be added, not left open.',
      v_unconstrained, v_untyped_keys;
  end if;
  if v_open > 0 then
    raise exception 'E17: % schemas are still open to further keys after E16 closed the input side', v_open;
  end if;
end $$;
