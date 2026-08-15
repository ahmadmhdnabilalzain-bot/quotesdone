-- Phase B — record the tagged commit on the baseline, now that it exists.
--
-- The founder's approval asked for "final Git commit". The baseline was recorded at
-- 675c111eb465986f6003fef336ac53dc561609c2, which is the tree the registry digests were computed
-- from. The FINAL commit is 763e318d574a74ef8a78926cc5f52344c534a2f6, the merge that carries both
-- the architecture and its freeze, and the commit the tag points at:
--
--   git rev-list -n 1 phase-b-founder-approved-2026-08-15   ->  763e318d574a…
--
-- Both are recorded, and the difference is stated rather than left to be found. That is the
-- whole point: Phase A recorded final_commit = d5107300 while its tag sits on 00f1f47, with
-- nothing explaining the gap, and a future reader comparing the two finds a discrepancy that
-- looks like a mistake and is not one.
--
-- Nothing between the two commits touched a phase_b_* registry row. That is not an assumption —
-- fn_phase_b_baseline_drift() returns zero rows at the tagged commit, which is exactly the
-- statement that the digests taken at 675c111 still describe the tagged tree. The verification
-- block below re-checks it rather than trusting this comment.

set lock_timeout = '8s';
set statement_timeout = '600s';

update public.org_phase_baseline
   set final_commit = '763e318d574a74ef8a78926cc5f52344c534a2f6',
       counts = counts || jsonb_build_object(
         'digests_computed_at_commit', '675c111eb465986f6003fef336ac53dc561609c2',
         'final_commit_note', 'final_commit is the tagged merge that carries the approved '
           || 'architecture and its freeze. digests_computed_at_commit is the tree the registry '
           || 'checksums were taken from. Nothing between them touched a registry row, which '
           || 'fn_phase_b_baseline_drift() returning zero at the tagged commit is the proof of.')
 where phase = 'B';

do $$
declare v_drift bigint; v_commit text;
begin
  select final_commit into v_commit from public.org_phase_baseline where phase = 'B';
  if v_commit <> '763e318d574a74ef8a78926cc5f52344c534a2f6' then
    raise exception 'phase_b: final_commit was not recorded, found %', coalesce(v_commit, '<null>');
  end if;

  -- the load-bearing assertion: the digests recorded before the freeze still describe the
  -- tagged tree. If they did not, this file would be relabelling a baseline that had moved.
  select count(*) into v_drift from public.fn_phase_b_baseline_drift();
  if v_drift <> 0 then
    raise exception 'phase_b: baseline drifted (% row(s)) — the recorded digests do NOT describe '
      'the tagged commit, and final_commit must not be relabelled', v_drift;
  end if;
  raise notice 'phase_b: final_commit recorded as the tagged merge; drift 0, digests still describe it';
end $$;
