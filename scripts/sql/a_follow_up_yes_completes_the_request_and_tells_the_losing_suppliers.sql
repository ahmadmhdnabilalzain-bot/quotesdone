-- Seat: sales_engineer. Assigned: sales_engineer (customer-journey follow-up, 10 Nov 2026; founder ruling 1608).
--
-- MEASURED on origin/main (fn_customer_followup_answer, canonical in
-- customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades.sql, read back equal to
-- production): the day-3 / day-14 follow-up's "yes, I hired them" set inquiries.hired_supplier_id and nothing else. The
-- request stayed 'revealed' with no outcome and no completed_at, and the losing suppliers were never told. #1899 fixed the
-- Hire door (customer_api lib/hire.ts) so a Hire pressed AFTER such a yes completes it; this fixes the yes itself.
--
-- WHAT THIS CHANGES: a yes writes what Hire writes (status 'completed', outcome 'hired', completed_at, hired_supplier_id),
-- guarded the same way (not completed, not awarded to another supplier), and tells every other supplier who quoted, once
-- (fn_sales_engineer_tells_losing_suppliers, new: the job_awarded_other notice Hire's notifyLosers sends, keyed per
-- supplier). Either door may come first; the losers are told once. "no" and "not yet" are unchanged.
-- NOT CHANGED: the rating, the outcome records, the answer's idempotency (the first definite answer stands).
-- The losers' notice quotes no customer text: SQL has no identity scrubber, so it names the trade and the request number,
-- both platform values (customer_api's notifyLosers falls back to the same kind of phrase when it cannot scrub).
-- prevented by: scripts/checks/a_follow_up_yes_completes_the_request.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_follow_up_yes_completes_the_request_and_tells_the_losing_suppliers.txt

create or replace function public.fn_sales_engineer_tells_losing_suppliers(p_inquiry uuid, p_winner bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; c public.customers; v_fx boolean; l record; v_job text; v_why text; v_d jsonb; v_told int := 0; v_not int := 0;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('told', 0, 'reason', 'no such request'); end if;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  v_job := 'the ' || coalesce(public.fn_trade_label(i.category, 'en'), 'job') || coalesce(' job in ' || nullif(btrim(i.emirate), ''), ' job')
           || ' (request ' || coalesce(i.rfq_no::text, '-') || ')';
  for l in select le.id, lower(btrim(coalesce(le.email, ''))) as to_email
             from (select distinct q.supplier_id from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id is distinct from p_winner) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id) loop
    v_why := public.fn_seat_clock_refusal(v_fx, l.to_email, 'job_awarded_other');
    if v_why is not null then v_not := v_not + 1; continue; end if;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'job_awarded_other', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', l.to_email, 'to_role', 'supplier',
      'lead_id', l.id, 'inquiry_id', p_inquiry, 'lang', 'en', 'subject', 'Update on a job you quoted — QuotesDone',
      'body', 'Thank you for taking the time to quote on ' || v_job || '. On this occasion the customer has chosen to proceed with another supplier. We genuinely appreciate the effort you put into your quote, and it was great having you compete for the work. New matching opportunities come through QuotesDone regularly — please keep an eye on your supplier inbox, and we wish you the very best of luck on the next one.',
      'dedupe_key', 'job_awarded_other:' || p_inquiry || ':' || l.id)));
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'claimed') then v_told := v_told + 1; else v_not := v_not + 1; end if;
  end loop;
  return jsonb_build_object('told', v_told, 'not_told', v_not);
end $fn$;
revoke execute on function public.fn_sales_engineer_tells_losing_suppliers(uuid, bigint) from public, anon, authenticated;

create or replace function public.fn_customer_followup_answer(p_token uuid, p_hired text, p_stars integer default null,
  p_comment text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.customer_followup; t public.transactions; v_comment text; v_reason text; v_out jsonb := '{}'::jsonb; v_won int := 0;
begin
  if p_hired is null or p_hired not in ('yes', 'no', 'not_yet') then
    raise exception 'hired is yes, no or not_yet' using errcode = '22023';
  end if;
  if p_stars is not null and p_stars not between 1 and 5 then
    raise exception 'stars are 1 to 5' using errcode = '22023';
  end if;
  select * into f from public.customer_followup where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  -- the first definite answer stands; a second tap on an old e-mail changes nothing
  if f.hired in ('yes', 'no') then return jsonb_build_object('ok', true, 'already', true, 'hired', f.hired); end if;
  select * into t from public.transactions where id = f.transaction_id;
  v_comment := nullif(left(btrim(coalesce(p_comment, '')), 1000), '');

  if p_hired in ('yes', 'no') then
    v_reason := 'customer answered on ' || replace(f.stage, '_', ' ') || ': '
      || case when p_hired = 'yes' then 'hired the revealed supplier' else 'did not hire the revealed supplier' end
      || coalesce(', rated ' || p_stars || '/5', '') || coalesce(': ' || left(v_comment, 300), '');
    if t.inquiry_id is not null then
      v_out := v_out || jsonb_build_object('inquiry', public.fn_outcome_record('inquiries', t.inquiry_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'inquiry', null));
    end if;
    if t.quote_id is not null then
      v_out := v_out || jsonb_build_object('quote', public.fn_outcome_record('quotes', t.quote_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'quote', null));
    end if;
    -- 10 Nov 2026 (sales_engineer): "yes, I hired them" COMPLETES the request, exactly as the portal's Hire does
    -- (customer_api complete_inquiry: status, outcome, completed_at, hired_supplier_id), and tells the losing suppliers.
    -- It wrote hired_supplier_id ONLY, so the request stayed 'revealed' for good and nobody was told. The write is the
    -- lock, as Hire's: only a request not yet completed, and not awarded to another supplier, changes. A Hire pressed
    -- after this finds the same supplier completed and sends nothing (lib/hire.ts already_completed); a yes after Hire
    -- changes no row, so the losers are told once whichever door came first.
    if p_hired = 'yes' and t.inquiry_id is not null then
      update public.inquiries
         set status = 'completed', outcome = 'hired', completed_at = coalesce(completed_at, now()), hired_supplier_id = t.supplier_id
       where id = t.inquiry_id and (hired_supplier_id is null or hired_supplier_id = t.supplier_id)
         and coalesce(status, '') <> 'completed';
      get diagnostics v_won = row_count;
      if v_won > 0 then
        v_out := v_out || jsonb_build_object('completed', true, 'losers', public.fn_sales_engineer_tells_losing_suppliers(t.inquiry_id, t.supplier_id));
      end if;
    end if;
  end if;

  -- HOW WAS THE SUPPLIER: one rating per reveal. reviews_reason_required wants ten characters or no comment.
  if p_stars is not null and not exists (select 1 from public.reviews r where r.transaction_id = t.id) then
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
    values (t.supplier_id, t.customer_id, t.inquiry_id, t.id, p_stars, case when length(v_comment) >= 10 then v_comment end);
    v_out := v_out || jsonb_build_object('review', true);
  end if;

  update public.customer_followup
     set answered_at = now(), hired = p_hired, stars = coalesce(p_stars, stars), comment = coalesce(v_comment, comment), outcome = v_out
   where id = f.id;
  return jsonb_build_object('ok', true, 'hired', p_hired, 'recorded', v_out);
end $fn$;

select case
  when has_function_privilege('anon', 'public.fn_sales_engineer_tells_losing_suppliers(uuid, bigint)', 'execute') then 'PROBE FAILED: anon can run the losers notice'
  when position('fn_sales_engineer_tells_losing_suppliers' in pg_get_functiondef('public.fn_customer_followup_answer(uuid, text, integer, text)'::regprocedure)) = 0
    then 'PROBE FAILED: the follow-up yes does not complete the request'
  else 'PROBE OK' end as verdict;
