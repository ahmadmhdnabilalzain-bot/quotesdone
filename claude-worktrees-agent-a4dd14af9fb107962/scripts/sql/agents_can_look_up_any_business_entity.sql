-- AGENTS CAN LOOK UP ANY BUSINESS ENTITY (company knowledge — the CRM connection).
--
-- An employee knows the business by being able to look it up. Agents had the aggregate counts but no
-- way to pull a specific customer, supplier, inquiry, quote or transaction — and no live summary of
-- the whole entity landscape. This builds that connection. It works on the SHAPE of the data, not its
-- presence: today customers/inquiries/quotes/transactions are 0 and suppliers are a 20k-row leads
-- pool, so the lookups return "none found" or the pool — and the instant real records arrive, the same
-- calls return them, with no further work.
--
--   node scripts/apply_sql.mjs scripts/sql/agents_can_look_up_any_business_entity.sql --apply --ddl

begin;

-- 1. THE LIVE LANDSCAPE — counts an agent can state without looking anything up.
create or replace function public.fn_business_entity_summary()
 returns jsonb language sql stable security definer set search_path to 'public','pg_temp'
as $fn$
  select jsonb_build_object(
    'as_of', now(),
    'customers',            (select count(*) from public.customers),
    'customers_with_inquiry',(select count(distinct customer_id) from public.inquiries where customer_id is not null),
    'suppliers_total',      (select count(*) from public.leads),
    'suppliers_approved',   (select count(*) from public.leads where approval_status='approved'),
    'suppliers_prospective',(select count(*) from public.leads where coalesce(approval_status,'') <> 'approved'),
    'sendable_supplier_pool',(select coalesce(sum(sendable),0)::int from public.v_supply_gap),
    'inquiries',            (select count(*) from public.inquiries),
    'quotes',               (select count(*) from public.quotes),
    'transactions',         (select count(*) from public.transactions),
    'categories_total',     (select count(*) from public.catalog_supplier_categories),
    'categories_at_target', (select count(*) from public.v_supply_gap where approved >= 10));
$fn$;
revoke execute on function public.fn_business_entity_summary() from public;
grant execute on function public.fn_business_entity_summary() to service_role;

-- 2. LOOK UP ONE SPECIFIC ENTITY by id, email, name or phone — returns its full profile.
create or replace function public.fn_business_entity_lookup(p_entity text, p_key text)
 returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $fn$
declare v jsonb; e text := lower(btrim(coalesce(p_entity,''))); k text := btrim(coalesce(p_key,''));
begin
  if k = '' then return jsonb_build_object('ok',false,'error','a key is required (id, email, company name or phone)'); end if;
  if e in ('customer','buyer') then
    select to_jsonb(c) into v from public.customers c where c.id::text=k or lower(c.email)=lower(k) or c.phone=k limit 1;
  elsif e in ('supplier','lead','vendor') then
    select to_jsonb(l) into v from public.leads l where l.id::text=k or lower(l.email)=lower(k) or l.company_name ilike k or l.phone=k limit 1;
  elsif e in ('inquiry','rfq','request') then
    select to_jsonb(i) into v from public.inquiries i where i.id::text=k limit 1;
  elsif e in ('quote','quotation','offer') then
    select to_jsonb(q) into v from public.quotes q where q.id::text=k limit 1;
  elsif e in ('transaction','payment','order','reveal') then
    select to_jsonb(t) into v from public.transactions t where t.id::text=k limit 1;
  else
    return jsonb_build_object('ok',false,'error','unknown entity "'||e||'". Use: customer, supplier, inquiry, quote or transaction.');
  end if;
  if v is null then return jsonb_build_object('ok',true,'entity',e,'key',k,'found',false); end if;
  return jsonb_build_object('ok',true,'entity',e,'found',true,'profile',v);
end $fn$;
revoke execute on function public.fn_business_entity_lookup(text,text) from public;
grant execute on function public.fn_business_entity_lookup(text,text) to service_role;

-- 3. LIST / SEARCH entities — "who are our suppliers?", "recent inquiries", "approved suppliers".
create or replace function public.fn_business_entity_list(p_entity text, p_filter text default null, p_limit integer default 25)
 returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $fn$
declare v jsonb; e text := lower(btrim(coalesce(p_entity,''))); f text := btrim(coalesce(p_filter,'')); n int := least(greatest(coalesce(p_limit,25),1),200);
begin
  if e in ('customer','buyer') then
    select jsonb_agg(to_jsonb(c)) into v from (select id,email,phone,created_at from public.customers order by created_at desc limit n) c;
  elsif e in ('supplier','lead','vendor') then
    select jsonb_agg(to_jsonb(l)) into v from (
      select id,company_name,contact_name,email,phone,approval_status,created_at from public.leads
       where f='' or company_name ilike '%'||f||'%' or approval_status=f
       order by (approval_status='approved') desc, created_at desc limit n) l;
  elsif e in ('inquiry','rfq','request') then
    select jsonb_agg(to_jsonb(i)) into v from (
      select id,customer_id,category,status,created_at from public.inquiries
       where f='' or status=f or category ilike '%'||f||'%' order by created_at desc limit n) i;
  elsif e in ('quote','quotation','offer') then
    select jsonb_agg(to_jsonb(q)) into v from (select id,inquiry_id,supplier_id,quote_amount,status,created_at from public.quotes order by created_at desc limit n) q;
  elsif e in ('transaction','payment','order','reveal') then
    select jsonb_agg(to_jsonb(t)) into v from (select id,inquiry_id,supplier_id,customer_id,quote_amount from public.transactions limit n) t;
  else
    return jsonb_build_object('ok',false,'error','unknown entity "'||e||'". Use: customer, supplier, inquiry, quote or transaction.');
  end if;
  return jsonb_build_object('ok',true,'entity',e,'filter',nullif(f,''),'items',coalesce(v,'[]'::jsonb),'count',jsonb_array_length(coalesce(v,'[]'::jsonb)));
end $fn$;
revoke execute on function public.fn_business_entity_list(text,text,integer) from public;
grant execute on function public.fn_business_entity_list(text,text,integer) to service_role;

-- Delivery: these are granted to service_role, which is exactly the identity the agent runtime runs
-- as, so every agent can call them. Awareness comes from the universal company_core 'business-entities'
-- record (fn_company_org_directory_sync), which tells every agent the three calls and when to use them.
-- org_action_executor is keyed by action_class alone (one department per tool), so it cannot carry a
-- universal tool; the knowledge record is the right, universal delivery.

commit;
