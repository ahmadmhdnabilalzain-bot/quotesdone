-- TWILIO RETRIES. NOTHING IN wa_inbound REMEMBERED THE MESSAGE.
--
-- wa_inbound parses MessageSid on both the JSON and the form path and uses it for provenance
-- verification, then writes it into wa_messages.meta.message_sid - a JSONB field with no unique
-- index, which cannot refuse a second copy. Measured by reading the function 11 Aug 2026: there is
-- no idempotency check anywhere in its 386 lines.
--
-- That is survivable only while every reply finishes inside Twilio's 15-second webhook wall. Twilio
-- redelivers on timeout, so the moment anything slow runs on this path the founder gets the message
-- handled TWICE: two model calls, two WhatsApp replies, two wa_messages rows, and - once the
-- founder path can dispatch work - two handoffs for one instruction.
--
-- This table is the claim. The primary key IS the mechanism: the second delivery of the same
-- MessageSid loses the insert and the function returns 200 without doing the work again.
--
-- It is created BEFORE the founder path is routed through agent_brain, which runs to 70 seconds
-- against that 15-second wall, because building them in the other order is exactly how you ship the
-- duplicate-dispatch defect.

create table if not exists public.wa_inbound_seen (
  message_sid   text primary key,
  wa_from       text,
  first_seen_at timestamptz not null default now()
);

alter table public.wa_inbound_seen enable row level security;

create index if not exists wa_inbound_seen_first_seen_idx
  on public.wa_inbound_seen (first_seen_at desc);

comment on table public.wa_inbound_seen is
  'One row per Twilio MessageSid accepted by wa_inbound. The primary key is the idempotency guard: Twilio redelivers a webhook it thinks timed out, and before this table a redelivery produced a second model call, a second WhatsApp reply and a second wa_messages row. Added 11 Aug 2026 alongside routing the founder path through agent_brain.';
