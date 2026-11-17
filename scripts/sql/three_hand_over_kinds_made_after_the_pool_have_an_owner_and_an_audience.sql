-- THREE HAND-OVER KINDS MADE AFTER THE POOL HAVE AN OWNER AND AN AUDIENCE (it_engineer, 17 Nov 2026; for the ceo, who owns the
-- one pool, and the sending seats named below).
--
-- MEASURED 17 Nov 2026 (SELECT on production): public.event_subscription has NO row for any status of three registered
-- hand-over kinds, so their echoes (handoff.<kind>.sent / waiting / done / failed) reach no seat's digest and a FAILED one
-- reaches nobody, IT included:
--   partnership.proposed     customer_support -> ceo             a_partnership_email_reaches_the_ceo_with_the_senders_facts.sql
--   supplier.reply_overdue   sales_engineer   -> ceo             every_interested_supplier_reply_is_answered_the_same_day_...sql
--   comparison.points        sales_engineer   -> sales_engineer  the_comparison_hands_its_open_points_to_the_sales_engineer.sql
--   mail.routed              customer_support -> accountant, it_engineer, marketing, ceo  info_and_management_mail_is_read_before_it_is_answered.sql
--                            (a fourth kind, added on review 17 Nov: registered by insert ... select, so the check missed it)
-- 0 events of these kinds so far, so nothing was missed yet. Each file registered its kind in seat_handoff_kind after the pool
-- file (every_seat_reads_one_pool_and_every_hand_over_comes_back.sql) seeded event_subscription, and none added its rows; the
-- check every_seat_reads_one_pool failed on exactly these twelve types, unseen because the gate skips npm-test.
--
-- WHAT THIS DOES: the pool's own rule, as its seed writes it for every other kind (one producing owner per type: the seat that
-- sends the kind; the receiving seat holds the hand-over itself; a failed one is the sender's to re-send and IT watches it).
-- Written as seed rows (qd.pool_seed on), so a row a seat has edited since is never overwritten, exactly as the seed does.
-- NOT CHANGED: seat_handoff_kind, the three files, any routine, any other subscription.
-- prevented by: scripts/checks/every_seat_reads_one_pool.test.mjs (now reads event_subscription rows from every file after the
-- pool file, and fails on these twelve without this one), and this file's _probe.sql after the apply.
-- Pending: scripts/sql/pending/three_hand_over_kinds_made_after_the_pool_have_an_owner_and_an_audience.txt
set local lock_timeout = '3s';
select set_config('qd.pool_seed', 'on', true);
insert into public.event_subscription as s (event_type, agent_key, owns, delivery, reason) values
  ('handoff.partnership.proposed.sent', 'customer_support', true, 'none', 'the one seat that sends partnership.proposed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.partnership.proposed.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.partnership.proposed.waiting', 'customer_support', true, 'none', 'the one seat that sends partnership.proposed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.partnership.proposed.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.partnership.proposed.done', 'customer_support', true, 'none', 'the one seat that sends partnership.proposed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.partnership.proposed.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.partnership.proposed.failed', 'customer_support', true, 'digest', 'the one seat that sends partnership.proposed; a failed hand-over is the sender''s to re-send'),
  ('handoff.partnership.proposed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.supplier.reply_overdue.sent', 'sales_engineer', true, 'none', 'the one seat that sends supplier.reply_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.reply_overdue.sent', 'ceo', false, 'none', 'ceo holds it as a hand-over in its own queue (the row itself, not this echo)'),
  ('handoff.supplier.reply_overdue.waiting', 'sales_engineer', true, 'none', 'the one seat that sends supplier.reply_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.reply_overdue.waiting', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.supplier.reply_overdue.done', 'sales_engineer', true, 'none', 'the one seat that sends supplier.reply_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo'),
  ('handoff.supplier.reply_overdue.done', 'ceo', false, 'none', 'nobody else: ceo wrote this answer itself'),
  ('handoff.supplier.reply_overdue.failed', 'sales_engineer', true, 'digest', 'the one seat that sends supplier.reply_overdue; a failed hand-over is the sender''s to re-send'),
  ('handoff.supplier.reply_overdue.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  ('handoff.comparison.points.sent', 'sales_engineer', true, 'none', 'the one seat that sends comparison.points, to itself; nobody else: the sales engineer holds it as a hand-over in its own queue'),
  ('handoff.comparison.points.waiting', 'sales_engineer', true, 'none', 'the one seat that sends and answers comparison.points; nobody else: it wrote this answer itself'),
  ('handoff.comparison.points.done', 'sales_engineer', true, 'none', 'the one seat that sends and answers comparison.points; nobody else: it wrote this answer itself'),
  ('handoff.comparison.points.failed', 'sales_engineer', true, 'digest', 'the one seat that sends comparison.points; a failed hand-over is the sender''s to re-send'),
  ('handoff.comparison.points.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches'),
  -- review of 17 Nov 2026: mail.routed (info_and_management_mail_is_read_before_it_is_answered.sql) is registered by
  -- insert ... select from unnest, which the check did not read; production had no row for it either (SELECT 17 Nov)
  ('handoff.mail.routed.sent', 'customer_support', true, 'none', 'the one seat that sends mail.routed (to the accountant, IT, marketing or the CEO); nobody else: the receiving seat holds it as a hand-over in its own queue'),
  ('handoff.mail.routed.waiting', 'customer_support', true, 'none', 'the one seat that sends mail.routed (to the accountant, IT, marketing or the CEO); nobody else: the receiving seat holds it as a hand-over in its own queue'),
  ('handoff.mail.routed.done', 'customer_support', true, 'none', 'the one seat that sends mail.routed (to the accountant, IT, marketing or the CEO); nobody else: the receiving seat holds it as a hand-over in its own queue'),
  ('handoff.mail.routed.failed', 'customer_support', true, 'digest', 'the one seat that sends mail.routed; a failed hand-over is the sender''s to re-send'),
  ('handoff.mail.routed.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches')
on conflict (agent_key, event_type) do update
   set owns = excluded.owns, delivery = excluded.delivery, reason = excluded.reason
 where s.edited_by is null;
select set_config('qd.pool_seed', '', true);
