-- WHY: Founder's standing spec — "The Command Center is a monitoring dashboard only
-- — not an approval system... Apart from rare high-level instructions the company
-- should run fully unattended." 136 items were parked on the founder (121 agent_actions
-- in needs_review + 15 org_tasks needs_founder). Routine, reversible operational work
-- is re-tiered to autonomous. Money movement, destruction, credentials, external legal
-- acts and third-party bans stay GATED: the founder wants freedom from routine
-- approvals, not from control of money and destruction.

-- Reversible, routine, self-correcting -> autonomous
update org_authority set max_tier='autonomous',
  note='2026-07-29 autonomy policy: publishing is reversible (edit/unpublish); monitoring-only dashboard, no pre-approval'
  where dept_key='marketing' and action_class='content_publish';

update org_authority set max_tier='autonomous',
  note='2026-07-29 autonomy policy: sending is routine sales work, ramp/deliverability caps enforced in flow; PDPL/TDRA consent capture still open (see action 1723)'
  where dept_key='sales' and action_class='outreach_send';

update org_authority set max_tier='autonomous',
  note='2026-07-29 autonomy policy: intake-form changes are versioned and revertible'
  where dept_key='knowledge' and action_class='intake_change';

update org_authority set max_tier='autonomous',
  note='2026-07-29 autonomy policy: defining a role is a reversible document; actual hiring/comp still hits the finance.money_move gate'
  where dept_key='hr' and action_class='role_define';

-- Judgement: deploys are reversible via rollback and it.code_selfheal/incident_fix are
-- ALREADY autonomous (deploy-shaped work ships today without the founder). Pre-approval
-- was inconsistent and is what stalls the company. Moved to supervised: ships through the
-- safety pipeline with post-hoc monitoring, not founder pre-approval. Assumes green CI —
-- CI test jobs (money_tests, qa_suite, meta_sync) are currently failing per action 1724.
update org_authority set max_tier='supervised',
  note='2026-07-29 autonomy policy: ship via safety pipeline + rollback, post-hoc review not pre-approval; requires green CI'
  where dept_key='it' and action_class='code_deploy';

-- Judgement: ad_spend STAYS GATED. It is the one "operational" class that irreversibly
-- spends real money — spent ad budget cannot be clawed back. Drafting/calendaring/creative
-- is already autonomous (marketing.content_calendar, content_draft); only budget activation
-- is gated, so the routine work flows and only the money decision reaches the founder.
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — ad budget is unrecoverable spend; campaigns are built and scheduled autonomously, only activation/budget needs the founder'
  where dept_key='marketing' and action_class='ad_spend';

-- Explicitly retained gates (money / destruction / credentials / external legal / third-party harm)
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — moves real money; hard cap retained'
  where dept_key='finance' and action_class='money_move';
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — irreversible destruction of company/customer data, any dept'
  where dept_key='exec' and action_class='data_delete';
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — permanent commercial harm to a third party, not agent-reversible'
  where dept_key='procurement' and action_class='supplier_ban';
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — credential rotation can lock the company out of its own systems'
  where dept_key='it' and action_class='secret_change';
update org_authority set
  note='2026-07-29 autonomy policy: KEPT GATED — demand letters / PDPL erasure bind the company externally and destroy data'
  where dept_key='legal' and action_class='legal_action';
