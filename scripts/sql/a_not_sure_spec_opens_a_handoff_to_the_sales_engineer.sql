-- A "NOT SURE" SPEC OPENS A HANDOFF TO THE SALES ENGINEER (sales_engineer, 5 Oct 2026; founder review of #1186:
-- "'Not sure' opens a handoff to the sales engineer for that spec. Do not rely on the passive hold.").
--
-- customer_api add_missing_specs calls public.fn_seat_handoff('customer_support', 'sales_engineer', 'spec.not_sure',
-- 'inquiries', <inquiry id>, {not_sure: [keys], waiting_for}) when the customer answers "not sure" on a held request
-- (supabase/functions/customer_api/spec_handoff.ts). fn_seat_handoff refuses an unregistered kind (the row is born
-- failed and the IT engineer is told), so the conversation is registered here. No new routine: the handler is the
-- existing reader that reports what a waiting handoff is waiting for (its detail.waiting_for).
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'spec.not_sure', 'customer_support', 'sales_engineer',
       'A customer answered "not sure" on a spec their held request needs: the sales engineer helps them settle it.',
       'fn_marketing_social_handoff_waits', interval '24 hours', false,
       'scripts/sql/a_not_sure_spec_opens_a_handoff_to_the_sales_engineer.sql'
 where not exists (select 1 from public.seat_handoff_kind
                    where type = 'spec.not_sure' and from_seat = 'customer_support' and to_seat = 'sales_engineer');

select case when exists (select 1 from public.seat_handoff_kind where type = 'spec.not_sure' and to_seat = 'sales_engineer')
            then 'PROBE OK' else 'PROBE FAILED: spec.not_sure not registered' end as verdict;
