-- Component 7, Inputs: make "Every OS receives events" true, and give the `planned` excuse a date.
--
-- MEASURED 6 Aug 2026 against production: 470 event deliveries in 7 days across
-- only 8 distinct os_key. finance and legal_gov have NEVER received one. Not for want of wiring --
-- finance has 5 active employees and 4 active subscriptions, legal_gov 4 and 4 -- but because every
-- event type those two subscribe to has never once been emitted: invoice.received,
-- budget.exceeded, invoice.flagged and regulation.changed are all traffic- or condition-gated, and
-- production has no supplier invoice, no budget breach and no regulator feed. Two of the ten
-- Operating Systems are plugged into a bus that carries nothing addressed to them.
--
-- The fix is NOT to fabricate an invoice so a number turns green. It is to subscribe each of those
-- OSes to an event type that (a) actually flows and (b) genuinely belongs to it:
--   finance   <- kpi.missed      (18 emitted, 9 in the last 7 days)  the CFO owns a missed number
--   legal_gov <- security.event  (12 emitted, 9 in the last 7 days)  risk/governance owns incidents
--
-- os_interface is declared in the same file so the declaration matches the traffic. Without it
-- fn_event_dispatch stamps every assessment 'UNDECLARED INPUT: os_interface does not list this
-- event type for this OS' -- the drift comp-07-inputs-coverage measures. Three OSes already carried
-- that drift in the other direction: commercial, marketplace and technology RECEIVE
-- content.published, supply.gap and security.event through active subscriptions they never
-- declared. Those three declarations are added too, so that after this file every active OS has at
-- least one declared input that is not marked planned and has actually carried an event.
--
-- planned_since / planned_until. os_interface.planned was an unbounded excuse: 11 of 17 active
-- input declarations carried planned=true with a prose reason and no expiry, so "not yet live" was
-- a permanent green button and 16 of 17 rows could have been excused at once. The flag now has to
-- say WHEN it was raised and WHEN it lapses. The CHECK makes an undated excuse unrepresentable
-- rather than merely discouraged -- a scorer runs weekly, a constraint runs on every write.
-- The dates are recorded as of today with a one-quarter horizon; renewing them is a decision
-- somebody has to take again, which is the whole point of an expiry.

alter table public.os_interface
  add column if not exists planned_since timestamptz,
  add column if not exists planned_until timestamptz;

update public.os_interface
   set planned_since = coalesce(planned_since, timestamptz '2026-08-06 00:00:00+00'),
       planned_until = coalesce(planned_until, timestamptz '2026-11-04 00:00:00+00')
 where coalesce(planned, false);

alter table public.os_interface drop constraint if exists os_interface_planned_dated;
alter table public.os_interface add constraint os_interface_planned_dated
  check (not coalesce(planned, false) or planned_until is not null);

insert into public.os_interface (os_key, direction, kind, description, event_type, active, planned, severity)
values
  ('finance', 'input', 'kpi.missed',
   'A KPI the company measures came in under target. Finance owns the money consequence: '
   || 're-forecast the line, re-cut the budget, or escalate the shortfall.',
   'kpi.missed', true, false, 'high'),
  ('legal_gov', 'input', 'security.event',
   'A security event was recorded. Risk & Governance owns the incident record, the regulatory '
   || 'notification clock and the control that failed.',
   'security.event', true, false, 'high'),
  ('commercial', 'input', 'content.published',
   'Published content is a commercial asset the moment it ships: Commercial owns the claim it '
   || 'makes, the audience it reaches and the pipeline it is supposed to move.',
   'content.published', true, false, 'low'),
  ('marketplace', 'input', 'supply.gap',
   'Demand exists that supply cannot serve. Marketplace owns supplier coverage, so a gap is its '
   || 'input, not a report about it.',
   'supply.gap', true, false, 'medium'),
  ('technology', 'input', 'security.event',
   'A security event was recorded. Technology owns the system it happened in and the fix.',
   'security.event', true, false, 'high')
on conflict (os_key, direction, kind) do nothing;

insert into public.event_subscription (agent_key, event_type, reason, active)
values
  ('cfo', 'kpi.missed',
   'Finance owns the money consequence of a missed number: re-forecast the line, re-cut the '
   || 'budget, or escalate the shortfall.', true),
  ('risk_governance_mgr', 'security.event',
   'Risk & Governance owns the incident record, the regulatory notification clock and the control '
   || 'that failed.', true)
on conflict (agent_key, event_type) do update
   set active = true, reason = excluded.reason;

-- Drain the backlog now rather than waiting up to 15 minutes for event_dispatch_15min. 30 new
-- (event, subscriber) pairs against a batch cap of 50, so one call covers it. Deploying is not
-- verifying: the delivery rows are read back in a separate statement afterwards.
select public.fn_event_dispatch();
