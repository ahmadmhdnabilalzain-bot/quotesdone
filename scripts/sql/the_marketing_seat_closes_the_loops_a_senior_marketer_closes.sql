-- THE MARKETING SEAT CLOSES THE LOOPS A SENIOR MARKETER CLOSES (marketing, founder ledger 1003 stage 2, 19 Oct 2026).
--
-- Assigned: marketing. Stage 1 of ledger 1003 measured the marketing seat against a 20-year senior bar
-- (knowledge/standards/marketing.json, seat-audit branch). Ten contributions were partial or missing. MKT-C06 (the
-- competitor watch) is its own file, the_competitor_watch_reads_real_pages_and_never_briefs_on_nothing.sql. The other
-- nine become seat_duties here that ACT -- write a row, move a post, decide, open or close a finding -- in code, no model.
--
-- ══ MEASURED, 19 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════════════════════════════════
--   C03  marketing_geo_check October: 24 checks over 18 active questions, 0 cited; competitors_cited is filled (e.g.
--        YellowPages-UAE). Nothing turns an uncited question into a fix.
--   C05  marketing.recruitment_funnel totals {pool,invited,registered,quoting} all null: supply_gap has 217 rows, all
--        'deferred', 0 'recruit', so the per-gap funnel has no row and sum() of nothing is null. leads says 171
--        invited; notifications holds 0 supplier_invite rows (the 305 sent supplier_invite_seed rows go to the
--        deliverability seed inboxes: 0 of their addresses is a lead). Measured from delivered invitations the funnel
--        is 0 delivered, so its losing stage is delivery -- which the status column hid.
--   C07  app_secrets has no public_review_url and no google_place_id; company_review_ask 0 rows; asks_sent 0.
--   C10  marketing_post: 54 published, 12 scheduled ahead, 4 'scheduled' whose slot passed (missed_slot: "reschedule
--        and re-approve") since 28 Sep-12 Oct, untouched. The weekend trigger moves a post only when it is written; a
--        holiday added later never moves an existing post. No seat_duty owns publishing.
--   C11  social_message 19 (17 in, 2 out held_switch_off); fn:marketing_social_inbox's "half failing" was 4 unsigned
--        curl probes (fixed in observe.ts / marketing_social_inbox in this PR). No seat_duty owns the inbox.
--   C12  marketing_trend 511: 113 relevant, 204 not, 194 NEVER judged (seen 24 Sep - 4 Oct). No 48-hour decision.
--   C13  marketing_scorecard_report: 5 weekly post rankings; no monthly KPI scorecard.
--   C14  pricing_config is the one fact store (3% reveal, AED 1,000/yr supplier fee, AED 500 non-response fee);
--        quotesdone.ae/faq states all three, /how-it-works and / state 3%; /llms.txt answers 404. Nothing watches them.
--   C15  fn_marketing_paid_allowed() false, marketing_ad_spend_day 0 rows. Paid stays OFF: nothing here turns it on.
--
-- ══ WHAT THIS ADDS (contribution -> seat_duty) ════════════════════════════════════════════════════════════════════
--   C03 marketing.geo_fix          daily   each active question uncited this month gets ONE fix row: comparison
--                                          passage (a competitor was cited), answer-first service passage (trade+city),
--                                          or entity fix; closed the day a check cites us.
--   C05 marketing.recruitment_funnel (extended)  totals are 0 not null, plus the company-wide funnel measured from
--                                          DELIVERED invitations (notifications), with stage conversion, kept per day.
--   C07 marketing.reputation (extended)  the review link is also derived from app_secrets.google_place_id; with neither
--                                          set the asks stay queued and the IT finding stands (the link is a fact).
--   C10 marketing.social_publish   daily   scheduled posts now landing on a weekend/holiday re-slid to the next working
--                                          day; every scheduled/draft link carries UTM; missed slots handed to the CEO
--                                          (approval is the CEO's) once; yesterday's due posts audited published/failed.
--   C11 marketing.social_inbox     hourly  owed messages (question, complaint, lead, supplier, legal) unanswered 2h on a
--                                          working day, signed webhooks rejected (a stale meta_app_secret) and failed
--                                          sends become marketing findings, closed when clear.
--   C12 marketing.trend_decision   daily   a trend seen 48h ago and still unjudged is decided: rejected, reason
--                                          recorded; the week's accepted trends kept as the weekly trend brief; a feed
--                                          silent for 2 days is a finding.
--   C13 marketing.kpi_scorecard    daily   the month's scorecard (registered suppliers per campaign, cost per
--                                          registered supplier, GEO citations, share of voice, post results by pillar),
--                                          month-to-date daily and closed for the last month.
--   C14 marketing.fact_register    daily   the public facts read from pricing_config, hashed; each public surface is
--                                          fetched and must state them; a surface that does not is a finding the same
--                                          day, closed when it does.
--   C15 marketing.paid_spend_report daily  paid OFF: proves no spend exists (spend without a budget is a finding);
--                                          paid ON (never switched here): pacing against ad_spend_policy and every
--                                          spend day handed to the accountant within 2 days, else a finding.
-- Every duty reads real rows only (qd.duty_fixtures = 'on' reads only demo rows). Nothing notifies the founder, posts
-- publicly or contacts a person. Suppliers are not addressed here at all. No posting on a non-working day.
-- Prevented by: scripts/checks/the_marketing_senior_duties_are_registered_and_act.test.mjs, and the aborted-transaction
-- probe the_marketing_seat_closes_the_loops_a_senior_marketer_closes_probe.sql (0 founder notifications).
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql --apply --ddl

-- ── shared: one record per duty per period ────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_duty_record (
  duty       text not null,
  period     date not null,
  body       jsonb not null,
  written_at timestamptz not null default now(),
  primary key (duty, period)
);
alter table public.marketing_duty_record enable row level security;
drop policy if exists marketing_duty_record_service_role_only on public.marketing_duty_record;
create policy marketing_duty_record_service_role_only on public.marketing_duty_record as permissive for all to public using (false) with check (false);
revoke all on public.marketing_duty_record from anon, authenticated;

-- ── C03 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_geo_fix (
  id            bigint generated always as identity primary key,
  month         date not null,
  question_id   bigint not null,
  checks        int not null,
  engines       text[] not null,
  competitors_cited text[] not null default '{}',
  action        text not null check (action in ('comparison_passage', 'answer_first_service_passage', 'entity_fix')),
  brief         text not null,
  status        text not null default 'open' check (status in ('open', 'closed')),
  opened_at     timestamptz not null default now(),
  closed_at     timestamptz,
  close_note    text,
  unique (month, question_id)
);
alter table public.marketing_geo_fix enable row level security;
drop policy if exists marketing_geo_fix_service_role_only on public.marketing_geo_fix;
create policy marketing_geo_fix_service_role_only on public.marketing_geo_fix as permissive for all to public using (false) with check (false);
revoke all on public.marketing_geo_fix from anon, authenticated;

create or replace function public.fn_marketing_geo_fix()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_month date := date_trunc('month', now() at time zone 'Asia/Dubai')::date; q record; n_open int := 0; n_closed int := 0; v_action text; v_brief text;
begin
  -- closed: a later check cited us
  update public.marketing_geo_fix f set status = 'closed', closed_at = now(),
         close_note = 'cited by ' || (select string_agg(distinct g.engine, ', ') from public.marketing_geo_check g
                                       where g.question_id = f.question_id and g.cited and g.checked_at > f.opened_at)
   where f.status = 'open' and exists (select 1 from public.marketing_geo_check g where g.question_id = f.question_id and g.cited and g.checked_at > f.opened_at);
  get diagnostics n_closed = row_count;

  for q in
    select g.question_id, count(*) checks, array_agg(distinct g.engine) engines,
           coalesce((select array_agg(distinct c) from public.marketing_geo_check g2, unnest(g2.competitors_cited) c
                      where g2.question_id = g.question_id and g2.month = v_month), '{}') comps,
           max(qq.question) question, max(qq.trade) trade, max(qq.city) city
      from public.marketing_geo_check g join public.marketing_geo_question qq on qq.id = g.question_id and qq.active
     where g.month = v_month
     group by g.question_id
    having not bool_or(g.cited)
       and not exists (select 1 from public.marketing_geo_fix f where f.month = v_month and f.question_id = g.question_id)
  loop
    if cardinality(q.comps) > 0 then
      v_action := 'comparison_passage';
      v_brief := format('Engines answered "%s" citing %s and not QuotesDone. Publish an honest, answer-first comparison passage '
                        '(what each does, who pays what, where QuotesDone differs: best-3 quotes, 3%% reveal paid by the buyer) '
                        'and seek a listing or citation on the cited sources.', q.question, array_to_string(q.comps, ', '));
    elsif q.trade is not null then
      v_action := 'answer_first_service_passage';
      v_brief := format('Engines answered "%s" without citing QuotesDone. Put a 40-word answer-first passage that answers it '
                        'verbatim at the top of the %s service page%s, with Service JSON-LD for that trade and area.',
                        q.question, q.trade, coalesce(' for ' || q.city, ''));
    else
      v_action := 'entity_fix';
      v_brief := format('Engines answered "%s" without citing QuotesDone. Check the Organization entity (name, sameAs, '
                        'description) is identical on the site, the directories and the profiles, and that the answer appears on one page.', q.question);
    end if;
    insert into public.marketing_geo_fix (month, question_id, checks, engines, competitors_cited, action, brief)
    values (v_month, q.question_id, q.checks, q.engines, q.comps, v_action, v_brief);
    n_open := n_open + 1;
  end loop;
  return jsonb_build_object('month', v_month, 'fixes_opened', n_open, 'fixes_closed', n_closed,
    'open', (select count(*) from public.marketing_geo_fix where status = 'open'),
    'by_action', (select coalesce(jsonb_object_agg(action, n), '{}'::jsonb) from (select action, count(*) n from public.marketing_geo_fix where status = 'open' group by 1) a));
end $fn$;
revoke execute on function public.fn_marketing_geo_fix() from public, anon, authenticated;
grant execute on function public.fn_marketing_geo_fix() to service_role;

-- ── C05 (extends the existing routine; the per-gap part is unchanged) ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_marketing_recruitment_funnel()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0; v_keys text[] := '{}';
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; v_company jsonb;
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         -- l.id is not null: a gap with NO matching lead is a null-extended row whose invite_status is
         -- null, which counted as a pool of 1 and so never fired pool_empty (found by this PR's probe).
         count(*) filter (where l.id is not null and l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
         count(*) filter (where l.invited_at is not null),
         count(*) filter (where l.invite_clicked_at is not null),
         count(*) filter (where l.registration_submitted_at is not null or coalesce(l.claimed, false)),
         count(*) filter (where l.approval_status = 'approved'),
         count(*) filter (where exists (select 1 from public.quotes q where q.supplier_id = l.id))
    from public.supply_gap g
    left join public.leads l on g.trade = any(coalesce(l.invite_trades, '{}'::text[]))
                            and (g.emirate = 'UAE' or l.emirate = g.emirate) and coalesce(l.is_demo, false) = v_fx
   where g.status = 'recruit'
   group by g.trade, g.emirate
  on conflict (trade, emirate, day) do update set pool = excluded.pool, invited = excluded.invited, clicked = excluded.clicked,
    registered = excluded.registered, approved = excluded.approved, quoting = excluded.quoting;
  get diagnostics v_rows = row_count;

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per trade group.
  for gp in select coalesce(tt.group_code, 'ungrouped') as grp, count(*)::int as n,
                   jsonb_agg(jsonb_build_object('trade', f.trade, 'emirate', f.emirate) order by f.trade, f.emirate) as gaps
              from public.supplier_recruitment_funnel f
              join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
              left join public.taxonomy_trade tt on tt.code = f.trade
             where f.day = v_day and f.pool = 0
             group by 1 loop
    v_empty := v_empty + gp.n;
    v_keys := v_keys || ('recruitment:pool_empty:' || gp.grp);
    perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.grp,
      'No uninvited lead is left for ' || gp.n || ' recruiting gap(s) in trade group ' || gp.grp,
      'public.supplier_recruitment_funnel', 'agent_facing', gp.n,
      jsonb_build_object('trade_group', gp.grp, 'gap_count', gp.n, 'gaps', gp.gaps, 'owner_seat', 'marketing'), '{}'::text[],
      array['which source can supply leads for these trades while lead scraping is paused'], 'marketing');
  end loop;
  update public.it_engineer_finding fi
     set closed_at = now(),
         close_note = case when fi.issue_key ~ '^recruitment:pool_empty:[^:]+:'
                           then 'superseded: empty pools are now one finding per trade group'
                           else 'no recruiting gap in this trade group has an empty pool' end
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null and not (fi.issue_key = any(v_keys));

  -- THE COMPANY FUNNEL FROM DELIVERED INVITATIONS (19 Oct 2026, ledger 1003 C05). A lead's status column is not a
  -- delivery record: the stage starts at the invitation email the provider reported delivered, then follows that lead.
  with inv as (
    select lower(btrim(n.to_email)) email, bool_or(n.provider_status = 'delivered') delivered
      from public.notifications n
     -- supplier_invite only: supplier_invite_seed rows are the deliverability seed inboxes, not suppliers (measured:
     -- 305 sent seeds, 0 of their addresses is a lead)
     where n.type = 'supplier_invite' and n.status = 'sent' and n.to_email is not null
     group by 1),
  f as (
    select count(*) sent, count(*) filter (where i.delivered) delivered,
           count(*) filter (where i.delivered and l.invite_clicked_at is not null) clicked,
           count(*) filter (where i.delivered and (l.registration_submitted_at is not null or coalesce(l.claimed, false))) registered,
           count(*) filter (where i.delivered and l.approval_status = 'approved') approved,
           count(*) filter (where i.delivered and exists (select 1 from public.quotes q where q.supplier_id = l.id)) quoting
      from inv i join public.leads l on lower(btrim(l.email)) = i.email and coalesce(l.is_demo, false) = v_fx)
  select jsonb_build_object('leads_marked_invited', (select count(*) from public.leads l where l.invited_at is not null and coalesce(l.is_demo, false) = v_fx),
           'invitations_sent', sent, 'delivered', delivered, 'clicked', clicked, 'registered', registered,
           'approved', approved, 'quoting', quoting,
           'pct_delivered_clicked', case when delivered > 0 then round(100.0 * clicked / delivered, 1) end,
           'pct_clicked_registered', case when clicked > 0 then round(100.0 * registered / clicked, 1) end,
           'pct_registered_approved', case when registered > 0 then round(100.0 * approved / registered, 1) end,
           'pct_approved_quoting', case when approved > 0 then round(100.0 * quoting / approved, 1) end,
           'losing_stage', case when delivered = 0 then 'delivery' when clicked = 0 then 'delivered_to_clicked'
                                when registered = 0 then 'clicked_to_registered' when approved = 0 then 'registered_to_approved'
                                when quoting = 0 then 'approved_to_quoting' else null end)
    into v_company from f;
  insert into public.marketing_duty_record (duty, period, body) values ('marketing.recruitment_funnel', v_day, v_company)
  on conflict (duty, period) do update set body = excluded.body, written_at = now();

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty, 'empty_pool_findings', cardinality(v_keys),
    'totals', (select jsonb_build_object('pool', coalesce(sum(pool), 0), 'invited', coalesce(sum(invited), 0), 'registered', coalesce(sum(registered), 0),
                                         'approved', coalesce(sum(approved), 0), 'quoting', coalesce(sum(quoting), 0))
                 from public.supplier_recruitment_funnel where day = v_day),
    'company_funnel', v_company,
    -- which stage lost them, filed to the CEO when a channel has N invited and 0 registered (#1012)
    'diagnosis', public.fn_marketing_funnel_diagnosis(false, true));
end $function$;

-- ── C07 (extends the existing routine: the link may also come from the Google place id) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_marketing_reputation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_link text := coalesce(
      nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), ''),
      -- Google's own "write a review" address for a Business Profile, built from its place id (19 Oct 2026, C07)
      'https://search.google.com/local/writereview?placeid=' || nullif(btrim((select value from public.app_secrets where key = 'google_place_id')), ''));
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
        'app_secrets public_review_url / google_place_id', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile place id (app_secrets.google_place_id) or a directory review link (public_review_url)'], 'marketing');
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

-- ── C10 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_social_publish()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_today date := (now() at time zone 'Asia/Dubai')::date; v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  n_moved int := 0; n_utm int := 0; v_missed int; v_task bigint; v_audit jsonb; v_title text;
begin
  -- a post now landing on a weekend or a holiday added after it was written: re-slid by the a05 trigger on write
  update public.marketing_post p set scheduled_at = p.scheduled_at, updated_at = now()
   where p.status = 'scheduled' and p.scheduled_at > now() and p.is_demo = v_fx
     and not public.fn_is_working_day((p.scheduled_at at time zone 'Asia/Dubai')::date);
  get diagnostics n_moved = row_count;

  -- every link a post carries is tagged, so a registration can be traced to the post (UTM)
  update public.marketing_post p
     set cta_url = p.cta_url || case when p.cta_url like '%?%' then '&' else '?' end
                   || 'utm_source=' || p.channels[1] || '&utm_medium=social&utm_campaign='
                   || coalesce((select c.campaign_key from public.marketing_campaign c where c.id = p.campaign_id), 'organic')
                   || '&utm_content=' || p.ingest_key,
         updated_at = now()
   where p.status in ('draft', 'scheduled') and p.is_demo = v_fx and p.cta_url is not null and p.cta_url !~ 'utm_source=';
  get diagnostics n_utm = row_count;

  -- a slot that passed unpublished needs re-approval, and approval is the CEO's: handed once, while it is open
  select count(*) into v_missed from public.marketing_post
   where status = 'scheduled' and scheduled_at < now() - interval '2 hours' and is_demo = v_fx;
  v_title := 'Marketing: re-approve or cancel the social post(s) whose slot passed unpublished';
  if v_missed > 0 and not v_fx and not exists (select 1 from public.ceo_task where title = v_title and state = 'open') then
    v_task := public.fn_ceo_task_open(v_title, v_missed || ' scheduled post(s) passed their slot without publishing (the publisher marks them '
      || '"missed_slot: reschedule and re-approve"): ' || (select string_agg(ingest_key || ' (' || to_char(scheduled_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ')', ', ' order by scheduled_at)
         from public.marketing_post where status = 'scheduled' and scheduled_at < now() - interval '2 hours' and not is_demo)
      || '. Approve a new working-day slot for each, or cancel it.');
  end if;

  -- yesterday's due posts, audited
  select jsonb_build_object('due', count(*), 'published', count(*) filter (where status = 'published'),
           'failed', count(*) filter (where status = 'failed'), 'unconfirmed', count(*) filter (where status in ('publishing', 'unconfirmed')),
           'still_scheduled', count(*) filter (where status = 'scheduled'))
    into v_audit from public.marketing_post
   where is_demo = v_fx and (scheduled_at at time zone 'Asia/Dubai')::date = v_today - 1;
  insert into public.marketing_duty_record (duty, period, body)
  values ('marketing.social_publish', v_today - 1, v_audit) on conflict (duty, period) do update set body = excluded.body, written_at = now();

  return jsonb_build_object('posting_day', public.fn_is_working_day(v_today), 'moved_off_non_working_days', n_moved,
    'links_tagged', n_utm, 'missed_slots', v_missed, 'ceo_task', v_task, 'yesterday', v_audit,
    'scheduled_ahead', (select count(*) from public.marketing_post where status = 'scheduled' and scheduled_at > now() and is_demo = v_fx));
end $fn$;
revoke execute on function public.fn_marketing_social_publish() from public, anon, authenticated;
grant execute on function public.fn_marketing_social_publish() to service_role;

-- ── C11 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_social_inbox()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; v_overdue jsonb; n_over int;
  n_sig int; n_fail int; v_working boolean := public.fn_is_working_day((now() at time zone 'Asia/Dubai')::date);
begin
  -- owed: a person asked something a seat must answer; unanswered 2 hours on a working day is late
  select count(*), coalesce(jsonb_object_agg(cls, n), '{}'::jsonb) into n_over, v_overdue from (
    select m.classification cls, count(*) n
      from public.social_message m join public.social_conversation c on c.id = m.conversation_id and c.is_demo = v_fx
     where m.direction = 'in' and m.author = 'person'
       and m.classification in ('question', 'complaint', 'sales_lead', 'supplier_enquiry', 'sensitive_legal')
       and m.occurred_at < now() - interval '2 hours' and m.occurred_at > now() - interval '30 days'
       and c.status <> 'handed_to_human'
       and not exists (select 1 from public.social_message o where o.in_reply_to = m.id and o.direction = 'out' and o.send_status = 'sent')
     group by 1) x;
  n_over := coalesce((select sum(value::int) from jsonb_each_text(v_overdue)), 0);
  if v_working and n_over > 0 then
    perform public.fn_it_engineer_finding_upsert('social_inbox:overdue', n_over || ' social message(s) owed an answer for over 2 working hours',
      'public.social_message', 'agent_facing', n_over, jsonb_build_object('by_class', v_overdue, 'owner_seat', 'marketing'),
      '{}'::text[], array['whether the reply is held (social_send_enabled) or was never composed'], 'marketing');
  elsif n_over = 0 then
    update public.it_engineer_finding set closed_at = now(), close_note = 'no owed social message is unanswered'
     where issue_key = 'social_inbox:overdue' and closed_at is null;
  end if;

  -- a SIGNED webhook we could not verify is a stale meta_app_secret (unsigned pokes are 'skipped', not counted)
  select count(*) into n_sig from public.agent_runs
   where agent = 'fn:marketing_social_inbox' and status = 'warn' and counts->>'signed_rejected' = 'true' and started_at > now() - interval '24 hours';
  if n_sig > 0 then
    perform public.fn_it_engineer_finding_upsert('social_inbox:signature_rejected', n_sig || ' signed Meta webhook(s) failed verification in 24h',
      'fn:marketing_social_inbox', 'agent_facing', n_sig, jsonb_build_object('owner_seat', 'marketing'), '{}'::text[],
      array['whether meta_app_secret was rotated in the Meta app'], 'marketing');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no signed webhook rejected in 24h'
     where issue_key = 'social_inbox:signature_rejected' and closed_at is null;
  end if;

  select count(*) into n_fail from public.social_message m join public.social_conversation c on c.id = m.conversation_id and c.is_demo = v_fx
   where m.direction = 'out' and m.send_status = 'failed' and m.created_at > now() - interval '24 hours';
  if n_fail > 0 then
    perform public.fn_it_engineer_finding_upsert('social_inbox:send_failed', n_fail || ' social reply/replies failed to send in 24h',
      'public.social_message', 'agent_facing', n_fail, jsonb_build_object('owner_seat', 'marketing'), '{}'::text[],
      array['the send_error of each'], 'marketing');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no social reply failed in 24h'
     where issue_key = 'social_inbox:send_failed' and closed_at is null;
  end if;

  return jsonb_build_object('working_day', v_working, 'overdue', n_over, 'overdue_by_class', v_overdue,
    'signed_webhooks_rejected_24h', n_sig, 'sends_failed_24h', n_fail,
    'held_switch_off', (select count(*) from public.social_message where send_status = 'held_switch_off'));
end $fn$;
revoke execute on function public.fn_marketing_social_inbox() from public, anon, authenticated;
grant execute on function public.fn_marketing_social_inbox() to service_role;

-- ── C12 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_trend_decision()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; n_expired int; v_brief jsonb; v_silent jsonb;
begin
  -- the 48-hour decision: unjudged after 48 hours is rejected, with the reason, so nothing waits forever
  update public.marketing_trend set relevant = false, judged_at = now(), judged_by = 'rule:48h',
         why_it_matters = 'Not judged within 48 hours of being seen, so rejected; a trend older than two days is not acted on.'
   where relevant is null and judged_at is null and seen_at < now() - interval '48 hours';
  get diagnostics n_expired = row_count;

  select jsonb_build_object('accepted', count(*) filter (where t.relevant), 'rejected', count(*) filter (where not t.relevant),
           'accepted_items', coalesce(jsonb_agg(jsonb_build_object('title', t.title, 'url', t.url, 'source', s.name, 'why', t.why_it_matters)
                                              order by t.judged_at desc) filter (where t.relevant), '[]'::jsonb))
    into v_brief from public.marketing_trend t join public.marketing_trend_source s on s.id = t.source_id
   where t.judged_at >= v_week::timestamp at time zone 'Asia/Dubai';
  insert into public.marketing_duty_record (duty, period, body) values ('marketing.trend_decision', v_week, v_brief)
  on conflict (duty, period) do update set body = excluded.body, written_at = now();

  select coalesce(jsonb_agg(name), '[]'::jsonb) into v_silent from public.marketing_trend_source
   where active and (last_error is not null or last_read_at is null or last_read_at < now() - interval '2 days');
  if jsonb_array_length(v_silent) > 0 then
    perform public.fn_it_engineer_finding_upsert('trends:feed_silent', jsonb_array_length(v_silent) || ' trend feed(s) unread for 2 days or failing',
      'public.marketing_trend_source', 'monitor', jsonb_array_length(v_silent), jsonb_build_object('feeds', v_silent, 'owner_seat', 'marketing'),
      '{}'::text[], '{}'::text[], 'marketing');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'every trend feed read within 2 days'
     where issue_key = 'trends:feed_silent' and closed_at is null;
  end if;
  return jsonb_build_object('expired_rejected', n_expired, 'week', v_week, 'accepted', v_brief->'accepted', 'rejected', v_brief->'rejected',
    'unjudged_under_48h', (select count(*) from public.marketing_trend where relevant is null), 'silent_feeds', v_silent);
end $fn$;
revoke execute on function public.fn_marketing_trend_decision() from public, anon, authenticated;
grant execute on function public.fn_marketing_trend_decision() to service_role;

-- ── C13 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_kpi_scorecard_for(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := p_month::timestamp at time zone 'Asia/Dubai'; v_to timestamptz := (p_month + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_reg int; v_spend numeric; v_ours int; v_theirs int;
begin
  select count(*) into v_reg from public.leads l
   where coalesce(l.is_demo, false) = v_fx and l.registration_submitted_at >= v_from and l.registration_submitted_at < v_to;
  select coalesce(sum(spend), 0) into v_spend from public.marketing_ad_spend_day where is_demo = v_fx and day >= p_month and day < (p_month + interval '1 month')::date;
  select count(*) filter (where cited), coalesce(sum(cardinality(competitors_cited)), 0) into v_ours, v_theirs
    from public.marketing_geo_check where month = p_month;
  return jsonb_build_object(
    'month', p_month,
    'suppliers_registered', v_reg,
    'registered_by_campaign', (select coalesce(jsonb_object_agg(cmp, n), '{}'::jsonb) from (
        select coalesce(ft.utm_campaign, '(no campaign)') cmp, count(*) n
          from public.leads l left join public.marketing_first_touch ft on ft.lead_id = l.id
         where coalesce(l.is_demo, false) = v_fx and l.registration_submitted_at >= v_from and l.registration_submitted_at < v_to
         group by 1) x),
    'paid_spend_aed', v_spend,
    'cost_per_registered_supplier_aed', case when v_spend > 0 and v_reg > 0 then round(v_spend / v_reg, 2) end,
    'cost_note', case when v_spend = 0 then 'no paid spend: paid media is off until a budget is approved' end,
    'geo', (select coalesce(jsonb_object_agg(engine, jsonb_build_object('checked', n, 'cited', c)), '{}'::jsonb) from (
        select engine, count(*) n, count(*) filter (where cited) c from public.marketing_geo_check where month = p_month group by 1) g),
    'share_of_voice_pct', case when v_ours + v_theirs > 0 then round(100.0 * v_ours / (v_ours + v_theirs), 1) else 0 end,
    'share_of_voice_basis', format('%s answer(s) citing us vs %s competitor citation(s) in the month''s GEO checks', v_ours, v_theirs),
    'posts_by_pillar', (select coalesce(jsonb_object_agg(pillar, body), '{}'::jsonb) from (
        select coalesce(c.theme, '(no campaign)') pillar,
               jsonb_build_object('published', count(distinct p.id),
                 'metrics', (select coalesce(jsonb_object_agg(metric, v), '{}'::jsonb) from (
                     select m.metric, sum(m.value) v from public.marketing_post_metric m join public.marketing_post p2 on p2.id = m.post_id
                      where p2.is_demo = v_fx and p2.published_at >= v_from and p2.published_at < v_to and coalesce(p2.campaign_id, -1) = coalesce(c.id, -1)
                        and m.value is not null group by 1) mm)) body
          from public.marketing_post p left join public.marketing_campaign c on c.id = p.campaign_id
         where p.is_demo = v_fx and p.status = 'published' and p.published_at >= v_from and p.published_at < v_to
         group by c.id, c.theme) b));
end $fn$;
revoke execute on function public.fn_marketing_kpi_scorecard_for(date) from public, anon, authenticated;
grant execute on function public.fn_marketing_kpi_scorecard_for(date) to service_role;

create or replace function public.fn_marketing_kpi_scorecard()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m0 date := date_trunc('month', now() at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date; v_cur jsonb; v_closed boolean := false;
begin
  -- the last month is closed once, then never rewritten; the current month is rewritten daily as month-to-date
  if not exists (select 1 from public.marketing_duty_record where duty = 'marketing.kpi_scorecard' and period = v_pm and body->>'final' = 'true') then
    insert into public.marketing_duty_record (duty, period, body)
    values ('marketing.kpi_scorecard', v_pm, public.fn_marketing_kpi_scorecard_for(v_pm) || jsonb_build_object('final', true))
    on conflict (duty, period) do update set body = excluded.body, written_at = now();
    v_closed := true;
  end if;
  v_cur := public.fn_marketing_kpi_scorecard_for(v_m0) || jsonb_build_object('final', false);
  insert into public.marketing_duty_record (duty, period, body) values ('marketing.kpi_scorecard', v_m0, v_cur)
  on conflict (duty, period) do update set body = excluded.body, written_at = now();
  return jsonb_build_object('closed_last_month', v_closed, 'month_to_date', v_cur);
end $fn$;
revoke execute on function public.fn_marketing_kpi_scorecard() from public, anon, authenticated;
grant execute on function public.fn_marketing_kpi_scorecard() to service_role;

-- ── C14 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_fact_watch (
  surface      text primary key,
  url          text not null check (url ~ '^https://'),
  expects      text[] not null default '{}',
  fact_hash    text,
  request_id   bigint,
  requested_at timestamptz,
  checked_at   timestamptz,
  carries      boolean,
  missing      text[] not null default '{}',
  http_status  int
);
alter table public.marketing_fact_watch enable row level security;
drop policy if exists marketing_fact_watch_service_role_only on public.marketing_fact_watch;
create policy marketing_fact_watch_service_role_only on public.marketing_fact_watch as permissive for all to public using (false) with check (false);
revoke all on public.marketing_fact_watch from anon, authenticated;
-- the public surfaces that state the facts (measured 19 Oct 2026: /faq states all three; / and /how-it-works the 3%)
insert into public.marketing_fact_watch (surface, url) values
  ('site_faq', 'https://quotesdone.ae/faq'), ('site_home', 'https://quotesdone.ae/'), ('site_how_it_works', 'https://quotesdone.ae/how-it-works')
on conflict (surface) do nothing;

create or replace function public.fn_marketing_public_facts()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'reveal_fee', trim(to_char(standard_reveal_rate * 100, 'FM990.##')) || '%',
    'supplier_subscription', 'AED ' || trim(to_char(supplier_reg_fee, 'FM9,999,990')),
    'nonresponse_admin_fee', 'AED ' || trim(to_char(supplier_nonresponse_admin_fee_aed, 'FM9,999,990')),
    'supplier_period', supplier_reg_period, 'refund_window_working_days', refund_window_working_days)
  from public.pricing_config where id = 1
$fn$;
revoke execute on function public.fn_marketing_public_facts() from public, anon, authenticated;
grant execute on function public.fn_marketing_public_facts() to service_role;

create or replace function public.fn_marketing_fact_register()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_facts jsonb := public.fn_marketing_public_facts(); v_hash text; v_prev text; w record; r record; v_missing text[]; e text;
  n_req int := 0; n_checked int := 0; v_changed boolean; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_hash := md5(v_facts::text);
  select body->>'hash' into v_prev from public.marketing_duty_record where duty = 'marketing.fact_register' order by period desc limit 1;
  v_changed := v_prev is distinct from v_hash;
  insert into public.marketing_duty_record (duty, period, body)
  values ('marketing.fact_register', v_today, jsonb_build_object('hash', v_hash, 'facts', v_facts, 'changed_from', v_prev))
  on conflict (duty, period) do update set body = excluded.body, written_at = now();
  -- what each surface must say: the FAQ every fact, the others the reveal fee
  update public.marketing_fact_watch set expects = case when surface = 'site_faq'
      then array[v_facts->>'reveal_fee', v_facts->>'supplier_subscription', v_facts->>'nonresponse_admin_fee'] else array[v_facts->>'reveal_fee'] end;

  -- read what came back
  for w in select * from public.marketing_fact_watch where request_id is not null and checked_at is distinct from requested_at loop
    select status_code, content into r from net._http_response where id = w.request_id;
    continue when not found and w.requested_at > now() - interval '6 hours';
    v_missing := '{}';
    foreach e in array w.expects loop
      if coalesce(r.content, '') not like '%' || e || '%' then v_missing := v_missing || e; end if;
    end loop;
    update public.marketing_fact_watch set checked_at = requested_at, http_status = r.status_code,
           carries = cardinality(v_missing) = 0 and coalesce(r.status_code, 0) between 200 and 299, missing = v_missing where surface = w.surface;
    if cardinality(v_missing) > 0 or coalesce(r.status_code, 0) not between 200 and 299 then
      perform public.fn_it_engineer_finding_upsert('facts:surface_stale:' || w.surface,
        w.url || ' does not state ' || coalesce(array_to_string(v_missing, ', '), '') || ' (HTTP ' || coalesce(r.status_code::text, 'no answer') || ')',
        w.url, 'customer_facing', 1, jsonb_build_object('facts', v_facts, 'missing', v_missing, 'owner_seat', 'marketing'),
        '{}'::text[], array['which page component states the fact'], 'marketing');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'the surface states every public fact'
       where issue_key = 'facts:surface_stale:' || w.surface and closed_at is null;
    end if;
    n_checked := n_checked + 1;
  end loop;

  -- request: every day, and at once when a fact changed
  for w in select * from public.marketing_fact_watch
            where v_changed or requested_at is null or requested_at < now() - interval '1 day' loop
    update public.marketing_fact_watch set request_id = net.http_get(w.url, '{}'::jsonb,
             jsonb_build_object('User-Agent', 'QuotesDone fact register (+https://www.quotesdone.ae)', 'Accept', 'text/html'), 20000),
           requested_at = now(), fact_hash = v_hash where surface = w.surface;
    n_req := n_req + 1;
  end loop;
  return jsonb_build_object('facts', v_facts, 'changed', v_changed, 'requested', n_req, 'checked', n_checked,
    'stale_surfaces', (select coalesce(jsonb_agg(surface), '[]'::jsonb) from public.marketing_fact_watch where carries is false));
end $fn$;
revoke execute on function public.fn_marketing_fact_register() from public, anon, authenticated;
grant execute on function public.fn_marketing_fact_register() to service_role;

-- ── C15 (reports; never switches paid on) ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_paid_spend_report()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; v_paid boolean := public.fn_marketing_paid_allowed();
  v_30 numeric; v_mtd numeric; v_unhanded int; v_unbooked int; p public.ad_spend_policy; v_body jsonb; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  select coalesce(sum(spend), 0) into v_30 from public.marketing_ad_spend_day where is_demo = v_fx and day >= v_today - 30;
  select coalesce(sum(spend), 0) into v_mtd from public.marketing_ad_spend_day where is_demo = v_fx and day >= date_trunc('month', v_today)::date;
  select count(*) filter (where handed_off_at is null), count(*) filter (where handed_off_at < now() - interval '2 days' and booked_ack_at is null)
    into v_unhanded, v_unbooked from public.marketing_ad_spend_day where is_demo = v_fx and spend > 0 and day < v_today - 1;
  select * into p from public.ad_spend_policy where policy_key = 'default';
  v_body := jsonb_build_object('paid_allowed', v_paid, 'spend_30d_aed', v_30, 'spend_month_to_date_aed', v_mtd,
    'days_not_handed_to_accountant', v_unhanded, 'days_handed_not_booked_2d', v_unbooked,
    'pace', case when v_paid and p.monthly_cap_aed is not null then
        jsonb_build_object('monthly_cap_aed', p.monthly_cap_aed, 'expected_by_today_aed',
          round(p.monthly_cap_aed * extract(day from v_today) / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day')), 2),
          'over_pace', v_mtd > p.monthly_cap_aed * extract(day from v_today) / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day')) * 1.1) end);
  if not v_fx then
    if not v_paid and v_30 > 0 then
      perform public.fn_it_engineer_finding_upsert('paid:spend_without_budget', 'AED ' || v_30 || ' of ad spend in 30 days while paid media is not approved',
        'public.marketing_ad_spend_day', 'monitor', 1, v_body || jsonb_build_object('owner_seat', 'marketing'), '{}'::text[], array['which account spent'], 'marketing');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'no spend without an approved budget'
       where issue_key = 'paid:spend_without_budget' and closed_at is null;
    end if;
    if v_unhanded + v_unbooked > 0 then
      perform public.fn_it_engineer_finding_upsert('paid:spend_not_reported', (v_unhanded + v_unbooked) || ' ad-spend day(s) not handed to or not booked by the accountant',
        'public.marketing_ad_spend_day', 'monitor', v_unhanded + v_unbooked, v_body || jsonb_build_object('owner_seat', 'marketing'), '{}'::text[], '{}'::text[], 'marketing');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'every spend day is with the accountant'
       where issue_key = 'paid:spend_not_reported' and closed_at is null;
    end if;
    insert into public.marketing_duty_record (duty, period, body) values ('marketing.paid_spend_report', v_today, v_body)
    on conflict (duty, period) do update set body = excluded.body, written_at = now();
  end if;
  return v_body;
end $fn$;
revoke execute on function public.fn_marketing_paid_spend_report() from public, anon, authenticated;
grant execute on function public.fn_marketing_paid_spend_report() to service_role;

-- ── the duties ────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.geo_fix', 'marketing', interval '1 day', 'fn_marketing_geo_fix',
   'C03: every answer-engine question uncited this month gets one recorded fix (comparison passage, answer-first service passage or entity fix), closed when a check cites us.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.social_publish', 'marketing', interval '1 day', 'fn_marketing_social_publish',
   'C10: the approved calendar kept on UAE working days with UTM links; missed slots handed to the CEO for re-approval; yesterday''s due posts audited.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.social_inbox', 'marketing', interval '1 hour', 'fn_marketing_social_inbox',
   'C11: owed comments and DMs unanswered 2 working hours, signed webhooks rejected and failed replies become marketing findings, closed when clear.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.trend_decision', 'marketing', interval '1 day', 'fn_marketing_trend_decision',
   'C12: every trend decided within 48 hours of being seen; the week''s accepted trends kept as the trend brief; a silent feed is a finding.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.kpi_scorecard', 'marketing', interval '1 day', 'fn_marketing_kpi_scorecard',
   'C13: the monthly scorecard -- suppliers registered per campaign, cost per registered supplier, GEO citations, share of voice, posts by pillar -- month to date daily, last month closed once.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.fact_register', 'marketing', interval '1 day', 'fn_marketing_fact_register',
   'C14: the public facts read from pricing_config; every public surface fetched and must state them, the same day a fact changes; a stale surface is a finding.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql'),
  ('marketing.paid_spend_report', 'marketing', interval '1 day', 'fn_marketing_paid_spend_report',
   'C15: paid spend reported -- none while paid is off (spend without a budget is a finding); when a budget is approved, pacing and every spend day with the accountant.',
   'scripts/sql/the_marketing_seat_closes_the_loops_a_senior_marketer_closes.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- Per-signature revokes on the routines this file replaces (release operator, #1551). CREATE OR REPLACE keeps the ACL;
-- these make the closed state explicit whatever the ACL was.
revoke execute on function public.fn_marketing_recruitment_funnel() from public, anon, authenticated;
grant execute on function public.fn_marketing_recruitment_funnel() to service_role;
revoke execute on function public.fn_marketing_reputation() from public, anon, authenticated;
grant execute on function public.fn_marketing_reputation() to service_role;

-- The three tables this file creates go to the daily export (release operator, #1551). PENDING: applied at merge only.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('marketing_duty_record', true, 'marketing', 'One record per marketing duty per period: what each senior duty found and did.', 'marketing'),
  ('marketing_geo_fix', true, 'marketing', 'C03: each AI-answer question the site loses, the fix briefed for it, and when it closed.', 'marketing'),
  ('marketing_fact_watch', true, 'marketing', 'C14: each public surface that must state the public facts, and whether it did when last fetched.', 'marketing')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
