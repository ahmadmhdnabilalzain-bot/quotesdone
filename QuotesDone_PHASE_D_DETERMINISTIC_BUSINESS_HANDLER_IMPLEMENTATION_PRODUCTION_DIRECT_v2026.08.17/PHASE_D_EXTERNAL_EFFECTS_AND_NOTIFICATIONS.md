# External Effects and Notifications

Phase D sends no real external effect.

Resend, Twilio/WhatsApp, social publishing, Stripe/refunds, Dropbox, Apify and paid AI remain mock/disabled.

Every effect has source workflow/step/task, approved payload revision, target, consent/suppression, provider mode, idempotency, attempts, result ID, retry/dead-letter, trace and reconciliation.

Provider delivery may be at-least-once, but business effect is deduplicated. Refused/suppressed effects cannot count as delivered.

Cancellation makes undelivered effects non-deliverable. Delivered effects retain evidence and use compensation/supersession.
