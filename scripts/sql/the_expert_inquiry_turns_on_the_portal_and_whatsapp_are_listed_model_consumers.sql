-- THE EXPERT INQUIRY TURNS ON THE PORTAL AND WHATSAPP ARE LISTED MODEL CONSUMERS (10 Nov 2026).
-- Seat: sales_engineer (customer_support owns the WhatsApp row). Founder ledger 1572, 1579, 1586.
--
-- WHAT CHANGED IN CODE (branch sales_engineer-expert-advice): a customer conversation about a job is now answered on the
-- interview class, inquiry_qualification_conversation (the T3 interview class of it_engineer-model-tiers), on two more
-- surfaces than the request chat: the signed-in portal (fn sales_engineer, sales_engineer/actions/portal.ts) and WhatsApp
-- (fn wa_inbound, wa_inbound/say.ts). And one bounded json_extraction call per customer turn on those two surfaces reads
-- which taxonomy trades the conversation is about, the solutions the last reply put to them and the one they chose
-- (_shared/inquiry_reading.ts), for the state (public.inquiry_state).
--
-- MEASURED: fn_it_model_consumer_listed('sales_engineer', 'inquiry_qualification_conversation') and the three others below
-- are false today (it_model_consumer holds inquiry_intake:inquiry_qualification_conversation, sales_engineer:think and
-- wa_inbound:think only), so it_engineer's spend watch would file 'unlisted:<fn>:<class>' for each from their first call.
--
-- WHAT THIS DOES NOT DO: it routes nothing. Which model a class runs on is model_policy's, and is it_engineer's to change
-- (scripts/sql/the_inquiry_interview_moves_to_the_model_eval_b_passes.sql on it_engineer-model-tiers moves the interview
-- after eval B). Prevented by: the verdict row below, and scripts/checks/every_inquiry_conversation_keeps_one_state.test.mjs
-- (each class a surface names in code is listed here).
insert into public.it_model_consumer (consumer, owner_seat, why_a_model)
values
  ('sales_engineer:inquiry_qualification_conversation', 'sales_engineer', 'the portal reply in a job conversation: diagnose, offer the suitable options, qualify (ledger 1572/1586)'),
  ('wa_inbound:inquiry_qualification_conversation', 'customer_support', 'the WhatsApp reply when a customer describes a job: the same expert interview (ledger 1572/1586)'),
  ('sales_engineer:json_extraction', 'sales_engineer', 'reading the portal job''s trades, the options offered and the one chosen into inquiry_state; and the plan''s undecided slots'),
  ('wa_inbound:json_extraction', 'customer_support', 'reading a WhatsApp job''s trades, the options offered and the one chosen into inquiry_state')
on conflict (consumer) do update set owner_seat = excluded.owner_seat, why_a_model = excluded.why_a_model;

select case when public.fn_it_model_consumer_listed('sales_engineer', 'inquiry_qualification_conversation')
             and public.fn_it_model_consumer_listed('wa_inbound', 'inquiry_qualification_conversation')
             and public.fn_it_model_consumer_listed('sales_engineer', 'json_extraction')
             and public.fn_it_model_consumer_listed('wa_inbound', 'json_extraction')
            then 'PROBE OK: the four expert-interview consumers are listed'
            else 'PROBE FAILED: an expert-interview consumer is not listed' end as verdict;
