-- A "NOT SURE" SPEC OPENS A HANDOFF TO THE SALES ENGINEER (sales_engineer, 5 Oct 2026; founder review of #1186:
-- "'Not sure' opens a handoff to the sales engineer for that spec. Do not rely on the passive hold.").
--
-- customer_api add_missing_specs calls public.fn_seat_handoff('customer_support', 'sales_engineer', 'spec.not_sure',
-- 'inquiries', <inquiry id>, {not_sure: [keys], waiting_for}) when the customer answers "not sure" on a held request
-- (supabase/functions/customer_api/spec_handoff.ts). fn_seat_handoff refuses an unregistered kind (the row is born
-- failed and the IT engineer is told), so the conversation is registered here.
--
-- THE HANDLER IS THE SALES ENGINEER'S OWN. The first draft borrowed fn_marketing_social_handoff_waits, a marketing
-- routine, which made the marketing seat's file the owner of a sales_engineer conversation and tied this kind to
-- whatever marketing later does to its reader. No generic reader exists (every handler on seat_handoff_kind is
-- seat-specific), so this is a small one: it reports what the waiting handoff is waiting for (detail.waiting_for).
create or replace function public.fn_sales_engineer_spec_handoff_waits(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for',
                                                'the sales engineer to help the customer settle the spec'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_sales_engineer_spec_handoff_waits(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('spec.not_sure', 'customer_support', 'sales_engineer',
        'A customer answered "not sure" on a spec their held request needs: the sales engineer helps them settle it.',
        'fn_sales_engineer_spec_handoff_waits', interval '24 hours', false,
        'scripts/sql/a_not_sure_spec_opens_a_handoff_to_the_sales_engineer.sql')
on conflict (type, from_seat, to_seat) do update set handler = excluded.handler, meaning = excluded.meaning,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

select case when not exists (select 1 from public.seat_handoff_kind
                              where type = 'spec.not_sure' and to_seat = 'sales_engineer'
                                and handler = 'fn_sales_engineer_spec_handoff_waits')
            then 'PROBE FAILED: spec.not_sure not registered to the sales engineer handler'
            when has_function_privilege('anon', 'public.fn_sales_engineer_spec_handoff_waits(bigint)', 'execute')
            then 'PROBE FAILED: anon can execute the handler'
            when (public.fn_sales_engineer_spec_handoff_waits(-1)) is not null
            then 'PROBE FAILED: the handler answered for a handoff that does not exist'
            else 'PROBE OK' end as verdict;
