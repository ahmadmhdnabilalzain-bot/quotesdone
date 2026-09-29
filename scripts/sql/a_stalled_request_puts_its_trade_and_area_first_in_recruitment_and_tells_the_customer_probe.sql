-- PROBE (pure, no DDL, aborted transaction) for a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer.sql.
-- Run AFTER that file, in the same transaction (while it is pending), or on its own once it is applied. It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Subjects: ZZ DEMO customers and one ZZ DEMO supplier at
-- @example.invalid, created here. Needs #1105's file (public.stalled_inquiry_rescue, fn_stalled_inquiry_flag) applied or run first. Real leads are only READ (the invitation queue's order); nothing is written to one, and
-- the only message this probe causes goes to an @example.invalid address, which the outbox records 'suppressed'.
do $$
declare
  c_ar uuid; c_en uuid; sup bigint; a uuid; b uuid; cq uuid; d uuid; e uuid; fl jsonb; sup2 bigint; f text := ''; o jsonb := '{}';
  r1 jsonb; r2 jsonb; r3 jsonb; n jsonb; base bigint[]; fix bigint[]; top bigint[]; v int; v_inv_before int; v_inv_after int;
  v_ranks int[]; v_key text;
begin
  select count(*) into v_inv_before from public.notifications where type = 'supplier_invite' and not public.fn_is_demo_email(to_email);
  base := array(select c.lead_id from public.fn_supplier_invite_candidates(10) c);

  insert into public.customers (full_name, email, locale) values ('ZZ DEMO rescue ar', 'zz-demo-rescue-ar@example.invalid', 'ar') returning id into c_ar;
  insert into public.customers (full_name, email, locale) values ('ZZ DEMO rescue en', 'zz-demo-rescue-en@example.invalid', 'en') returning id into c_en;
  insert into public.leads (company_name, email) values ('ZZ DEMO — rescue matched supplier', 'zz-demo-rescue-sup@example.invalid') returning id into sup;

  -- A: Arabic request, electrical in Ajman (NOT marketing's first plan, so the rescue has to move the queue), matched 50 h ago, no quote -> rescued, told in Arabic
  insert into public.inquiries (customer_id, category, trades, emirate, lang, status, summary, created_at)
    values (c_ar, 'electrical', array['electrical'], 'Ajman', 'ar', 'sent', 'ZZ DEMO rescue A', now() - interval '3 days') returning id into a;
  -- B: matched 20 h ago -> too early
  insert into public.inquiries (customer_id, category, trades, emirate, lang, status, summary, created_at)
    values (c_en, 'painting', array['painting'], 'Dubai', 'en', 'sent', 'ZZ DEMO rescue B', now() - interval '1 day') returning id into b;
  -- C: matched 50 h ago but a supplier has a (held) draft quote -> answered, not stalled
  insert into public.inquiries (customer_id, category, trades, emirate, lang, status, summary, created_at)
    values (c_en, 'painting', array['painting'], 'Dubai', 'en', 'sent', 'ZZ DEMO rescue C', now() - interval '3 days') returning id into cq;
  -- D: English request in a trade nobody can be invited for -> rescued, nobody to invite, marketing's finding
  insert into public.inquiries (customer_id, category, trades, emirate, lang, status, summary, created_at)
    values (c_en, 'zz_demo_trade', array['zz_demo_trade'], 'Ajman', 'en', 'sent', 'ZZ DEMO rescue D', now() - interval '3 days') returning id into d;
  -- E: sent to nobody (no match): #1105's intake flags it 'no_reachable_supplier'; the ONE rescue routine acts on it too
  insert into public.inquiries (customer_id, category, trades, emirate, lang, status, summary, created_at)
    values (c_en, 'painting', array['painting'], 'Dubai', 'en', 'sent', 'ZZ DEMO rescue E', now() - interval '1 hour') returning id into e;

  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason, sent_at) values
    (a, sup, 0.9, 'ZZ DEMO', now() - interval '50 hours'), (b, sup, 0.9, 'ZZ DEMO', now() - interval '20 hours'),
    (cq, sup, 0.9, 'ZZ DEMO', now() - interval '50 hours'), (d, sup, 0.9, 'ZZ DEMO', now() - interval '50 hours');
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (cq, sup, 1000, 'draft');

  fl := public.fn_stalled_inquiry_flag(e, 'zz demo probe');
  if not coalesce((fl->>'flagged')::boolean, false) then f := f || '#1105''s intake did not flag E; '; end if;

  -- the daily run skips fixtures entirely
  r1 := public.fn_sales_engineer_stalled_inquiry_rescue(false);
  if exists (select 1 from public.stalled_inquiry_rescue where inquiry_id in (a, b, cq, d) and reason = 'no_quote_48h') or exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = e and acted_at is not null) then f := f || 'the daily run rescued a fixture; '; end if;

  r1 := public.fn_sales_engineer_stalled_inquiry_rescue(true);
  o := o || jsonb_build_object('run1', r1);
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = a and uninvited_pool > 0 and 'electrical' = any(trades)
                   and emirate = 'Ajman' and fixture and cleared_at is null and reason = 'no_quote_48h') then f := f || 'A was not rescued with its pool; '; end if;
  if exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = b) then f := f || 'B was rescued before 48 h; '; end if;
  if exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = cq) then f := f || 'C was rescued although a supplier answered; '; end if;
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = d and uninvited_pool = 0) then f := f || 'D was not rescued with an empty pool; '; end if;
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = e and reason = 'no_reachable_supplier' and acted_at is not null
                   and uninvited_pool > 0 and cleared_at is null) then f := f || 'the rescue did not act on #1105''s unreachable request E; '; end if;
  select plan_rank into v from public.stalled_inquiry_rescue where inquiry_id = a;
  if v is null then f := f || 'A carries no marketing rank although electrical is planned; '; end if;

  -- the customer: once, in the request's language, honest about the pool
  select to_jsonb(x) into n from (select lang, subject, body, status, to_email from public.notifications
                                    where type = 'inquiry_rescue_update' and inquiry_id = a) x;
  o := o || jsonb_build_object('notice_a', n);
  if n is null or n->>'lang' <> 'ar' or n->>'body' !~ 'تحية طيبة وبعد' or n->>'body' !~ 'قدّمنا مجال طلبكم'
     or n->>'to_email' <> 'zz-demo-rescue-ar@example.invalid' then f := f || 'A''s customer was not told in Arabic that the trade is first; '; end if;
  select to_jsonb(x) into n from (select lang, body from public.notifications where type = 'inquiry_rescue_update' and inquiry_id = d) x;
  if n is null or n->>'lang' <> 'en' or n->>'body' !~ 'sourcing new ones' then f := f || 'D''s customer was not told in English that suppliers are being sourced; '; end if;
  if (select count(*) from public.notifications where type = 'inquiry_rescue_update' and inquiry_id in (b, cq)) > 0 then
    f := f || 'B or C''s customer was written to; '; end if;
  select to_jsonb(x) into n from (select lang, body from public.notifications where type = 'inquiry_rescue_update' and inquiry_id = e) x;
  if n is null or n->>'lang' <> 'en' or n->>'body' !~ 'has not yet reached a supplier who can quote it' then
    f := f || 'E''s customer was not told that nobody can take the request on now; '; end if;

  -- ONE SUBJECT, ONE HOME: #1105''s intake clears only its own reason. A''s supplier becomes reachable; A stays rescued.
  -- (a ZZ DEMO supplier that IS matchable - verified, approved, demo - is matched to A too; nothing is written to it)
  select l.id into sup2 from public.leads l
   where public.fn_seat_clock_lead_is_fixture(l) and coalesce(l.is_demo, false)
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
   order by l.id limit 1;
  if sup2 is null then f := f || 'no matchable ZZ DEMO supplier to make A reachable; ';
  else
    insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason, sent_at) values (a, sup2, 0.9, 'ZZ DEMO', now() - interval '50 hours');
    fl := public.fn_stalled_inquiry_flag(a, 'zz demo probe');
    o := o || jsonb_build_object('flag_a_reachable', fl - 'detail');
    if coalesce((fl->>'reachable')::int, 0) < 1 then f := f || 'A did not become reachable, so the clearing case was not exercised; '; end if;
  end if;
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = a and reason = 'no_quote_48h' and cleared_at is null) then
    f := f || '#1105''s intake cleared the no-quote rescue of a reachable-but-silent request; '; end if;
  if exists (select 1 from pg_class where relname = 'inquiry_rescue' and relnamespace = 'public'::regnamespace) then
    f := f || 'a second rescue table exists; '; end if;

  -- nobody to invite: marketing's finding, raised by the sales engineer
  select finding_key into v_key from public.stalled_inquiry_rescue where inquiry_id = d;
  if not exists (select 1 from public.it_engineer_finding where issue_key = v_key and closed_at is null and evidence->>'owner_seat' = 'marketing') then
    f := f || 'no open marketing finding for the empty pool; '; end if;

  -- suppliers: nothing but English, and no invitation while the founder's go switch is off
  if exists (select 1 from public.notifications where to_role = 'supplier' and coalesce(lang, 'en') <> 'en' and created_at = now()) then
    f := f || 'a supplier row in this transaction is not English; '; end if;

  -- once only
  r2 := public.fn_sales_engineer_stalled_inquiry_rescue(true);
  if (r2->>'flagged_no_quote')::int <> 0 or (r2->>'acted')::int <> 0
     or (select count(*) from public.notifications where type = 'inquiry_rescue_update' and inquiry_id in (a, d, e)) <> 3 then
    f := f || 'a second run opened again or wrote a second update; '; end if;

  -- a FIXTURE rescue never moves the real queue
  fix := array(select c.lead_id from public.fn_supplier_invite_candidates(10) c);
  if fix is distinct from base then f := f || 'a fixture rescue moved the real invitation queue; '; end if;

  -- a REAL rescue puts its trade and area first, in marketing's order (made real inside this aborted transaction only)
  update public.stalled_inquiry_rescue set fixture = false where inquiry_id = a;
  top := array(select c.lead_id from public.fn_supplier_invite_candidates(10) c);
  o := o || jsonb_build_object('top10', to_jsonb(top), 'before', to_jsonb(base));
  if cardinality(top) < 10 or exists (select 1 from unnest(top) t(id) join public.leads l on l.id = t.id
                                       where not ('electrical' = any(coalesce(l.invite_trades, '{}'::text[])) and l.emirate = 'Ajman')) then
    f := f || 'the rescued trade and area are not first in the queue; '; end if;
  if top is not distinct from base then f := f || 'the real rescue did not move the queue at all, so the test above proves nothing; '; end if;
  v_ranks := array(select coalesce((select min(p.rank) from public.marketing_gap_recruitment_plan p
                                     where p.trade = any(coalesce(l.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = l.emirate)), 2147483647)
                     from unnest(top) with ordinality t(id, k) join public.leads l on l.id = t.id order by t.k);
  if exists (select 1 from generate_subscripts(v_ranks, 1) i where i > 1 and v_ranks[i] < v_ranks[i - 1]) then
    f := f || 'inside the rescue tier the queue does not follow marketing''s gap ranking; '; end if;
  -- ... and the one door still holds: with the go switch off nothing is queued
  if coalesce((select value from public.app_secrets where key = 'invite_enabled'), 'false') <> 'true'
     and public.enqueue_supplier_invites() <> 0 then f := f || 'enqueue queued while the go switch is off; '; end if;
  select count(*) into v_inv_after from public.notifications where type = 'supplier_invite' and not public.fn_is_demo_email(to_email);
  if v_inv_after <> v_inv_before then f := f || 'a real invitation was queued; '; end if;

  -- the rescue ends: A is quoted, D is cancelled; the finding closes with it
  update public.stalled_inquiry_rescue set fixture = true where inquiry_id = a;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (a, sup, 2000, 'draft');
  update public.inquiries set status = 'cancelled' where id = d;
  r3 := public.fn_sales_engineer_stalled_inquiry_rescue(true);
  o := o || jsonb_build_object('run3', r3);
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = a and cleared_why = 'quoted') then f := f || 'A''s rescue did not end on its quote; '; end if;
  if not exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = d and cleared_why = 'request closed') then f := f || 'D''s rescue did not end with the request; '; end if;
  if exists (select 1 from public.it_engineer_finding where issue_key = v_key and closed_at is null) then f := f || 'the empty-pool finding stayed open; '; end if;

  -- clean up and assert it is gone (the rollback below is the second guarantee)
  delete from public.notifications where inquiry_id in (a, b, cq, d, e);
  delete from public.quotes where inquiry_id in (a, b, cq, d, e);
  delete from public.inquiries where id in (a, b, cq, d, e);
  delete from public.leads where id = sup;
  delete from public.customers where id in (c_ar, c_en);
  if exists (select 1 from public.stalled_inquiry_rescue where inquiry_id in (a, b, cq, d, e)) then f := f || 'cleanup left a rescue row; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end, 'steps', o)::text;
end $$;
