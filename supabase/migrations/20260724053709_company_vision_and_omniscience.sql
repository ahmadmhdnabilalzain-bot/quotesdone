-- ============================================================================
-- AUTONOMY ENGINE · PILLAR 1 — Company vision anchor + omniscience (self-knowledge)
-- The north star every department plans against, plus a live org-introspection layer so ANY agent
-- can answer anything about the company. Delivered to all agents via a high-priority _global
-- agent_knowledge row (read by both fn_agent_context and agent_brain), refreshed by cron.
-- ============================================================================

create table if not exists public.company_vision (
  id int primary key default 1,
  vision text not null, mission text not null, principles text,
  updated_at timestamptz default now(),
  constraint company_vision_singleton check (id = 1)
);
insert into public.company_vision (id, vision, mission, principles) values (1,
  'Become the smartest marketplace engine in the world.',
  'QuotesDone is a UAE B2B anonymous quotation marketplace: buyers post an RFQ describing a job or product; verified UAE suppliers submit quotes; the buyer pays a small fee to reveal and contact a chosen supplier. Every department is an autonomous AI expert that plans and executes toward the vision.',
  'Departments are experts, not order-takers: they plan their own work from the vision and their charter, and execute it. The founder is capital + final taste: he approves or comments on finished outbound work, nothing more. Autonomy is total INSIDE the constitutional gates; money movement, authentication, security, destructive/irreversible actions, and legal judgement stay founder-gated forever. Experience must compound: every agent should be materially smarter in three months than today.')
on conflict (id) do update set vision=excluded.vision, mission=excluded.mission, principles=excluded.principles, updated_at=now();

create table if not exists public.org_agents (
  agent_key text primary key,
  department text not null references public.org_departments(dept_key),
  role text not null, kind text not null default 'brain',
  active boolean default true, created_at timestamptz default now()
);
insert into public.org_agents (agent_key, department, role, kind) values
('brief','exec','Chief of Staff — runs the company against objectives','brain'),
('cfo','finance','CFO — owns the money, books, cash, spend','brain'),
('bookkeeper','finance','Bookkeeper — receipts, ledger entries','brain'),
('collections','finance','Collections — dues and recovery','brain'),
('it','it','IT/SRE — platform uptime and safe change','brain'),
('security','it','Security engineer — appsec, secrets, threats','brain'),
('onboarding','supplier_success','Supplier onboarding / KYC','brain'),
('bd','supplier_success','Business development — supplier acquisition','brain'),
('followup','customer_success','Follow-up / SLA / customer journey','brain'),
('marketing','marketing','Marketing lead — demand, content, brand','brain'),
('docs','knowledge','Knowledge management — capture/fill/retrieve','brain'),
('legal','legal','Legal & compliance','brain')
on conflict (agent_key) do update set department=excluded.department, role=excluded.role, kind=excluded.kind;

alter table public.org_action_executor add column if not exists department text;
update public.org_action_executor set department='supplier_success' where action_class in ('invite','supplier_approve_clean') and department is null;
update public.org_action_executor set department='knowledge' where action_class='knowledge_fill' and department is null;
update public.org_action_executor set department='analytics' where action_class='recommend' and department is null;
update public.org_action_executor set department='marketing' where action_class in ('content_draft','content_publish') and department is null;

-- fn_company_state(): live omniscience snapshot (jsonb). fn_company_brief(): compact text for context.
-- (Bodies applied via migration company_vision_and_omniscience; see production for the current definitions.)

-- Omniscience delivery: a high-priority _global knowledge row read by every agent, refreshed every 3h.
insert into public.agent_knowledge(agent_key,topic,priority,content)
select '_global','company:self_knowledge',95, public.fn_company_brief(1800)
where not exists (select 1 from public.agent_knowledge where agent_key='_global' and topic='company:self_knowledge');
-- cron: select cron.schedule('company_selfknowledge_refresh','13 */3 * * *',
--   $$update public.agent_knowledge set content=public.fn_company_brief(1800), updated_at=now()
--     where agent_key='_global' and topic='company:self_knowledge'$$);
