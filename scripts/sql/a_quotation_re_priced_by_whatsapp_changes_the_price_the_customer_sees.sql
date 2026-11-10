-- A QUOTATION RE-PRICED BY WHATSAPP CHANGES THE PRICE THE CUSTOMER SEES.
-- Seat: customer_support (the WhatsApp channel, supplier_directive; the quotation is the supplier's). 10 Nov 2026, found in
-- the supplier-quoting audit after #1901 (founder ruling 1608).
--
-- MEASURED BEFORE THIS FILE (code and production, read-only, 10 Nov 2026): wa_inbound supplier_directive applies "change my
-- price to X" through fn_supplier_apply_change, which ran `update quotes set quote_amount = X` and told the supplier "The
-- customer sees the new price from now on". It does not: quote_compare shows the customer `price_ex_vat ?? quote_amount`
-- (quote_compare/index.ts, both the comparison and the levelled terms), and every quote written by the portal sets
-- price_ex_vat (storedPrice, _shared/stated_price.ts; 3 of 3 quotes on production carry it, equal to quote_amount). So after
-- a WhatsApp re-price the customer kept comparing the OLD price while the reveal fee (app_fee, generated from quote_amount)
-- was computed on the NEW one, and vat_amount stayed the old VAT. No re-price has been applied yet (channel_directive: 0).
--
-- WHAT THIS CHANGES: fn_quote_reprice(quote, amount) is the one write of a new total: quote_amount, price_ex_vat and
-- amount_as_stated take the new figure (it is read as the price excluding VAT, the basis both columns already hold); the VAT
-- amount keeps its rate (scaled with the price, so a 5 % VAT stays 5 % and a zero stays zero); a gross price and a discount
-- the supplier stated for the OLD total are cleared rather than left describing a price that no longer exists (nothing is
-- invented). fn_supplier_apply_change (live body md5 dbe8fac1..., read 10 Nov) calls it and tells the supplier the figure is
-- excluding VAT and that the line prices did not move.
-- WHAT IT DOES NOT CHANGE: the quotation's lines (quote_items) - a WhatsApp sentence carries one figure, so the lines no
-- longer add up to the new total; reported, and the supplier is told to send a revised quotation from the portal if they
-- should change. The fat-finger bound, the scoping by phone and every refusal are unchanged.
-- Prevented by: scripts/checks/a_quotation_re_priced_by_whatsapp_changes_the_price_the_customer_sees.test.mjs and the probe of
-- the same name (rolled back on production, on a ZZ DEMO quotation).

create or replace function public.fn_quote_reprice(p_quote_id uuid, p_amount numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_q public.quotes;
begin
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'error', 'not_an_amount'); end if;
  select * into v_q from public.quotes where id = p_quote_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'quote_not_found'); end if;
  update public.quotes
     set quote_amount = p_amount,
         price_ex_vat = p_amount,
         amount_as_stated = p_amount,
         vat_amount = case when v_q.vat_amount is not null and coalesce(v_q.quote_amount, 0) > 0
                           then round(v_q.vat_amount * p_amount / v_q.quote_amount, 2) end,
         gross_amount = null, discount_amount = null, discount_label = null
   where id = p_quote_id;
  return jsonb_build_object('ok', true, 'quote_id', p_quote_id, 'old', v_q.quote_amount, 'new', p_amount);
end $fn$;
revoke execute on function public.fn_quote_reprice(uuid, numeric) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_supplier_apply_change(p_phone text, p_field text, p_value text, p_inbound text, p_quote_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT 'whatsapp'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_lead bigint; v_num numeric; v_q record; v_n int; v_refusal text; v_old numeric; v_list text;
        v_company text;
begin
  -- SCOPE FIRST, AND FROM THE PHONE. Nothing downstream takes a supplier id from the caller.
  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is null then
    insert into public.channel_directive(actor_type, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, 'no supplier account matches this number');
    return jsonb_build_object('ok', false, 'refusal',
      'This number is not linked to a supplier account, so there is nothing of yours I can change. Sign in at https://quotesdone.com/suppliers.');
  end if;
  select company_name into v_company from public.leads where id = v_lead;

  if not exists (select 1 from public.fn_supplier_changeable() c where c.field = p_field) then
    v_refusal := 'I cannot change "' || coalesce(p_field,'(nothing)') || '" from a message. What I can change this way: '
              || (select string_agg(c.field, ', ' order by c.field) from public.fn_supplier_changeable() c)
              || '. Everything else — your licence, your company details, and generating a new quotation — is in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  begin v_num := p_value::numeric; exception when others then v_num := null; end;
  if v_num is null or v_num <= 0 then
    v_refusal := '"' || coalesce(p_value,'') || '" is not an amount I can put on a quotation.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  -- WHICH QUOTATION. Editable means: theirs, still open, nobody has paid to reveal them, not
  -- committed, not already accepted. Each of those is a different reason and each gets said.
  select count(*) into v_n
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);

  if v_n = 0 then
    -- Say WHY there is nothing to change rather than "no quotation found", which is true of a
    -- supplier who has never quoted and of one whose customer paid an hour ago.
    select string_agg(distinct r, '; ') into v_refusal from (
      select case
               when q.committed_at is not null then 'one is committed and cannot be re-priced'
               when coalesce(q.status,'') = 'accepted' then 'one has already been accepted'
               when exists (select 1 from public.transactions t where t.inquiry_id = q.inquiry_id
                             and t.supplier_id = q.supplier_id and t.revealed_at is not null)
                 then 'the customer has already paid to reveal you on one, so the price they paid to see stands'
               else 'the request is closed on one' end as r
        from public.quotes q where q.supplier_id = v_lead
         and (p_quote_id is null or q.id = p_quote_id)) z;
    v_refusal := coalesce('I cannot change a price right now: ' || v_refusal || '.',
                          'You have no open quotation for me to re-price. You can send a new one from the portal.');
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  if v_n > 1 then
    select string_agg(i.category || ' in ' || coalesce(i.emirate,'the UAE') || ' (currently AED ' || q.quote_amount || ')', '; ' order by q.created_at desc)
      into v_list
      from public.quotes q join public.inquiries i on i.id = q.inquiry_id
     where q.supplier_id = v_lead and q.committed_at is null
       and coalesce(q.status,'') not in ('accepted','withdrawn','expired');
    v_refusal := 'You have ' || v_n || ' open quotations, so I will not guess which one you mean: ' || v_list
              || '. Tell me which, or change it in the portal.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'open_quotes', v_n);
  end if;

  select q.* into v_q
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_lead
     and (p_quote_id is null or q.id = p_quote_id)
     and q.committed_at is null
     and coalesce(q.status,'') not in ('accepted','withdrawn','expired')
     and coalesce(i.status,'') not in ('concluded','closed','cancelled','awarded')
     and not exists (select 1 from public.transactions t
                      where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id
                        and t.revealed_at is not null);
  v_old := v_q.quote_amount;

  -- THE FAT-FINGER BOUND. A supplier may price their own work at whatever they like — that is
  -- their commercial decision and not ours. But this arrives as a sentence typed on a phone, where
  -- a missing or extra zero is one keystroke, and a quotation is a number a customer will compare
  -- against others and pay to unlock. Beyond half up or half down, the portal asks for it twice.
  if v_old is not null and v_old > 0 and (v_num > v_old * 1.5 or v_num < v_old * 0.5) then
    v_refusal := 'That would move the price from AED ' || v_old || ' to AED ' || v_num
              || ', which is more than half up or down. I have not changed it — if you do mean that, please set it in the portal so you can see the whole quotation while you do.';
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'old', v_old, 'asked', v_num);
  end if;

  if v_old is not distinct from v_num then
    insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied, refusal)
    values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, false, 'already at that value');
    return jsonb_build_object('ok', true, 'unchanged', true, 'old', v_old, 'new', v_num,
      'message', 'Your quotation is already AED ' || v_num || '. Nothing to change.');
  end if;

  -- 10 Nov 2026: every price column the customer, the reveal fee and the VAT record read moves together (fn_quote_reprice);
  -- this used to set quote_amount alone, so the comparison (price_ex_vat) kept showing the old price.
  perform public.fn_quote_reprice(v_q.id, v_num);

  insert into public.channel_directive(actor_type, actor_id, actor_phone, channel, inbound, field, target_id, old_value, new_value, applied)
  values ('supplier', v_lead, p_phone, p_channel, left(coalesce(p_inbound,''),2000), p_field, v_q.id::text, v_old::text, v_num::text, true);

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_directive', 'ok',
          jsonb_build_object('lead_id', v_lead, 'quote_id', v_q.id, 'old', v_old, 'new', v_num, 'channel', p_channel),
          coalesce(v_company,'lead ' || v_lead) || ' changed a quotation from AED ' || coalesce(v_old::text,'(unset)')
          || ' to AED ' || v_num || ' by ' || p_channel || '. Instruction: ' || left(coalesce(p_inbound,''),200),
          now(), now());

  return jsonb_build_object('ok', true, 'quote_id', v_q.id, 'old', v_old, 'new', v_num,
    'message', 'Done — your quotation is now AED ' || v_num || ' excluding VAT (it was AED ' || coalesce(v_old::text,'unset') || '). The customer sees the new price from now on. Its line prices are unchanged: if they should change too, send a revised quotation from the portal.');
end $function$;

