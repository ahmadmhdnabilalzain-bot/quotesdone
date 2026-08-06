-- ROW #4 (customer portal) — spec §13, a relationship score PER CUSTOMER per supplier.
--
-- WHY THIS EXISTS. public.supplier_score holds 20,464 rows and has no customer_id: it is one GLOBAL
-- verdict per supplier — how that supplier behaves toward the platform. §13 asks a different
-- question, "how has this supplier behaved toward ME", and nothing in the estate could express it.
-- This routine computes it from the asking customer's OWN history with that supplier and returns
-- the global figures beside it, clearly labelled, so the two are never confused for one another.
--
-- ZERO-DATA CONTRACT. With no shared history the score is NULL and `basis` says 'no_shared_history'.
-- It is never 0: a 0 out of 100 is a bad supplier, and "we have never worked together" is not that.

create or replace function public.fn_customer_supplier_score(p_customer uuid, p_supplier bigint)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_sent int; v_quoted int; v_awarded int; v_reveals int; v_acked int; v_refunds int;
  v_avg_quote numeric; v_resp_hours numeric; v_last timestamptz;
  v_rating numeric; v_dims jsonb; v_reviews int;
  v_responsiveness numeric; v_award_rate numeric; v_delivery numeric;
  v_quality numeric; v_refund_free numeric;
  v_parts jsonb := '[]'::jsonb; v_sum numeric := 0; v_wt numeric := 0;
  v_global jsonb; v_supplier text;
  -- each component contributes only when the customer's history actually carries it, so a single
  -- review does not become the whole verdict and a missing dimension does not read as a zero
  v_method text := 'weighted mean over the components with data';
begin
  select l.company_name into v_supplier from leads l where l.id = p_supplier;
  if v_supplier is null then
    return jsonb_build_object('error', 'unknown_supplier', 'supplier_id', p_supplier);
  end if;

  select count(*) into v_sent
    from inquiry_matches m join inquiries i on i.id = m.inquiry_id
   where m.supplier_id = p_supplier and i.customer_id = p_customer;

  select count(*), round(avg(q.quote_amount), 0),
         round(avg(extract(epoch from (q.created_at - i.created_at)) / 3600.0)::numeric, 1),
         max(q.created_at)
    into v_quoted, v_avg_quote, v_resp_hours, v_last
    from quotes q join inquiries i on i.id = q.inquiry_id
   where q.supplier_id = p_supplier and i.customer_id = p_customer
     and coalesce(q.status, '') <> 'draft';

  select count(*) into v_awarded
    from inquiries i
   where i.customer_id = p_customer and i.hired_supplier_id = p_supplier;

  select count(*),
         count(*) filter (where t.supplier_ack_at is not null),
         count(*) filter (where coalesce(t.refund_status, '') = 'approved')
    into v_reveals, v_acked, v_refunds
    from transactions t
   where t.customer_id = p_customer and t.supplier_id = p_supplier;

  select count(*), round(avg(r.rating)::numeric, 2),
         jsonb_build_object(
           'communication', round(avg(r.r_communication)::numeric, 2),
           'quality', round(avg(r.r_quality)::numeric, 2),
           'punctuality', round(avg(r.r_punctuality)::numeric, 2),
           'documentation', round(avg(r.r_documentation)::numeric, 2),
           'after_sales', round(avg(r.r_after_sales)::numeric, 2),
           'compliance', round(avg(r.r_compliance)::numeric, 2))
    into v_reviews, v_rating, v_dims
    from reviews r
   where r.customer_id = p_customer and r.supplier_id = p_supplier;

  select jsonb_build_object('reliability', s.reliability, 'quality_rating', s.quality_rating,
                            'price_index', s.price_index, 'response_rate', s.response_rate,
                            'avg_response_hours', s.avg_response_hours,
                            'quotes_submitted', s.quotes_submitted, 'quotes_won', s.quotes_won,
                            'computed_at', s.computed_at)
    into v_global from supplier_score s where s.lead_id = p_supplier;

  -- Nothing shared: report the global figures and refuse to invent a relationship.
  if coalesce(v_sent, 0) = 0 and coalesce(v_quoted, 0) = 0 and coalesce(v_reveals, 0) = 0
     and coalesce(v_reviews, 0) = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'supplier_id', p_supplier, 'supplier_name', v_supplier,
      'basis', 'no_shared_history', 'relationship_score', null,
      'empty_reason', format('You have not worked with %s yet. A relationship score is built from your own RFQs, quotes, orders and reviews with a supplier, so there is nothing to score until the first one.', v_supplier),
      'history', jsonb_build_object('rfqs_sent', 0, 'quotes_received', 0, 'orders', 0,
                                    'reveals', 0, 'reviews', 0),
      'delivery_pct', null, 'quality_pct', null, 'win_rate_pct', null,
      'avg_response_hours', null, 'avg_quote_aed', null, 'last_interaction_at', null,
      'your_rating', null, 'your_rating_dimensions', null,
      'components', '[]'::jsonb,
      'platform_wide', coalesce(v_global, 'null'::jsonb));
  end if;

  if v_sent > 0 then
    v_responsiveness := round(least(100, 100.0 * v_quoted / v_sent), 1);
    v_parts := v_parts || jsonb_build_object('name', 'responsiveness', 'value', v_responsiveness,
      'weight', 30, 'basis', format('%s of %s RFQs you sent came back with a quote', v_quoted, v_sent));
    v_sum := v_sum + v_responsiveness * 30; v_wt := v_wt + 30;
  end if;

  if v_quoted > 0 then
    v_award_rate := round(100.0 * v_awarded / v_quoted, 1);
    v_parts := v_parts || jsonb_build_object('name', 'award_rate', 'value', v_award_rate,
      'weight', 15, 'basis', format('you awarded %s of their %s quote(s)', v_awarded, v_quoted));
    v_sum := v_sum + v_award_rate * 15; v_wt := v_wt + 15;
  end if;

  if v_reveals > 0 then
    v_delivery      := round(100.0 * v_acked / v_reveals, 1);
    v_refund_free   := round(100.0 * (v_reveals - v_refunds) / v_reveals, 1);
    v_parts := v_parts || jsonb_build_object('name', 'delivery', 'value', v_delivery,
      'weight', 30, 'basis', format('%s of %s reveal(s) were acknowledged by the supplier', v_acked, v_reveals));
    v_parts := v_parts || jsonb_build_object('name', 'no_refund', 'value', v_refund_free,
      'weight', 10, 'basis', format('%s of %s reveal(s) ended in a refund', v_refunds, v_reveals));
    v_sum := v_sum + v_delivery * 30 + v_refund_free * 10; v_wt := v_wt + 40;
  end if;

  if v_reviews > 0 and v_rating is not null then
    v_quality := round(100.0 * v_rating / 5.0, 1);
    v_parts := v_parts || jsonb_build_object('name', 'your_rating', 'value', v_quality,
      'weight', 25, 'basis', format('your %s review(s) average %s out of 5', v_reviews, v_rating));
    v_sum := v_sum + v_quality * 25; v_wt := v_wt + 25;
  end if;

  return jsonb_build_object(
    'customer_id', p_customer, 'supplier_id', p_supplier, 'supplier_name', v_supplier,
    'basis', 'shared_history', 'empty_reason', null,
    'relationship_score', case when v_wt > 0 then round(v_sum / v_wt, 0)::int end,
    'score_method', v_method,
    'history', jsonb_build_object('rfqs_sent', v_sent, 'quotes_received', v_quoted,
                                  'orders', v_awarded, 'reveals', v_reveals, 'reviews', v_reviews),
    'delivery_pct', v_delivery,
    'quality_pct', v_quality,
    'win_rate_pct', v_award_rate,
    'avg_response_hours', v_resp_hours,
    'avg_quote_aed', v_avg_quote,
    'last_interaction_at', v_last,
    'your_rating', v_rating,
    'your_rating_dimensions', case when v_reviews > 0 then v_dims end,
    'components', v_parts,
    'platform_wide', coalesce(v_global, 'null'::jsonb));
end $function$;

revoke execute on function public.fn_customer_supplier_score(uuid, bigint) from public;
grant execute on function public.fn_customer_supplier_score(uuid, bigint) to service_role, postgres;
