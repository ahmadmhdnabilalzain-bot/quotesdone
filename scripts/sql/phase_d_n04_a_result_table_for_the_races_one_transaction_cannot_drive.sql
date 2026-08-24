-- N04. A RESULT TABLE FOR THE RACES ONE TRANSACTION CANNOT DRIVE.
--
-- public.fn_phase_d_run_injected_defects runs entirely inside ONE aborted transaction. That is what
-- makes it safe, and it is also why every concurrency case in the catalogue carried NOT_RUN with
-- the same reason: "a true race needs TWO concurrent database sessions ... a second claimant cannot
-- exist."
--
-- THE BLOCKER WAS A CLAIM ABOUT THE TRANSPORT AND IT WAS WRONG. Measured 24 Aug 2026
-- (scripts/tmp_diag/conc_probe.mjs): two statements issued together against the management endpoint
-- run on TWO DISTINCT BACKENDS whose transactions overlap in time --
--
--     A pid=1719034  00:48:42.416 -> 00:48:46.419
--     B pid=1719035  00:48:42.420 -> 00:48:46.424
--
-- -- so a session that takes a lock and sleeps is holding it while another session tries to take
-- it. Two concurrent claimants have been available to this harness the entire time.
--
-- THIS TABLE IS THE SAME SHAPE AS public.phase_d_section8_probe_result, and for the same reason:
-- a fact that cannot be produced inside the runner's transaction is produced by a harness that can,
-- recorded, and READ by the runner. What the runner may never do is invent one. The branch that
-- reads this table reports NOT_RUN when it finds nothing, so an unrun probe stays visibly unrun.
--
-- WHAT THE HARNESS IS PERMITTED TO LEAVE BEHIND: nothing. It creates a temporary committed canary,
-- races two sessions on it, removes it, and asserts the relation is back at its starting
-- watermark. The rows in THIS table are audit evidence and are labelled as such -- they are not
-- business activity and must be reported separately from business counts.

CREATE TABLE IF NOT EXISTS public.phase_d_concurrency_probe_result (
  probe_id       text primary key,
  verdict        text not null,
  observed       text not null,
  claimants      integer,
  winners        integer,
  duplicate_effects integer,
  residue        integer,
  audit_run_id   uuid,
  ran_at         timestamptz not null default now()
);

COMMENT ON TABLE public.phase_d_concurrency_probe_result IS
  'AUDIT EVIDENCE, not business activity. One row per two-session concurrency probe, written by '
  'scripts/phase_d/run_concurrency_probes.mjs and read by fn_phase_d_run_injected_defects. Report '
  'these rows separately from business counts.';

-- THE VERDICT VOCABULARY IS CLOSED, so a harness cannot invent a status that means "we did not
-- look" and have the runner read it as a pass.
ALTER TABLE public.phase_d_concurrency_probe_result
  DROP CONSTRAINT IF EXISTS phase_d_concurrency_probe_result_verdict_ck;
ALTER TABLE public.phase_d_concurrency_probe_result
  ADD CONSTRAINT phase_d_concurrency_probe_result_verdict_ck
  CHECK (verdict IN ('REFUSED_AS_REQUIRED','SAFE_SCOPED_RESULT_AS_REQUIRED',
                     'IDEMPOTENT_NO_DUPLICATE','FAIL_CLOSED_AS_REQUIRED',
                     'NOT_REFUSED','NOT_DISCRIMINATED'));

-- A PASS THAT LEFT ROWS BEHIND IS NOT A PASS. The table refuses to hold one, so the zero-residue
-- requirement is enforced where the evidence lives rather than asserted in a document.
ALTER TABLE public.phase_d_concurrency_probe_result
  DROP CONSTRAINT IF EXISTS phase_d_concurrency_probe_result_zero_residue_ck;
ALTER TABLE public.phase_d_concurrency_probe_result
  ADD CONSTRAINT phase_d_concurrency_probe_result_zero_residue_ck
  CHECK (verdict IN ('NOT_REFUSED','NOT_DISCRIMINATED') OR coalesce(residue,0) = 0);

-- A GENUINE RACE NEEDS MORE THAN ONE CLAIMANT AND EXACTLY ONE WINNER. A probe recording a pass
-- with one claimant measured nothing; the table refuses that too, so "the race did not race"
-- cannot be stored as a green result.
ALTER TABLE public.phase_d_concurrency_probe_result
  DROP CONSTRAINT IF EXISTS phase_d_concurrency_probe_result_real_race_ck;
ALTER TABLE public.phase_d_concurrency_probe_result
  ADD CONSTRAINT phase_d_concurrency_probe_result_real_race_ck
  CHECK (verdict IN ('NOT_REFUSED','NOT_DISCRIMINATED')
         OR (coalesce(claimants,0) >= 2 AND coalesce(winners,-1) = 1));

REVOKE ALL ON public.phase_d_concurrency_probe_result FROM PUBLIC;
