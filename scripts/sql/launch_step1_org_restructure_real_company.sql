-- LAUNCH STEP 1 — RESTRUCTURE THE REPORTING LINES TO A REAL, WELL-RUN COMPANY.
--
-- Founder directive, 1 Sep 2026: "restructure it in the perfect way as if it's a real company with
-- humans." Measured first: the two reporting columns DISAGREED. The canonical role graph
-- (org_role.manager_role_id) already had the C-suite reporting to the CEO, but the runtime
-- (org_agents.manager_key) routed EIGHT of nine department heads through the Chief of Staff (brief) —
-- a single chokepoint that also inverted seniority (a Chief of Staff line-managing the CFO, CTO and
-- even the COO) and buried Independent Assurance and Legal/Compliance inside the operational chain,
-- destroying the independence their names claim. fn_phase_a_organization_violations() was 0 and no
-- constraint pins the two columns together, so the runtime had simply drifted from the design.
--
-- This sets BOTH columns to one clean, real-company structure (no change to the NUMBER of departments,
-- roles or overlays, so Phase A's count freeze is untouched; the a10 no-cycle guard is satisfied):
--
--   CEO
--     ├─ COO (chief_operating_officer)              — owns all operational delivery
--     │    ├─ Marketplace Director                  — supplier network & matching ops
--     │    └─ Customer Success Director             — customer operations
--     ├─ CFO                                        — finance
--     ├─ Chief Product & Technology Officer         — product & engineering
--     ├─ Chief Revenue Officer                      — growth (sales + marketing)
--     ├─ General Counsel                            — legal, risk, compliance, trust (independent)
--     ├─ Data & Intelligence Director               — data & knowledge
--     ├─ Head of Independent Assurance (QA/Sec/Rel) — reports to the CEO for genuine independence
--     └─ Chief of Staff — Office of the CEO
--          ├─ Chief Performance Officer
--          └─ Strategy Director
--
-- Why the COO tier: a CEO with eleven direct reports is not a real executive team. The COO now owns
-- operations (marketplace, customer, and its own people/ops department), giving the CEO a focused
-- eight-seat executive committee. Why Assurance and Legal to the CEO: internal audit and compliance
-- must be able to raise a red flag without it being filtered by the operations they check.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_org_restructure_real_company.sql --apply --ddl

begin;

-- RUNTIME (org_agents.manager_key): honour the canonical design and add the two new tiers.
-- The C-suite reports to the CEO.
update public.org_agents set manager_key = 'ceo'
 where agent_key in ('cfo','cto','sales_director','ops_director','legal','qa_manager')
   and manager_key = 'brief';
-- Operations sit under the COO.
update public.org_agents set manager_key = 'ops_director'
 where agent_key in ('procurement','followup') and manager_key = 'brief';
-- The Office of the CEO (strategy + performance) sits under the Chief of Staff.
update public.org_agents set manager_key = 'brief'
 where agent_key in ('cpo','strategy_director') and manager_key = 'ceo';

-- CANONICAL (org_role.manager_role_id): mirror the two new tiers. The C-suite roles are already
-- recorded against the CEO; only the operations tier and the office-of-the-CEO tier move.
update public.org_role set manager_role_id = 'chief_operating_officer'
 where role_id in ('marketplace_director','customer_success_director') and manager_role_id = 'ceo';
update public.org_role set manager_role_id = 'chief_of_staff'
 where role_id in ('corporate_performance_director','strategy_director') and manager_role_id = 'ceo';

-- FULL RECONCILIATION. The runtime (org_agents.manager_key) is the operative reporting line — it is
-- what fn_should_escalate routes on, what the org chart draws, and what fn_agent_context_v3 tells each
-- agent its manager is. Sixteen sub-agents had a canonical role manager (org_role.manager_role_id)
-- that disagreed with their operative manager, a pre-existing drift. Align the canonical graph to the
-- runtime for every role whose two disagree, so the whole company is internally consistent with what
-- actually operates. This changes NO operative behaviour (manager_key is untouched); it makes the
-- design record match reality. The a10 no-cycle and no-self-manage guards both hold: the runtime graph
-- is acyclic up to the CEO and no agent manages itself.
update public.org_role r
   set manager_role_id = mgr_role.role_id
  from public.org_agents a
  join public.org_role mgr_role on mgr_role.runtime_agent_key = a.manager_key and mgr_role.status = 'active'
 where r.runtime_agent_key = a.agent_key and r.status = 'active' and a.active
   and a.manager_key is not null
   and coalesce((select runtime_agent_key from public.org_role rr where rr.role_id = r.manager_role_id),
                r.manager_role_id) is distinct from a.manager_key;

commit;
