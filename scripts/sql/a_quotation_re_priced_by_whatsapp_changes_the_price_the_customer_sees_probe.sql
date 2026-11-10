-- Assigned: customer_support
-- PURE PROBE (no DDL) for a_quotation_re_priced_by_whatsapp_changes_the_price_the_customer_sees.sql. It always ends in
-- raise exception 'CHK<<...>>', so every row it writes rolls back. Run it with the file in one rolled-back transaction
-- (node scripts/ci/rehearse_sql.mjs <file> <this>) or after the file is applied.
-- Its subject is one open, unrevealed quotation of a ZZ DEMO supplier at @example.invalid (both marks asserted); every other
-- quotation is fingerprinted before and after and must not move.
--   reprice : AED +10 %          -> quote_amount = price_ex_vat = amount_as_stated = new; VAT keeps its rate; gross/discount cleared
--   refuse  : 0                  -> not an amount, nothing written
--   wiring  : fn_supplier_apply_change writes through fn_quote_reprice (read from its live definition)
do $$
declare v_id uuid; b public.quotes; a public.quotes; v_new numeric; r jsonb; r0 jsonb; v_others_before text; v_others_after text;
        v_wired boolean; fail text := '';
begin
  select q.id into v_id from public.quotes q join public.leads l on l.id = q.supplier_id
   where l.company_name like 'ZZ DEMO%' and l.email like '%@example.invalid' and q.committed_at is null
     and coalesce(q.status, '') not in ('accepted', 'withdrawn', 'expired', 'revealed')
     and not exists (select 1 from public.transactions t where t.quote_id = q.id)
   order by (q.vat_amount is null), q.created_at limit 1;   -- one with a VAT amount first, so the rate is exercised
  if v_id is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no open ZZ DEMO quotation to probe'); end if;
  select md5(string_agg(q.id::text || q.quote_amount || coalesce(q.price_ex_vat::text, '') || coalesce(q.vat_amount::text, ''), ',' order by q.id))
    into v_others_before from public.quotes q where q.id <> v_id;
  select * into b from public.quotes where id = v_id;
  v_new := round(b.quote_amount * 1.1, 2);
  r := public.fn_quote_reprice(v_id, v_new);
  select * into a from public.quotes where id = v_id;
  if not (a.quote_amount = v_new and a.price_ex_vat = v_new and a.amount_as_stated = v_new) then
    fail := fail || format('reprice: amount %s, ex VAT %s, as stated %s, not %s; ', a.quote_amount, a.price_ex_vat, a.amount_as_stated, v_new); end if;
  if b.vat_amount is not null and a.vat_amount is distinct from round(b.vat_amount * v_new / b.quote_amount, 2) then
    fail := fail || format('reprice: VAT %s did not keep its rate (was %s on %s); ', a.vat_amount, b.vat_amount, b.quote_amount); end if;
  if b.vat_amount is null and a.vat_amount is not null then fail := fail || 'reprice: a VAT amount was invented; '; end if;
  if a.gross_amount is not null or a.discount_amount is not null then fail := fail || 'reprice: a gross or discount for the old price survived; '; end if;
  r0 := public.fn_quote_reprice(v_id, 0);
  if coalesce((r0 ->> 'ok')::boolean, true) then fail := fail || 'refuse: 0 was accepted; '; end if;
  if (select quote_amount from public.quotes where id = v_id) <> v_new then fail := fail || 'refuse: the refused call wrote; '; end if;
  v_wired := pg_get_functiondef('public.fn_supplier_apply_change(text,text,text,text,uuid,text)'::regprocedure) ilike '%perform public.fn_quote_reprice(v_q.id, v_num)%';
  if not v_wired then fail := fail || 'wiring: fn_supplier_apply_change does not write through fn_quote_reprice; '; end if;
  select md5(string_agg(q.id::text || q.quote_amount || coalesce(q.price_ex_vat::text, '') || coalesce(q.vat_amount::text, ''), ',' order by q.id))
    into v_others_after from public.quotes q where q.id <> v_id;
  if v_others_before is distinct from v_others_after then fail := fail || 'other quotations moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'quote', v_id, 'before', jsonb_build_object('amount', b.quote_amount, 'ex_vat', b.price_ex_vat, 'vat', b.vat_amount),
    'after', jsonb_build_object('amount', a.quote_amount, 'ex_vat', a.price_ex_vat, 'vat', a.vat_amount), 'wired', v_wired);
end $$;
