-- Seat: sales_engineer. Assigned: sales_engineer (customer-journey follow-up, 10 Nov 2026; founder ruling 1608, the free audit
-- before the last paid test round; the first journey audit, #1899, reported this as its one HIGH).
--
-- MEASURED on origin/main:
--   customer_api lib/matching.ts asked the sales engineer's matcher twice, 1.5 s apart; when neither answered, the request
--   was left with routing.matcher_unavailable = true and no supplier, and nothing in the estate ever asked again. Then:
--     * the portal told the customer at post time "we are still registering suppliers for this trade" (nr_posted_none);
--     * fn_customer_concierge_held read "no inquiry_matches row" as finding_suppliers, so the first-request letter said
--       the same, and the 15-minute availability sweep put the request in the stalled-supplier rescue, whose notice says
--       "none of the suppliers registered for it can take it on right now";
--     * after 14 days fn_sales_engineer_closes_unreached_requests closed it, e-mailing "because we are still registering
--       suppliers for this trade" — about a trade that had never been searched;
--     * the IT finding used ONE fixed key, so every outage was one row whose evidence named only the last request.
--
-- WHAT THIS CHANGES (with customer_api lib/rematch.ts, lib/rematch_io.ts, lib/matching.ts and the portal):
--   1. decision_policy.rematch_backoff_minutes: the re-match schedule, ten tries over about six days, tunable here. The
--      sweep runs on resilience_ping's specoffer step (the sales engineer's existing 15-minute beat), not a new cron.
--   2. fn_stalled_inquiry_flag: a request waiting on the re-match is not flagged "no reachable supplier" (and an open flag
--      of that reason is cleared); it goes to the rescue only once the matcher has answered with nobody.
--   3. fn_customer_concierge_held answers matching = true (not finding_suppliers) while a request or a part of it waits;
--      fn_customer_concierge_message's first-request letter then says "we are matching your request; you will hear
--      from us shortly" instead of "we are still registering suppliers".
--   4. fn_sales_engineer_closes_unreached_requests skips a request whose re-match is still running; one whose schedule is
--      spent is closed after the same 14 days with a reason that is ours ("a fault on our side stopped us matching it").
--   5. fn_sales_engineer_rematch_told (new): once the re-match reaches suppliers, the customer is told, once per request,
--      in the request's language. A re-match that answers "nobody" says nothing here: the rescue's own notice does.
-- NOT CHANGED: the matcher itself (sales_engineer {action:'match'}), the portal's other states, the split/turnkey posting.
-- Every body below is its canonical file's, read back equal to production on 10 Nov 2026, with only the lines marked
-- "10 Nov 2026" added. CREATE OR REPLACE keeps the four existing ACLs; the one new routine is revoked below.
-- prevented by: supabase/functions/customer_api/rematch.test.ts and
--   scripts/checks/a_request_the_matcher_could_not_reach_is_matched_again.test.mjs
-- Pending until the release applies it: scripts/sql/pending/a_request_the_matcher_could_not_reach_is_matched_again_and_never_closed_as_unreached.txt

insert into public.decision_policy (key, value, description) values
  ('rematch_backoff_minutes', '[15, 30, 60, 180, 360, 720, 1440, 1440, 1440, 2880]'::jsonb,
   'customer_api lib/rematch.ts: minutes to wait before the 1st, 2nd, ... re-match of a request the sales engineer''s matcher did not answer. After the last step the request is "exhausted" and fn_sales_engineer_closes_unreached_requests may close it after 14 days, saying the fault was ours. Sales engineer, 10 Nov 2026 (customer-journey follow-up, ruling 1608).')
on conflict (key) do nothing;

create or replace function public.fn_stalled_inquiry_flag(p_inquiry_id uuid, p_by text default 'sales_engineer')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; v_fixture boolean; v_quotes int; v_matched int; v_reach int; v_busy int; v_paused int;
  v_blocked int; v_back date; v_trades text[]; v_trade_busy int; v_trade_paused int; v_trade_back date;
  v_open boolean; v_detail jsonb; v_by text := coalesce(nullif(btrim(p_by), ''), 'sales_engineer');
  v_prev_reason text; v_prev_cleared timestamptz; v_had boolean; v_written int;   -- 29 Sep 2026 (review of #1106)
begin
  select * into i from public.inquiries where id = p_inquiry_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such inquiry'); end if;
  -- 29 Sep 2026 (review of #1106): only this intake's own reason
  v_open := exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier');

  select count(*)::int into v_quotes from public.quotes q
   where q.inquiry_id = i.id
     and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
     and q.stale_at is null;

  if coalesce(i.status, '') not in ('sent', 'quoted') or v_quotes > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(),
             cleared_why = case when v_quotes > 0 then v_quotes || ' live quote(s)' else 'inquiry is ' || coalesce(i.status, 'null') end
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open,
                              'why', case when v_quotes > 0 then 'quoted' else 'not open' end);
  end if;

  -- 10 Nov 2026 (sales_engineer): the MATCHER did not answer for this request, so nobody was searched, and "none of
  -- the suppliers registered for it can take it on" (the rescue's notice) would be false. It waits for the re-match
  -- (customer_api lib/rematch.ts); once the matcher has answered, routing no longer says matcher_unavailable.
  if coalesce((i.routing->>'matcher_unavailable')::boolean, false) then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(), cleared_why = 'the matcher did not answer: waiting for the re-match'
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open, 'why', 'waiting for the re-match');
  end if;

  select count(*)::int,
         count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
                            and public.fn_supplier_available(av.state, av.busy_until))::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'busy')::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'paused')::int,
         count(*) filter (where not public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes))::int,
         min(av.busy_until) filter (where not public.fn_supplier_available(av.state, av.busy_until))
    into v_matched, v_reach, v_busy, v_paused, v_blocked, v_back
    from public.inquiry_matches m
    join public.leads l on l.id = m.supplier_id
    left join public.supplier_availability av on av.supplier_id = m.supplier_id
   where m.inquiry_id = i.id;

  if v_reach > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(), cleared_why = v_reach || ' reachable supplier(s)'
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open, 'reachable', v_reach);
  end if;

  -- Nobody can reach it. Say why, for the rescue: the matched suppliers' states, and the suppliers of its
  -- trades who confirmed their scope and are matchable but said busy or paused (the trade gate only: role,
  -- authority, value and emirate are the matcher's, not repeated here).
  v_trades := public.fn_taxonomy_trades_for(case when coalesce(cardinality(i.trades), 0) > 0 then i.trades
                                                 else array[coalesce(i.category, '')] end);
  select count(*) filter (where av.state = 'busy')::int, count(*) filter (where av.state = 'paused')::int, min(av.busy_until)
    into v_trade_busy, v_trade_paused, v_trade_back
    from public.supplier_capabilities sc
    join public.leads l on l.id = sc.supplier_id
    join public.supplier_availability av on av.supplier_id = sc.supplier_id
   where sc.confirmed_at is not null
     and sc.trades && coalesce(v_trades, '{}'::text[])
     and not (sc.excluded_trades && coalesce(v_trades, '{}'::text[]))
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     and not public.fn_supplier_available(av.state, av.busy_until);

  select public.fn_seat_clock_customer_is_fixture(c) into v_fixture from public.customers c where c.id = i.customer_id;
  v_detail := jsonb_build_object(
    'matched', v_matched, 'reachable', 0, 'matched_busy', v_busy, 'matched_paused', v_paused, 'matched_not_matchable', v_blocked,
    'earliest_back', v_back, 'trades', to_jsonb(v_trades), 'category', i.category, 'emirate', i.emirate,
    'in_trade_busy', coalesce(v_trade_busy, 0), 'in_trade_paused', coalesce(v_trade_paused, 0), 'in_trade_earliest_back', v_trade_back,
    'matcher_unavailable', coalesce((i.routing->>'matcher_unavailable')::boolean, false), 'at', now());

  -- 29 Sep 2026 (review of #1106 at 3d1bbb8): the WRITE is filtered too. An open row of the other reason (no_quote_48h)
  -- is the rescue's, already acted on: it is not touched and not counted. A cleared row, of either reason, is reopened as
  -- this reason with the rescue's own record reset, so the rescue acts on it afresh and the customer hears this reason.
  select x.reason, x.cleared_at into v_prev_reason, v_prev_cleared from public.stalled_inquiry_rescue x where x.inquiry_id = i.id;
  v_had := found;
  insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by)
  values (i.id, 'no_reachable_supplier', v_detail, coalesce(v_fixture, false), now(), v_by)
  on conflict (inquiry_id) do update
     set reason = excluded.reason, detail = excluded.detail, fixture = excluded.fixture,
         -- an open flag keeps the time it was first raised; a cleared one is raised again from now
         flagged_at = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_at else excluded.flagged_at end,
         flagged_by = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_by else excluded.flagged_by end,
         -- reopened: the rescue's record starts over (an open own-reason row keeps what the rescue already did)
         acted_at        = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.acted_at end,
         customer_notice = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.customer_notice end,
         enqueue_result  = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.enqueue_result end,
         trades          = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.trades end,
         uninvited_pool  = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.uninvited_pool end,
         plan_rank       = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.plan_rank end,
         finding_key     = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.finding_key end,
         matched_at      = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.matched_at end,
         stalled_hours   = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.stalled_hours end,
         cleared_at = null, cleared_why = null
   where stalled_inquiry_rescue.reason = 'no_reachable_supplier' or stalled_inquiry_rescue.cleared_at is not null;
  get diagnostics v_written = row_count;
  if v_written = 0 then
    -- open under the other reason: already in the rescue; nothing written, nothing counted
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'new', false, 'in_rescue_as', v_prev_reason);
  end if;
  return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', true,
                            'new', not v_had or v_prev_cleared is not null, 'detail', v_detail);
end
$fn$;

create or replace function public.fn_customer_concierge_held(p_inquiry uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; u public.inquiries; v_ar boolean; v_units uuid[]; v_split boolean; v_fields jsonb;
  v_missing jsonb := '[]'::jsonb; m jsonb; f jsonb; k text; v_pre text; v_lang text;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('held', false, 'finding_suppliers', false, 'reason', 'no such request'); end if;
  v_ar := coalesce(public.fn_inquiry_locale(i.id), (select c.locale from public.customers c where c.id = i.customer_id)) = 'ar';
  v_lang := case when v_ar then 'ar' else 'en' end;
  -- 10 Nov 2026: expired and lost are ends too (one list with _shared/request_closed.ts)
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed', 'expired', 'lost') then
    return jsonb_build_object('held', false, 'finding_suppliers', false, 'lang', v_lang);
  end if;
  v_units := array(select c.id from public.inquiries c where c.parent_inquiry_id = i.id order by c.created_at);
  v_split := cardinality(v_units) > 0;
  if not v_split then v_units := array[i.id]; end if;
  -- 10 Nov 2026 (sales_engineer): reached nobody because the MATCHER did not answer is "we are matching it", never
  -- "we are still registering suppliers" — that trade was never searched. The re-match (customer_api lib/rematch.ts)
  -- clears matcher_unavailable once the matcher answers; from then the request reads as it would have at posting.
  if not exists (select 1 from public.inquiry_matches x where x.inquiry_id = any(v_units) or x.inquiry_id = i.id)
     and exists (select 1 from public.inquiries x where (x.id = any(v_units) or x.id = i.id)
                    and coalesce((x.routing->>'matcher_unavailable')::boolean, false)) then
    return jsonb_build_object('held', false, 'finding_suppliers', false, 'matching', true, 'lang', v_lang, 'missing', '[]'::jsonb);
  end if;
  if not exists (select 1 from public.inquiry_matches x where x.inquiry_id = any(v_units) or x.inquiry_id = i.id) then
    return jsonb_build_object('held', false, 'finding_suppliers', true, 'lang', v_lang, 'missing', '[]'::jsonb);
  end if;

  for u in select * from public.inquiries x where x.id = any(v_units) and not coalesce(x.rfq_ready, false)
            order by x.created_at loop
    v_pre := case when v_split then coalesce((select cs.label from public.category_specs cs where cs.category = u.category),
                                             replace(coalesce(u.category, ''), '_', ' ')) || ': ' else '' end;
    -- The category's required fields that are still open, in the plain words the intake asks them with.
    select cs.fields into v_fields from public.category_specs cs where cs.category = u.category;
    for m in select value from jsonb_array_elements(coalesce(u.completeness->'category_missing', '[]'::jsonb)) loop
      f := null;
      select value into f from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) where value->>'key' = m->>'key' limit 1;
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', m->>'key', 'inquiry_id', u.id,
        'ask', v_pre || coalesce(nullif(f->>case when v_ar then 'question_plain_ar' else 'question_plain_en' end, ''),
                                 nullif(m->>'question', ''), m->>'key')));
    end loop;
    -- The general score only holds a request when it is below the bar; then each missing part is named.
    if not coalesce((u.completeness->>'generic_ready')::boolean, true) then
      for k in select value from jsonb_array_elements_text(coalesce(u.completeness->'missing', '[]'::jsonb)) loop
        v_missing := v_missing || coalesce((select jsonb_build_array(jsonb_build_object('key', k, 'inquiry_id', u.id, 'ask', v_pre || case when v_ar then g.ar else g.en end))
          from (values
            ('category', 'What kind of work is it (the trade)?', 'ما نوع العمل المطلوب (التخصص)؟'),
            ('emirate', 'Which emirate and area is the work in?', 'في أي إمارة ومنطقة سيُنفَّذ العمل؟'),
            ('scope_detail', 'A fuller description of the work: what, how much and to what standard.', 'وصف أوفى للعمل: ما المطلوب، وبأي كمية، ووفق أي مواصفة.'),
            ('scope_type', 'Is it one trade, or several trades together?', 'هل يشمل تخصصًا واحدًا أم عدة تخصصات معًا؟'),
            ('budget', 'Your budget for the work (a range is fine).', 'الميزانية المرصودة للعمل (يكفي نطاق تقريبي).'),
            ('supporting_detail', 'A drawing (PDF, DWG or DXF), a bill of quantities, or the trades involved.', 'مخطط (PDF أو DWG أو DXF)، أو جدول كميات، أو التخصصات المعنية.')
          ) g(key, en, ar) where g.key = k), '[]'::jsonb);
      end loop;
    end if;
  end loop;
  return jsonb_build_object('held', jsonb_array_length(v_missing) > 0, 'finding_suppliers', false, 'lang', v_lang,
                            'missing', v_missing);
end $fn$;

create or replace function public.fn_customer_concierge_message(p_inquiry uuid, p_kind text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; c public.customers; g jsonb; h jsonb; v_ar boolean; v_name text; v_ref text; v_held text := ''; v_find text := '';
  v_steps text; v_subj text; v_body text; v_link text; v_match text := '';
begin
  if p_kind not in ('first_request', 'held_for_specs', 'finding_suppliers') then
    raise exception 'a concierge message is first_request, held_for_specs or finding_suppliers, not %', p_kind;
  end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then raise exception 'no request %', p_inquiry; end if;
  select * into c from public.customers where id = i.customer_id;
  g := public.fn_customer_concierge(i.customer_id, i.category, null, i.id);
  h := g->'held';
  v_ar := g->>'lang' = 'ar';
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_ref := 'QD-' || public.fn_job_no(i.id);
  v_link := case when v_ar then 'https://quotesdone.com/ar/me' else 'https://quotesdone.com/me' end;

  if coalesce((h->>'held')::boolean, false) then
    v_held := (select string_agg('- ' || (e->>'ask'), chr(10)) from jsonb_array_elements(h->'missing') e) || chr(10) || chr(10)
      || case when v_ar
           then 'يمكنكم تعديل الميزانية والإمارة من حسابكم: ' || v_link || chr(10) || 'ولأي تفاصيل أخرى، يسعدنا أن تردّوا على هذه الرسالة بها.'
           else 'You can change the budget and the emirate from your account: ' || v_link || chr(10) || 'For anything else, reply to this e-mail with the details.' end;
  end if;
  -- NO SUPPLIER HAS IT YET: said as it is, never blamed on the specs (re-review of #1112).
  if coalesce((h->>'finding_suppliers')::boolean, false) and not public.fn_inquiry_awaits_specs(i.id) then
    v_find := case when v_ar
      then 'ما زلنا نسجّل الموردين في تخصصكم. لا يغطي هذا الطلب أيٌّ من الموردين المسجّلين لدينا اليوم، ولذلك لم يصل إلى أي مورّد، ولا يمكننا أن نعدكم بعرض سعر أو بموعد له، فنرجو ألا تؤخروا عملكم انتظارًا لنا. سنبقي طلبكم مفتوحًا 14 يومًا؛ وإذا لم يصل إلى أي مورّد خلالها أغلقناه وأبلغناكم. لا يلزمكم أي إجراء ولا أي مبلغ.'
      else 'We are still registering suppliers for your trade. No supplier registered with us today covers this request, so it has not reached anyone, and we cannot promise a quote or say when one might come. Please do not hold your work for us. We will keep your request open for 14 days; if it has reached no supplier by then, we will close it and tell you. Nothing is needed from you, and there is nothing to pay.' end;
  end if;
  -- 10 Nov 2026 (sales_engineer): the matcher did not answer at posting; the request is being matched again.
  if coalesce((h->>'matching')::boolean, false) then
    v_match := case when v_ar
      then 'نعمل على مطابقة طلبكم مع الموردين المختصين فيه، وسنتواصل معكم قريبًا، ولا يلزمكم أي مبلغ.'
      else 'We are matching your request with the suppliers who cover it. You will hear from us shortly, and there is nothing to pay.' end;
  end if;
  -- The steps, numbered; only the specs step for a later request (the customer has seen the rest before).
  v_steps := (select string_agg(n || '. ' || (e->>'title') || ': ' || (e->>'body'), chr(10) || chr(10) order by n)
                from jsonb_array_elements(g->'steps') with ordinality s(e, n)
               where p_kind = 'first_request' or e->>'key' = 'specs');

  if p_kind = 'first_request' then
    v_subj := case when v_ar then 'استلمنا طلبكم ' || v_ref || ': الخطوات التالية' else 'We have your request ' || v_ref || ': what happens next' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم الأول على QuotesDone، ورقمه ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'وقبل أن يتمكّن الموردون من تسعيره، نحتاج منكم إلى التفاصيل التالية:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || case when v_match <> '' then v_match || chr(10) || chr(10) else '' end
        || 'وللحصول على عروض دقيقة قابلة للمقارنة، إليكم الخطوات:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your first request on QuotesDone. Its number is ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'Before suppliers can price it, we need a few details from you:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || case when v_match <> '' then v_match || chr(10) || chr(10) else '' end
        || 'Here is how to get exact, comparable quotes, step by step:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  elsif p_kind = 'finding_suppliers' then
    if v_find = '' then return jsonb_build_object('lang', g->>'lang', 'not_finding', true); end if;
    v_subj := case when v_ar then 'نبحث عن موردين لطلبكم ' || v_ref else 'We are finding suppliers for your request ' || v_ref end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your request ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  else
    if v_held = '' then return jsonb_build_object('lang', g->>'lang', 'not_held', true); end if;
    v_subj := case when v_ar then 'طلبكم ' || v_ref || ' يحتاج إلى بعض التفاصيل' else 'Your request ' || v_ref || ' needs a few details' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'يحتاج الموردون الذين وصلهم طلبكم ' || v_ref || ' إلى التفاصيل التالية ليسعّروه بدقة:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The suppliers who have your request ' || v_ref || ' need the following to price it exactly:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  end if;
  return jsonb_build_object('lang', g->>'lang', 'subject', v_subj, 'body', v_body, 'held', h, 'first_inquiry', g->'first_inquiry');
end $fn$;

create or replace function public.fn_sales_engineer_closes_unreached_requests(p_at timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_ar boolean; v_ref text; v_closed int := 0; v_ours boolean;
begin
  for r in select i.id, i.lang, c.email from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.parent_inquiry_id is null and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and i.created_at <= p_at - interval '14 days'
              and not exists (select 1 from public.inquiry_matches m join public.inquiries k on k.id = m.inquiry_id where k.id = i.id or k.parent_inquiry_id = i.id)
              and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
              -- Held for its own missing specs: the customer owes us an answer, and "no supplier" would be a false reason.
              and not public.fn_inquiry_awaits_specs(i.id)
              -- 10 Nov 2026: the matcher did not answer, and its re-match is still running (customer_api lib/rematch.ts).
              -- "No supplier in 14 days" would be a verdict on a trade nobody searched; it waits until the schedule is spent.
              and not exists (select 1 from public.inquiries w where (w.id = i.id or w.parent_inquiry_id = i.id)
                                 and coalesce((w.routing->>'matcher_unavailable')::boolean, false)
                                 and not coalesce((w.routing#>>'{rematch,exhausted}')::boolean, false))
            order by i.created_at limit 100 loop
    update public.inquiries set status = 'expired' where id = r.id or parent_inquiry_id = r.id;
    update public.stalled_inquiry_rescue set cleared_at = p_at, cleared_why = 'request closed' where inquiry_id = r.id and cleared_at is null;
    v_ar := coalesce(r.lang, '') like 'ar%'; v_ref := 'QD-' || public.fn_job_no(r.id);
    -- reached nobody because the matcher never answered, every re-match spent: that is our fault, said as ours
    v_ours := exists (select 1 from public.inquiries w where (w.id = r.id or w.parent_inquiry_id = r.id)
                         and coalesce((w.routing->>'matcher_unavailable')::boolean, false));
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'request_closed_no_supplier', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', lower(btrim(r.email)), 'to_role', 'customer',
      'inquiry_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'request_closed_no_supplier:' || r.id,
      'subject', case when v_ar then 'أغلقنا طلبكم ' || v_ref else 'We have closed your request ' || v_ref end,
      'body', case when v_ours and v_ar then 'شكرًا لتواصلكم معنا. لم يصل طلبكم ' || v_ref || ' إلى أي مورّد خلال 14 يومًا، إذ حال عطل لدينا دون مطابقته مع الموردين المختصين فيه، ولذلك أغلقناه. نعتذر عن ذلك، ولا يلزمكم أي مبلغ. ويسعدنا أن ترسلوا طلبًا جديدًا في أي وقت.'
                   when v_ours then 'Thank you for coming to us. Your request ' || v_ref || ' did not reach a supplier in 14 days: a fault on our side stopped us matching it to the suppliers who cover it, so we have closed it. We are sorry, and there is nothing to pay. You are welcome to send a new request at any time.'
                   when v_ar then 'شكرًا لتواصلكم معنا. لم يصل طلبكم ' || v_ref || ' إلى أي مورّد خلال 14 يومًا، لأننا ما زلنا نسجّل الموردين في هذا التخصص، ولذلك أغلقناه. نعتذر عن ذلك، ولا يلزمكم أي مبلغ. ويسعدنا أن ترسلوا طلبًا جديدًا في أي وقت.'
                   else 'Thank you for coming to us. Your request ' || v_ref || ' did not reach a supplier in 14 days, because we are still registering suppliers for this trade, so we have closed it. We are sorry, and there is nothing to pay. You are welcome to send a new request at any time.' end)));
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'request_closed_no_supplier', 'auto_done', 'low', 'Request closed: no supplier in 14 days — ' || v_ref, 'No action required. The customer was told.',
            jsonb_build_object('inquiry_id', r.id, 'matcher_never_answered', v_ours), 'inquiries', r.id::text);
    v_closed := v_closed + 1;
  end loop;
  return jsonb_build_object('closed', v_closed);
end $fn$;

-- 5. the customer hears the re-match reached suppliers: once per request, in its language, through the duty door
create or replace function public.fn_sales_engineer_rematch_told(p_inquiry uuid, p_matches integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare u public.inquiries; t public.inquiries; c public.customers; v_lang text; v_ar boolean; v_ref text; v_name text;
        v_trade text; v_link text; v_n int := greatest(coalesce(p_matches, 0), 0);
begin
  select * into u from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('sent', false, 'reason', 'no such request'); end if;
  -- "Nobody covers it" is the rescue's notice (fn_sales_engineer_stalled_inquiry_rescue), sent once the flag is raised.
  if v_n = 0 then return jsonb_build_object('sent', false, 'reason', 'reached nobody: the stalled-inquiry rescue tells the customer'); end if;
  select * into t from public.inquiries where id = coalesce(u.parent_inquiry_id, u.id);
  select * into c from public.customers where id = t.customer_id;
  if not found or coalesce(c.banned, false) then return jsonb_build_object('sent', false, 'reason', 'no customer to write to'); end if;
  v_lang := public.fn_customer_message_lang(t.id, c.locale);
  v_ar := v_lang = 'ar';
  v_ref := 'QD-' || public.fn_job_no(t.id);
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_trade := coalesce(public.fn_trade_label(u.category, v_lang), case when v_ar then 'هذا التخصص' else 'this trade' end);
  v_link := case when v_ar then 'https://quotesdone.com/ar/me' else 'https://quotesdone.com/me' end;
  return public.fn_customer_support_duty_send('rematch.matched', t.id::text, 'customer', c.email, v_lang,
    case when v_ar then 'وصل طلبكم ' || v_ref || ' إلى الموردين' else 'Your request ' || v_ref || ' has reached suppliers' end,
    case when v_ar then
      'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
      || 'وصل طلبكم ' || v_ref || ' إلى ' || v_n || ' من الموردين المختصين في ' || v_trade || '، ويقدّمون عروضهم دون أن يعرفوا هويتكم، وسنُعلمكم فور وصول أول عرض سعر.' || chr(10) || chr(10)
      || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
      || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
    else
      'Dear ' || v_name || ',' || chr(10) || chr(10)
      || 'Your request ' || v_ref || ' has now reached ' || v_n || case when v_n = 1 then ' supplier' else ' suppliers' end || ' who cover ' || v_trade
      || '. They quote without knowing who you are, and we will let you know as soon as the first quotation arrives.' || chr(10) || chr(10)
      || 'You can follow your request from your account: ' || v_link end,
    c.id, null, t.id) || jsonb_build_object('stage', 'rematch.matched', 'inquiry_id', t.id);
end $fn$;
revoke execute on function public.fn_sales_engineer_rematch_told(uuid, integer) from public, anon, authenticated;

-- Verdict row (a DDL file, so no raise): the setting is there, the new routine is closed to the public, and the closer and
-- the flag carry the re-match guard. The behaviour itself is proved by the companion _probe.sql (rolled back).
select case
  when not exists (select 1 from public.decision_policy where key = 'rematch_backoff_minutes' and jsonb_typeof(value) = 'array')
    then 'PROBE FAILED: decision_policy.rematch_backoff_minutes is missing'
  when has_function_privilege('anon', 'public.fn_sales_engineer_rematch_told(uuid, integer)', 'execute')
    then 'PROBE FAILED: anon can run fn_sales_engineer_rematch_told'
  when position('rematch,exhausted' in pg_get_functiondef('public.fn_sales_engineer_closes_unreached_requests(timestamptz)'::regprocedure)) = 0
    then 'PROBE FAILED: the unreached closer does not wait for the re-match'
  else 'PROBE OK' end as verdict;
