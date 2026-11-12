-- a_case_summary_owed_after_a_reply_is_written_by_the_next_beat.sql
-- Seat: customer_support. Founder ruling 1635 (11 Nov 2026): "After each exchange the agent records a summary of the case."
-- Review of the WhatsApp fix branch (12 Nov 2026, SHOULD FIX 5): the summary after a WhatsApp reply is written inside the turn's
-- edge worker after the reply (support_case_memory.ts settleExchange, retried 3 times there). A worker killed before that ends
-- left nothing that remembered the summary was owed. This lists what is owed, from rows that already say so, with no new table:
-- an open WhatsApp case whose last inbound message is newer than every summary of that person, more than 5 minutes ago (the turn
-- is over), within the last day, and answered (a wa_messages row of that number carries a reply that was sent, or captured on
-- a fixture number; a ZZ DEMO number only while decision_policy.demo_rehearsal_active is true). resilience_ping's step caseCatchup
-- (every 15 minutes, kicked detached: it calls the model) writes them from the conversation, at most 3 a beat.
-- Other doors keep the in-turn retries and an it_engineer finding; their transcripts are in four different tables.
-- Apply: AFTER resilience_ping is deployed with the caseCatchup step (an unknown step name in resilience_step is skipped and
-- reported by the tick plan until then). Probe: a_case_summary_owed_after_a_reply_is_written_by_the_next_beat_probe.sql.

create or replace function public.fn_support_case_summaries_owed(p_limit integer default 5)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_inbound_at), '[]'::jsonb)
    from (
      select c.case_ref, c.summary_text, c.summary_version, c.last_inbound_at, c.summary_updated_at, p.phone_tail, p.id as profile
        from public.support_case c
        join public.support_customer_profile p on p.id = c.customer_profile_id
       where c.state <> 'closed' and c.last_channel = 'whatsapp' and p.phone_tail is not null
         and c.last_inbound_at between now() - interval '24 hours' and now() - interval '5 minutes'
         -- not owed when ANY case of the person was summarised since the message (review round 2): the arrival attaches a message
         -- to the newest open case, the step after the reply may record it on another one, and the exchange is then recorded
         and not exists (select 1 from public.support_case c2
                          where c2.customer_profile_id = c.customer_profile_id and c2.summary_updated_at >= c.last_inbound_at)
         and exists (select 1 from public.wa_messages m
                      where m.created_at >= c.last_inbound_at - interval '2 minutes'
                        and right(regexp_replace(coalesce(m.wa_from, ''), '[^0-9]', '', 'g'), 9) = p.phone_tail
                        and coalesce(btrim(m.inbound), '') <> '' and coalesce(btrim(m.reply), '') <> ''
                        -- the reply reached them: sent, or captured on a reserved fixture number
                        and (m.sent or coalesce(m.meta ->> 'send_error', '') like 'captured:%')
                        -- each catch-up is a paid model call: a ZZ DEMO number only while a rehearsal window is open
                        and (not public.fn_is_demo_phone(m.wa_from)
                             or coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d where d.key = 'demo_rehearsal_active'), false)))
       order by c.last_inbound_at
       limit greatest(1, least(coalesce(p_limit, 5), 20))
    ) x;
$fn$;
revoke execute on function public.fn_support_case_summaries_owed(integer) from public, anon, authenticated;
grant execute on function public.fn_support_case_summaries_owed(integer) to service_role;

-- the catch-up's clock: resilience_ping kicks caseCatchup (detached, its own budget) every 15 minutes
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('caseCatchup', interval '15 min', 1500, 'plan', 0,
   'KICKED, not run inline: case summaries a WhatsApp reply owes and its worker did not write (support_case_memory.ts catchUpOwedSummaries; ruling 1635), at most 3 a beat',
   'customer_support')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank,
       note = excluded.note, owner_seat = excluded.owner_seat;
