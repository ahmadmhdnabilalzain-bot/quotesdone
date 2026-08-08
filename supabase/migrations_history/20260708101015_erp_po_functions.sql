-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101015   name: erp_po_functions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ---- Create a PO (draft) -------------------------------------------------
-- p_lines = [{"description":"Cloud hosting","account":"6000","qty":1,"unit_price":500,"item":null}, ...]
create or replace function public.fn_po_create(
  p_vendor bigint, p_order_date date, p_expected date,
  p_memo text, p_lines jsonb, p_created_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_po bigint; ln jsonb; i int := 0; sub numeric(18,2) := 0;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'PO needs at least one line';
  end if;
  insert into public.po_orders(vendor_id,order_date,expected_date,memo,created_by)
    values (p_vendor, coalesce(p_order_date,current_date), p_expected, p_memo, p_created_by)
    returning id into v_po;
  update public.po_orders set po_no = 'PO-'||lpad(v_po::text,6,'0') where id=v_po;
  for ln in select * from jsonb_array_elements(p_lines) loop
    i := i + 1;
    insert into public.po_lines(po_id,line_no,description,account_code,item_id,qty,unit_price)
      values (v_po, i, ln->>'description', ln->>'account',
              nullif(ln->>'item','')::bigint,
              (ln->>'qty')::numeric, coalesce((ln->>'unit_price')::numeric,0));
    sub := sub + (ln->>'qty')::numeric * coalesce((ln->>'unit_price')::numeric,0);
  end loop;
  update public.po_orders set subtotal = sub where id=v_po;
  return v_po;
end $$;

-- ---- Approve a PO (commitment only, no GL) --------------------------------
create or replace function public.fn_po_approve(p_po bigint, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare st text;
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st <> 'draft' then raise exception 'PO % is % (only draft can be approved)', p_po, st; end if;
  update public.po_orders set status='approved', approved_by=p_by, approved_at=now() where id=p_po;
  return p_po;
end $$;

-- ---- Receive goods/services ---------------------------------------------
-- p_recv = [{"line_no":1,"qty":1}, ...]  (omit -> receive all outstanding)
-- GL: Dr line account (inventory/expense)  Cr GRNI 2250
create or replace function public.fn_po_receive(
  p_po bigint, p_recv jsonb default null, p_date date default null, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; q numeric(18,4); amt numeric(18,2); gl_lines jsonb := '[]'::jsonb;
        total numeric(18,2) := 0; j bigint; st text; all_recv boolean;
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st not in ('approved','partial') then
    raise exception 'PO % is % (must be approved before receiving)', p_po, st; end if;

  for r in select * from public.po_lines where po_id=p_po order by line_no loop
    if p_recv is null then
      q := r.qty - r.qty_received;                        -- receive all outstanding
    else
      q := coalesce((select (e->>'qty')::numeric
             from jsonb_array_elements(p_recv) e
             where (e->>'line_no')::int = r.line_no), 0);
    end if;
    if q <= 0 then continue; end if;
    if r.qty_received + q > r.qty then
      raise exception 'line % over-receipt: %/% ', r.line_no, r.qty_received+q, r.qty; end if;
    amt := round(q * r.unit_price, 2);
    total := total + amt;
    gl_lines := gl_lines || jsonb_build_object('account', r.account_code, 'debit', amt);
    update public.po_lines set qty_received = qty_received + q where id=r.id;
  end loop;

  if total = 0 then raise exception 'nothing to receive on PO %', p_po; end if;
  gl_lines := gl_lines || jsonb_build_object('account','2250','credit', total);  -- GRNI
  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Goods receipt '||(select po_no from public.po_orders where id=p_po),
         'po_receipt', p_po::text, gl_lines, p_by);

  select bool_and(qty_received >= qty) into all_recv from public.po_lines where po_id=p_po;
  update public.po_orders set status = case when all_recv then 'received' else 'partial' end where id=p_po;
  return j;
end $$;

-- ---- Create a vendor bill for received-but-unbilled qty -------------------
-- GL: Dr GRNI 2250 (subtotal) + Dr VAT Recoverable 1150 (vat)  Cr AP 2000 (total)
create or replace function public.fn_po_bill(
  p_po bigint, p_bill_no text, p_bill_date date, p_due date,
  p_vat numeric default 0, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; q numeric(18,4); amt numeric(18,2); sub numeric(18,2) := 0;
        vat numeric(18,2) := coalesce(round(p_vat,2),0); tot numeric(18,2);
        gl_lines jsonb := '[]'::jsonb; j bigint; v_bill bigint; v_vendor bigint;
        all_billed boolean;
begin
  select vendor_id into v_vendor from public.po_orders where id=p_po;
  if v_vendor is null then raise exception 'PO % not found', p_po; end if;

  for r in select * from public.po_lines where po_id=p_po order by line_no loop
    q := r.qty_received - r.qty_billed;                   -- received not yet billed
    if q <= 0 then continue; end if;
    amt := round(q * r.unit_price, 2);
    sub := sub + amt;
    update public.po_lines set qty_billed = qty_billed + q where id=r.id;
  end loop;
  if sub = 0 then raise exception 'PO % has no received-unbilled qty to bill', p_po; end if;
  tot := sub + vat;

  gl_lines := jsonb_build_array(jsonb_build_object('account','2250','debit', sub));  -- clear GRNI
  if vat > 0 then
    gl_lines := gl_lines || jsonb_build_object('account','1150','debit', vat); end if;
  gl_lines := gl_lines || jsonb_build_object('account','2000','credit', tot);        -- AP

  j := public.fn_gl_entry(coalesce(p_bill_date,current_date),
         'Vendor bill '||coalesce(p_bill_no,'(PO-'||p_po||')'),
         'ap_bill', p_po::text, gl_lines, p_by);

  insert into public.ap_bills(bill_no,vendor_id,po_id,bill_date,due_date,
        subtotal,vat_amount,total,gl_journal_id,created_by)
    values (p_bill_no, v_vendor, p_po, coalesce(p_bill_date,current_date), p_due,
            sub, vat, tot, j, p_by)
    returning id into v_bill;
  update public.ap_bills set bill_no = coalesce(bill_no,'BILL-'||lpad(v_bill::text,6,'0')) where id=v_bill;

  select bool_and(qty_billed >= qty) into all_billed from public.po_lines where po_id=p_po;
  update public.po_orders set status = case when all_billed then 'billed' else status end where id=p_po;
  return v_bill;
end $$;

-- ---- Pay a vendor bill (full or partial) ---------------------------------
-- GL: Dr AP 2000  Cr cash/bank (default 1000)
create or replace function public.fn_ap_pay(
  p_bill bigint, p_date date default null, p_amount numeric default null,
  p_from_account text default '1000', p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare b record; pay numeric(18,2); j bigint; newpaid numeric(18,2);
begin
  select * into b from public.ap_bills where id=p_bill;
  if b.id is null then raise exception 'bill % not found', p_bill; end if;
  if b.status in ('paid','void') then raise exception 'bill % is %', p_bill, b.status; end if;
  pay := coalesce(round(p_amount,2), b.total - b.amount_paid);
  if pay <= 0 then raise exception 'nothing to pay on bill %', p_bill; end if;
  if b.amount_paid + pay > b.total then raise exception 'overpay bill %: %/%', p_bill, b.amount_paid+pay, b.total; end if;

  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Payment '||coalesce(b.bill_no,'bill '||p_bill),
         'ap_payment', p_bill::text,
         jsonb_build_array(jsonb_build_object('account','2000','debit', pay),
                           jsonb_build_object('account',p_from_account,'credit', pay)),
         p_by);
  newpaid := b.amount_paid + pay;
  update public.ap_bills
     set amount_paid = newpaid,
         status = case when newpaid >= total then 'paid' else 'partial' end,
         pay_journal_id = j
   where id=p_bill;
  return j;
end $$;

