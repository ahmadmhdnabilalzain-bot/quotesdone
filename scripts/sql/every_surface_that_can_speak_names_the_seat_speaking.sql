-- EVERY SURFACE THAT CAN SPEAK NAMES THE SEAT SPEAKING.
--
-- Assigned: it_engineer (the register), customer_support and marketing (the seats named). 22 Sep 2026.
-- Founder, 22 Sep 2026: the model is set per seat. A surface that can answer a person and does not
-- name its seat cannot be given a model, cannot be held to a seat's rules, and does not appear in
-- the per-seat ledger.
--
-- ══ MEASURED, htdblwldjkcgjvmqkbeh, 22 Sep 2026 ══════════════════════════════════════════════
--   public.llm_seat_binding holds 27 rows. Every edge function that calls ai_gateway is in it
--   EXCEPT three: site_assistant, marketing_social_inbox and resilience_ping (SEATS-13).
--     site_assistant         answers the public website widget — the support agent the visitor
--                            meets. The founder, 9 Sep 2026: the homepage widget is Support.
--     marketing_social_inbox answers the company's social inbox from company knowledge, which is
--                            the marketing seat's own duty (org_agents.role, marketing).
--     resilience_ping        is NOT added: its only ai_gateway call is {action:'embed'} for the
--                            knowledge embedding queue. It answers nobody and speaks as no seat, so
--                            binding it to one would say something untrue about who is talking.
--
--   node scripts/apply_sql.mjs scripts/sql/every_surface_that_can_speak_names_the_seat_speaking.sql --apply

insert into public.llm_seat_binding (fn, seat, note) values
  ('site_assistant', 'customer_support',
   'The public website chat widget. Founder, 9 Sep 2026: the homepage widget is Support. Answers from the support pack deterministically while the OpenRouter hold is on.'),
  ('marketing_social_inbox', 'marketing',
   'The company''s social inbox. org_agents.role (marketing): answers the company''s social inbox from company knowledge.')
on conflict do nothing;

do $$
declare v_missing text;
begin
  select string_agg(f, ', ') into v_missing from (values ('site_assistant'), ('marketing_social_inbox')) as x(f)
   where not exists (select 1 from public.llm_seat_binding b where b.fn = x.f);
  if v_missing is not null then raise exception 'llm_seat_binding still names no seat for: %', v_missing; end if;
  -- the seat named must be a live seat, or the binding points at nobody
  select string_agg(b.fn || '->' || b.seat, ', ') into v_missing from public.llm_seat_binding b
   where not exists (select 1 from public.org_agents a where a.agent_key = b.seat and a.active);
  if v_missing is not null then raise exception 'llm_seat_binding names a seat that is not live: %', v_missing; end if;
  raise notice 'site_assistant -> customer_support and marketing_social_inbox -> marketing are bound';
end $$;
