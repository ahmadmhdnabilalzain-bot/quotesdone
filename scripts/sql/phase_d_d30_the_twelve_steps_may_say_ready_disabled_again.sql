-- =================================================================================================
-- Phase D — D30. The twelve steps may say READY_DISABLED again, because now it is true.
--
-- D12 reclassified 12 steps from EXTERNAL_ADAPTER_READY_DISABLED to
-- EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT because READY_DISABLED was claiming a contract that did not
-- exist: 8 of the 14 contract fields were ABSENT or PARTIAL. That was the right call and it is why
-- this file can be written at all.
--
-- D29 built the contract. All 14 fields now read PRESENT, and each is backed by a CHECK constraint
-- or a refusal in the adapter rather than by a sentence — fn_phase_d_external_field_state() derives
-- every one of them from pg_constraint and prosrc, so the stored table is a projection of the
-- mechanism instead of an opinion about it. 84 of 84 mock cases pass across the 12 steps.
--
-- So READY_DISABLED is now accurate: the adapter is READY, and it is DISABLED — provider_mode is
-- CHECKed to mock, the routine refuses any other mode, and it contains no network call of any kind.
-- The control below refuses this file unless all 14 fields are PRESENT, so the classification
-- cannot run ahead of the contract a second time.
-- =================================================================================================

begin;

update public.phase_d_step_effect
   set implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED'
 where expected_effect_type = 'EXTERNAL_EFFECT_INTENT'
   and implementation_depth = 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT';

do $ctl$
declare v_absent text; v_ready int; v_notbuilt int; v_red int;
begin
  select string_agg(field_no || ' ' || field_name, ', ' order by field_no) into v_absent
    from public.fn_phase_d_external_field_state() where state <> 'PRESENT';
  if v_absent is not null then
    raise exception 'D30 control: the contract is not built — field(s) %. READY_DISABLED would be claiming it again.', v_absent;
  end if;

  select count(*) filter (where implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED'),
         count(*) filter (where implementation_depth = 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT')
    into v_ready, v_notbuilt
    from public.phase_d_step_effect where expected_effect_type = 'EXTERNAL_EFFECT_INTENT';
  if v_notbuilt <> 0 then
    raise exception 'D30 control: % external step(s) still read CONTRACT_NOT_BUILT.', v_notbuilt;
  end if;
  if v_ready <> 12 then
    raise exception 'D30 control: % external step(s) read READY_DISABLED and 12 are expected.', v_ready;
  end if;

  select count(*) into v_red from public.fn_phase_d_external_state() where state = 'RED';
  if v_red > 0 then
    raise exception 'D30 control: fn_phase_d_external_state() has % red check(s).', v_red;
  end if;

  raise notice 'D30: 12 external steps read EXTERNAL_ADAPTER_READY_DISABLED, 14/14 fields present.';
end $ctl$;

commit;
