-- A PROJECT IS SPLIT INTO TRADE PACKAGES ONLY WHEN THE CUSTOMER CHOSE IT (30 Sep 2026). Seat: sales_engineer.
--
-- Founder ruling 1021: a project is never split without asking the customer first; the default is ONE contractor.
-- MEASURED (ledger reconciliation, 30 Sep 2026): nothing in the database enforced it. The only writer of a split is
-- customer_api create_inquiry: when the body says scope_type 'multi' it saves a parent (scope_type 'multi', status
-- 'split') and one child per trade (parent_inquiry_id set). The customer's portal asked the question, but PRESELECTED
-- the split and labelled it "recommended" (src/components/me/NewRequest.tsx, fixed in the same change: the default is
-- now 'turnkey', one company).
--
-- THE GUARD. A per-trade part (inquiries.parent_inquiry_id set) may exist only under a parent whose recorded choice is
-- the split: parent.scope_type = 'multi', which create_inquiry writes only from the customer's own answer. Any other
-- path that tries to split a request - a seat, a repair script, a later feature - is refused here, whatever its code.
-- A parent that already has parts cannot have its choice rewritten to something else while they exist.
--
-- prevented by: scripts/checks/a_project_is_split_only_when_the_customer_chose_it.test.mjs

create or replace function public.trg_inquiry_split_needs_the_customers_choice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_scope text;
begin
  if tg_op = 'UPDATE' and new.parent_inquiry_id is null and old.scope_type = 'multi'
     and new.scope_type is distinct from 'multi'
     and exists (select 1 from public.inquiries c where c.parent_inquiry_id = new.id) then
    raise exception 'inquiry %: its per-trade parts exist, so the customer''s choice to split cannot be rewritten (ruling 1021)', new.id
      using errcode = 'P0001';
  end if;
  if new.parent_inquiry_id is not null
     and (tg_op = 'INSERT' or new.parent_inquiry_id is distinct from old.parent_inquiry_id) then
    select p.scope_type into v_scope from public.inquiries p where p.id = new.parent_inquiry_id;
    if v_scope is distinct from 'multi' then
      raise exception 'inquiry %: a request is split into trade packages only when the customer chose it; the parent''s recorded choice is %, not multi (ruling 1021: the default is one contractor)',
        new.parent_inquiry_id, coalesce(v_scope, 'none') using errcode = 'P0001';
    end if;
  end if;
  return new;
end
$fn$;
revoke execute on function public.trg_inquiry_split_needs_the_customers_choice() from public, anon, authenticated;

drop trigger if exists a03_inquiry_split_needs_the_customers_choice on public.inquiries;
create trigger a03_inquiry_split_needs_the_customers_choice
  before insert or update of parent_inquiry_id, scope_type on public.inquiries
  for each row execute function public.trg_inquiry_split_needs_the_customers_choice();

-- Every per-trade part already on file sits under a 'multi' parent, or this file refuses to apply.
select case when exists (select 1 from public.inquiries c join public.inquiries p on p.id = c.parent_inquiry_id
                          where p.scope_type is distinct from 'multi')
            then 'PROBE FAILED: a per-trade part exists under a parent the customer did not choose to split'
            else 'PROBE OK' end as verdict;
