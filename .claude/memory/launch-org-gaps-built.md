---
name: launch-org-gaps-built
description: "The 16 org-audit gap items (survival, spine, events, authority, upgrades) are built, proven, and merged onto PR #476."
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T08:12:26.622Z
---

**MERGED 1 Sep 2026.** The founder authorized merging PR #476 to main ("fine merge it"), overriding
the session brief's "never merge the launch branch" line — his in-chat instruction wins over a brief
line. Merge commit c69ce50 (merge-commit, NOT squash, to keep the 68 commits' per-change reasoning).
The deciding fact: the branch changed ZERO customer-facing files (no src/app/components) and everything
was already live via production-direct, so merging shipped nothing new — it only made main's
source-of-truth match production (main had been 68 commits behind live). Go-forward model he accepted:
launch upgrades merge INCREMENTALLY as each is proven, not one big-bang merge, precisely because it is
all backend-already-live and carries no user-facing risk. NB a main push runs a "deploy edge functions"
workflow, but it re-syncs bytes already deployed by production-direct.

1 Sep 2026: the full org-audit gap list (from artifact 4d6c8bfb) was built on branch
launch-readiness-plan-2026-08-27 / PR #476, each proven by an aborted-tx probe and CI-gated in
`scripts/checks/org_connectivity_scenarios.test.mjs` (119 assertions) and `..._signal_path.test.mjs`
(29). What now exists:

- **A** os_incidents get owner/acknowledged_at/due_at + a linked org_task + an SLA watchdog (table
  triggers, all writers); the exec meeting surfaces runway/cash/burn from `fn_ws_finance` + a
  `report_type='finance'` board report; Customer-Experience and Assurance each got their own
  operating_system (os_department remapped); W29 security workflow is accountable to
  cybersecurity_engineer (PACR-003/PBCR-003).
- **B** org_tasks.objective_id + employee_kpi.serves_objective stamped at source + backfilled
  (dead sole-objective fallback replaced by the department's primary objective).
- **C** the five missing event emitters (content.drafted/customer.churn_signal/customer.complaint/
  campaign.published triggers + a department.conflict detector); goal retirement re-plans through the
  kernel via a NEW RUNTIME workflow `goal_retirement_replan` in `public.workflow` (Phase C, NOT the 30
  frozen phase_b_workflow) — and the broken goal.retired emit (`fn_emit_event` called positionally,
  swallowed) is fixed to use `fn_emit`.
- **D** the executor gate got teeth: fn_check_spend on request amount, second_authority + a CHECK on
  money executors, autonomy-block refusal, escalated-remediation consumer; `fn_promotion_review` (the
  demotion mirror); `decision_policy.apex_backup='ops_director'` consulted before the exec fallback.
- **E** action_execution.author mandatory + self-approval fails closed; W14-S05 binding fixed to
  quote_evaluation + a step-owner parity check; cross-department reviewer independence on 10 workflows
  (PACR-004/PBCR-004, see [[workflow-ownership-frozen-in-both-baselines]]); agent_brain handoffs open a
  real contract via fn_handoff_open when complete; outcome grading self-pauses on the hold (its cron and
  the 4 new A/C/D crons are LEFT DISABLED until classified in phase_c_source_cutover + wrapped via
  fn_kernel_cron_exec — an active work-creating cron on a kernel-watched relation reddens the Phase C
  kernel gate + kernel_positive_controls otherwise).

Two CI reddenings the 16-item build caused, both fixed on the branch (root cause = a legitimate change
that a frozen check still described the old way, NOT a weakening):
- E13 dropped W14 from fn_phase_c_step_owner_valid's overlay hardcode (W14-S05 is quote_evaluation now,
  per PBCR-001), so phase_c_guards_reject_injected_defects' positive control `fn_phase_c_step_owner_valid
  ('W14-S05','relevant_category_overlay')=true` went stale — repointed at W05-S03 (still overlay-ownable).
- A2 grew os_incidents 11->16 columns, so PHASE_D_BUSINESS_OBJECT_RESULT.csv's live shape-md5 read-back
  for the `incident` object drifted — regenerate with `node scripts/phase_d/build_business_object_result.mjs`
  (the deliverables check strips generated_at; only the shape cell is meaningful). ANY column added to a
  Phase-D-bound table drifts this CSV.

Post-merge full §9 sweep (1 Sep 2026, all clean for this work): main CI all green; Phase A/B/C drift
[]; deploy parity 202/202 functions live; security advisors 725 all pre-existing/accepted (none of
this session's functions in any WARN — they all pin search_path + REVOKE PUBLIC); fn_os_portals_gates
21/23 (the 2 not_met = stand-down/unfunded: 0-of-0 ai_cost_log, and watch_failed_runs_hourly off —
it POSTs alert_founder so re-enabling is HIS call). Row #3 (SPEC #3 exec-UI) 107/152; the ONE
regression from this session — `exec-meeting-ten-participants` — is a STAND-DOWN ARTIFACT, not a gap:
A4 added 2 OS (customer_experience, assurance), the exec meeting reads os_review, and fn_os_review is
count-agnostic (drives off v_os_health which already lists all 12) but last ran W33 before A4. PROVEN
by aborted-tx probe: `perform fn_os_review()` created 12 reviews for W36 incl. both new OS
(new_os_reviewed=2), rolled back. LENS: adding an entity to a count-agnostic per-entity pipeline reads
as a scorer regression until the pipeline next runs — prove count-agnosticism with a probe, don't seed
rows (that is work during the hold). Pack scorecard NOT run (orthogonal KB; forbidden concurrent with
Row #3). pg_get_functiondef throws on aggregates — filter prokind='f' when scanning all functions.

Traps hit: `cron.schedule` does NOT flip a disabled job's active flag — use
`cron.alter_job(jobid, active:=true)`. `fn_emit` writes company_event (what `fn_workflow_start_due`
reads); `fn_emit_event` is a trigger function, not a callable helper. Reputation/promotion/outcome
grading all self-pause on an open `company_stand_down` row — respect it in any new scorer.
Ledger sync after superseding a routine: `application_source_of_truth.test.mjs --emit-ledger-sync` →
a `*_ownership_ledger.sql` file, apply `--ddl`, add to MANIFEST.
