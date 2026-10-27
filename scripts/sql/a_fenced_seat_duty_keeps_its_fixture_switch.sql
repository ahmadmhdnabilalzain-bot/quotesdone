-- A FENCED SEAT DUTY KEEPS ITS FIXTURE SWITCH.
--
-- Agent: it_engineer (the fence of #1348 is its own); the duties stay their seats' (ceo: fn_ceo_pricing_monitor;
-- sales_engineer: fn_sales_engineer_supplier_onboarding, fn_sales_engineer_supplier_performance; marketing:
-- fn_marketing_reputation). 13 Oct 2026.
--
-- Two production checks went red on the full npm test the morning #1348 applied:
--   ceo_reviews_pricing_and_forecast_act        "the 20 ZZ DEMO quoted requests were not counted"
--   sales_engineer_and_marketing_duties_act     "the matched ZZ DEMO supplier is not at stage matched"
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only and aborted probes, 13 Oct 2026): #1348
-- (demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql, founder ruling 1199) put "and not <demo>" on
-- these four duties. That is right for a real run -- and it left them with NO way to be proved: their aborted
-- probes may use only ZZ DEMO rows (the sandbox rule), and the duty now skips exactly those, so the probe measures
-- nothing. The estate's answer already exists and #1348 itself kept it on fn_accountant_ubo_rescreen and
-- fn_sales_engineer_quote_quality_tick: qd.duty_fixtures = 'on' (set local, inside a probe) makes the duty read
-- ONLY demo rows; off (every real run, every cron) it reads ONLY real ones. Neither mode can see the other's rows.
--
-- WHAT THIS DOES: each "not <predicate>" in the four bodies becomes "<predicate> = v_fx". Nothing else in them
-- changes. fn_sales_engineer_supplier_performance's clean-up of stale scores is fenced the same way, so a fixture
-- run can never drop a real supplier's score. The probes in the two checks set the switch.
-- Prevented by: scripts/checks/ceo_reviews_pricing_and_forecast_act.test.mjs,
-- scripts/checks/sales_engineer_and_marketing_duties_act.test.mjs, scripts/checks/no_seat_duty_reads_demo_rows.test.mjs.
--   node scripts/apply_sql.mjs scripts/sql/a_fenced_seat_duty_keeps_its_fixture_switch.sql --apply --ddl --seat it_engineer


CREATE OR REPLACE FUNCTION public.fn_ceo_pricing_monitor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days' and public.fn_inquiry_is_demo(i.id) = v_fx
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions t where t.revealed_at > now() - interval '90 days' and public.fn_transaction_is_demo(t.id) = v_fx),
    'refunds_90d', (select count(*) from public.transactions t where t.refund_requested_at > now() - interval '90 days' and public.fn_transaction_is_demo(t.id) = v_fx),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes x where x.created_at > now() - interval '90 days' and x.quote_amount > 0 and public.fn_quote_is_demo(x.id) = v_fx),
    'avg_reveal_fee_aed', (select round(avg(t.reveal_fee), 2) from public.transactions t where t.revealed_at > now() - interval '90 days' and public.fn_transaction_is_demo(t.id) = v_fx),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads where is_demo = v_fx),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null and is_demo = v_fx),
    'competitors_on_file', (select count(*) from public.competitor),
    'unit_economics_last_month', public.fn_accountant_unit_economics((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $function$;


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_nudged int := 0; v_to text; v_stages jsonb; v_inv jsonb;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where (l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null) and l.is_demo = v_fx
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE 'invited' STAGE (#1007): day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id and l.is_demo = v_fx
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    -- ENGLISH ONLY (#1007, review of 29 Sep 2026): #1065's body kept an Arabic branch behind a flag fixed to English; it is
    -- removed, not switched off. A matched supplier is registered, so the link is the English portal (no claim token).
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en',
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', 'Customer requests are waiting for your quotation',
      -- #1070's greeting guard (#1007): an Arabic-script company name is not written into an English letter
      'body', 'Dear ' || coalesce(nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), ''), 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: '
          || coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
          || '/en/portal' || chr(10) || chr(10)
          || 'QuotesDone')));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged, 'invite_nudges', v_inv);
end $function$;


CREATE OR REPLACE FUNCTION public.fn_marketing_reputation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_link text := nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), '');
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
  r record; v_asked int := 0; v_waiting int := 0; v_ar boolean;
begin
  insert into public.company_review_ask (customer_id, transaction_id, status)
  select k.customer_id, k.transaction_id, 'waiting_link' from public.fn_marketing_review_ask_candidates() k
  on conflict (transaction_id) do nothing;

  if v_link is null then
    select count(*) into v_waiting from public.company_review_ask where status = 'waiting_link';
    if v_waiting > 0 then
      perform public.fn_it_engineer_finding_upsert('reputation:no_public_review_link',
        v_waiting || ' customer job(s) are waiting to be asked for a public review, and no review link is configured',
        'app_secrets public_review_url', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile or directory review link to use'], 'marketing');
    end if;
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a public review link is configured'
     where issue_key = 'reputation:no_public_review_link' and closed_at is null;
    for r in select a.id, a.customer_id, coalesce(a.transaction_id::text, a.customer_id::text) as job,
                    c.full_name, lower(btrim(c.email)) as email, c.locale
               from public.company_review_ask a join public.customers c on c.id = a.customer_id and c.is_demo = v_fx
              where a.status = 'waiting_link' and a.created_at > now() - interval '60 days'
                and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
              order by a.id limit 50 loop
      v_ar := r.locale = 'ar';
      -- customer_support is the only seat that addresses a customer; the ask is marketing's, the send is support's.
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'public_review_ask', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', r.email,
        'to_role', 'customer', 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'public_review_ask:' || r.job,
        'subject', case when v_ar then 'هل تشاركون تجربتكم مع QuotesDone؟' else 'Would you share your experience of QuotesDone?' end,
        'body', case when v_ar then
            'عزيزنا ' || coalesce(nullif(btrim(r.full_name), ''), 'العميل') || '،' || chr(10) || chr(10)
            || 'شكرًا لاستخدامكم QuotesDone. نرحب برأيكم الصريح علنًا، أيًّا كان، فذلك يساعد غيركم على اختيار موردين موثوقين: '
            || v_link || chr(10) || chr(10) || 'مع خالص الشكر والتقدير،'
          else
            'Dear ' || coalesce(nullif(btrim(r.full_name), ''), 'customer') || ',' || chr(10) || chr(10)
            || 'Thank you for using QuotesDone. If you have a minute, we would welcome your honest public review, '
            || 'whatever your experience; it helps other companies find reliable suppliers: ' || v_link
            || chr(10) || chr(10) || 'QuotesDone' end)));
      update public.company_review_ask set status = 'asked', asked_at = now() where id = r.id;
      v_asked := v_asked + 1;
    end loop;
  end if;

  -- The snapshot measures reputation; it is written after the asks and decides none of them.
  insert into public.company_reputation_snapshot as s (day, reviews, avg_rating, low_ratings_30d, asks_sent, asks_waiting)
  select (now() at time zone 'Asia/Dubai')::date, count(*), round(avg(rating)::numeric, 2),
         count(*) filter (where rating <= 2 and created_at > now() - interval '30 days'),
         (select count(*) from public.company_review_ask where status = 'asked'),
         (select count(*) from public.company_review_ask where status = 'waiting_link')
    from public.reviews
  on conflict (day) do update set reviews = excluded.reviews, avg_rating = excluded.avg_rating, low_ratings_30d = excluded.low_ratings_30d,
    asks_sent = excluded.asks_sent, asks_waiting = excluded.asks_waiting;
  return jsonb_build_object('asked', v_asked, 'waiting_for_link', v_link is null,
    'snapshot', (select to_jsonb(s) from public.company_reputation_snapshot s where day = (now() at time zone 'Asia/Dubai')::date));
end $function$;


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_performance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_refreshed int; v_scored int; v_null int;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
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
      join public.leads l on l.id = s.lead_id and l.is_demo = v_fx
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
  delete from public.supplier_performance p where p.computed_at < now() - interval '1 minute'
     and public.fn_supplier_is_demo(p.lead_id) = v_fx;   -- a fixture run never drops a real supplier's score
  get diagnostics v_null = row_count;
  return jsonb_build_object('score_rows_refreshed', v_refreshed, 'scored', v_scored, 'dropped_unmeasured', v_null);
end $function$;

select case
  when (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
          and proname in ('fn_ceo_pricing_monitor', 'fn_sales_engineer_supplier_onboarding',
                          'fn_sales_engineer_supplier_performance', 'fn_marketing_reputation')
          and prosrc like '%qd.duty_fixtures%' and prosrc !~ 'not (public.fn_[a-z]+_is_demo|[a-z].is_demo|is_demo)') <> 4
    then 'PROBE FAILED: a fenced duty has no fixture switch, or still skips demo rows unconditionally'
  else 'PROBE OK' end as verdict;
