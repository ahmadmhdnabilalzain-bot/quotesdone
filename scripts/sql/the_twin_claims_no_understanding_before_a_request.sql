-- THE TWIN CLAIMS NO UNDERSTANDING BEFORE A REQUEST — founder walk of /me, 14 Sep 2026.
--
-- SEEN LIVE: the Overview printed "AI understanding 63%" for an account with 0 requests and no
-- industry. MEASURED the same day: fn_twin('customer', <that account>) counted 5 of 8 facts —
-- name, phone, verified email, Terms accepted and locale. Those are sign-up fields every account
-- has; none of them is anything the system learned about how this customer BUYS, so labelling the
-- tally "understanding" put a number on the screen that measured nothing it claimed to.
--
-- THE RULE NOW: understanding_pct is NULL until the customer has raised at least one request. The
-- portal (src/components/portal/twin/CompanyTwin.tsx) already prints nothing when it is null. Once
-- a request exists the same eight-fact count applies, unchanged. Every other key is unchanged; the
-- body is the live definition read back on 14 Sep 2026 with only that one expression edited.
--
-- CREATE OR REPLACE keeps the existing ACL (postgres, service_role only), so no revoke here.
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
      -- AI UNDERSTANDING (§2) — the share of eight profile facts held, and ONLY once the customer
      -- has raised a request. Before that there is no buying behaviour to understand, and a tally of
      -- sign-up fields is not understanding (see the header of this file).
      'understanding_pct',(case when exists (select 1 from inquiries where customer_id=c.id) then
         (select round(100.0 * (
             (c.full_name is not null and c.full_name <> '')::int
           + (c.phone is not null and c.phone <> '')::int
           + coalesce(c.email_verified,false)::int
           + (c.tos_accepted_at is not null)::int
           + (c.locale is not null)::int
           + (c.industry is not null and c.industry <> '')::int
           + 1
           + (exists (select 1 from customer_preference cp where cp.customer_id=c.id))::int
         ) / 8.0)) end),
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
