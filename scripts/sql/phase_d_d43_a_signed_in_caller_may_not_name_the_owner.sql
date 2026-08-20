-- =================================================================================================
-- Phase D — D43. A signed-in caller may not name the owner whose records it reads.
--
-- fn_phase_d_object_read(jsonb) is SECURITY DEFINER, is granted EXECUTE to `authenticated`, and takes
-- the identity it filters on from the request body:
--
--     phase_d_d2_business_object_map.sql:635
--       and (b.ownership_scope = 'COMPANY' or r.owner_ref = v_ref)
--
-- where v_ref is p_input->>'caller_ref'. Its comment-stripped body contains zero references to
-- auth.uid(), auth.jwt(), request.jwt, current_user or session_user. It serves nine owner-scoped
-- objects out of public.phase_d_object_record: customer_case, customer_selection,
-- customer_terms_acceptance, supplier_correction_case, supplier_coverage_case,
-- supplier_retention_case, supplier_safe_package, supplier_terms_acceptance,
-- supplier_verification_case. The only thing the guard enforces is that SOME ref is named — omitting
-- it raises pd_object_owner_unstated, and naming somebody else's returns their row.
--
-- CONFIRMED BY EXECUTION, not inferred: seeding one record under owner A and one under owner B, then
-- reading as `authenticated` with auth.uid() null, returned B's payload for caller_ref B and A's for
-- caller_ref A. The table holds 0 rows in production, so this is precisely the case where a zero
-- cannot tell a dead guard from an idle system.
--
-- WHAT THIS FILE DOES NOT DO, AND WHY. The remediation plan's E1 says derive caller_ref from
-- auth.uid(). Measured, there is nothing to derive it against: phase_d_object_record.owner_ref is
-- text and holds 0 rows, customers.id is uuid, leads.id is bigint, and no writer has ever
-- established which of those owner_ref carries. `where r.owner_ref = auth.uid()::text` would invent
-- a contract no writer honours and go green over an empty table — a guard that has never been seen
-- to refuse anything.
--
-- The honest fix is the one the acceptance document itself offers as its alternative, and it is what
-- fn_phase_d_object_write already has: the routine is not client-callable. It has no caller — zero
-- edge functions, zero frontend, zero database routines reference it — so the `authenticated` grant
-- is attack surface and nothing else. When a real reader is built it will arrive with a real
-- identity contract, and that is the increment that earns a session-derived predicate.
--
-- PUBLIC IS NAMED FIRST. A revoke from anon alone is a silent no-op while the grant is held through
-- PUBLIC. Measured here the ACL is {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
-- with no bare =X/postgres, so the earlier PUBLIC revoke did land — public is still named because the
-- next person to read this file should not have to re-derive that.
--
-- AND THE GRANT MUST BE APPLIED, NOT PROMOTED. apply_sql --promote sends only the routine body: a
-- REVOKE in the same file would land nowhere and still print success. This file carries no body, so
-- it must be applied with --apply --ddl and the ACL read back out of pg_proc.proacl. Re-applying
-- phase_d_d2_business_object_map.sql after this file silently reverts it, because :711 there still
-- grants to authenticated. That line is corrected in the same commit.
-- =================================================================================================

revoke execute on function public.fn_phase_d_object_read(jsonb) from public, anon, authenticated;
grant  execute on function public.fn_phase_d_object_read(jsonb) to service_role;


-- ---- CONTROL — the ACL, and the refusal, tested AS THE ROLE -------------------------------------
-- A SECURITY DEFINER routine reads its own identity from inside, so `current_user` proves nothing
-- here. The only test that means anything is executing it as `authenticated`.

do $ctl$
declare
  v_acl text;
  v_anon boolean; v_auth boolean; v_svc boolean;
  v_denied boolean := false;
  v_rows int;
begin
  select coalesce(p.proacl::text,'(null)'),
         has_function_privilege('anon',          p.oid, 'EXECUTE'),
         has_function_privilege('authenticated', p.oid, 'EXECUTE'),
         has_function_privilege('service_role',  p.oid, 'EXECUTE')
    into v_acl, v_anon, v_auth, v_svc
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'fn_phase_d_object_read';

  if v_anon or v_auth then
    raise exception 'D43: fn_phase_d_object_read is still executable by % — acl %',
      case when v_anon and v_auth then 'anon and authenticated'
           when v_anon then 'anon' else 'authenticated' end, v_acl;
  end if;
  if not v_svc then
    raise exception 'D43: the revoke removed service_role EXECUTE, which is the grant a real reader would use. acl %', v_acl;
  end if;
  if v_acl like '%=X/postgres%' and v_acl not like '%postgres=X/postgres%' then
    raise exception 'D43: a bare PUBLIC grant survives on the ACL: %', v_acl;
  end if;

  -- POSITIVE CONTROL FOR THE CHECK ITSELF: the routine must actually refuse a call made as the role.
  -- Without this the three booleans above are a catalogue reading, not a measurement of behaviour.
  begin
    set local role authenticated;
    perform public.fn_phase_d_object_read(jsonb_build_object(
      'object_id','customer_case','caller_scope','CUSTOMER','caller_ref','ZZ-DEMO-D43-B'));
  exception
    when insufficient_privilege then v_denied := true;
    when others then
      reset role;
      raise exception 'D43: executing as authenticated raised % (%) rather than insufficient_privilege — the revoke is not what stopped it.',
        SQLERRM, SQLSTATE;
  end;
  reset role;
  if not v_denied then
    raise exception 'D43: fn_phase_d_object_read answered a call made as authenticated.';
  end if;

  -- NEGATIVE CONTROL: service_role must still be able to call it, or this is an outage, not a fix.
  begin
    perform public.fn_phase_d_object_read(jsonb_build_object(
      'object_id','customer_case','caller_scope','CUSTOMER','caller_ref','ZZ-DEMO-D43-B'));
  exception when others then
    raise exception 'D43: the owner can no longer call the routine either: % (%)', SQLERRM, SQLSTATE;
  end;

  select count(*) into v_rows from public.phase_d_object_record;
  raise notice 'D43: fn_phase_d_object_read is service_role only (acl %); a call as authenticated is refused; phase_d_object_record holds % rows.',
    v_acl, v_rows;
end
$ctl$;
