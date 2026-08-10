-- THE MARKETPLACE OS HAS NEVER BEEN TOLD ABOUT AN INQUIRY.
--
-- Applied to BOTH projects 2026-08-10.
--
-- `procurement` subscribes to event_type 'inquiry.created' with the reason "OS interface: Marketplace
-- OS consumes inquiry.created". Nothing has ever emitted that name. The trigger that fires when an
-- inquiry is inserted is:
--
--     CREATE TRIGGER trg_event_inquiry AFTER INSERT ON public.inquiries
--       FOR EACH ROW EXECUTE FUNCTION fn_emit_event('inquiry', 'rfq.created')
--
-- so the event is 'rfq.created' — 7 of them on file, one per inquiry — and the subscription sat on a
-- name that does not exist. One row, pointed at the name that is actually emitted.
--
-- WHY IT WAS NOT VISIBLE. fn_emit_event is generic: it takes the event type from tg_argv[1], so the
-- literal lives in pg_get_triggerdef, NOT in the function body. s21-events-nine-classes scans
-- pg_get_functiondef for `fn_emit*('<literal>'`, so it cannot see ANY of the seven emitters wired
-- this way — idea.submitted, rfq.created, security.event, quote.received, review.step,
-- process.repeated_failure, payment.received. That is a blind spot in the check, not a defect in the
-- estate, and it is recorded here rather than "fixed" by editing the scorer.
--
-- THE WIDER FINDING, MEASURED AND NOT ACTED ON. Fifteen event types carry ACTIVE subscriptions and
-- have never been emitted once — 33 subscriptions wired to nothing:
--
--     regulation.changed      10 subs   0 events
--     rfq.classified           5        0
--     budget.exceeded          2        0     (fn_budget_rollup does emit it; no dept has crossed halt)
--     invoice.received         2        0
--     invoice.flagged          2        0
--     outcome.graded           2        0
--     supplier.applied         2        0
--     campaign.published       1        0
--     content.drafted          1        0
--     customer.churn_signal    1        0
--     customer.complaint       1        0
--     department.conflict      1        0
--     health.degraded          1        0
--     sla.breached             1        0
--
-- Only 'inquiry.created' is corrected here, because it is the only one where the intended event
-- provably exists under another name and the trigger can be pointed at. The rest are either genuinely
-- unemitted capabilities (supplier.applied, campaign.published) or plausible-but-unproven renames
-- (invoice.received vs the emitted payment.received; health.degraded vs the emitted os.health_changed)
-- and guessing at those would be routing decisions dressed up as bug fixes.

update public.event_subscription
   set event_type = 'rfq.created',
       reason = 'OS interface: Marketplace OS consumes new inquiries. Corrected 2026-08-10: this row '
                || 'said inquiry.created, which NOTHING emits — trg_event_inquiry on public.inquiries '
                || 'fires fn_emit_event(''inquiry'',''rfq.created''), so procurement had never been '
                || 'notified of a single inquiry.'
 where event_type = 'inquiry.created' and agent_key = 'procurement';
