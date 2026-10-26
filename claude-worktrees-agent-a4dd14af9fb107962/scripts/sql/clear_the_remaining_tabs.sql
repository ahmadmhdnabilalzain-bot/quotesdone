-- ---------------------------------------------------------------------------------------------
-- THE TABS THE FIRST STAND-DOWN DID NOT REACH.
--
-- The founder walked the console and named them: "operations tab: still open tasks / assistance:
-- 6 open tasks / intelligence tab: 6 risks / documents tab has some pending / company tab log
-- still is not clear / reports tab is not clear / fraud and risk tab is not clear".
--
-- Two different causes, and only one of them is data.
--
-- CAUSE A — THREE TABLES THE STAND-DOWN NEVER TOUCHED. strategy_risks (6 open), fraud_flags
-- (6 open) and doc_reviews (2 pending) are work queues in everything but name, and the first
-- pass cleared org_tasks, agent_actions, phase_c_task, crm_tasks, evolution_proposal and
-- opportunity without them. They are cleared here, with the same terminal-state discipline: each
-- table's own CHECK decides the legal value, so strategy_risks goes to 'closed' (its CHECK allows
-- open/mitigating/accepted/closed and nothing else), fraud_flags to 'dismissed' beside the one
-- already there, and doc_reviews to 'skipped'.
--
-- CAUSE B — A PREDICATE THAT NEVER KNEW ABOUT 'cancelled'. The Operations and Assistance tabs are
-- not reading stale rows, they are reading the SAME six crm_tasks the stand-down cancelled: both
-- routines filter `where coalesce(status,'') <> 'done'`, which was correct when 'done' was the
-- only terminal state and became wrong the moment 'cancelled' existed. A cancelled task is not
-- open work. That is fixed in the routines rather than by touching data, because the data is
-- already right.
--
-- The Company and Reports tabs read history deliberately — escalation counts over 30 days, the
-- report registry, evaluation snapshots — so they take the fresh-start watermark rather than a
-- status filter. There is nothing wrong with those rows; he simply does not want the old company
-- on the screen while the new chain of command is designed.
-- ---------------------------------------------------------------------------------------------

update public.strategy_risks
   set status = 'closed'
 where status <> 'closed';

update public.fraud_flags
   set status = 'dismissed'
 where coalesce(status,'open') not in ('dismissed','resolved','closed');

update public.doc_reviews
   set status = 'skipped'
 where status = 'pending';
