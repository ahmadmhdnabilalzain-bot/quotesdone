-- The company emitted payment.received to nobody
-- ==============================================
--
-- Chasing s21-no-polling turned up something better than a latency number. 290 company_event rows
-- have never been delivered to anyone, and for seven of the eight event types involved the reason
-- is that NOBODY IS SUBSCRIBED:
--
--     task.assigned        168   no subscription
--     supplier.approved     37   no subscription
--     improvement.proposed  15   no subscription
--     knowledge.updated     11   no subscription
--     customer.registered    8   no subscription
--     payment.received       8   no subscription
--     metric.alert           2   no subscription
--     review.step           41   HAS a subscription (historical, 6-9 Aug, pre-dates it)
--
-- payment.received and customer.registered are the two most commercially important things this
-- company can ever emit, and both go into a void. supplier.approved - a new supplier becoming
-- matchable, which changes category coverage - reaches nobody either.
--
-- WHILE I WAS THERE: s21's own number is not what it looks like. The check reads "median delivery
-- lag 264s over 1820 deliveries/7d" against a 60s threshold, but that window is polluted by
-- backfill: when a subscription is added, every historical event of that type is delivered at once
-- with a lag measured in days. Measured on events that OCCURRED in the last 24 hours: median lag
-- 0 seconds, 258 of 258 delivered inside 60 seconds. The trigger works. s21 clears on its own as
-- the backfilled deliveries age out of the 7-day window, and adding these subscriptions will make
-- it look WORSE first for exactly the same reason.
--
-- Each subscription names a real, active employee whose job already covers the event, and carries
-- the reason in the same form as the twelve already on file.
--
-- task.assigned is DELIBERATELY LEFT UNSUBSCRIBED. It is the largest group at 168, and the
-- subscription model is per-agent-per-type, not dynamic - so a static row would funnel every
-- assignment in the company to one inbox. The assignee is already named on org_tasks.assigned_agent
-- by fn_org_task_assign; a broadcast would be noise, not delivery.

insert into public.event_subscription (agent_key, event_type, reason, active) values
  ('cfo', 'payment.received',
   'Revenue recognition is a Finance decision; the Finance Director sees every payment the company takes.', true),
  ('bookkeeper', 'payment.received',
   'Posts the transaction to the ledger and issues the receipt - the payment workflow step that follows the charge.', true),
  ('cs_onboarding', 'customer.registered',
   'Owns the first-request guidance a newly registered customer needs; nobody else was watching registrations.', true),
  ('procurement', 'supplier.approved',
   'A newly approved supplier changes category coverage, which Procurement owns and plans invites against.', true),
  ('innovation_mgr', 'improvement.proposed',
   'Evolution owns the improvement backlog; a proposal nobody receives is a proposal nobody triages.', true),
  ('docs', 'knowledge.updated',
   'Documentation Manager keeps the corpus current and needs to know when knowledge changes underneath it.', true),
  ('analytics_director', 'metric.alert',
   'A metric moving outside its band is an Analytics call before it is anyone else''s.', true)
on conflict do nothing;
