-- CORRECTING A KPI I WROTE AN HOUR AGO. IT COUNTED DELIBERATE SUCCESS AS FAILURE.
--
-- In #213 I gave notification_ops the measure:
--
--   select count(*) from notifications where coalesce(status,'')<>'sent' and created_at < now()-'24h'
--
-- and reported the result - 36 - as a finding: "36 notifications are older than 24 hours and still
-- unsent ... exactly the gap named in the email_delivery_stops scenario". That was WRONG, and the
-- error is the precise one this session has spent the night removing: a number that measures
-- something other than what it names.
--
-- Measured properly, the whole table by status:
--
--   sent       355   (325 older than 24h)
--   digested    34   ( 33 older than 24h)   TERMINAL AND DELIBERATE - folded into a digest
--   skipped      4   (  3 older than 24h)   TERMINAL AND DELIBERATE
--   digest       3   (  0 older than 24h)   pending batch
--   queued       0                          THE QUEUE IS EMPTY
--
-- Not one row has attempts > 0 outside 'sent', and none of the 36 carried a last_error. There is
-- no stuck queue. The email path is draining correctly and my measure was counting two deliberate
-- terminal states as outages.
--
-- The employee's own KPI text said so and I did not read it closely enough: comms_manager's KPI is
-- "Alerts raised that reach the founder - share SENT OR PROVABLY DIGESTED". Digested IS delivery in
-- this company's vocabulary.
--
-- The corrected measure counts only what is genuinely still waiting to go out. It reads 0 today,
-- which is the truth, and it will read a real number the moment the sender actually stalls.

update public.employee_kpi set measure_sql =
  $q$select count(*)::numeric from notifications where coalesce(status,'') in ('queued','digest','pending','') and created_at < now()-interval '24 hours'$q$
 where agent_key='notification_ops' and kpi='Notifications older than 24h still unsent';
