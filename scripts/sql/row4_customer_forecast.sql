-- ROW #4 (customer portal) — spec §11 (next-year procurement forecast) and §20 (AI predictive
-- intelligence: "based on your projects you will likely need X within N days").
--
-- WHY A NEW ROUTINE. fn_finance_forecast() takes NO ARGUMENTS. It projects the COMPANY's cash from
-- gl_journal, ap_open_bills and supplier_dues — there is no customer anywhere in it and no way to
-- scope it to one. A customer-facing forecast has to be built from the customer's own history, so
-- this is that routine, not a wrapper over that one.
--
-- THE ZERO-DATA CONTRACT. Production has zero customers and zero inquiries. Every branch below that
-- would otherwise invent a number returns null and says why in `empty_reason`, and `series` returns
-- [] rather than twelve zero-valued months — a chart drawn from twelve zeros looks like a business
-- that bought nothing, which is a claim about the customer, not an absence of data about them.

create or replace function public.fn_customer_forecast(p_customer uuid, p_horizon_days integer default 365)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rfqs int; v_months int; v_first timestamptz; v_last timestamptz;
  v_spend numeric; v_span_days numeric;
  v_series jsonb; v_by_cat jsonb; v_predictions jsonb;
  v_sufficient boolean; v_reason text;
  v_proj_rfqs numeric; v_proj_spend numeric;
begin
  select count(*), min(i.created_at), max(i.created_at),
         count(distinct date_trunc('month', i.created_at))
    into v_rfqs, v_first, v_last, v_months
    from inquiries i
   where i.customer_id = p_customer and i.parent_inquiry_id is null;

  select coalesce(sum(coalesce(t.quote_amount, 0)), 0) into v_spend
    from transactions t
   where t.customer_id = p_customer and coalesce(t.refund_status, '') <> 'approved';

  -- No history at all. Say so; do not project.
  if coalesce(v_rfqs, 0) = 0 then
    return jsonb_build_object(
      'customer_id', p_customer, 'as_of', now(), 'horizon_days', p_horizon_days,
      'basis', 'no_history', 'sufficient_data', false,
      'empty_reason', 'No requests recorded on this account yet. This forecast is derived from your own past RFQs and orders, so there is nothing to project from until you post your first request.',
      'observed', jsonb_build_object('rfqs', 0, 'months_active', 0, 'spend_aed', 0,
                                     'first_rfq', null, 'last_rfq', null),
      'series', '[]'::jsonb,
      'next_year', jsonb_build_object('horizon_days', p_horizon_days, 'projected_rfqs', null,
                                      'projected_spend_aed', null, 'by_category', '[]'::jsonb),
      'predictions', '[]'::jsonb);
  end if;

  -- The observed window only. The series starts at the customer's FIRST request, never at a padded
  -- twelve months back, so a three-month-old account shows three points and not nine empty ones.
  with months as (
    select generate_series(date_trunc('month', v_first), date_trunc('month', now()), interval '1 month') m
  ), actual as (
    select date_trunc('month', i.created_at) m, count(*) c,
           round(coalesce(sum(i.expected_value), 0), 0) v
      from inquiries i
     where i.customer_id = p_customer and i.parent_inquiry_id is null
     group by 1
  )
  select jsonb_agg(jsonb_build_object('month', to_char(months.m, 'Mon YY'),
                                      'rfqs', coalesce(actual.c, 0),
                                      'value_aed', coalesce(actual.v, 0)) order by months.m)
    into v_series
    from months left join actual on actual.m = months.m;

  -- Two months of activity and three requests is the floor for a run-rate projection. Below it the
  -- figures are null and the reason is printed rather than a straight line drawn through one point.
  v_span_days  := greatest(30, extract(epoch from (now() - v_first)) / 86400.0);
  v_sufficient := v_rfqs >= 3 and v_months >= 2;
  if v_sufficient then
    v_proj_rfqs  := round((v_rfqs::numeric / v_span_days) * p_horizon_days, 1);
    v_proj_spend := round((coalesce(v_spend, 0) / v_span_days) * p_horizon_days, 0);
    v_reason     := null;
  else
    v_proj_rfqs  := null;
    v_proj_spend := null;
    v_reason     := format('Only %s request(s) across %s active month(s) so far. A run-rate projection needs at least 3 requests spanning 2 months, so the next-year figures are withheld rather than extrapolated from a single point.',
                           v_rfqs, v_months);
  end if;

  -- Category mix, projected forward at the same run rate. Shares come from the customer's own
  -- requests, so a customer who only ever bought joinery is not shown an HVAC line.
  with cat as (
    select coalesce(i.category, 'uncategorised') c, count(*) n,
           round(coalesce(sum(i.expected_value), 0), 0) v
      from inquiries i
     where i.customer_id = p_customer and i.parent_inquiry_id is null
     group by 1
  )
  select jsonb_agg(jsonb_build_object(
           'category', c,
           'observed_rfqs', n,
           'observed_value_aed', v,
           'share_pct', round(100.0 * n / nullif(v_rfqs, 0), 1),
           'projected_rfqs', case when v_sufficient
                                  then round(v_proj_rfqs * n / nullif(v_rfqs, 0), 1) end,
           'projected_spend_aed', case when v_sufficient
                                  then round(v_proj_spend * n / nullif(v_rfqs, 0), 0) end
         ) order by n desc, c)
    into v_by_cat from cat;

  -- ── §20: what this customer will likely need next, and by when ────────────────────────────────
  -- Derived, never guessed: for each of the customer's OPEN projects that has a target open date,
  -- the categories they have procured on their other projects and have not yet raised here. The
  -- horizon is that project's own deadline minus the lead time this customer has actually observed
  -- in that category (median days between raising a request and the project's target open date).
  with own as (
    select i.project_id, coalesce(i.category, 'uncategorised') c, i.created_at, p.target_open_date
      from inquiries i join projects p on p.id = i.project_id
     where i.customer_id = p_customer and i.project_id is not null
  ), lead_time as (
    select c, percentile_cont(0.5) within group (
             order by (target_open_date - created_at::date)) med_days
      from own where target_open_date is not null
     group by c
  ), history as (
    select c, count(distinct project_id) projects_used, max(created_at) last_used
      from own group by c
  ), open_projects as (
    select p.id, p.name, p.target_open_date
      from projects p
     where p.customer_id = p_customer
       and coalesce(p.status, 'active') not in ('completed', 'archived', 'cancelled')
       and p.target_open_date is not null
  ), gaps as (
    select op.id project_id, op.name project_name, op.target_open_date, h.c category,
           h.projects_used, lt.med_days,
           greatest(0, (op.target_open_date - current_date)
                       - coalesce(round(lt.med_days)::int, 0)) within_days
      from open_projects op
      cross join history h
      left join lead_time lt on lt.c = h.c
     where not exists (select 1 from inquiries i2
                        where i2.project_id = op.id
                          and coalesce(i2.category, 'uncategorised') = h.c)
  )
  select jsonb_agg(jsonb_build_object(
           'project_id', project_id,
           'project_name', project_name,
           'category', category,
           'target_open_date', target_open_date,
           'within_days', within_days,
           'expected_by', current_date + within_days,
           'confidence', case when projects_used >= 2 and med_days is not null then 'high'
                              when projects_used >= 1 and med_days is not null then 'medium'
                              else 'low' end,
           'reason', format('You have procured %s on %s of your other project(s)%s, and %s has no %s request yet.',
                            category, projects_used,
                            case when med_days is null then ''
                                 else format(', typically %s days before the target open date', round(med_days)) end,
                            project_name, category),
           'recommended_action', case
             when within_days = 0 then format('Post the %s RFQ now — the lead time you have historically needed has already started.', category)
             else format('Contact suppliers and post the %s RFQ within %s day(s) to keep %s on its target open date of %s.',
                         category, within_days, project_name, target_open_date) end
         ) order by within_days, category)
    into v_predictions from gaps;

  return jsonb_build_object(
    'customer_id', p_customer, 'as_of', now(), 'horizon_days', p_horizon_days,
    'basis', 'history', 'sufficient_data', v_sufficient, 'empty_reason', v_reason,
    'observed', jsonb_build_object('rfqs', v_rfqs, 'months_active', v_months,
                                   'spend_aed', round(coalesce(v_spend, 0), 0),
                                   'first_rfq', v_first, 'last_rfq', v_last),
    'series', coalesce(v_series, '[]'::jsonb),
    'next_year', jsonb_build_object('horizon_days', p_horizon_days,
                                    'projected_rfqs', v_proj_rfqs,
                                    'projected_spend_aed', v_proj_spend,
                                    'by_category', coalesce(v_by_cat, '[]'::jsonb)),
    'predictions', coalesce(v_predictions, '[]'::jsonb));
end $function$;

revoke execute on function public.fn_customer_forecast(uuid, integer) from public;
grant execute on function public.fn_customer_forecast(uuid, integer) to service_role, postgres;
