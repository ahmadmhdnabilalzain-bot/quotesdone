-- THE FOUNDER RESERVES THE TARGET, NOT EVERY RUN TOWARD IT (autonomy audit, blocking gap 4, part A).
--
-- MEASURED. fn_phase_d_founder_authority already encodes the founder's 26-Aug refund-only ruling: a
-- founder boundary reserves the ACT only when it has NO CONSTRAINS_THE_CONFIGURATION disposition (it
-- fails closed). Only FDR-002 carried a disposition, so eight other boundaries defaulted to reserving,
-- and every workflow they name was blocked whole — 13 operational workflows could not run a single step
-- autonomously even where nothing about that step is reserved.
--
-- THIS FILE disposes the TWO boundaries whose frozen enforcement text unambiguously constrains the
-- CONFIGURATION rather than reserving a per-run act:
--   FDR-003  "Company revenue objective" — the AED 1,000,000 target. "Management may operationalize but
--            not replace." The founder OWNS the target; pursuing it is the delegated, autonomous act.
--   FDR-005  "Company identity and permanent policy" — brand, positioning, permanent policy.
--            "Departments operate within approved policy." The founder OWNS the policy; operating within
--            it is delegated.
-- This is a faithful application of his standing ruling (FDR-002 disposition, 26 Aug 2026: "regarding
-- the refund, that's the only thing where my decision is involved"): he sets the target and the brand;
-- pursuing/operating within them is automatic. Changing either reverts here — the disposition names the
-- enforcement text's digest, and an amendment stops it matching, failing closed to reserving.
--
-- REFUNDS ARE NOT TOUCHED. Neither FDR-003 nor FDR-005 names W17 (the refund workflow); the refund act
-- stays reserved by FDR-010 (undispositioned) and by z00_refund_founder_decision_only on public.refunds.
-- The genuinely-reserving boundaries (FDR-001/004/006/007/008/009/010) are LEFT reserving — this loosens
-- nothing the founder holds. It fully delegates the workflows covered by these two alone (W20, W25).
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_reserves_the_target_not_every_run_toward_it.sql --apply --ddl

begin;

insert into public.phase_d_founder_boundary_disposition
  (boundary_id, disposition, founder_ruling, enforcement_digest, recorded_at)
select b.boundary_id, 'CONSTRAINS_THE_CONFIGURATION',
       'Applied from the founder''s standing ruling that the refund is the only act reserved to him '
       || '(recorded in the FDR-002 disposition, 26 Aug 2026). '
       || case b.boundary_id
            when 'FDR-003' then 'FDR-003 reserves the AED 1,000,000 revenue TARGET he set — management '
                              || 'operationalizes it but may not replace it — so pursuing the target is '
                              || 'the delegated act; only changing the target is his.'
            when 'FDR-005' then 'FDR-005 reserves the company IDENTITY and permanent policy he set — '
                              || 'departments operate within it — so operating within the brand and '
                              || 'policy is the delegated act; only changing them is his.'
          end
       || ' The configuration is his; the per-run act is delegated. Refunds remain held by FDR-010 and '
       || 'z00_refund_founder_decision_only on public.refunds, neither touched here.',
       encode(sha256(convert_to(b.phase_b_enforcement, 'UTF8')), 'hex'),
       now()
  from public.phase_b_founder_boundary b
 where b.boundary_id in ('FDR-003', 'FDR-005')
   and not exists (select 1 from public.phase_d_founder_boundary_disposition dp where dp.boundary_id = b.boundary_id);

commit;
