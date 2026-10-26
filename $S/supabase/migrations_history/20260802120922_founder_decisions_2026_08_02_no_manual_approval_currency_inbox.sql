-- FOUNDER DECISIONS, 2 Aug 2026, taken in response to the external code review.
-- Three questions the reviewer correctly identified as unanswerable from the code, answered.

-- ---------------------------------------------------------------------------------------------
-- 1. NO MANUAL APPROVAL PATH for supplier registration.
-- The code contained two contradictory ideas: auto-approve when the licence reads, and an implicit
-- human queue ('pending') when it does not. Founder chose fully automatic. A failed licence gate is
-- now a refusal the supplier can fix themselves, not a ticket. This column carries the reason so
-- the portal and the email can name the exact problem instead of saying "pending".
alter table public.leads add column if not exists licence_gate_reason text;
comment on column public.leads.licence_gate_reason is
  'Why automatic approval refused this supplier (no_licence | licence_expired). Null once approved. Set by supplier_api; cleared automatically when a readable, in-date licence is uploaded. There is no human approval queue - this is what the supplier is told to fix.';

-- Retire the human queue that the old behaviour created. These rows asked a person to chase a
-- supplier; under the new policy the supplier is emailed directly and self-serves, so leaving them
-- as needs_review would keep a queue alive that nobody is meant to work.
update public.agent_actions set status = 'logged'
where kind = 'supplier_licence_gate' and status = 'needs_review';

-- ---------------------------------------------------------------------------------------------
-- 2. THE SUPPLIER SUBSCRIPTION FEE IS IN AED. The reviewer flagged that pricing_config carried the
-- number 1000 with NO currency column at all, while the founder's written spec said EUR 1,000 and
-- everything actually built (public site, supplier agreement, supplier_subscription_term) said AED
-- 1,000. Founder confirmed AED. Made explicit so it can never be ambiguous again - a 4x pricing
-- error is not something that should depend on which document you happen to read.
alter table public.pricing_config add column if not exists supplier_reg_currency text not null default 'AED';
alter table public.pricing_config add column if not exists reveal_currency text not null default 'AED';
update public.pricing_config set supplier_reg_currency = 'AED', reveal_currency = 'AED' where id = 1;
comment on column public.pricing_config.supplier_reg_currency is
  'Currency of supplier_reg_fee. Confirmed AED by the founder on 2 Aug 2026. Stripe checkout, the Supplier Agreement, the public supplier page and the accounting entries must all agree with this value.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE COMMAND CENTER IS AN OPERATIONAL CONSOLE, and the dashboard should say so honestly.
-- The reviewer was right that it is not monitoring-only. Founder chose to keep the capability but
-- to stop the dashboard implying he is a bottleneck. The data-side half of that is this split:
-- what genuinely BLOCKS the company vs what is merely available to him.
-- Blocking = money, destruction, credentials, external legal acts, third-party bans - the classes
-- deliberately left gated in the 29 Jul autonomy re-tiering. Everything else is work the company
-- is supposed to be doing itself, and its presence here is a bug in automation, not a decision.
create or replace view public.v_founder_inbox as
select a.id, a.created_at, a.agent, a.kind, a.risk, a.title, a.recommendation,
       a.target_table, a.target_id,
       case
         when a.kind in ('payment_approval','purchase_order','refund_decision','credential_change',
                         'legal_flag','security_incident','supplier_ban','data_deletion')
           then 'blocking'
         else 'automation_gap'
       end as bucket
from public.agent_actions a
where a.status = 'needs_review';

comment on view public.v_founder_inbox is
  'Splits the founder queue in two. bucket=blocking: money, destruction, credentials, legal, security - genuinely his call, deliberately gated. bucket=automation_gap: work the company should be doing unattended that has no executor yet, so it silently landed on him. The second number is the honest measure of how far from unattended we actually are; it should trend to zero, and it is a bug list, not a to-do list.';
