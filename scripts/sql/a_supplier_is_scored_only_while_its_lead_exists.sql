-- Seat: sales_engineer. Seat duty sales_engineer.supplier_performance failed 4 times running (last ok
-- 24 Sep 00:01) with: insert or update on table "supplier_performance" violates foreign key constraint
-- "supplier_performance_lead_id_fkey".
--
-- MEASURED 28 Sep 2026: supplier_performance.lead_id references leads(id) ON DELETE CASCADE, but
-- supplier_score has no such key, and 12 supplier_score rows name a lead that no longer exists (leads
-- removed after they were scored). The routine read supplier_score alone, so one orphan score aborts the
-- whole day's scoring. FIX: score only suppliers whose lead exists. The orphan score rows are left as
-- they are (they are read by nothing once this join is in).
-- prevented by: scripts/checks/supplier_performance_reads_only_live_leads.test.mjs
-- Finding it closes: seat_duty:sales_engineer.supplier_performance

create or replace function public.fn_sales_engineer_supplier_performance()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_refreshed int; v_scored int; v_null int;
begin
  v_refreshed := public.fn_supplier_score_refresh();
  -- WEIGHTED OVER WHAT WAS MEASURED: reliability 0.5, the customers' rating 0.3, disputes 0.2 (only once a customer
  -- has reviewed him). A part that does not exist is left out of both sides of the average, never counted as zero.
  -- Only a supplier whose lead still exists is scored: supplier_performance keys on leads(id).
  with parts as (
    select s.lead_id,
           case when s.reliability is not null then least(1, greatest(0, s.reliability / 100.0)) end as rel,
           case when s.quality_rating is not null then least(1, greatest(0, s.quality_rating / 100.0)) end as qual,
           case when coalesce(r.review_count, 0) > 0 then 1 - least(1, greatest(0, coalesce(r.dispute_rate_pct, 0) / 100.0)) end as disp
      from public.supplier_score s
      join public.leads l on l.id = s.lead_id
      left join public.supplier_reputation r on r.supplier_id = s.lead_id
     where s.reliability is not null or s.quality_rating is not null or coalesce(r.review_count, 0) > 0
  )
  insert into public.supplier_performance as p (lead_id, score, components, computed_at)
  select lead_id,
         round((coalesce(0.5 * rel, 0) + coalesce(0.3 * qual, 0) + coalesce(0.2 * disp, 0))
               / nullif((case when rel is not null then 0.5 else 0 end) + (case when qual is not null then 0.3 else 0 end)
                        + (case when disp is not null then 0.2 else 0 end), 0), 3),
         jsonb_build_object('reliability', rel, 'rating', qual, 'disputes', disp), now()
    from parts
  on conflict (lead_id) do update set score = excluded.score, components = excluded.components, computed_at = now();
  get diagnostics v_scored = row_count;
  -- a supplier who lost every measurement is unmeasured again, not scored on stale numbers
  delete from public.supplier_performance p where p.computed_at < now() - interval '1 minute';
  get diagnostics v_null = row_count;
  return jsonb_build_object('score_rows_refreshed', v_refreshed, 'scored', v_scored, 'dropped_unmeasured', v_null);
end $function$;

-- verdict: the routine runs to completion (it writes only derived scores; the duty rewrites them daily)
select case when (public.fn_sales_engineer_supplier_performance() ? 'scored') then 'PROBE OK'
            else 'PROBE FAILED: the scoring did not complete' end as verdict;
