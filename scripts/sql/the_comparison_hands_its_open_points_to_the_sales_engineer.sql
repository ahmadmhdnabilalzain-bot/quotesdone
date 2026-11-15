-- THE COMPARISON HANDS ITS OPEN POINTS TO THE SALES ENGINEER (sales_engineer, 15 Nov 2026; the CEO's decision under founder
-- ruling 1696, on the final review of the comparison branch, FIX 1).
--
-- quote_compare measures each quote against what the customer asked for (supabase/functions/_shared/request_fit.ts) and
-- finds the points a quote leaves open ("Is this price final, or subject to the site visit?"). The first wiring wrote a
-- code-made engineer message into the supplier's quotation conversation. Rulings 1195-1197 and 1339 say an engineer message
-- there is written by a model, in its turn, never by code; a submitted conversation could not take the supplier's answer; and
-- the review's auto-close marked the points answered without one. Now:
--   1. quote_compare files ONE hand-over per quote, kind 'comparison.points', sales_engineer -> sales_engineer, through
--      public.fn_seat_handoff (one per kind and subject: the quote; never again on the next view). It files nothing once a
--      supplier is revealed on the request or the request is at an end (request_fit.ts mayRaisePoints), and this handler
--      checks the same again.
--   2. The handler records each point as an open clarification (code 'comparison_point') in the supplier's quotation
--      conversation, in the same transaction as the hand-over row: there is no message, so nothing is said before the rows
--      exist. The sales engineer's model turns read the points there and raise them; a submitted conversation takes the
--      supplier's text answer while one is open (supplier_api quote_review_flow); the review's auto-close never closes one.
--      A quote with no conversation stays on the seat's desk, waiting for the sales engineer to ask the supplier.
--   3. The supplier's answer closes the point (answered_message_id), quote_compare shows it to the customer on the next view,
--      and fn_sales_engineer_comparison_points_answered closes the hand-over once no point of that conversation is open.
--   4. THE SUPPLIER IS TOLD ONCE (COMPARE4, gap 1 of the COMPARE3 hand-back). A supplier who already SUBMITTED does not sit
--      in the conversation, so points added to a submitted conversation would wait unseen. The handler then asks
--      customer_support for ONE notice (fn_sales_engineer_comparison_points_notice), the way the sales engineer's other
--      notices about a supplier's own quotation go (fn_sales_engineer_quote_quality_tick's quote_quality_fixes; the hold
--      desk's quote_spec_hold): public.fn_customer_support_takes_delivery, requested_by sales_engineer, to_role supplier,
--      English only (ruling 1008; z05 refuses anything else), the address checked by fn_seat_clock_refusal (suppression,
--      unsubscribe, a dead domain, a fixture subject never writing to a real address and the reverse), keyed
--      'quote_comparison_points:<quote>:<the point set>' and refused when fn_seat_clock_asked already holds that key: one
--      notice per quote per point set, never repeated. Its WhatsApp twin is trg_wa_fanout's, to a confirmed number the
--      supplier agreed to only (a03), on the supplier_account_notice template (send_whatsapp templates.ts; held queued until its SID is approved); at send,
--      send_outbox re-reads the suppressions and send_whatsapp the WhatsApp opt-out. The notice names the request number,
--      the trade and the emirate the supplier was invited on, and how many points: never the customer, never the points'
--      text. Its outcome is kept on the hand-over (detail.notice).
--   5. NOTHING IS ASKED AFTER THE DECISION (COMPARE4, gap 2). The moment the customer reveals any supplier on the request
--      (transactions.revealed_at) or the request is revealed or concluded (inquiries.status: _shared/request_closed.ts, the
--      one list), fn_sales_engineer_comparison_points_supersede closes every open comparison point of that request as
--      'superseded' with its reason (closed_reason), closes each open comparison.points hand-over with the same reason, and
--      cancels a notice still queued. Two triggers call it, so every door that reveals or ends a request does, with no list
--      of doors to keep in step (the pattern of a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.sql).
-- Tests: supabase/functions/_shared/request_fit.review.test.ts (6), supabase/functions/supplier_api/
-- the_comparison_points_are_answered_only_by_the_supplier.test.ts, supabase/functions/quote_compare/
-- the_comparison_points_tell_the_supplier_once_and_stop_at_the_decision.test.ts, supabase/functions/send_whatsapp/
-- comparison_points_notice.test.ts;
-- the probe: the_comparison_hands_its_open_points_to_the_sales_engineer_probe.sql (local Postgres 16, never production).

-- why a point stopped being asked when it was not answered (gap 2): the rows closed as superseded carry it
alter table public.quote_review_request add column if not exists closed_reason text;

-- The one notice to a supplier whose SUBMITTED quotation conversation was just given comparison points.
create or replace function public.fn_sales_engineer_comparison_points_notice(p_id bigint, p_review uuid, p_keys text[])
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; v_quote uuid; v_inquiry uuid; v_supplier bigint; v_status text; v_to text; v_name text; v_banned boolean;
  v_cat text; v_em text; v_trade text; v_site text; v_ref text; v_key text; v_why text; v_n int; v_subj text; v_body text; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail ->> 'type' = 'comparison.points';
  if not found then return jsonb_build_object('sent', false, 'reason', 'no comparison.points hand-over ' || coalesce(p_id::text, 'null')); end if;
  v_n := coalesce(cardinality(p_keys), 0);
  if v_n = 0 then return jsonb_build_object('sent', false, 'reason', 'no new point'); end if;
  select r.status, r.inquiry_id, r.supplier_id into v_status, v_inquiry, v_supplier from public.quote_reviews r where r.id = p_review;
  if v_status is distinct from 'submitted' then
    return jsonb_build_object('sent', false, 'reason', 'the conversation is not submitted: the sales engineer raises the points in it');
  end if;
  begin v_quote := (a.detail ->> 'quote_id')::uuid; exception when others then v_quote := null; end;
  -- never after the decision: the same test as the handler (and the supersede triggers)
  if exists (select 1 from public.inquiries i where i.id = v_inquiry
               and i.status in ('revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost'))
     or exists (select 1 from public.transactions t where t.inquiry_id = v_inquiry and t.revealed_at is not null) then
    return jsonb_build_object('sent', false, 'reason', 'the customer has already chosen, or the request is closed');
  end if;
  select lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), l.company_name, coalesce(l.banned, false)
    into v_to, v_name, v_banned from public.leads l where l.id = v_supplier;
  if v_banned then return jsonb_build_object('sent', false, 'reason', 'the supplier is banned'); end if;
  v_key := 'quote_comparison_points:' || coalesce(v_quote::text, p_review::text) || ':'
           || left(md5(array_to_string(array(select distinct k from unnest(p_keys) k order by 1), '|')), 12);
  v_why := public.fn_seat_clock_refusal(public.fn_inquiry_is_demo(v_inquiry), v_to, 'quote_comparison_points');
  if v_why is null and public.fn_seat_clock_asked(v_key) then v_why := 'already sent'; end if;
  if v_why is not null then return jsonb_build_object('sent', false, 'reason', v_why, 'dedupe_key', v_key); end if;

  select i.category, nullif(btrim(coalesce(i.emirate, '')), '') into v_cat, v_em from public.inquiries i where i.id = v_inquiry;
  select t.label into v_trade from public.taxonomy_trade t where t.code = (public.fn_taxonomy_trades_for(array[coalesce(v_cat, '')]))[1];
  v_trade := coalesce(v_trade, nullif(btrim(coalesce(v_cat, '')), ''), 'your trade');
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_ref := coalesce('QD-' || nullif(public.fn_job_no(v_inquiry), ''), 'the request');
  -- English only (ruling 1008): an Arabic-script company name, trade or emirate is left out, never written into the letter
  if v_name ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then v_name := null; end if;
  if v_trade ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then v_trade := 'your trade'; end if;
  if v_em ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then v_em := null; end if;
  v_subj := 'The sales engineer has a question about your quotation for ' || v_ref || ' — ' || v_trade || coalesce(' in ' || v_em, '');
  v_body := coalesce('Dear ' || nullif(btrim(coalesce(v_name, '')), '') || ',', 'Dear Sir or Madam,') || E'

'
    || 'QuotesDone''s sales engineer compared the quotation you submitted for request ' || v_ref || ' (' || v_trade
    || coalesce(' in ' || v_em, '') || ') with what was asked for, and has '
    || case when v_n = 1 then 'one point' else v_n || ' points' end || ' for you to confirm. '
    || case when v_n = 1 then 'It is' else 'They are' end
    || ' in the quotation''s conversation with the sales engineer in your supplier portal: please open it and answer there. '
    || 'Your quotation stays as you submitted it.'
    || E'

' || coalesce(v_site, 'https://quotesdone.com') || '/en/portal';
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'quote_comparison_points', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to,
    'to_role', 'supplier', 'lead_id', v_supplier, 'inquiry_id', v_inquiry, 'quote_id', v_quote,
    'lang', 'en', 'subject', v_subj, 'body', v_body, 'dedupe_key', v_key)));
  -- queued means customer_support has the row (a demo capture included); a refused request says why and is not "asked", so a
  -- later raise of the same point set may try again
  return jsonb_build_object('sent', (v -> 0 ->> 'notification_id') is not null, 'dedupe_key', v_key, 'points', v_n, 'delivery', v -> 0)
    || case when (v -> 0 ->> 'notification_id') is null
            then jsonb_build_object('reason', coalesce(v -> 0 ->> 'error', 'customer_support queued nothing')) else '{}'::jsonb end;
end $fn$;
revoke execute on function public.fn_sales_engineer_comparison_points_notice(bigint, uuid, text[]) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_comparison_points_raise(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; v_quote_id uuid; v_inquiry uuid; v_supplier bigint; v_review uuid; v_pt jsonb; v_n int := 0;
  v_keys text[] := '{}'; v_notice jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then return null; end if;
  begin v_quote_id := (a.detail ->> 'quote_id')::uuid; exception when others then v_quote_id := null; end;
  select q.inquiry_id, q.supplier_id into v_inquiry, v_supplier from public.quotes q where q.id = v_quote_id;
  if v_inquiry is null or v_supplier is null then
    return jsonb_build_object('raised', 0, 'reason', 'the quote is not on file');
  end if;
  -- never after a reveal, nor once the request is a live deal or at an end (_shared/request_closed.ts, the one list)
  if exists (select 1 from public.inquiries i where i.id = v_inquiry
               and i.status in ('revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost'))
     or exists (select 1 from public.transactions t where t.inquiry_id = v_inquiry and t.revealed_at is not null) then
    return jsonb_build_object('raised', 0, 'reason', 'the customer has already chosen, or the request is closed');
  end if;
  select r.id into v_review from public.quote_reviews r
   where r.inquiry_id = v_inquiry and r.supplier_id = v_supplier and r.status <> 'closed';
  if v_review is null then
    return jsonb_build_object('raised', 0,
      'waiting', 'the sales engineer to ask the supplier these points: the quotation has no conversation with the sales engineer');
  end if;
  for v_pt in select * from jsonb_array_elements(case when jsonb_typeof(a.detail -> 'points') = 'array' then a.detail -> 'points' else '[]'::jsonb end) loop
    continue when coalesce(btrim(v_pt ->> 'key'), '') = '' or coalesce(btrim(v_pt ->> 'supplier'), '') = '';
    -- a point is raised once in a conversation, in any state: answered is answered
    continue when exists (select 1 from public.quote_review_request x where x.review_id = v_review and x.key = left(v_pt ->> 'key', 120));
    insert into public.quote_review_request (review_id, key, code, kind, label_en, label_ar)
    values (v_review, left(v_pt ->> 'key', 120), 'comparison_point', 'clarification', left(v_pt ->> 'supplier', 600), left(v_pt ->> 'supplier', 600));
    v_n := v_n + 1;
    v_keys := v_keys || left(v_pt ->> 'key', 120);
  end loop;
  update public.agent_actions set detail = detail || jsonb_build_object('review_id', v_review) where id = p_id;
  -- a SUBMITTED supplier is told once that the points are waiting (gap 1). A notice that cannot be queued never undoes the
  -- points: its reason stays on the hand-over, which waits on the seat's desk with reply_within.
  if v_n > 0 then
    begin
      v_notice := public.fn_sales_engineer_comparison_points_notice(p_id, v_review, v_keys);
    exception when others then
      v_notice := jsonb_build_object('sent', false, 'reason', 'the notice could not be queued: ' || left(sqlerrm, 300));
    end;
    update public.agent_actions set detail = detail || jsonb_build_object('notice', v_notice) where id = p_id;
  end if;
  if v_n = 0 and not exists (select 1 from public.quote_review_request x
                              where x.review_id = v_review and x.code = 'comparison_point' and x.state = 'open') then
    return jsonb_build_object('raised', 0, 'review_id', v_review, 'reason', 'every point was already asked and answered in this conversation');
  end if;
  return jsonb_build_object('raised', v_n, 'review_id', v_review, 'notice', v_notice,
    'waiting', 'the supplier to answer the comparison''s open points in the quotation conversation');
end $fn$;
revoke execute on function public.fn_sales_engineer_comparison_points_raise(bigint) from public, anon, authenticated;

-- The supplier answered the last open point of a conversation: its comparison hand-overs are done.
create or replace function public.fn_sales_engineer_comparison_points_answered(p_review_id uuid)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_n int := 0;
begin
  if p_review_id is null or exists (select 1 from public.quote_review_request x
                                     where x.review_id = p_review_id and x.code = 'comparison_point' and x.state = 'open') then
    return 0;
  end if;
  for v_id in select id from public.agent_actions
               where kind = 'handoff' and agent = 'sales_engineer' and detail ->> 'type' = 'comparison.points'
                 and detail ->> 'review_id' = p_review_id::text and status not in ('done', 'failed') loop
    perform public.fn_seat_handoff_complete(v_id, jsonb_build_object('answered', true, 'review_id', p_review_id,
      'by', 'the supplier''s answer in the quotation conversation'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_sales_engineer_comparison_points_answered(uuid) from public, anon, authenticated;

-- The decision supersedes every point still open on the request (gap 2): nothing is asked after the reveal or the end.
create or replace function public.fn_sales_engineer_comparison_points_supersede(p_inquiry uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_reason text := coalesce(nullif(btrim(p_reason), ''), 'the request moved on'); v_rows int := 0; v_handoffs int := 0; v_notices int := 0; v_id bigint;
begin
  if p_inquiry is null then return jsonb_build_object('points', 0, 'handoffs', 0, 'notices', 0); end if;
  update public.quote_review_request x
     set state = 'superseded', answered_at = now(), closed_reason = left(v_reason, 300)
    from public.quote_reviews r
   where r.id = x.review_id and r.inquiry_id = p_inquiry and x.code = 'comparison_point' and x.state = 'open';
  get diagnostics v_rows = row_count;
  for v_id in select a.id from public.agent_actions a
               where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.detail ->> 'type' = 'comparison.points'
                 and a.status not in ('done', 'failed')
                 and (a.detail ->> 'inquiry_id' = p_inquiry::text
                      or a.detail ->> 'quote_id' in (select q.id::text from public.quotes q where q.inquiry_id = p_inquiry)) loop
    perform public.fn_seat_handoff_complete(v_id, jsonb_build_object('superseded', true, 'reason', left(v_reason, 300),
      'by', 'the customer''s decision on the request: nothing more is asked of the supplier'));
    v_handoffs := v_handoffs + 1;
  end loop;
  update public.notifications n
     set status = 'cancelled', last_error = left('not sent: the comparison point it announced was superseded (' || v_reason || ')', 500)
   where n.type = 'quote_comparison_points' and n.inquiry_id = p_inquiry and n.status in ('queued', 'held');
  get diagnostics v_notices = row_count;
  return jsonb_build_object('points', v_rows, 'handoffs', v_handoffs, 'notices', v_notices, 'reason', v_reason);
end $fn$;
revoke execute on function public.fn_sales_engineer_comparison_points_supersede(uuid, text) from public, anon, authenticated;

create or replace function public.trg_request_decision_supersedes_comparison_points()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(NEW.status, '') in ('revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost')
     and NEW.status is distinct from OLD.status then
    perform public.fn_sales_engineer_comparison_points_supersede(NEW.id,
      case when NEW.status = 'revealed' then 'the customer revealed a supplier on this request'
           else 'the request is ' || NEW.status end);
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_request_decision_supersedes_comparison_points() from public, anon, authenticated;
drop trigger if exists z33_request_decision_supersedes_comparison_points on public.inquiries;
create trigger z33_request_decision_supersedes_comparison_points after update of status on public.inquiries
  for each row execute function public.trg_request_decision_supersedes_comparison_points();

create or replace function public.trg_reveal_supersedes_comparison_points()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.revealed_at is not null and NEW.inquiry_id is not null
     and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    perform public.fn_sales_engineer_comparison_points_supersede(NEW.inquiry_id, 'the customer revealed a supplier on this request');
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_reveal_supersedes_comparison_points() from public, anon, authenticated;
drop trigger if exists z31_reveal_supersedes_comparison_points on public.transactions;
create trigger z31_reveal_supersedes_comparison_points after insert or update of revealed_at on public.transactions
  for each row execute function public.trg_reveal_supersedes_comparison_points();

-- what is already decided when this is applied (production on 15 Nov 2026: the kind is unregistered, so none; run anyway)
select public.fn_sales_engineer_comparison_points_supersede(r.inquiry_id,
         case when i.status = 'revealed' or exists (select 1 from public.transactions t where t.inquiry_id = r.inquiry_id and t.revealed_at is not null)
              then 'the customer revealed a supplier on this request' else 'the request is ' || i.status end)
  from (select distinct v.inquiry_id from public.quote_review_request x join public.quote_reviews v on v.id = x.review_id
         where x.code = 'comparison_point' and x.state = 'open') r
  join public.inquiries i on i.id = r.inquiry_id
 where i.status in ('revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost')
    or exists (select 1 from public.transactions t where t.inquiry_id = r.inquiry_id and t.revealed_at is not null);

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('comparison.points', 'sales_engineer', 'sales_engineer',
        'The comparison found points a quote leaves open against the customer''s request: the sales engineer asks the supplier to confirm them, and the answer joins the comparison.',
        'fn_sales_engineer_comparison_points_raise', interval '72 hours', false,
        'scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql')
on conflict (type, from_seat, to_seat) do update set handler = excluded.handler, meaning = excluded.meaning,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

select case when not exists (select 1 from public.seat_handoff_kind
                              where type = 'comparison.points' and to_seat = 'sales_engineer'
                                and handler = 'fn_sales_engineer_comparison_points_raise')
            then 'PROBE FAILED: comparison.points not registered to the sales engineer handler'
            when has_function_privilege('anon', 'public.fn_sales_engineer_comparison_points_raise(bigint)', 'execute')
              or has_function_privilege('anon', 'public.fn_sales_engineer_comparison_points_answered(uuid)', 'execute')
            then 'PROBE FAILED: anon can execute a comparison.points routine'
            when exists (select 1 from (values ('public.fn_sales_engineer_comparison_points_notice(bigint,uuid,text[])'),
                                               ('public.fn_sales_engineer_comparison_points_supersede(uuid,text)'),
                                               ('public.trg_request_decision_supersedes_comparison_points()'),
                                               ('public.trg_reveal_supersedes_comparison_points()')) f(sig)
                          where has_function_privilege('anon', f.sig, 'execute') or has_function_privilege('authenticated', f.sig, 'execute'))
            then 'PROBE FAILED: anon or authenticated can execute a comparison.points notice or supersede routine'
            when not exists (select 1 from pg_trigger where tgname = 'z33_request_decision_supersedes_comparison_points' and not tgisinternal)
              or not exists (select 1 from pg_trigger where tgname = 'z31_reveal_supersedes_comparison_points' and not tgisinternal)
            then 'PROBE FAILED: a trigger that supersedes the points at the decision is missing'
            when (public.fn_sales_engineer_comparison_points_supersede(null, 'probe') ->> 'points')::int <> 0
            then 'PROBE FAILED: a null request superseded points'
            when public.fn_sales_engineer_comparison_points_raise(-1) is not null
            then 'PROBE FAILED: the handler answered for a handoff that does not exist'
            when public.fn_sales_engineer_comparison_points_answered(null) <> 0
            then 'PROBE FAILED: a null conversation closed a hand-over'
            else 'PROBE OK' end as verdict;
