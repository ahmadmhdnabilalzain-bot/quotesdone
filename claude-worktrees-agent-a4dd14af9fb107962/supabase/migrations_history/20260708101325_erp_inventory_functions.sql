-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101325   name: erp_inventory_functions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ---- Receive stock (in). post_gl=false when GL already posted (e.g. by PO receipt)
create or replace function public.fn_inv_receive(
  p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date default null,
  p_ref_type text default 'manual', p_ref_id text default null,
  p_post_gl boolean default true, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare amt numeric(18,2); j bigint; inv_acct text; m bigint;
begin
  if p_qty <= 0 then raise exception 'receive qty must be > 0'; end if;
  select inventory_account into inv_acct from public.inv_items where id=p_item;
  if inv_acct is null then raise exception 'item % not found', p_item; end if;
  amt := round(p_qty * p_unit_cost, 2);
  if p_post_gl then                                   -- Dr Inventory  Cr Cash(1000)
    j := public.fn_gl_entry(coalesce(p_date,current_date),
           'Inventory receipt item '||p_item, 'inv_receipt', p_ref_id,
           jsonb_build_array(jsonb_build_object('account',inv_acct,'debit',amt),
                             jsonb_build_object('account','1000','credit',amt)), p_by);
  end if;
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
    values (p_item, coalesce(p_date,current_date),'in', p_qty, amt, p_unit_cost,
            p_ref_type, p_ref_id, j, p_by)
    returning id into m;
  return m;
end $$;

-- ---- Issue stock (out) at weighted-average cost -> Dr COGS  Cr Inventory
create or replace function public.fn_inv_issue(
  p_item bigint, p_qty numeric, p_date date default null,
  p_ref_type text default 'manual', p_ref_id text default null, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare onq numeric(18,4); onv numeric(18,2); avg_c numeric(18,4);
        amt numeric(18,2); j bigint; inv_acct text; cogs_acct text; m bigint;
begin
  select coalesce(sum(qty_delta),0), coalesce(sum(cost_delta),0)
    into onq, onv from public.inv_stock_moves where item_id=p_item;
  if p_qty <= 0 then raise exception 'issue qty must be > 0'; end if;
  if p_qty > onq then raise exception 'insufficient stock for item %: have %, need %', p_item, onq, p_qty; end if;
  avg_c := case when onq <> 0 then onv/onq else 0 end;
  amt := round(p_qty * avg_c, 2);
  select inventory_account, cogs_account into inv_acct, cogs_acct from public.inv_items where id=p_item;
  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Inventory issue item '||p_item, 'inv_issue', p_ref_id,
         jsonb_build_array(jsonb_build_object('account',cogs_acct,'debit',amt),
                           jsonb_build_object('account',inv_acct,'credit',amt)), p_by);
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
    values (p_item, coalesce(p_date,current_date),'out', -p_qty, -amt, avg_c,
            p_ref_type, p_ref_id, j, p_by)
    returning id into m;
  return m;
end $$;

-- ---- Adjust stock (count correction / write-down) -> Inventory vs offset acct
create or replace function public.fn_inv_adjust(
  p_item bigint, p_qty_delta numeric, p_unit_cost numeric default null,
  p_offset_account text default '6300', p_date date default null,
  p_memo text default null, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare onq numeric(18,4); onv numeric(18,2); avg_c numeric(18,4);
        uc numeric(18,4); amt numeric(18,2); j bigint; inv_acct text; m bigint;
begin
  if p_qty_delta = 0 then raise exception 'adjustment qty_delta cannot be 0'; end if;
  select coalesce(sum(qty_delta),0), coalesce(sum(cost_delta),0)
    into onq, onv from public.inv_stock_moves where item_id=p_item;
  avg_c := case when onq <> 0 then onv/onq else 0 end;
  uc := coalesce(p_unit_cost, avg_c);                 -- default to current avg for reductions
  amt := round(p_qty_delta * uc, 2);                  -- signed
  select inventory_account into inv_acct from public.inv_items where id=p_item;
  if inv_acct is null then raise exception 'item % not found', p_item; end if;
  -- positive delta: Dr Inventory / Cr offset ; negative: Dr offset / Cr Inventory
  if amt >= 0 then
    j := public.fn_gl_entry(coalesce(p_date,current_date), coalesce(p_memo,'Inventory adjustment'),
           'inv_adjust', p_item::text,
           jsonb_build_array(jsonb_build_object('account',inv_acct,'debit',amt),
                             jsonb_build_object('account',p_offset_account,'credit',amt)), p_by);
  else
    j := public.fn_gl_entry(coalesce(p_date,current_date), coalesce(p_memo,'Inventory adjustment'),
           'inv_adjust', p_item::text,
           jsonb_build_array(jsonb_build_object('account',p_offset_account,'debit',-amt),
                             jsonb_build_object('account',inv_acct,'credit',-amt)), p_by);
  end if;
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,memo,created_by)
    values (p_item, coalesce(p_date,current_date),'adjust', p_qty_delta, amt, uc,
            'adjust', p_item::text, j, p_memo, p_by)
    returning id into m;
  return m;
end $$;

