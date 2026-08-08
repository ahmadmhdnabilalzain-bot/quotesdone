-- ROW #4 (customer portal) — THE SCHEMA THE SPEC ASKS FOR AND THE DATABASE DID NOT CARRY.
--
-- Nine requirements scored MISSING because the MECHANISM was absent, not because a surface had not
-- been wired to it. Each block below names the requirement it exists for and the measurement that
-- said so (production, 7 Aug 2026, verify_portal_blueprint.mjs at 104/147).
--
-- NOTHING HERE BACK-FILLS A ROW. Production holds 0 customers, 0 inquiries, 0 quotes, 0 projects,
-- 0 messages and 0 po_orders, so every table added here lands empty and every column added here is
-- null on the rows that exist. A capability is being built; no history is being invented.

-- ═══ 1. §2 twin-industry ═════════════════════════════════════════════════════════════════════════
-- MEASURED: "customers columns matching industry/sector/vertical=0; every sector column in the
-- schema belongs to the SUPPLIER record instead: scrape_runs.sector, leads.sector,
-- yello_staging.sector." The buyer's own industry — the first line of the spec's §2 profile — had
-- nowhere to live.
alter table public.customers add column if not exists industry text;
comment on column public.customers.industry is
  'Spec §2 Digital Twin: the buyer''s own industry (construction, hospitality, ...). Free text on '
  'purpose — the taxonomy that exists (leads.categories) describes what a SUPPLIER sells, which is '
  'a different axis from what a BUYER builds.';

-- ═══ 2. §6 3d-floor-drilldown ════════════════════════════════════════════════════════════════════
-- MEASURED: "floor dimension on projects/inquiries/quotes/po_orders/documents: 0 column(s);
-- routines naming a per-floor dimension: 0." The spec's §6 drills Floor 25 -> HVAC -> Ordered, and
-- the status it lands on is an RFQ's or an order's, so the floor has to be recorded where those are.
alter table public.inquiries add column if not exists floor text;
comment on column public.inquiries.floor is
  'Spec §6: the floor/level this RFQ is scoped to ("25", "B2", "20-40"). Text, not an integer: '
  'basements, mezzanines and ranges are all real answers and none of them is a number.';

-- ═══ 3. §7 rfq-delivery-extraction ═══════════════════════════════════════════════════════════════
-- MEASURED: "the intake contract emits brief.timeline = true and the ready-brief card shows it
-- before sending = true; create_inquiry reads it = false; inquiries columns matching a delivery
-- window: 0." The assistant extracts the window, shows it, and then the RFQ drops it on the floor.
alter table public.inquiries add column if not exists required_by date;
alter table public.inquiries add column if not exists delivery_window text;
comment on column public.inquiries.delivery_window is
  'Spec §7: the delivery window as the customer stated it ("90 days", "before Ramadan"). The '
  'resolved date, when one can be resolved, goes in required_by; both are kept because a supplier '
  'quotes against the phrase and the portal sorts against the date.';

-- ═══ 4. §16 comm-attached-to-entities / comm-documents-in-thread ═════════════════════════════════
-- MEASURED: "messages links: inquiry_id, supplier_id, customer_id ... so the project link is one
-- column away" and "messages columns that could carry a file: none; documents rows pointing at a
-- message: 0".
alter table public.messages add column if not exists project_id uuid references public.projects(id);
alter table public.messages add column if not exists attachment_path text;
alter table public.messages add column if not exists document_id bigint references public.documents(id);
alter table public.chat_threads add column if not exists project_id uuid references public.projects(id);
comment on column public.messages.project_id is
  'Spec §16: every conversation is attached to a project as well as an RFQ and a supplier. '
  'Nullable — a thread raised before the RFQ is linked to a project has no project yet, and '
  'refusing the message would be worse than carrying the null.';

-- ═══ 5. §16 comm-calls ═══════════════════════════════════════════════════════════════════════════
-- MEASURED: "tables logging calls that link to an inquiry/supplier/customer: none; every table
-- whose name identifies it as a log of calls: llm_calls" — an API-usage ledger with no counterparty.
-- A call log records a conversation WITH SOMEBODY, so all three counterparty links are on the row.
create table if not exists public.customer_calls (
  id            bigserial primary key,
  customer_id   uuid references public.customers(id),
  inquiry_id    uuid references public.inquiries(id),
  supplier_id   bigint,
  project_id    uuid references public.projects(id),
  direction     text not null default 'outbound' check (direction in ('inbound','outbound')),
  status        text not null default 'completed'
                check (status in ('completed','missed','voicemail','failed','scheduled')),
  started_at    timestamptz not null default now(),
  duration_s    integer,
  summary       text,
  recording_path text,
  created_at    timestamptz not null default now()
);
create index if not exists customer_calls_customer_idx on public.customer_calls (customer_id, started_at desc);
create index if not exists customer_calls_inquiry_idx  on public.customer_calls (inquiry_id);
comment on table public.customer_calls is
  'Spec §16: calls logged in the SAME place as chat, WhatsApp and e-mail. Deliberately NOT '
  'llm_calls, which is an API-usage ledger and logs no conversation with a counterparty.';

-- ═══ 6. §6 3d-component-status ═══════════════════════════════════════════════════════════════════
-- MEASURED: "relations with a component/line-item identity column: scope_component.component,
-- scope_marker.component, of which 0 also carry a status and 0 link to a project or RFQ." Both are
-- scope-DETECTION taxonomy tables — they classify text, they do not describe a building. The spec
-- wants a component of a project, on a floor, with a status a customer can read off the model.
create table if not exists public.project_component (
  id           bigserial primary key,
  project_id   uuid references public.projects(id),
  inquiry_id   uuid references public.inquiries(id),
  component    text not null,
  floor        text,
  trade        text,
  status       text not null default 'planned'
               check (status in ('planned','quotation','ordered','delivered','installed','cancelled')),
  qty          numeric,
  uom          text,
  cost_aed     numeric,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists project_component_project_idx on public.project_component (project_id, floor);
create index if not exists project_component_inquiry_idx on public.project_component (inquiry_id);
comment on table public.project_component is
  'Spec §6: one row per component per floor, carrying the status the 3D model paints. project_id '
  'and inquiry_id are both nullable and at least one is always set — a component can exist before '
  'an RFQ is raised for it, and an RFQ can name a component on a project that was never modelled.';

-- ═══ 7. §19 spatial-supply-chain-map ═════════════════════════════════════════════════════════════
-- MEASURED: "relations carrying a chain leg (an origin and a destination on one row): 0; po_orders
-- holds only order_date, expected_date, status." A map of a chain needs rows that CARRY a chain.
create table if not exists public.shipment_leg (
  id             bigserial primary key,
  po_order_id    bigint references public.po_orders(id),
  inquiry_id     uuid references public.inquiries(id),
  project_id     uuid references public.projects(id),
  customer_id    uuid references public.customers(id),
  leg_no         integer not null default 1,
  origin         text not null,
  origin_kind    text not null default 'factory'
                 check (origin_kind in ('factory','warehouse','port','site','supplier')),
  destination    text not null,
  destination_kind text not null default 'site'
                 check (destination_kind in ('factory','warehouse','port','site','supplier')),
  status         text not null default 'planned'
                 check (status in ('planned','shipping','in_transit','customs','delivered','delayed')),
  departed_at    timestamptz,
  eta            timestamptz,
  arrived_at     timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists shipment_leg_order_idx    on public.shipment_leg (po_order_id, leg_no);
create index if not exists shipment_leg_customer_idx on public.shipment_leg (customer_id, status);
comment on table public.shipment_leg is
  'Spec §19: Supplier Factory -> Warehouse -> Project Site, one row per leg with a live status. '
  'origin/destination are free text with a KIND beside them: the estate has no place registry and '
  'inventing one to hold "Jebel Ali warehouse" would be a second unpopulated table, not a map.';

-- ═══ 8. §21 ui-ai-generated-layouts ══════════════════════════════════════════════════════════════
-- MEASURED: "layout descriptor(s) emitted by the 24 customer-reachable edge fn(s): 0; places the
-- portal builds its tree from one: 0; per-customer layout relation(s) in public: 0."
create table if not exists public.customer_layout (
  customer_id  uuid primary key references public.customers(id),
  layout       jsonb not null default '[]'::jsonb,
  reason       text,
  pinned       jsonb not null default '[]'::jsonb,
  computed_at  timestamptz not null default now()
);
comment on table public.customer_layout is
  'Spec §21: the panel order the portal renders for THIS customer, plus the reason it was chosen. '
  'pinned holds panels the customer fixed by hand — a computed layout must never silently move a '
  'panel the customer deliberately placed.';

-- ═══ 9. §2 twin-* — the customer branch of fn_twin ═══════════════════════════════════════════════
-- MEASURED, per key: industry=0, projects-count=0, supplier-shaped=0, confidence/understanding=0.
-- The customer branch emitted rfqs, deals, spend_aed, categories, last_active — a transaction
-- summary. The spec asks for a BUSINESS PROFILE. Every figure below is computed from rows that
-- exist; none is a constant, and understanding_pct is a count of facts actually known rather than
-- the spec's illustrative 96%.
create or replace function public.fn_twin(p_kind text, p_id text default null::text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare res jsonb;
begin
  if p_kind='customer' then
    select jsonb_build_object('kind','customer','id',c.id,'name',c.full_name,'email',c.email,
      'industry',c.industry,
      'rfqs',(select count(*) from inquiries where customer_id=c.id),
      'deals',(select count(*) from transactions where customer_id=c.id),
      'spend_aed',(select coalesce(sum(reveal_fee),0) from transactions where customer_id=c.id and coalesce(fee_status,'')='paid'),
      'categories',(select coalesce(jsonb_agg(distinct category),'[]') from inquiries where customer_id=c.id),
      -- BUYING PATTERNS (§2) — categories ORDERED BY how often the customer actually buys them,
      -- with the count beside each. `categories` above is a set and a set is not a pattern.
      'preferred_categories',(select coalesce(jsonb_agg(jsonb_build_object('category',k.category,'rfqs',k.n) order by k.n desc),'[]')
         from (select category, count(*) n from inquiries where customer_id=c.id and category is not null
               group by category order by count(*) desc limit 8) k),
      'projects_active',(select count(*) from projects
         where customer_id=c.id and coalesce(status,'') not in ('closed','cancelled','completed','done')),
      'projects_total',(select count(*) from projects where customer_id=c.id),
      -- PREFERRED SUPPLIERS (§2) — the suppliers this customer has actually paid to reveal. A
      -- preference the customer demonstrated, not one they were asked to declare.
      'preferred_suppliers',(select count(distinct supplier_id) from transactions
         where customer_id=c.id and coalesce(fee_status,'')='paid' and supplier_id is not null),
      -- The chain the spec's §2 profile draws (Engineer -> Manager -> Finance). Resolved through
      -- the same two relations fn_approval_policy_match uses — owned organizations and memberships
      -- — so the twin and the approval engine can never disagree about whose chain this is.
      'approval_chain',(select coalesce(p.steps,'[]'::jsonb) from procurement_approval_policy p
         where p.active and p.organization_id in (
           select o.id from customer_organization o where o.owner_customer_id=c.id
           union
           select m.organization_id from customer_organization_member m
            where m.user_id=c.id and coalesce(m.active,true))
         limit 1),
      'last_active',(select max(created_at) from inquiries where customer_id=c.id),
      -- AI UNDERSTANDING (§2) — the share of the eight profile facts the system actually holds for
      -- this customer. The spec prints 96%; a constant would be a decoration, so this counts.
      'understanding_pct',(select round(100.0 * (
             (c.full_name is not null and c.full_name <> '')::int
           + (c.phone is not null and c.phone <> '')::int
           + coalesce(c.email_verified,false)::int
           + (c.tos_accepted_at is not null)::int
           + (c.locale is not null)::int
           + (c.industry is not null and c.industry <> '')::int
           + (exists (select 1 from inquiries where customer_id=c.id))::int
           + (exists (select 1 from customer_preference cp where cp.customer_id=c.id))::int
         ) / 8.0)),
      'banned',c.banned) into res from customers c where c.id::text=p_id;

  elsif p_kind='rfq' then
    select jsonb_build_object('kind','rfq','id',i.id,'category',i.category,'emirate',i.emirate,'status',i.status,
      'completeness',i.completeness,'ready',i.rfq_ready,'budget',i.budget,
      'quotes',(select count(*) from quotes where inquiry_id=i.id),
      'avg_quote_quality',(select round(avg(nullif(quality->>'score','')::numeric),1) from quotes where inquiry_id=i.id),
      'matched_suppliers',(select count(*) from inquiry_matches where inquiry_id=i.id),
      'created',i.created_at,'completed',i.completed_at,'outcome',i.outcome) into res from inquiries i where i.id::text=p_id;

  elsif p_kind='category' then
    res := jsonb_build_object('kind','category','category',p_id,
      'demand_rfqs',(select count(*) from inquiries where category=p_id),
      'approved_suppliers',(select count(*) from leads where coalesce(approval_status,'')='approved' and (lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%')),
      'supplier_pool_total',(select count(*) from leads where lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%'),
      'avg_quote_quality',(select round(avg(nullif(q.quality->>'score','')::numeric),1) from quotes q join inquiries i on i.id=q.inquiry_id where i.category=p_id),
      'agent',public.fn_resolve_cat_agent(p_id));

  elsif p_kind='company' then
    res := jsonb_build_object('kind','company','name','QuotesDone',
      'health',public.fn_health_index(),
      'suppliers_total',(select count(*) from leads),'suppliers_approved',(select count(*) from leads where coalesce(approval_status,'')='approved'),
      'customers',(select count(*) from customers),'rfqs',(select count(*) from inquiries),'quotes',(select count(*) from quotes),
      'revenue_paid_aed',(select coalesce(sum(reveal_fee),0) from transactions where coalesce(fee_status,'')='paid'),
      'eval',public.fn_eval_snapshot(30));
  else
    res := jsonb_build_object('error','kind must be customer|rfq|category|company');
  end if;
  return coalesce(res, jsonb_build_object('error','not found','kind',p_kind,'id',p_id));
end $function$;
