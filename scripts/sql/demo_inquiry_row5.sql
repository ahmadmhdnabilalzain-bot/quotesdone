-- ROW #5 §18 — THE FENCED DEMO INQUIRY, ON BOTH PROJECTS.
--
-- Founder decision, 2026-08-08: "create a demo for whatever we need to verify. no staging only, we
-- need to go on production." This is that demo: one customer relationship so the collaboration
-- workspace can be exercised against real rows rather than asserted from source.
--
-- ── WHAT AN INSERT INTO inquiries ACTUALLY SETS OFF, MEASURED NOT ASSUMED ───────────────────────
-- Twelve triggers. Eleven are database-only. Exactly one reaches outside — trg_autodispatch_inquiry,
-- which calls the dispatch_inquiry edge function — and it is gated:
--
--     if NEW.rfq_ready is true and (TG_OP='INSERT' or OLD.rfq_ready is distinct from NEW.rfq_ready)
--
-- So this row leaves rfq_ready NULL and the dispatch never happens. That is the fence that matters:
-- not a comment asking nicely, a condition in the trigger that cannot be satisfied by this row.
-- No supplier is contacted, no customer is emailed, nothing leaves the database.
--
-- ── THE ONE COST, STATED PLAINLY ────────────────────────────────────────────────────────────────
-- trg_event_inquiry -> fn_emit_event still fires and writes one 'rfq.created' event. That event
-- lands in row #2's separately-measured event backbone (107/110). It is ONE synthetic row and it is
-- findable: its inquiry_id is this fixture's id. Row #2's next re-run must subtract it or say so.
-- The founder accepted this cost when choosing production over staging.
--
-- ── customer_id IS NULL, DELIBERATELY ───────────────────────────────────────────────────────────
-- The column is nullable, so the demo needs no customer at all. Inventing a fake customer row would
-- put a person-shaped record into a table real people live in, and every customer-facing query
-- filters on customer_id — a NULL belongs to nobody and can be revealed to nobody.
--
-- ── REMOVABLE IN TWO STATEMENTS ─────────────────────────────────────────────────────────────────
--     delete from public.inquiry_matches where inquiry_id in
--       (select id from public.inquiries where brief_source = 'qd_demo_fixture');
--     delete from public.inquiries where brief_source = 'qd_demo_fixture';

-- The relationship is (inquiry, supplier). The supplier is the existing fenced demo fixture —
-- unverified and unmatchable on two independent legs — so this pairs one fenced row with another
-- and creates no path to a real company.
-- TWO PLAIN STATEMENTS, NOT ONE CLEVER CTE. The first version wrote the inquiry inside a
-- data-modifying CTE and cross-joined its RETURNING against the supplier lookup to make the match
-- row. The inquiry landed and the match did not — measured on staging, 8 Aug 2026 — so the
-- workspace stayed empty and the fixture proved nothing. Two statements that each re-select what
-- they need are idempotent, re-runnable, and there is nothing left to be subtle about.
insert into public.inquiries (
    customer_id, category, emirate, role_needed, summary, raw_input,
    status, brief_source, rfq_ready, scope_type
  )
  select
    null,                                   -- belongs to nobody; see the note above
    'aluminium', 'Sharjah', 'supplier',
    'ZZ DEMO — curtain walling to a mall atrium (QuotesDone fixture, not a real project)',
    'Demo fixture used to exercise the QuotesDone supplier collaboration workspace. '
      || 'Not a real enquiry. Fenced out of dispatch: rfq_ready is NULL so trg_autodispatch_inquiry '
      || 'cannot fire.',
    'open', 'qd_demo_fixture',
    null,                                   -- THE FENCE. Not false — NULL, which the trigger's
                                            -- `is true` test rejects either way, and which reads
                                            -- honestly as "this brief was never completed".
    'supply_only'
  where not exists (select 1 from public.inquiries where brief_source = 'qd_demo_fixture');

-- ── THE RELATIONSHIP COMES FROM THE MESSAGE LEG, NOT THE MATCH LEG, AND THAT IS FORCED ──────────
-- fn_supplier_workspaces opens a workspace for an inquiry the supplier was MATCHED to *or* has
-- EXCHANGED MESSAGES about. The match leg is unavailable to a fenced fixture, and the reason is a
-- neat piece of platform coherence rather than an obstacle:
--
--     trg_gate_incomplete_match:  if ready is not true then return null;
--
-- An incomplete RFQ is not routed to suppliers AND is not matched to them — the same condition,
-- enforced twice. So the very field that fences this fixture out of dispatch (rfq_ready) also makes
-- an inquiry_matches row silently vanish: a BEFORE trigger returning NULL, no error, no row.
-- Measured on staging 8 Aug 2026, which is how this was found rather than assumed.
--
-- Forcing it would mean setting rfq_ready = true, and that buys three things nobody asked for:
-- the dispatch_inquiry call, a queued 'new_inquiry' notification e-mail from
-- fn_notify_matched_supplier, and a fixture that is no longer fenced.
--
-- public.messages has NO triggers at all. One inbound message creates the relationship with no
-- dispatch, no notification and no event — and it is also the more honest demo, because what the
-- supplier is meant to do with a workspace is REPLY to it.
insert into public.messages (inquiry_id, supplier_id, customer_id, sender, body)
select i.id, s.id, null, 'customer',
       'ZZ DEMO — Hello, we are looking at curtain walling for a mall atrium in Sharjah. '
       || 'Could you share indicative rates and your lead time? (QuotesDone demo fixture, not a real customer.)'
from public.inquiries i
join public.leads s on s.place_id = 'qd-demo-supplier-001'
where i.brief_source = 'qd_demo_fixture'
  and not exists (
    select 1 from public.messages m
    where m.inquiry_id = i.id and m.supplier_id = s.id
  );
