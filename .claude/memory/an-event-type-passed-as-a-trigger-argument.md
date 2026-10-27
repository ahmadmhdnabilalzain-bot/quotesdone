---
name: an-event-type-passed-as-a-trigger-argument
description: fn_emit_event reads the event type from tg_argv, so pg_get_functiondef contains no event type at all
metadata:
  type: project
---

`trg_event_inquiry` is `AFTER INSERT ON public.inquiries EXECUTE FUNCTION
fn_emit_event('inquiry', 'rfq.created')`, and `fn_emit_event` reads the type as `tg_argv[1]`.
So `pg_get_functiondef(fn_emit_event)` contains **no event type**, and any scan for
`fn_emit*('<type>'` literals inside routine bodies is blind to it.

Eight types are emitted only this way: idea.submitted, os.health_changed, payment.received,
process.repeated_failure, quote.received, review.step, rfq.created, security.event.

**Why:** spec #3's s21 reported "RFQ created" as the one event class production does not emit,
while it had been emitting it on every inquiry insert.

**How to apply:** when asking what this estate emits, read `pg_get_triggerdef(t.oid)` for triggers
whose function is named `fn_emit*` as well as routine bodies, taking only arguments containing a
dot so the entity-type argument beside them is not mistaken for an event type. Same family as
[[cron-command-no-longer-names-the-routine]] and
[[the-primary-identity-is-not-how-producers-key-a-subject]].
