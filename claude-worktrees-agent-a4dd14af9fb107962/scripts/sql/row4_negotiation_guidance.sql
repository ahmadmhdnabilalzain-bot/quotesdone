-- ROW #4 (customer portal) — spec §15, the AI negotiation assistant, server side.
--
-- WHAT WAS THERE AND WHAT WAS NOT. category_price_stats already computes the market median, p25, p75
-- and mean per category, and fn_price_confidence already turns a quote and a category into a band.
-- Neither had a single customer-authed reader, and supplier_negotiation_policy — the declared home
-- for "what should I actually ask for" — held zero rows. Surfacing the two that exist is the floor;
-- this routine is the rest: it joins the benchmark to the house policy and emits a recommended
-- action, a target price bounded by that policy, and a message the customer can send as written.
--
-- THE ZERO-DATA CONTRACT, AND IT IS THE IMPORTANT ONE HERE. Production holds zero quotes, so
-- category_price_stats is empty and every call today returns band 'insufficient_data'. In that
-- state this routine returns NO target price, NO discount percentage and a message that asks the
-- supplier to clarify scope and terms rather than one that cites a market average nobody measured.
-- A negotiation assistant that invents a benchmark from fewer than `min_sample` quotes would be the
-- same defect class as the empty state that told customers they had been "matched with suitable
-- suppliers" whether or not anyone was matched.

create or replace function public.fn_negotiation_guidance(p_customer uuid, p_quote uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_amount numeric; v_cat text; v_supplier bigint; v_supplier_name text; v_inquiry uuid;
  v_stats jsonb; v_policy jsonb; v_scope text; v_band text; v_rule jsonb;
  v_median numeric; v_n int; v_ask numeric; v_max_ask numeric; v_floor_pct numeric;
  v_target numeric; v_delta numeric; v_action text; v_msg text; v_msg_ar text; v_headline text;
begin
  select q.quote_amount, q.supplier_id, i.category, i.id
    into v_amount, v_supplier, v_cat, v_inquiry
    from quotes q join inquiries i on i.id = q.inquiry_id
   where q.id = p_quote and i.customer_id = p_customer;

  -- Ownership is the first gate, not a filter added later: a quote on someone else's RFQ is not a
  -- quote this caller may benchmark.
  if v_inquiry is null then
    return jsonb_build_object('error', 'not_your_quote', 'quote_id', p_quote);
  end if;

  select l.company_name into v_supplier_name from leads l where l.id = v_supplier;

  v_stats := fn_price_confidence(v_cat, v_amount);
  v_band  := coalesce(v_stats ->> 'band', 'insufficient_data');
  v_median := nullif(v_stats ->> 'median', '')::numeric;
  v_n      := coalesce(nullif(v_stats ->> 'n', '')::int, 0);

  -- Per-supplier override first, house policy second. Neither is invented here: if the table is
  -- empty the routine says so instead of falling back to a hard-coded percentage.
  select p.policy, p.scope into v_policy, v_scope from supplier_negotiation_policy p
   where p.supplier_id = v_supplier limit 1;
  if v_policy is null then
    select p.policy, p.scope into v_policy, v_scope from supplier_negotiation_policy p
     where p.scope = 'default' limit 1;
  end if;
  if v_policy is null then
    return jsonb_build_object(
      'quote_id', p_quote, 'inquiry_id', v_inquiry, 'category', v_cat,
      'quote_amount', v_amount, 'supplier_id', v_supplier, 'supplier_name', v_supplier_name,
      'market', v_stats, 'policy_scope', null,
      'recommended_action', 'no_policy', 'target_price', null, 'ask_discount_pct', null,
      'headline', 'No negotiation policy is configured yet.',
      'suggested_message', null, 'suggested_message_ar', null,
      'empty_reason', 'supplier_negotiation_policy holds no rule for this supplier and no default rule, so no target price is proposed.');
  end if;

  if v_n < coalesce((v_policy ->> 'min_sample')::int, 4) then v_band := 'insufficient_data'; end if;
  v_rule      := coalesce(v_policy -> 'bands' -> v_band, v_policy -> 'bands' -> 'insufficient_data');
  v_action    := coalesce(v_rule ->> 'action', 'no_benchmark_yet');
  v_ask       := coalesce((v_rule ->> 'ask_discount_pct')::numeric, 0);
  v_max_ask   := coalesce((v_rule ->> 'max_ask_discount_pct')::numeric, 0);
  v_floor_pct := coalesce((v_policy ->> 'never_target_below_pct_of_median')::numeric, 80);
  v_ask       := least(v_ask, v_max_ask);

  if v_band = 'insufficient_data' or v_median is null or v_ask <= 0 then
    -- No benchmark, or a band the policy says not to push on. Both get an honest message.
    v_target := null;
    v_delta  := case when v_median is not null and v_median > 0
                     then round(100 * (v_amount - v_median) / v_median, 1) end;
    v_headline := case
      when v_band = 'insufficient_data' then
        format('No market benchmark yet — only %s comparable quote(s) recorded in %s, and this house policy needs %s before it will quote a market price.',
               v_n, coalesce(v_cat, 'this category'), coalesce(v_policy ->> 'min_sample', '4'))
      when v_band = 'suspiciously_low' then
        format('This quote is well below the market median of AED %s. Confirm the scope before pushing the price.', v_median)
      else format('This quote sits inside the market range; the house policy does not push on it.') end;
    v_msg := case
      when v_band = 'suspiciously_low' then
        format('Hello%s,%s%sThank you for the quotation on %s. Before we proceed I would like to confirm the scope: could you set out exactly what is included, what is excluded, the delivery lead time and the warranty terms? Your price is materially below the other submissions we hold and I want to be sure we are comparing the same package.%s%sKind regards',
               case when v_supplier_name is null then '' else ' ' || v_supplier_name end,
               chr(10), chr(10), coalesce(v_cat, 'this package'), chr(10), chr(10))
      else
        format('Hello%s,%s%sThank you for the quotation on %s. Could you confirm the inclusions and exclusions, the delivery lead time, the payment terms and the warranty period in writing? Once I have those on the same basis from each supplier I will come back to you on price.%s%sKind regards',
               case when v_supplier_name is null then '' else ' ' || v_supplier_name end,
               chr(10), chr(10), coalesce(v_cat, 'this package'), chr(10), chr(10)) end;
    v_msg_ar := format('تحية طيبة،%s%sشكرًا لعرضكم بخصوص %s. نرجو تأكيد البنود المشمولة والمستثناة، ومدة التسليم، وشروط الدفع، وفترة الضمان كتابةً. وبمجرد استلام ذلك من جميع المورّدين على الأساس نفسه سنعود إليكم بشأن السعر.%s%sمع خالص التقدير',
                       chr(10), chr(10), coalesce(v_cat, 'هذا البند'), chr(10), chr(10));
  else
    v_target := greatest(round(v_amount * (1 - v_ask / 100), 0),
                         round(v_median * v_floor_pct / 100, 0));
    v_delta  := round(100 * (v_amount - v_median) / nullif(v_median, 0), 1);
    v_headline := format('AED %s is %s%s%% against a market median of AED %s over %s comparable quote(s). Policy says %s: target AED %s.',
                         v_amount, case when v_delta >= 0 then '+' else '' end, v_delta,
                         v_median, v_n, replace(v_action, '_', ' '), v_target);
    v_msg := format('Hello%s,%s%sThank you for the quotation on %s at AED %s. Based on comparable submissions we are holding for the same scope, our benchmark for this package is around AED %s. If you can meet AED %s on the same inclusions, lead time and warranty, we are ready to proceed with you.%s%sIf the price cannot move, tell me what would have to change in the scope to reach it and I will consider that instead.%s%sKind regards',
                    case when v_supplier_name is null then '' else ' ' || v_supplier_name end,
                    chr(10), chr(10), coalesce(v_cat, 'this package'), v_amount, v_median, v_target,
                    chr(10), chr(10), chr(10), chr(10));
    v_msg_ar := format('تحية طيبة،%s%sشكرًا لعرضكم بخصوص %s بمبلغ %s درهم. استنادًا إلى العروض المماثلة لدينا لنفس النطاق، فإن السعر المرجعي لهذا البند يقارب %s درهم. إذا أمكنكم الوصول إلى %s درهم بنفس البنود ومدة التسليم والضمان، فنحن مستعدون للمضي معكم.%s%sوإذا تعذّر تعديل السعر، فأخبرونا بما يلزم تغييره في النطاق للوصول إليه.%s%sمع خالص التقدير',
                       chr(10), chr(10), coalesce(v_cat, 'هذا البند'), v_amount, v_median, v_target,
                       chr(10), chr(10), chr(10), chr(10));
  end if;

  return jsonb_build_object(
    'quote_id', p_quote, 'inquiry_id', v_inquiry, 'category', v_cat,
    'quote_amount', v_amount, 'supplier_id', v_supplier, 'supplier_name', v_supplier_name,
    'market', v_stats,
    'market_median', v_median, 'market_sample_n', v_n,
    'delta_vs_median_pct', v_delta,
    'band', v_band,
    'policy_scope', v_scope,
    'recommended_action', v_action,
    'ask_discount_pct', case when v_target is null then null else v_ask end,
    'target_price', v_target,
    'headline', v_headline,
    'suggested_message', v_msg,
    'suggested_message_ar', v_msg_ar,
    'empty_reason', case when v_target is null
      then format('No target price is proposed: %s.', case when v_band = 'insufficient_data'
        then 'the category has fewer comparable quotes than this policy requires'
        else 'the house policy does not push on this band' end) end);
end $function$;

revoke execute on function public.fn_negotiation_guidance(uuid, uuid) from public;
grant execute on function public.fn_negotiation_guidance(uuid, uuid) to service_role, postgres;
