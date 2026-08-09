-- ROW #3 layer 3 — the lobby has a prose slot for an insight and puts nothing in it.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   exec-intel-narrative-insight  MISSING  2 lobby surface(s) render a prose key; the value behind
--                                          it right now is (null), causal: n/a, quantified: n/a
-- 
-- The requirement is "the AI states an insight in prose with a cause, instead of a chart", and the
-- check reads the ACTUAL value the lobby's prose key resolves to: fn_ws_exec()->command->health->note.
-- The UI half has been done for a while — two lobby surfaces render it. The value is null.
-- 
-- fn_health_index already has the slot and fills it for exactly one case:
-- 
--     'note', case when present < 3 then 'insufficient data — pre-traction; …' else null end
-- 
-- So the company says something when it has almost no data and nothing at all when it has some.
-- Production has seven of eight components measured and an index of 58.0, and the lobby prints a
-- blank.
-- 
-- ── THE CAUSE IS ARITHMETIC, NOT INFERENCE ──────────────────────────────────────────────────────
-- `overall` is the MEAN of the present components. The components furthest below that mean are
-- therefore exactly what hold the index where it is — that is division, not a guess, which is what
-- makes "driven by" an honest connective here rather than a narrative flourish.
-- 
-- The sentence names the two lowest with their own scores, against the average and the number of
-- components it was taken over. On production today that reads:
-- 
--   Company health is 58.0 of 100 (watch), driven by RFQ completion at 0.0 and customer
--   acquisition at 0.0 — the two furthest below the 58.0-point average of 7 measured components.
-- 
-- A cause and a magnitude, both of them numbers the routine already computed. The check requires
-- both, and requires them in the SAME string, because a cause without a magnitude is not the
-- requirement's example ("revenue will miss by 6% BECAUSE supplier response time rose 14%").
-- 
-- The `present < 3` branch is left exactly as it was. It is the more honest sentence when there is
-- nothing to be causal about, and replacing it would be trading a true statement for a longer one.

CREATE OR REPLACE FUNCTION public.fn_health_index()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days';
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days';
  select count(*) into approved_suppliers from leads
     where coalesce(approval_status,'')='approved' or claimed=true;
  -- RFQ completion: real RFQs only (exclude split-parent containers and customer-cancelled),
  -- success = completed/won or closed-with-a-hire (a "closed, not hired" is NOT a completion).
  select count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and coalesce(status,'')<>'cancelled'),
         count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and (status in ('completed','won')
                                 or (status='closed' and coalesce(outcome,'') in ('hired','hired_elsewhere'))))
    into inq_total, inq_done from inquiries;
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days';
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  s_acq  := least(100, signups_7d * 10.0);
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall, 'band', band, 'components_present', present,
    -- A PROSE INSIGHT WITH A CAUSE AND A MAGNITUDE, not a blank.
    -- `overall` is the mean of the present components, so the ones furthest below it are
    -- arithmetically what hold the index there. "driven by" is division, not narrative.
    'note', case
      when present < 3 then 'insufficient data — pre-traction; index will firm up with volume'
      else (select 'Company health is '||overall||' of 100 ('||band||'), driven by '
              ||string_agg(w.label||' at '||w.score, ' and ' order by w.score, w.label)
              ||' — the two furthest below the '||overall||'-point average of '||present
              ||' measured components.'
              from (select v.label, v.score from (values
                      ('customer acquisition', s_acq), ('supplier activity', s_supp),
                      ('RFQ completion', s_rfq), ('quote quality', s_qual),
                      ('response time', s_resp), ('dispute health', s_disp), ('uptime', s_up)
                    ) v(label, score)
                     where v.score is not null order by v.score, v.label limit 2) w)
      end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq, 'supplier_activity', s_supp, 'rfq_completion', s_rfq,
       'quote_quality', s_qual, 'response_time', s_resp, 'dispute_health', s_disp,
       'uptime', s_up, 'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_eligible_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $function$
;
