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
-- Tests: supabase/functions/_shared/request_fit.review.test.ts (6), supabase/functions/supplier_api/
-- the_comparison_points_are_answered_only_by_the_supplier.test.ts.

create or replace function public.fn_sales_engineer_comparison_points_raise(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; v_quote_id uuid; v_inquiry uuid; v_supplier bigint; v_review uuid; v_pt jsonb; v_n int := 0;
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
  end loop;
  update public.agent_actions set detail = detail || jsonb_build_object('review_id', v_review) where id = p_id;
  if v_n = 0 and not exists (select 1 from public.quote_review_request x
                              where x.review_id = v_review and x.code = 'comparison_point' and x.state = 'open') then
    return jsonb_build_object('raised', 0, 'review_id', v_review, 'reason', 'every point was already asked and answered in this conversation');
  end if;
  return jsonb_build_object('raised', v_n, 'review_id', v_review,
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
            when public.fn_sales_engineer_comparison_points_raise(-1) is not null
            then 'PROBE FAILED: the handler answered for a handoff that does not exist'
            when public.fn_sales_engineer_comparison_points_answered(null) <> 0
            then 'PROBE FAILED: a null conversation closed a hand-over'
            else 'PROBE OK' end as verdict;
