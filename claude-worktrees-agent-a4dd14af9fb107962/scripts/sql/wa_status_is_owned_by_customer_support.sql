-- WA_STATUS IS OWNED BY CUSTOMER SUPPORT (22 Sep 2026; seat: customer_support).
--
-- every_whatsapp_says_whether_it_arrived.sql (PR #840) added the edge function wa_status, which receives
-- Twilio's delivery reports for every WhatsApp and SMS customer_support sends. It was deployed without a
-- function_owner row, and every_deployed_function_has_an_owner failed on #840. Customer support owns every
-- send, so it owns the report of what became of each one.
-- Prevented by: scripts/checks/every_deployed_function_has_an_owner.mjs

begin;

insert into public.function_owner (function_slug, owner, note)
values ('wa_status', 'customer_support',
        'Twilio delivery reports for every WhatsApp/SMS customer_support sends (PR #840): records delivered, read, '
        'failed and undelivered by MessageSid through fn_twilio_status_arrived and hands failures back to the seat that asked.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

commit;
