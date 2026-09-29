# Postmortem: `duty:delivery` — a delivery request had no confirmed outcome within its window

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `duty:delivery:request:<id>` — 20 distinct requests |
| Handoffs covered | **20** (all high) |
| First / last | 15 Sep 2026 02:01Z / 22 Sep 2026 |
| Answering seat | customer_support |

## Impact
Every request in this class was raised by the **ceo** seat (a notice to the founder or a seat), not by a customer.
Each finding closed as "the delivery duty no longer finds it", i.e. an outcome was later recorded.

## Root cause
Measured in `docs/it/IT_FAILURES_18_21_SEP_2026.md` cause 3: `send_whatsapp` never stored Twilio's message SID
(24 of 24 WhatsApp rows marked sent since 18 Sep had `provider_message_id` NULL), so the delivery watch could not
confirm the outcome and reported `sent_unconfirmed`; the email twin was confirmed in every case. The 11 handoffs of 15 Sep
(handoffs 25895–25906, delivery requests 25447–25691) predate that measurement; their cause was **not re-measured** here.

## Detection
`customer_support` delivery duty ("no confirmed outcome for 2/3 hours"). Worked.

## Fix (found in git)
- `1de84e3` (#767): `send_whatsapp` stores the provider id; the report family gained a CEO decider.
- `dc09a9f`: delivery outcomes recorded (email deliverability).
- `df4cfcb` (#832): every handoff answered within its window.

## Action items
1. **customer_support** — none open; the class has not recurred since 22 Sep (last handoff 53285).

## Handoff ids covered
`duty:delivery` (20): 25895, 25896, 25898, 25899, 25900, 25901, 25902, 25903, 25904, 25905, 25906, 52059, 52060, 53256, 53280, 53281, 53282, 53283, 53284, 53285.
