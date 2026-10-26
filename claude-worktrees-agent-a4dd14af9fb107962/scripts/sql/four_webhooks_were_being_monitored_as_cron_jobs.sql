-- THE COMPANY WAS DISPATCHING REAL WORK TO DIAGNOSE WEBHOOKS THAT WERE SIMPLY NOT CALLED.
--
-- Found while verifying the founder's WhatsApp channel on 2026-08-11 19:05 UTC. agent_actions had
-- two fresh handoffs addressed to the `it` employee:
--
--   2721  "Diagnose recurring wa_inbound scheduled-run failure (3rd+ occurrence)"
--   2722  "Diagnose recurring dropbox_sync scheduled-job failure (3rd occurrence)"
--
-- wa_inbound has no scheduled run to fail. It is the Twilio WhatsApp webhook: it executes when
-- somebody sends a message and at no other time. Measured: agent_expectations holds it with
-- on_demand = false and a "cadence learned from 11 run(s) across 7 day(s), median gap 17.45h" -
-- a cadence inferred from how often people happened to text us. When nobody texts for 53 hours the
-- monitor calls that a failure, opens a handoff, and an employee spends its capacity diagnosing an
-- endpoint that is working perfectly.
--
-- This is the "instruments report on the wrong subject" defect again: a green-or-red number that
-- measures something other than what it names. Here it costs real work, not just a wrong reading.
--
-- Four entries are externally event-driven and are marked on_demand. Their silence means NO EVENT
-- OCCURRED and must never be read as a fault:
--
--   wa_inbound       Twilio WhatsApp inbound webhook
--   resend_inbound   Resend inbound-email webhook
--   resend_webhook   Resend delivery/bounce callback
--   dispatch_inquiry fires when an inquiry arrives - currently silent=true, and the reason is that
--                    this company has had ZERO inquiries since 6 Aug. The monitor was reporting the
--                    absence of customers as a broken job.
--
-- DELIBERATELY NOT TOUCHED: chief_of_staff, docs and send_outbox also have no cron entry matching
-- their name, but they run 396 / 32 / 230 times and were all seen today, so something invokes them
-- on a cadence I did not identify. Marking those on_demand would suppress a real alarm. Their
-- silence still means something; these four's does not.

update public.agent_expectations
   set on_demand = true,
       silent    = false,
       note      = coalesce(note,'') ||
                   case when coalesce(note,'') = '' then '' else ' | ' end ||
                   'on_demand set 11 Aug 2026: event-driven endpoint, not a scheduled job. Silence means no inbound event, never a failure.'
 where agent in ('wa_inbound','resend_inbound','resend_webhook','dispatch_inquiry');
