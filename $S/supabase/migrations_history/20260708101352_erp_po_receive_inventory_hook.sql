-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101352   name: erp_po_receive_inventory_hook
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_po_receive(
  p_po bigint, p_recv jsonb default null, p_date date default null, p_by text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; q numeric(18,4); amt numeric(18,2); gl_lines jsonb := '[]'::jsonb;
        total numeric(18,2) := 0; j bigint; st text; all_recv boolean;
        recv_items jsonb := '[]'::jsonb;   -- {item, qty, unit_cost}
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st not in ('approved','partial') then
    raise exception 'PO % is % (must be approved before receiving)', p_po, st; end if;

  for r in select * from public.po_lines where po_id=p_po order by line_no loop
    if p_recv is null then
      q := r.qty - r.qty_received;
    else
      q := coalesce((select (e->>'qty')::numeric
             from jsonb_array_elements(p_recv) e
             where (e->>'line_no')::int = r.line_no), 0);
    end if;
    if q <= 0 then continue; end if;
    if r.qty_received + q > r.qty then
      raise exception 'line % over-receipt: %/%', r.line_no, r.qty_received+q, r.qty; end if;
    amt := round(q * r.unit_price, 2);
    total := total + amt;
    gl_lines := gl_lines || jsonb_build_object('account', r.account_code, 'debit', amt);
    update public.po_lines set qty_received = qty_received + q where id=r.id;
    if r.item_id is not null then
      recv_items := recv_items || jsonb_build_object('item', r.item_id, 'qty', q, 'unit_cost', r.unit_price);
    end if;
  end loop;

  if total = 0 then raise exception 'nothing to receive on PO %', p_po; end if;
  gl_lines := gl_lines || jsonb_build_object('account','2250','credit', total);
  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Goods receipt '||(select po_no from public.po_orders where id=p_po),
         'po_receipt', p_po::text, gl_lines, p_by);

  -- record inventory stock moves (GL already posted above; no double entry)
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
  select (e->>'item')::bigint, coalesce(p_date,current_date), 'in',
         (e->>'qty')::numeric, round((e->>'qty')::numeric*(e->>'unit_cost')::numeric,2),
         (e->>'unit_cost')::numeric, 'po_receipt', p_po::text, j, p_by
  from jsonb_array_elements(recv_items) e;

  select bool_and(qty_received >= qty) into all_recv from public.po_lines where po_id=p_po;
  update public.po_orders set status = case when all_recv then 'received' else 'partial' end where id=p_po;
  return j;
end $$;

