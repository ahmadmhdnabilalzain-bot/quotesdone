-- 28 (dept_key, action_class) pairs carry live org_tasks rows and have NO org_authority row, so
-- fn_ops_authority_check has been answering them from its fail-closed default: "no org_authority row
-- for this department and action class - defaulting to gated". Correct behaviour with no auditable
-- statement behind it - the same condition Phase 1.5 fixed for the eight hard gates on 2 Aug.
--
-- WHAT THIS CHANGES, AND WHAT IT DOES NOT.
--
-- It does NOT move any of the 110 existing tasks. org_tasks.status is written once at creation and
-- nothing recomputes it (queue-has-no-approval-path.md). Every one of these pairs stays exactly where
-- it is. This changes how FUTURE tasks are created, and what cos_execute's execution-time re-check
-- resolves to.
--
-- It also does not enable any executor. cos_execute runs a registered executor only when the model
-- grants 'autonomous' AND - since ccbb00c - the executor is registered to the task's OWN department.
-- Checked pair by pair below: every advisory row here is either executor-less, advisory_safe, or
-- points at an executor owned by a different department, so none of them can produce a side effect.
-- No row in this migration is 'autonomous' or 'supervised'.
--
-- WHY 'advisory' AND NOT 'gated' FOR 23 OF THEM.
-- Leaving them undeclared is not neutral. dept_plan (post-ccbb00c) writes status='proposed' for
-- 'gated' and status='assigned' for anything else, and 'proposed' currently means "parked forever":
-- nothing in the database or the repo can promote a proposed task. 'advisory' is the tier that means
-- produce the advice and act on nothing. For work that is a document - a recommendation, a review, an
-- investigation's findings - that is the accurate statement, and it is the one that lets the
-- department do the harmless half of its job instead of filing it into a queue nobody can open.
--
-- The 5 'gated' rows are the ones where the class touches suppliers, identity, or bulk
-- reclassification. Two of them (supplier_success) belong to an INACTIVE department and are declared
-- so that reactivating it cannot silently inherit procurement's autonomy - which is exactly how
-- org_tasks#20 sent 10 real supplier invites on 25 Jul 2026.
--
-- ON THE REASON STRING BELOW.
-- trg_org_authority_guard treats an INSERT as a widening whenever the new tier outranks 'advisory',
-- and refuses it without app.change_reason. The 23 advisory rows do not trip it; the 5 gated ones do.
-- set_config(..., true) is used rather than SET LOCAL so that this works whether or not the migration
-- runner wraps the file in its own transaction, and it is scoped inside the DO block so it cannot
-- leak a blanket reason to any later statement.

do $$
begin
  perform set_config(
    'app.change_reason',
    'Declaring the 28 dept/action_class pairs that carry live org_tasks rows but had no '
    'org_authority row, so every answer for them came from the fail-closed default rather than a '
    'stated decision. 23 advisory (document-producing, no reachable executor), 5 gated (suppliers, '
    'identity, bulk reclassification). None autonomous. See queue-has-no-approval-path.md.',
    true);

  insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note) values

  -- ---- advisory: produces a document, moves nothing ----------------------------------------------
  -- recommend. Precedent: it/recommend is already 'advisory'. The executor (analytics_recommend) is
  -- registered to `it`, so post-ccbb00c none of these six departments can reach it at all.
  ('exec',        'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),
  ('finance',     'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),
  ('knowledge',   'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),
  ('legal',       'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),
  ('marketing',   'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),
  ('procurement', 'recommend', 'advisory', null, '2026-08-04: advisory, matching the it/recommend precedent. Executor analytics_recommend belongs to it, so this department reaches the deliverable path only.'),

  -- exec_review. The output is a meeting document for the founder, not an action. exec_agents is
  -- advisory_safe and belongs to exec; the other six departments cannot reach it post-ccbb00c.
  ('exec',        'exec_review', 'advisory', null, '2026-08-04: advisory. exec_review produces a review document; exec_agents is advisory_safe. Advisory never satisfies cos_execute''s autonomous-only executor guard.'),
  ('finance',     'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),
  ('it',          'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),
  ('knowledge',   'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),
  ('legal',       'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),
  ('procurement', 'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),
  ('sales',       'exec_review', 'advisory', null, '2026-08-04: advisory. Executor exec_agents belongs to exec, so this department reaches the deliverable path only.'),

  -- investigate. No active org_action_executor exists for this class at all. Investigation produces
  -- findings; the fix is a different class. These rows state intent, they do not release work.
  ('exec',        'investigate', 'advisory', null, '2026-08-04: advisory. No active executor exists for investigate; the output is findings. Note fn_edge_health_scan writes these rows with a literal tier=supervised and does not consult this model - see task-writers-are-fourteen-not-three.md.'),
  ('knowledge',   'investigate', 'advisory', null, '2026-08-04: advisory. No active executor exists for investigate; the output is findings.'),
  ('procurement', 'investigate', 'advisory', null, '2026-08-04: advisory. No active executor exists for investigate; the output is findings.'),

  -- coordinate. exec/coordinate is already 'autonomous' and the executor (cos_execute itself) belongs
  -- to exec. DELIBERATE DEVIATION from the tier suggested in queue-has-no-approval-path.md, which
  -- said copy exec's 'autonomous': post-ccbb00c these four departments cannot reach exec's executor,
  -- so 'autonomous' would grant nothing today and would silently become live the moment a
  -- per-department coordinate executor is registered. Advisory says what is actually true.
  ('finance',     'coordinate', 'advisory', null, '2026-08-04: advisory, NOT exec''s autonomous. Executor cos_execute is registered to exec; a cross-department grant that does nothing today becomes a live one the day an executor is added.'),
  ('it',          'coordinate', 'advisory', null, '2026-08-04: advisory, NOT exec''s autonomous. Executor cos_execute is registered to exec.'),
  ('knowledge',   'coordinate', 'advisory', null, '2026-08-04: advisory, NOT exec''s autonomous. Executor cos_execute is registered to exec.'),
  ('procurement', 'coordinate', 'advisory', null, '2026-08-04: advisory, NOT exec''s autonomous. Executor cos_execute is registered to exec.'),

  -- own-department, advisory_safe executors. Advisory never reaches cos_execute's executor path
  -- (the guard requires the model to grant 'autonomous'), so these stay on the deliverable path.
  ('hr',          'self_review',      'advisory', null, '2026-08-04: advisory. fn_self_review is advisory_safe and hr-owned. An employee reviewing its own work is advice, not an action.'),
  ('legal',       'compliance_check', 'advisory', null, '2026-08-04: advisory. compliance_archive is advisory_safe and legal-owned. A compliance verdict issued autonomously is a claim, not a verdict.'),

  -- procurement/knowledge_acquire: 25 tasks, the single largest pair. knowledge/knowledge_acquire is
  -- 'autonomous', but kb_deepen belongs to knowledge and procurement cannot reach it post-ccbb00c.
  -- Advisory rather than copying knowledge's tier: procurement's sense of "acquire" may mean
  -- suppliers rather than the corpus, and nothing has established which.
  ('procurement', 'knowledge_acquire', 'advisory', null, '2026-08-04: advisory, NOT knowledge''s autonomous. Executor kb_deepen belongs to knowledge and is not advisory_safe. Raise this only after establishing what procurement''s "acquire" is meant to reach.'),

  -- ---- gated: touches suppliers, identity, or bulk reclassification -------------------------------
  ('knowledge',        'route_category',         'gated', null, '2026-08-04: gated. "Classify 7829 uncategorised leads" is wide and the executor route_inquiry belongs to procurement. A bulk reclassification nobody has exercised once is a claim, not a capability.'),
  ('procurement',      'capability_enrich',      'gated', null, '2026-08-04: gated. Enriching supplier CAPABILITY CLAIMS without review is manufacturing claims. enrich_capability is not advisory_safe.'),
  ('procurement',      'supplier_verify',        'gated', null, '2026-08-04: gated. Inert either way - action_class_gate maps this to the authentication_identity hard gate, default_tier gated, and a hard gate may only tighten. Declared so the answer has a statement behind it rather than a fail-closed default.'),
  ('supplier_success', 'invite',                 'gated', null, '2026-08-04: gated, explicitly NOT procurement''s autonomous. org_tasks#20 was created tier=autonomous by dept_plan''s old constant and executed on 25 Jul 2026, enqueueing 10 real supplier invites through procurement''s fn_org_exec_invite for a department with no authority row. This row is that refusal, written down. Department is currently inactive.'),
  ('supplier_success', 'supplier_approve_clean', 'gated', null, '2026-08-04: gated, explicitly NOT procurement''s autonomous. Auto-approving registrants on an OCR path nobody has exercised in anger. Department is currently inactive.')

  on conflict (dept_key, action_class) do nothing;
end $$;
