-- Suppliers could not ask the customer anything before the reveal
-- ================================================================
--
-- WHAT WAS WRONG. Website audit 14 Sep 2026, customer portal, verdict ABSENT: messages_api answers
-- {locked:true} on every thread until a transactions row exists, so between "posted" and "paid"
-- there was no channel at all. A supplier who needed one measurement before pricing could not ask
-- it, and the customer could not answer. The only adjacent path, rfq_flag, wrote an agent_actions
-- row of kind 'rfq_clarification' for staff to read and emailed the customer "please add detail"
-- with no way to reply to the question itself - production holds 0 such rows (measured 14 Sep).
-- Separately, RfqAssistant ("Ask the assistant about this request") posted the customer's
-- follow-up to inquiry_intake, which ignores inquiry_id, so every follow-up became an orphan intake
-- draft and reached no supplier.
--
-- WHAT THIS CHANGES. One table holds both halves of the pre-reveal conversation for an RFQ:
--   kind 'question' - a matched supplier asks (messages_api clarify_ask, and rfq_flag, which now
--                     forwards into the same action instead of writing agent_actions); the
--                     customer answers once (clarify_answer) and every matched supplier sees it.
--   kind 'note'     - the customer adds to the RFQ on their own (customer_api rfq_note); it is
--                     born answered, so it is visible to every matched supplier as an addendum.
-- Identities are masked both ways by the writers (contact details stripped server-side, suppliers
-- shown to the customer as "Supplier A/B..."); nothing here stores a name that is not already on
-- the inquiry or the lead.
--
-- ACCESS. Only the edge functions, which run as service_role, read or write it. RLS is on with a
-- single service_role policy and anon/authenticated hold no privilege, so a browser holding a
-- customer or supplier JWT cannot read another party's questions through PostgREST.
--
-- supplier_id carries no foreign key on purpose: an FK to a table that is ever emptied fails every
-- writer (lesson of 9 Sep, inquiries -> leads), and a question outliving its lead is harmless.

create table if not exists public.rfq_clarification (
  id           bigint generated always as identity primary key,
  inquiry_id   uuid        not null references public.inquiries(id) on delete cascade,
  supplier_id  bigint,
  kind         text        not null check (kind in ('question', 'note')),
  question     text,
  answer       text,
  source       text        not null default 'portal' check (source in ('portal', 'rfq_flag', 'rfq_note')),
  asked_at     timestamptz not null default now(),
  answered_at  timestamptz,
  constraint rfq_clarification_shape_ck check (
    (kind = 'question' and supplier_id is not null and question is not null)
    or (kind = 'note' and supplier_id is null and answer is not null and answered_at is not null)
  )
);

create index if not exists rfq_clarification_inquiry_idx on public.rfq_clarification (inquiry_id, asked_at);
create index if not exists rfq_clarification_supplier_idx on public.rfq_clarification (supplier_id, asked_at) where supplier_id is not null;

alter table public.rfq_clarification enable row level security;

drop policy if exists rfq_clarification_service_role_only on public.rfq_clarification;
create policy rfq_clarification_service_role_only on public.rfq_clarification
  for all to service_role using (true) with check (true);

revoke all on table public.rfq_clarification from public, anon, authenticated;
revoke all on sequence public.rfq_clarification_id_seq from public, anon, authenticated;
