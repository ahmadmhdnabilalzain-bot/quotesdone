-- ROW #4, SPEC §12 (Purchase Approval System) and §22 (Orders module) — THE MECHANISM.
--
-- WHAT WAS MEASURED BEFORE THIS FILE (6 Aug 2026, both projects):
--   * procurement_approval_policy and procurement_approval_request exist with exactly the columns
--     the spec names, hold zero rows, and have ZERO readers of any kind — no routine, no view, no
--     cron, no edge function. current_step is advanced by 0 routines. 0 triggers raise a request
--     when a quote is awarded. The tables are furniture; the workflow does not exist.
--   * v_approval_trace was a view over review_chain — the INTERNAL staff review ladder — and had
--     nothing to do with a customer's purchase approval. Nothing read it (0 routines, 0 views,
--     0 edge functions), so redefining it breaks no caller.
--   * po_orders had no column tying an order to a customer, an inquiry or a project. As built it
--     is the company's own purchasing (vendor_id -> po_vendors, account_code -> gl_accounts), so
--     a customer Orders module could not be scoped at all. Both projects hold ZERO po_orders rows,
--     so nothing is back-filled here and no historical ownership is invented.
--
-- THE SHAPE THE SPEC ASKS FOR (§12): a request moving through NAMED steps — Engineer, Project
-- Manager, Finance, CEO — each showing Approved / Pending / Waiting. That is three things:
--   RAISE     fn_approval_raise_on_award()  trigger on inquiries, fires when an award happens
--   ADVANCE   fn_approval_decide()          moves current_step and records WHO decided
--   PROJECT   v_approval_trace              one row per step with its per-step state
--
-- THE POLICY CONTRACT, defined here because zero policies exist anywhere to imply one:
--   conditions {"entity_type":"inquiry",        -- optional; any entity when absent
--               "min_amount": 50000,            -- optional; 0 when absent. Quote value in AED.
--               "categories": ["marble"],       -- optional; any-of
--               "emirates":  ["Dubai"]}         -- optional; any-of
--   steps      [{"key":"engineer","label":"Engineer","role":"engineer"}, ...]
--              ORDER IS THE CHAIN. current_step is 1-based into this array.
--              "role" is optional; when present only a member holding that role (or the
--              organization owner) may decide that step.
--
-- HONEST EMPTY STATE, DELIBERATELY: a customer with no organization, or an organization with no
-- matching policy, raises NOTHING and the endpoint returns empty arrays. An award is never blocked
-- by this file — the raiser cannot fail an award (see its exception block).

-- ═══ 1. po_orders: the customer link ══════════════════════════════════════════════════════════
-- Nullable on purpose. The company's own purchase orders have no customer and must stay valid.
alter table public.po_orders add column if not exists customer_id uuid references public.customers(id);
alter table public.po_orders add column if not exists inquiry_id  uuid references public.inquiries(id);
alter table public.po_orders add column if not exists quote_id    uuid references public.quotes(id);
alter table public.po_orders add column if not exists project_id  uuid references public.projects(id);
create index if not exists po_orders_customer_idx on public.po_orders(customer_id) where customer_id is not null;

comment on column public.po_orders.customer_id is
  'Customer this order belongs to. NULL = the company own purchasing (every row that existed before 6 Aug 2026 - there were none in either project). Derived from inquiry_id by trg_po_orders_link when not supplied.';

-- POPULATED GOING FORWARD BY DERIVATION, so no writer has to remember all four keys and no
-- existing writer has to change its argument list (an argument-list change to fn_po_create would
-- make an OVERLOAD, not a replacement, and the old body would keep being called).
create or replace function public.fn_po_orders_link() returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
begin
  if new.quote_id is not null and new.inquiry_id is null then
    select q.inquiry_id into new.inquiry_id from public.quotes q where q.id = new.quote_id;
  end if;
  if new.inquiry_id is not null and (new.customer_id is null or new.project_id is null) then
    select coalesce(new.customer_id, i.customer_id), coalesce(new.project_id, i.project_id)
      into new.customer_id, new.project_id
      from public.inquiries i where i.id = new.inquiry_id;
  end if;
  return new;
end $$;

drop trigger if exists trg_po_orders_link on public.po_orders;
create trigger trg_po_orders_link
  before insert or update of quote_id, inquiry_id, customer_id, project_id on public.po_orders
  for each row execute function public.fn_po_orders_link();

-- ═══ 2. Which policy covers this purchase ═════════════════════════════════════════════════════
-- A READER of procurement_approval_policy: it is the first thing in the estate that ever looked
-- at the steps column.
create or replace function public.fn_approval_policy_match(
  p_org uuid, p_entity_type text, p_amount numeric,
  p_category text default null, p_emirate text default null)
returns uuid
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $$
  select p.id
    from public.procurement_approval_policy p
   where p.organization_id = p_org
     and p.active
     and jsonb_typeof(p.steps) = 'array'
     and jsonb_array_length(p.steps) > 0
     and (p.conditions->>'entity_type' is null or p.conditions->>'entity_type' = p_entity_type)
     and coalesce(p_amount, 0) >= coalesce((p.conditions->>'min_amount')::numeric, 0)
     and (p.conditions->'categories' is null or p_category is null or p.conditions->'categories' ? p_category)
     and (p.conditions->'emirates'   is null or p_emirate  is null or p.conditions->'emirates'   ? p_emirate)
   order by coalesce((p.conditions->>'min_amount')::numeric, 0) desc, p.name
   limit 1
$$;

-- ═══ 3. RAISE — the award trigger ═════════════════════════════════════════════════════════════
-- Placed on inquiries rather than inside customer_api action=complete_inquiry on purpose: the
-- award is also settable from the staff console and from SQL, and a guard in the shared place is
-- a smaller diff than a guard in every caller.
--
-- IT CANNOT FAIL AN AWARD. A customer hiring a supplier must never be rolled back because an
-- approval policy is malformed, so the whole body is wrapped and a failure becomes a warning.
create or replace function public.fn_approval_raise_on_award() returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare v_org uuid; v_policy uuid; v_amount numeric;
begin
  select o.id into v_org from public.customer_organization o
   where o.owner_customer_id = new.customer_id limit 1;
  if v_org is null then
    select m.organization_id into v_org from public.customer_organization_member m
     where m.user_id = new.customer_id and coalesce(m.active, true) limit 1;
  end if;
  if v_org is null then return new; end if;          -- not an enterprise buyer: nothing to approve

  select coalesce(q.customer_price, q.quote_amount) into v_amount
    from public.quotes q
   where q.inquiry_id = new.id and q.supplier_id = new.hired_supplier_id
   order by q.created_at desc limit 1;

  v_policy := public.fn_approval_policy_match(v_org, 'inquiry', v_amount, new.category, new.emirate);
  if v_policy is null then return new; end if;       -- no policy covers this purchase

  if exists (select 1 from public.procurement_approval_request r
              where r.entity_type = 'inquiry' and r.entity_id = new.id::text
                and r.status in ('pending', 'approved')) then
    return new;                                      -- idempotent: one live chain per award
  end if;

  insert into public.procurement_approval_request (organization_id, entity_type, entity_id, policy_id)
  values (v_org, 'inquiry', new.id::text, v_policy);
  return new;
exception when others then
  raise warning 'fn_approval_raise_on_award skipped inquiry %: %', new.id, sqlerrm;
  return new;
end $$;

drop trigger if exists trg_approval_raise_on_award on public.inquiries;
create trigger trg_approval_raise_on_award
  after update of hired_supplier_id on public.inquiries
  for each row
  when (new.hired_supplier_id is not null and new.hired_supplier_id is distinct from old.hired_supplier_id)
  execute function public.fn_approval_raise_on_award();

-- ═══ 4. ADVANCE — a decision moves the chain and records who made it ══════════════════════════
create or replace function public.fn_approval_decide(
  p_request uuid, p_actor uuid, p_decision text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare r public.procurement_approval_request;
        v_steps jsonb; v_n int; v_step jsonb; v_role text; v_actor_role text;
        v_next int; v_status text;
begin
  if coalesce(p_decision, '') not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected, got %', p_decision;
  end if;
  select * into r from public.procurement_approval_request where id = p_request for update;
  if not found then raise exception 'approval request % not found', p_request; end if;
  if r.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'already_' || r.status,
                              'request_id', r.id, 'status', r.status);
  end if;

  -- THE TRUST BOUNDARY IS HERE, NOT IN THE ENDPOINT. Every caller — the customer endpoint, the
  -- staff console, a psql session — routes through this routine, so the membership and role check
  -- lives in it once instead of in each caller.
  select m.role into v_actor_role
    from public.customer_organization_member m
   where m.organization_id = r.organization_id and m.user_id = p_actor and coalesce(m.active, true);
  if v_actor_role is null then
    if exists (select 1 from public.customer_organization o
                where o.id = r.organization_id and o.owner_customer_id = p_actor) then
      v_actor_role := 'owner';
    else
      raise exception 'actor % is not an active member of organization %', p_actor, r.organization_id;
    end if;
  end if;

  select p.steps into v_steps from public.procurement_approval_policy p where p.id = r.policy_id;
  v_steps := coalesce(v_steps, '[]'::jsonb);
  v_n := jsonb_array_length(v_steps);
  if v_n = 0 then raise exception 'approval request % has no policy steps', r.id; end if;
  if r.current_step < 1 or r.current_step > v_n then
    raise exception 'approval request % is at step % of %', r.id, r.current_step, v_n;
  end if;

  v_step := v_steps -> (r.current_step - 1);
  v_role := v_step->>'role';
  if v_role is not null and v_actor_role <> v_role and v_actor_role <> 'owner' then
    raise exception 'step % (%) is decided by %, not %',
      r.current_step, coalesce(v_step->>'label', v_step->>'key'), v_role, v_actor_role;
  end if;

  if p_decision = 'rejected' then      v_status := 'rejected'; v_next := r.current_step;
  elsif r.current_step >= v_n then     v_status := 'approved'; v_next := r.current_step;
  else                                 v_status := 'pending';  v_next := r.current_step + 1;
  end if;

  update public.procurement_approval_request
     set decisions = decisions || jsonb_build_array(jsonb_build_object(
           'step', r.current_step,
           'key', v_step->>'key',
           'label', coalesce(v_step->>'label', v_step->>'key', 'Step ' || r.current_step),
           'decision', p_decision,
           'by', p_actor,
           'by_role', v_actor_role,
           'at', now(),
           'note', p_note)),
         current_step = v_next,
         status = v_status
   where id = r.id;

  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', v_status,
                            'decided_step', r.current_step, 'current_step', v_next,
                            'steps_total', v_n, 'decided_by', p_actor, 'decided_by_role', v_actor_role);
end $$;

-- ═══ 5. PROJECT — one row per named step, with its state ══════════════════════════════════════
-- The spec's own example is this view's output: Engineer approved, Project Manager approved,
-- Finance pending, CEO waiting.
--
-- v_approval_trace previously projected review_chain (the internal staff review ladder) and had
-- zero readers anywhere in the estate. It is replaced, not extended: the two things share nothing
-- but a name, and review_chain is still readable directly.
drop view if exists public.v_approval_trace;
create view public.v_approval_trace as
select r.id                                   as request_id,
       r.organization_id,
       r.entity_type,
       r.entity_id,
       r.status                               as request_status,
       r.current_step,
       r.created_at,
       s.ord::int                             as step,
       coalesce(s.step->>'key', 'step_' || s.ord)                          as step_key,
       coalesce(s.step->>'label', s.step->>'key', 'Step ' || s.ord)        as step_label,
       s.step->>'role'                        as step_role,
       case
         when d.decision is not null      then d.decision          -- approved / rejected
         when r.status = 'rejected'       then 'blocked'
         when r.status = 'approved'       then 'approved'
         when s.ord = r.current_step      then 'pending'
         else                                  'waiting'
       end                                    as step_status,
       d.decided_by,
       d.decided_at,
       d.note                                 as decision_note
  from public.procurement_approval_request r
  join public.procurement_approval_policy p on p.id = r.policy_id
 cross join lateral (select ord, step from jsonb_array_elements(p.steps) with ordinality t(step, ord)) s
  left join lateral (
        select x->>'decision' as decision,
               x->>'by'       as decided_by,
               (x->>'at')::timestamptz as decided_at,
               x->>'note'     as note
          from jsonb_array_elements(r.decisions) x
         where (x->>'step')::int = s.ord
         order by (x->>'at')::timestamptz desc
         limit 1) d on true;

-- ═══ 6. What the customer-authed endpoint calls ═══════════════════════════════════════════════
-- One round trip: the customer's organizations, their policies, and every request with its steps
-- already projected. Empty arrays when the customer has no organization — nothing is implied.
create or replace function public.fn_approval_list(p_customer uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $$
  with orgs as (
    select o.id, o.name from public.customer_organization o where o.owner_customer_id = p_customer
    union
    select o.id, o.name from public.customer_organization o
      join public.customer_organization_member m on m.organization_id = o.id
     where m.user_id = p_customer and coalesce(m.active, true)
  )
  select jsonb_build_object(
    'organizations', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name) from orgs), '[]'::jsonb),
    'policies', coalesce((select jsonb_agg(jsonb_build_object(
          'id', p.id, 'organization_id', p.organization_id, 'name', p.name,
          'active', p.active, 'conditions', p.conditions, 'steps', p.steps) order by p.name)
        from public.procurement_approval_policy p
       where p.organization_id in (select id from orgs)), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object(
            'id', r.id, 'organization_id', r.organization_id,
            'entity_type', r.entity_type, 'entity_id', r.entity_id,
            'policy_id', r.policy_id, 'status', r.status,
            'current_step', r.current_step, 'created_at', r.created_at,
            'steps', coalesce((select jsonb_agg(jsonb_build_object(
                        'step', t.step, 'key', t.step_key, 'label', t.step_label, 'role', t.step_role,
                        'status', t.step_status, 'decided_by', t.decided_by,
                        'decided_at', t.decided_at, 'note', t.decision_note) order by t.step)
                      from public.v_approval_trace t where t.request_id = r.id), '[]'::jsonb)) as x
            from public.procurement_approval_request r
           where r.organization_id in (select id from orgs)) y), '[]'::jsonb));
$$;

-- §22 Orders, scoped to the customer. vendor_id is deliberately NOT projected: it points at the
-- company's AP vendor master, and supplier identity in this product is reveal-gated.
create or replace function public.fn_customer_orders(p_customer uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'po_no', o.po_no, 'status', o.status,
      'order_date', o.order_date, 'expected_date', o.expected_date,
      'currency', o.currency, 'subtotal', o.subtotal, 'memo', o.memo,
      'inquiry_id', o.inquiry_id, 'quote_id', o.quote_id, 'project_id', o.project_id,
      'approved_at', o.approved_at,
      'lines', coalesce((select jsonb_agg(jsonb_build_object(
                  'line_no', l.line_no, 'description', l.description, 'qty', l.qty,
                  'unit_price', l.unit_price, 'qty_received', l.qty_received) order by l.line_no)
                from public.po_lines l where l.po_id = o.id), '[]'::jsonb))
      order by o.order_date desc, o.id desc), '[]'::jsonb)
    from public.po_orders o
   where o.customer_id = p_customer;
$$;

-- ═══ 7. Who may execute what ══════════════════════════════════════════════════════════════════
-- PostgREST exposes every function in public as an RPC to whatever role calls it. fn_approval_decide
-- takes a request id and an actor id, so leaving it executable by anon would let anyone who guesses
-- a uuid approve a purchase. The service role (the edge function) is the only caller.
revoke all on public.v_approval_trace from anon, authenticated;
grant select on public.v_approval_trace to service_role;

revoke execute on function public.fn_approval_decide(uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.fn_approval_list(uuid) from public, anon, authenticated;
revoke execute on function public.fn_customer_orders(uuid) from public, anon, authenticated;
revoke execute on function public.fn_approval_policy_match(uuid, text, numeric, text, text) from public, anon, authenticated;
grant execute on function public.fn_approval_decide(uuid, uuid, text, text) to service_role;
grant execute on function public.fn_approval_list(uuid) to service_role;
grant execute on function public.fn_customer_orders(uuid) to service_role;
grant execute on function public.fn_approval_policy_match(uuid, text, numeric, text, text) to service_role;

notify pgrst, 'reload schema';
