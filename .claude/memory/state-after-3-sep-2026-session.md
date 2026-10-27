---
name: state-after-3-sep-2026-session
description: "where the autonomous-company build stands after the 3 Sep 2026 session (branch deterministic-engine-2026-09-03, PR #490): what is proven in the sandbox, what the founder alone must supply, what the next session should pick up first"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T06:59:05.098Z
---

**Proven by execution on production, 3 Sep 2026** (all fixtures torn down, kernel orphan board clean):
- `rehearse_revenue_loop.mjs` 11/11 and `rehearse_full_funnel.mjs` 20/20: invite link → claim with a real
  account → licence-facts trigger approval (no human) → matchable → inquiry → matching → 3 quotes →
  deterministic best-3 (model held) → real Stripe Checkout session for the 3% fee (expired at once) →
  signed completion event → transaction paid, both parties emailed AND WhatsApped (via trg_wa_fanout) →
  customer reads the contact ([[revenue-loop-mechanics-proven-blocker-is-data]]).
- `rehearse_ad_spend.mjs` 19/19: the autonomous Meta spend manager ([[ad-spend-autopilot-built]]).
- Deterministic runtime: fn_apply_playbook, 82% of steps without the model; 5 functions record a held
  model as skipped, the action collector parks held actions ([[rehearsals-and-probes-page-the-founder]]).
- Founder-noise instruments fixed the same day: alert dedupe key stored, rehearsal windows, silence
  paged once per episode, legacy-secret view windowed, cron watchdog respects activation, os_review
  logs findings not errors, portal gate reads a held model as idle.

**3 Sep, afternoon — connectors.** The founder connected the Meta Ads MCP and the Stripe MCP to this session (not the
platform). Measured: Meta ad account 10151242677262668 (AED, ACTIVE, payment method on file) equals
app_secrets.meta_ad_account_id; it holds ONE QuotesDone campaign (120247871214360016, PAUSED, AED 0 spent) among the
founder's personal DJ campaigns (meta_campaign_filter keeps those out). Stripe: live acct_1To5DvC45SqX5pVb and a
separate SANDBOX acct_1To5EBFr2iPnkzTM. A sandbox webhook endpoint (we_1UBcGAFr2iPnkzTMH3Fp6CTR) now points at the
platform and its secret is stripe_webhook_secret_test; a REAL test-mode payment (pi_3UBcJXFr2iPnkzTM0z1s5rIz, AED
3,540) was paid by test card through a sandbox Payment Link and the platform recorded the reveal from Stripe's own
event — rehearse_stripe_test_payment.mjs 5/5 (PR #492). The MCP key cannot create Checkout Sessions (use Payment
Links) and cannot mint keys: the platform still needs meta_access_token for the ad autopilot to act.

**Only the founder can supply** (say so in the hand-over, never ask him technical questions):
- `app_secrets.meta_access_token` (ads_management) — the one switch for the ad autopilot.
- Stripe test mode (stripe_secret_key_test / stripe_webhook_secret_test) or a live card — the harness
  created a harness-only stripe_webhook_secret_test; his replaces it.
- Meta approval of the WhatsApp template `supplier_quote_accepted` (submitted 3 Sep, both languages).
- Real suppliers: the invite campaign is built but OFF (invite_enabled='false' since 4 Sep — his switch; crons supplier_invites_daily /
  invite_ramp_daily inactive) — his go decides when real emails leave.

**Row #3 scorer** (verify_os2_blueprint.mjs): 112/152 before the cron re-enables, 117/152 (77%) after, 4 items ERROR (management-API transport timeouts, infrastructure not findings). Pack scorecard: third-party kb_chunks kinds (book/manual/paper/spec…) 0% embedded by scope; company kinds 97-100%.

**PR #491** (founder-signal-hygiene-2026-09-03): cos_execute cross-department refusal logged as skipped + post-deploy verifier outlasts the 429 window — MERGED (81256d7).

**Still open, engineering** (next session, in this order): the Row #3 scorer's MISSING items that
are stand-down consequences (time-machine snapshots, nightly reflection now re-enabled, exec meeting
re-enabled 3 Sep — measure next Monday); the pack scorecard shows third-party reference kinds (book,
manual, paper, spec…) NOT EMBEDDED — a knowledge-track choice, not a loop defect; evolution loop
guardrails (§3) only matter once something auto-implements; departments with rosters but 0 runs are
idle because the marketplace has no events, not dead — do not schedule empty runs.

**Crons (3 Sep, later)**: 97 active. Re-enabled today beyond the 13 self-management ones: exec_meeting_weekly,
company_reflect_nightly, and 18 pure-SQL measurement crons (scripts/sql/reenable_measurement_crons.sql — each read
for what it writes first). Deliberately still OFF: outcome_evaluate_daily and reputation_weekly (held by the open
reputation stand-down that fn_reputation_hold_state asserts — re-enabling one reddened the kernel gate),
capability_verify_daily (pages the founder), every cron that sends, bills, bans, invites or calls an edge function.
Re-enabling a stand-down cron = wrap with the crosswalk role/dept/authority + Phase D row + cron_registry row.

**CI**: production-direct applies redden every OLDER commit's "repo and database agree" run
([[the-window-between-apply-and-merge]]); only the head's run matters, runs serialise (~10 min each),
so stop pushing before you need a green head. PR #490 MERGED into main at 07:53Z on 3 Sep 2026 (merge commit 7523ac8) with every check green. New work goes on a new branch from main.

## Later on 3 Sep 2026 (PR #493, branch master-plan-open-items-2026-09-03)
- MASTER_PLAN 5.2 items closed on production: #1 shared Stripe event list, #2 doc_render answers
  the hold (the "bypass" was a stale diagnosis), #7 (secrets were never in query strings; Referer
  closed), #10 quote_quality shape, #11 supplier honesty text, B1 preview gets no prod target,
  5.3 refund roles → decision_policy, secops allow-list → app_secrets.admin_emails, legacy
  credential id 1 retired, cron 124 cos_execute_hourly deactivated (0 tasks worked in 7d vs 81 by
  the kernel's employee_task spine), deploy.completed emitted by deploy_functions.mjs (proven →
  change_deployment run), lead_to_customer + contract_review deactivated (no emitter).
- STAFF_ORG re-carve applied as PACR-004 in 6 SQL files (staff_org_recarve*_2026_09_03.sql):
  10 depts (supply new, assurance merged into product_eng), 71 seated / 24 parked, every Phase
  B/C binding moved. Plan wanted ~48: 22 Phase B handoffs refuse the merge — see
  [[a-merge-that-collapses-a-handoff]]. COO keeps 237 kernel-default components (exec dept).
- ERP/GL "66 orphans" are a recorded deferral in phase_c_component (DEFERRED_RUNTIME_IMPLEMENTATION
  / WIRE_TO_CANONICAL), not drift — do not delete.
- Founder-only inputs unchanged: meta_access_token, WhatsApp template approval, real suppliers,
  the go for real invites. Stripe live keys already held.
- Row #3 scorer 3 Sep evening: 116/152 with 3 items ERROR "transport failed after 7 attempts"
  (genome-inherited-by-every-employee, s27-knowledge-seven-fields, s39-governance-can-pause).
  These are the scorer's single-query timeout, not the company: the genome fact measured one
  employee at a time is 11 of 11 attributes reaching all 71 active employees (fn_agent_context
  0.5–1.3 s and ~257 KB per employee; 71 in one statement exceeds the management API timeout).
- Pack scorecard NOT run: the extracted packs directory (--packs=) is recorded nowhere in the
  repo, skill or memory.

## 4 Sep 2026 — mirror gates retired, five agents integrated (PR #502, branch integration-2026-09-04)
- The two kernel gates the founder called a design issue: every check that compared production to a
  COPY in git is retired ([[mirror-gates-are-retired]]); production now proves its own properties
  (phase_c_components_are_owned, per-board harness with a 240s budget, ratchets only for gaps that fall).
- Five parallel agents (exec loop, consciousness, intelligence graph, supply engine, routing/reputation)
  merged through ONE integration tree; sibling agents' live applies redden every PR's parity job until
  all merge ([[always-max-parallel-agents]]).
- Row #3 scorer COMPLETE on the integrated state: 142/152 (93%), 0 ERROR. The 10 MISSING are
  calendar-bound (snapshots missing 16–31 Aug during the stand-down; six-month horizon; 4 of 6 meetings
  predate the ranked-priority fix), founder-gated (s26 invites: invite_enabled='false' is his switch),
  or the scorer's one-statement timeout (genome measured per employee is 11/11 across 71).
- Real defects found by the gates this day, all fixed + proven: fn_outcome_evaluate could not run twice
  in one transaction; two connectivity probes borrowed production's stand-down state
  ([[a-probe-that-borrows-production-state]]); dr_drill's after-response cleanup never ran and its
  PostgREST pre-clear could not reach a normal residue ([[work-after-the-response-never-ran]]) —
  monthly drill driven through fn_kernel_cron_exec(55): 11/11, dr_restore 0 rows after.
- sql_files_match_live is RETIRED; the canonical engine + application_source_of_truth (7 lines, 0) are
  the SQL parity now. The positive-control reporter prints a door's raise on FAIL (was
  accepted=undefined with the reason discarded).
- Founder inputs unchanged: meta_access_token, WhatsApp template approval, real suppliers + the go for
  invites (invite_enabled is 'false' — the supply agent found it open and closed it).

## 4 Sep 2026, later — MASTER_PLAN + STAFF_ORG finished by seven agents (PR #510 → main 7aa7174)
- Founder asked "are these fully done?" then "send as many agents as it takes". Seven packets ran in
  parallel, integrated through ONE tree (PRs #503–#509 → #510). Every gate green on main.
- Org: 54 active / 42 parked, 12 leads over 42 workers, every active seat passes the binding rule
  (event + executor + scoped playbook; new gate every_active_agent_owns_a_firing_decision), 25 collapsed
  handoffs walked with 0 refusals, 4 net-new seats wired (red_view_alerter is a real role + cron 324).
- Loop: the dead-since-15-Aug step 1 was three defects (never claimed; execution sweep cancelled every
  workflow-created row; applier closes were nearest-neighbour noise → now cosine ≥0.85 + keyword
  corroboration). Runs complete model-off where a corroborated actionable playbook exists;
  change_deployment / metric step 4 / strategic step 3 park as awaiting_model with a reason — they need
  AUTHORED playbooks (next build). Backlog drained honestly (916 → 226 parked coordinate steps).
- Triggers: all 12 have a real emitter or a recorded retirement; 14 phantom subscriptions cut; register
  gained class G (subscription without producer); customer refund path no longer throws on emit.
- Alerter live (15-min kernel cron, one page per episode); it paged the founder once the rehearsal
  windows closed (28 alerted episodes incl. policy_consistency_weekly red since 31 Aug).
- Ads: a pasted Meta token would have spent AED 200/day from an engineering default → cap is the
  founder's number or 0, meta_autospend_golive='false'; docs/FOUNDER_INPUTS.md lists what only he supplies.
- Phase E: frozen baselines dropped (GATE-001 retargeted to a live property), 7 drives retired, one
  routine gate, Phase D job folded into the serial kernel gate, 42 no-caller fns dropped / 8 wired.
- Seams found only at integration (see seven_packets_settle_into_one_estate.sql): two agents on one
  routine, alias kind merged_role not resolved by a board, stale event producers, unregistered crons at
  the scenario door, stale tier=autonomous rows, autofill paging under the hold, ratchets grown by
  declared doors, a board judging in-flight ticks, and a residue delta blaming the running company.

## 5 Sep 2026 — the loop performs the work (five packets, integration-2026-09-05)
- Founder: "what is on me leave it to the end; the rest all need to be done." Five agents, one tree.
- Applier (#513): the close reads the step's OWN facts (fn_workflow_step_facts/render) — distinct
  deliverables = distinct inputs on every rendered step; deterministic executors invoked inline;
  disposition discriminates (determined / advisory_held_model / needs_narrative); used_llm measured
  from llm_attempt + ai_cost_log with used_llm_basis; determination_source added; close floor 0.85.
- change_deployment (#516): its 28 "done" runs had been closed by pasting a playbook; now step 1
  captures a per-function error baseline, step 8 records the deploy's verification as parity, step 9
  DEFERS 60 min then grades the window vs baseline (worse → org_task for Platform, never a revert).
  Real deploy run 37f6bff6: 1→9→done, verified_all, improved. fn_action_invoke_rpc passes
  params||request||{action_execution_id} to a single-jsonb target and honours {defer_until}.
- org_task lane (#515): second closing path = fn_os_incident_close_task + fn_edge_health_scan; both
  now call fn_org_task_close_as_fact; guard a10_org_task_done_needs_a_determination refuses a bare
  done; backlog 453 assigned/51 escalated → 0/0, 528 closed through the spine with reviews, 2 parked
  with a reason; department scores 37–90 → 77–100; 5 department episodes resolved on the alerter's tick.
- Deterministic substitutes (#514): docs/DETERMINATIONS_CENSUS.md — 22 of 43 edge executors are
  model-backed; 152 of 155 held parks since 1 Sep were recommend / exec_review / knowledge_fill_gap;
  fn_recommend_deterministic, fn_exec_review_deterministic, fn_knowledge_gap_deterministic registered.
- Bus (#517): the 13 h median lag was two catch-up populations, not latency (trigger path 0.2 s);
  fn_event_dispatch no longer rolls a batch back on one poison pair; company_reflect_nightly is
  deterministic (reads 2 of 7 nights only because the cron was off — MET after 9 Sep); watcher
  signatures resolve when the subject succeeds; v_cron_stale read a monthly cron as daily.
- Seams: three agents edited fn_workflow_step_claim identically (converged); register class E had to
  learn the invoker passes one jsonb; the incident probe had to close through the fact-close door.
- Still founder-only: meta_access_token + daily cap + go switches, WhatsApp template, real suppliers.

## 6 Sep 2026 — integration PR #518 (13 heads) and what the skeptic found
- integration-2026-09-05 = main + #513 #514 #515 #516 #517 #519; CI reds head by head were: parity
  drift from an in-flight agent apply, an in-flight alerter tick judged failed (ledger now
  `end_time is not null`), a real 21:22Z alerter timeout (class C per-row LIKE → CTE
  trigger_consumed, register 1s), and the no-trace ratchet 10→11 disclosed with that cause.
- Skeptic refutations acted on: 'determined' only with a succeeded action_execution; the collector's
  close carries deliverable + decided_by; cpo@priority.updated retired (25 reorder tasks cancelled);
  lane closes render from fn_org_task_facts (#519).
- Overstatements to carry: change_deployment 'improved' = a quiet hour vs a baseline that was one old
  outage, steps 2–7 are generic health checks; used_llm ledger predicate is time-window-global, not
  keyed to the step; 34 proposed tasks held on missing org_authority rows (supply, analysis);
  edge (HTTP) executors are not queued by the task lane.
- Scorer 143/152; the nine misses are in [[scorer-misses-that-are-clocks-not-defects]].

## 6 Sep 2026 (later) — engineering leftovers + founder approvals are refunds only
- PR #520 (main 25310b7): resend_inbound through the gateway (bypass ratchet 2 -> 1); 62 fn.* credentials
  expire in 1y and rotate 30d ahead (cron 334, alerter arm at 7d); rc4 block gone; retire routine recorded.
- PR #521 (main de40074): founder surfaces read the refund queue only (fn_founder_refund_approvals_open,
  held-with-role everywhere else, OsxShell relabelled, decision_policy names roles, brief DECISIONS NEEDED
  = refunds); held rows went to owners (agent_actions 14 -> 0, org_tasks proposed 34 -> 0 with 16 new
  org_authority rows, decision_record unrouted 7 -> 0, founder_command loops 6 -> 0); cron 243 registered
  for the scenario door. Two CI checks guard it; both skip without the management token.
- Traps hit: Bash tool re-ran a MANIFEST append with its own flags (5 junk lines, removed in #521);
  duplicate `gh workflow run` dispatches contended on the scenario door.
- Still founder-only: Meta token + cap + go switches, invite_enabled, WhatsApp template, real suppliers.

## 6 Sep 2026 (night) — PR #523: the OS audited button by button in his browser
- main d54ff2c. Reports render as corporate PDFs (report_pdf edge fn, pdf-lib, private bucket,
  triggers via the action invoker; 9 latest rendered); social posts carry permalinks/media/preview
  with honest permalink_missing (24 Postiz drafts imported; nothing has ever been published — his
  switch); receipts book themselves (parser first, bookkeeper task otherwise); resilience watch
  pages once per condition; Knowledge page 10.6 s → 277 ms (kb_category_stats + cron); Automation
  page 10.9 s → 426 ms; Observe/Control Mode drawer removed; Smart Engine lists 54 staff + parked;
  Finance journal entry opens; ⌘K opens modules; one mounted panel at a time; one open-task
  definition; "status" returns the brief; four report types produce again.
- Audit file: scratchpad os_button_audit.md (session-local). Not exercised: Save/Revert, Run now,
  Publish/Generate/delete, model-backed buttons, supplier/document Approve/Reject.
- After the deploy his OS session was gone (sign-in screen; auth token absent from localStorage;
  nothing in #523 touches storage — likely refresh-token reuse by the hung tab). The post-deploy
  browser re-walk is NOT done; verified by tsc/deno/DB probes/CI only.
- Next: the knowledge audit of the 54 agents (five agents writing docs/knowledge_audit/*.md) and
  the per-agent missing-knowledge plan for him to check.

## 6 Sep 2026 (morning after) — PR #524: agents receive their knowledge; founder emailed exceptions only
- Knowledge audit (docs/knowledge_audit/*.md, 11 files) + docs/KNOWLEDGE_PLAN_2026-09-06.md (54 agents,
  P1 234 / P2 281 / P3 148; 15 founder inputs; artifact "QuotesDone Staff Knowledge Plan"). Nothing
  ingested yet — the plan awaits his check. Company-wide actions 6 (reasoning exam half) and 8
  (dept_library for 7 departments) still to do.
- Plumbing landed (branch agents-actually-receive-their-knowledge, 11 commits): LAYER 2 bodies 54/54,
  LAYER 3/4 inside 19,500, hard rules + thresholds in every head, fn_ws_supply, fn_dept_scope in
  LAYER 2c, category packs on category-scoped tasks, embedding backfill under the kernel (crons
  108/242/271; FOR UPDATE SKIP LOCKED claim), exam scoped + 397 fills quarantined, review dates set,
  Governance counts employees. Residue: workflow_dispatch asks fn_agent_context_capped(…, 6000) so
  workflow steps keep only 1,500 chars of head (pre-existing).
- Founder mail: founder_mail_policy (17 allowed / 41 routed), fn_notify_founder(+p_kind) routes to an
  owner task, senders fixed (smoke, backup, handoff watchdog, watchers), audit doc
  docs/EMAIL_AUDIT_info_at_quotesdone_2026-09-06.md. Remediation consumer no longer double-routes.
- His inputs still: WhatsApp founder template, AI credit top-up, Meta token/cap/switches, real
  suppliers, the 15 plan inputs, and signing back into the OS (session dropped after #523's deploy).
