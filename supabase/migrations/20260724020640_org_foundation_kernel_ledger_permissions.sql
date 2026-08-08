-- ORG FOUNDATION: the shared substrate that turns the agent fleet into a company.
-- Additive only. Internal OS tables (service-role/SECURITY DEFINER only).
-- Kernel (org_departments) + Permissions (org_authority + fn_dept_authority w/ constitutional caps)
-- + Objective/Task ledger (org_objectives/org_tasks) + Organizational memory (org_memory)
-- + fn_org_scorecard (whole-company view). Consumed by intent_router and secretary_act (Chief of Staff).

-- 1. DEPARTMENT KERNEL (as data)
create table if not exists public.org_departments (
  dept_key text primary key, name text not null, charter text not null,
  north_star text, health_fn text, lead_agent text,
  active boolean not null default true, sort int not null default 100
);

-- 2. PERMISSIONS
create table if not exists public.org_authority (
  dept_key text not null references public.org_departments(dept_key) on delete cascade,
  action_class text not null,
  max_tier text not null check (max_tier in ('advisory','gated','supervised','autonomous')),
  threshold_aed numeric, note text,
  primary key (dept_key, action_class)
);

-- 3. OBJECTIVE / TASK LEDGER
create table if not exists public.org_objectives (
  id bigint generated always as identity primary key,
  objective text not null, raw_input text, created_by text default 'founder',
  status text not null default 'open' check (status in ('open','in_progress','blocked','done','cancelled')),
  priority text not null default 'normal',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  closed_at timestamptz, outcome text
);
create table if not exists public.org_tasks (
  id bigint generated always as identity primary key,
  objective_id bigint references public.org_objectives(id) on delete cascade,
  dept_key text references public.org_departments(dept_key),
  title text not null, detail text, action_class text,
  status text not null default 'proposed' check (status in ('proposed','assigned','in_progress','blocked','done','failed','escalated')),
  tier text check (tier in ('advisory','gated','supervised','autonomous')),
  needs_founder boolean not null default false, result jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), decided_by text
);
create index if not exists ix_org_tasks_objective on public.org_tasks(objective_id);
create index if not exists ix_org_tasks_dept_status on public.org_tasks(dept_key, status);

-- 4. ORGANIZATIONAL MEMORY (shared, cross-department)
create table if not exists public.org_memory (
  id bigint generated always as identity primary key,
  scope text not null default 'global', kind text not null default 'note',
  content text not null, source text, active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists ix_org_memory_scope on public.org_memory(scope) where active;

alter table public.org_departments enable row level security;
alter table public.org_authority   enable row level security;
alter table public.org_objectives  enable row level security;
alter table public.org_tasks        enable row level security;
alter table public.org_memory       enable row level security;

-- fn_dept_authority: effective control tier for (department, action_class), with constitutional HARD CAPS.
create or replace function public.fn_dept_authority(p_dept text, p_action_class text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog'
as $function$
declare v_tier text; v_thr numeric; v_cap text; v_tier_rk int; v_cap_rk int;
begin
  select max_tier, threshold_aed into v_tier, v_thr from public.org_authority where dept_key=p_dept and action_class=p_action_class;
  if v_tier is null then v_tier := 'gated'; end if;
  if p_action_class ~* 'money|payout|payment|gl_|data_delete|delete|purge|secret|auth|password|code_deploy|supplier_ban|ban' then v_cap := 'gated';
  elsif p_action_class ~* 'legal_review|recommend' then v_cap := 'advisory'; end if;
  v_tier_rk := case v_tier when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 when 'autonomous' then 3 else 1 end;
  if v_cap is not null then
    v_cap_rk := case v_cap when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 else 3 end;
    if v_tier_rk > v_cap_rk then v_tier := v_cap; end if;
  end if;
  return jsonb_build_object('dept',p_dept,'action_class',p_action_class,'tier',v_tier,'threshold_aed',v_thr,'capped', v_cap is not null);
end $function$;
revoke execute on function public.fn_dept_authority(text,text) from public, anon, authenticated;
grant execute on function public.fn_dept_authority(text,text) to service_role;

-- fn_org_scorecard: whole-company view for the Chief of Staff brief + OS.
create or replace function public.fn_org_scorecard()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select coalesce(jsonb_agg(row_to_json(x) order by x.sort),'[]'::jsonb) from (
    select d.dept_key, d.name, d.north_star, d.lead_agent, d.sort,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and t.status in ('proposed','assigned','in_progress','blocked')) as open_tasks,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and (t.needs_founder or t.status='escalated') and t.status not in ('done','failed')) as escalations,
      (select count(*) from public.agent_actions a where a.status in ('pending','needs_review','open') and (
          (d.dept_key='finance' and a.kind ~* 'finance|refund|dues') or
          (d.dept_key='legal' and a.kind ~* 'legal|compliance') or
          (d.dept_key='supplier_success' and a.kind ~* 'supplier|approve|licence|kyc') or
          (d.dept_key='customer_success' and a.kind ~* 'customer|refund|escalation') or
          (d.dept_key='it' and a.kind ~* 'incident|security') or
          (d.dept_key='marketing' and a.kind ~* 'market|content') or
          (d.dept_key='knowledge' and a.kind ~* 'knowledge|coverage')
        )) as dept_queue
    from public.org_departments d where d.active
  ) x;
$function$;
revoke execute on function public.fn_org_scorecard() from public, anon, authenticated;
grant execute on function public.fn_org_scorecard() to service_role;

-- ---- SEEDS ----
insert into public.org_departments(dept_key,name,charter,north_star,health_fn,lead_agent,sort) values
('exec','Executive Office (Chief of Staff)','Run the company against the founder''s objectives with minimal founder intervention; be the single interface.','objectives completed without founder touch','fn_ws_company','brief',10),
('it','IT & Engineering','Keep the platform alive and safely evolving.','uptime x change-safety','fn_ws_ai','it',20),
('procurement','Procurement (Marketplace Core)','Run intake->match->quote->reveal at high match & quote quality.','quotes per RFQ / time-to-first-quote','fn_ws_marketplace',null,30),
('supplier_success','Supplier Success','Acquire, onboard, verify, activate and retain suppliers.','activated suppliers per week','fn_ws_suppliers','onboarding',40),
('customer_success','Customer Success','Own the customer journey: activation, response, satisfaction, fair refunds.','reveal conversion / time-to-first-quote','fn_ws_customers','followup',50),
('marketing','Marketing','Generate qualified demand: content, SEO, social, ads, brand.','cost per qualified inquiry','fn_ws_marketing','marketing',60),
('finance','Finance','Own the money: books correct, cash visible, dues collected, spend controlled.','cash position / collection rate','fn_ws_finance','cfo',70),
('knowledge','Knowledge Management','Capture, fill, retrieve and improve the company brain; never leave a gap open.','coverage % / gap-close time','fn_ws_knowledge','docs',80),
('analytics','Analytics & Intelligence','Turn data into decisions; advisory to every department.','insight-to-action latency','fn_ws_analytics',null,90),
('legal','Legal & Compliance','Keep the company compliant and defensible; never auto-decide legal judgment.','PDPL SLA / open legal risk','fn_ws_governance','legal',100)
on conflict (dept_key) do update set name=excluded.name, charter=excluded.charter, north_star=excluded.north_star, health_fn=excluded.health_fn, lead_agent=excluded.lead_agent, sort=excluded.sort;

insert into public.org_authority(dept_key,action_class,max_tier,threshold_aed,note) values
('it','code_selfheal','supervised',null,'auto-heal deploy-shaped failures + email flush'),
('it','code_deploy','gated',null,'Tier 0: agent proposes, founder promotes'),
('it','secret_change','gated',null,'rotate/reconnect integrations with approval'),
('finance','expense_log','autonomous',null,'bookkeeping from receipts'),
('finance','forecast','autonomous',null,null),
('finance','money_move','gated',10000,'refund/payout/GL post — founder approval, hard-capped'),
('customer_success','refund_within_window','supervised',null,'auto-refund a wronged customer inside the policy window'),
('customer_success','nudge','autonomous',null,'reveal/quote follow-ups'),
('marketing','content_draft','autonomous',null,null),
('marketing','content_publish','gated',null,'public posting needs approval'),
('marketing','ad_spend','gated',null,'campaigns created paused; activation gated'),
('supplier_success','supplier_approve_clean','supervised',null,'licence-OCR-clean suppliers auto-approve'),
('supplier_success','supplier_ban','gated',null,null),
('supplier_success','invite','autonomous',null,'ramped, deliverability-gated'),
('knowledge','knowledge_fill','supervised',null,'auto-fill gaps, generate packs'),
('knowledge','intake_change','gated',null,'live intake-form changes via prompt_gate'),
('procurement','match_inquiry','autonomous',null,'policy-capped fanout/relevance'),
('analytics','recommend','advisory',null,'never acts on the business directly'),
('legal','legal_review','advisory',null,'always needs_licensed_review'),
('legal','legal_action','gated',null,'demand letters, PDPL erase — approval'),
('exec','coordinate','autonomous',null,'route/track objectives across departments'),
('exec','data_delete','gated',null,'destructive ops always gated, any dept')
on conflict (dept_key,action_class) do update set max_tier=excluded.max_tier, threshold_aed=excluded.threshold_aed, note=excluded.note;

insert into public.org_memory(scope,kind,content,source) values
('global','directive','QuotesDone is an AI-native company. The OS is headquarters; each department performs real work within its authority. The founder is CEO: sets policy and objectives, approves exceptions, reviews KPIs — does not operate daily.','product_constitution'),
('global','directive','Escalate to the founder ONLY when: policy requires approval, legal judgment is needed, a financial limit is exceeded, confidence is below the floor, options are genuinely tied, or an irreversible action exceeds delegated authority. Everything else the responsible department handles.','product_constitution'),
('global','policy','Preserve existing value. Improve -> Extend -> Connect -> Automate -> Refactor -> Replace. Replacement is the last option.','product_constitution'),
('global','policy','Hard human gates (never autonomous, any department): money movement above limit, authentication/identity, security & secrets, destructive database operations, and the autonomy framework itself.','founder_directive')
on conflict do nothing;
