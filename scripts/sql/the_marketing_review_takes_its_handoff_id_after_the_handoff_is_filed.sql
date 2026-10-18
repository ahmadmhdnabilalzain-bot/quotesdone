-- THE MARKETING REVIEW TAKES ITS HANDOFF ID AFTER THE HANDOFF IS FILED (12 Oct 2026, it_engineer).
-- fn_marketing_reviews_tick failed on every marketing duties run (finding duty:marketing_duties:reviews, seen 336
-- times by 12 Oct): "tuple to be updated was already modified by an operation triggered by the current command"
-- (SQLSTATE 27000, reproduced in an aborted transaction on production). The routine filed the CEO handoff INSIDE
-- the UPDATE that stores its id: `update marketing_review set handoff_id = fn_seat_handoff(...) where id = v_id`.
-- Filing the handoff writes back to that same marketing_review row (the CEO's reader acts on the review as the
-- handoff lands), so the outer UPDATE then tried to update a row its own command had already changed, and the
-- whole run rolled back, review and handoff with it, to fail again 30 minutes later.
-- Now the handoff is filed first, into a variable, and the id is stored by a second statement. Same rows, same
-- handoff, one statement each. The body is otherwise the live one, byte for byte.
create or replace function public.fn_marketing_reviews_tick(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local date := (p_at at time zone 'Asia/Dubai')::date;
  v_last_month date := (date_trunc('month', v_local) - interval '1 month')::date;
  v_quarter date := date_trunc('quarter', v_local)::date;
  v_body jsonb; v_id bigint; v_handoff bigint; v_out jsonb := '{}'::jsonb;
begin
  if extract(day from v_local) >= 2 and not exists (select 1 from public.marketing_review where kind = 'geo_monthly' and period = v_last_month)
     and exists (select 1 from public.marketing_geo_check where month = v_last_month) then
    v_body := public.fn_marketing_geo_summary(v_last_month);
    insert into public.marketing_review (kind, period, body) values ('geo_monthly', v_last_month, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      v_handoff := public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'geo_monthly', 'period', v_last_month));
      update public.marketing_review set handoff_id = v_handoff where id = v_id;
      v_out := v_out || jsonb_build_object('geo_monthly', v_id);
    end if;
  end if;

  -- Only in the first 14 days of a quarter, so the file applied mid-quarter does not compose a review of an empty one.
  if v_local < v_quarter + 14 and not exists (select 1 from public.marketing_review where kind = 'brand_quarterly' and period = v_quarter) then
    v_body := jsonb_build_object(
      'quarter', v_quarter,
      'positioning', jsonb_build_object(
        'rule_source', 'profile_text.json (one description everywhere; "smart", never "AI"; no licence number)',
        'social_profiles_checked', (select count(*) from public.marketing_connection_check),
        'social_profiles_failing', (select count(*) from public.marketing_connection_check where not ok)),
      'reach_last_quarter', (select coalesce(jsonb_object_agg(platform, total), '{}'::jsonb) from (
          select platform, sum(value) total from public.marketing_insight_day
           where day >= (v_quarter - interval '3 months') and day < v_quarter group by platform) r),
      'posts_published_last_quarter', (select count(*) from public.marketing_post where status = 'published'
           and published_at >= (v_quarter - interval '3 months') and published_at < v_quarter),
      'geo_last_three_months', (select coalesce(jsonb_agg(public.fn_marketing_geo_summary(m::date) - 'rows' order by m), '[]'::jsonb)
           from generate_series((v_quarter - interval '3 months')::date, (v_quarter - interval '1 month')::date, interval '1 month') g(m)),
      'competitor_posts_seen', (select count(*) from public.market_intel where platform is not null and created_at >= v_quarter - interval '3 months'),
      'relevant_trends', (select count(*) from public.marketing_trend where relevant and seen_at >= v_quarter - interval '3 months'),
      'reputation', (select to_jsonb(s) from public.company_reputation_snapshot s order by day desc limit 1),
      -- THE JANUARY 2027 CUSTOMER LAUNCH (seat map, 24 Sep 2026): no customer campaign before January 2027, and
      -- customers launch only once suppliers can quote every inquiry. This is the proposal the CEO decides on.
      'customer_launch_2027', jsonb_build_object(
        'decision_owner', 'ceo',
        'rule', 'Oct-Dec 2026 supplier registration only; customers from January 2027 once the supplier base can quote every inquiry',
        'supply_gaps_open', (select count(*) from public.supply_gap where status in ('open', 'recruit')),
        'supply_gaps_recruiting', (select count(*) from public.supply_gap where status = 'recruit'),
        'suppliers_registered', (select coalesce(sum(registered), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'suppliers_approved', (select coalesce(sum(approved), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'plan', jsonb_build_array(
          'December 2026: the CEO decides the launch against supply_gaps_open = 0 for the launch trades',
          'December 2026: customer landing pages and the blog answer the buyer questions in marketing_geo_question',
          'January 2027: the first customer calendar (organic only) goes to the founder for one-shot approval',
          'January 2027 onward: the monthly GEO audit tracks whether answer engines name QuotesDone to buyers')));
    insert into public.marketing_review (kind, period, body) values ('brand_quarterly', v_quarter, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      v_handoff := public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'brand_quarterly', 'period', v_quarter));
      update public.marketing_review set handoff_id = v_handoff where id = v_id;
      v_out := v_out || jsonb_build_object('brand_quarterly', v_id);
    end if;
  end if;
  return v_out;
end $fn$;

select case when position('v_handoff := public.fn_seat_handoff(' in pg_get_functiondef('public.fn_marketing_reviews_tick(timestamptz)'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED: fn_marketing_reviews_tick still files the handoff inside its UPDATE' end as verdict;
