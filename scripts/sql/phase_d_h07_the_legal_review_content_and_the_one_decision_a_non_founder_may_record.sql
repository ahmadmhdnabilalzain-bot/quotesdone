-- H07 — the legal review content the catalogue never held, and the one refund decision a
--       non-founder may record
--
-- Five committed catalogue rows. Nothing here is a rule, a gate or a routine; every row is a value
-- the Phase D fixture machinery hands a deterministic handler as INPUT, inside a verified fixture
-- context only, marked so it can never be published.
--
-- 1. public.legal_reviews demands nothing -- every column is nullable -- so G14's population (the
--    NOT NULL, no-default columns the relation demands) filled nothing and W28-S01/S02/S07 reached
--    fn_phase_d_object_write with no mapped column at all:
--
--        legal_risk_review supplied no column the write map for public.legal_reviews can use.
--
--    H04 widened the population to mapped columns the catalogue speaks for at this step or in this
--    workflow. These four rows are that speech, scoped to W28 so a global "title" does not become the
--    title of every object that maps one.
--
-- 2. W17-S06 "Decide case outcome" is a DOMAIN_MUTATION on refund_dispute_case whose declared
--    transition is "status; decided_by; decided_at -> Case decision with required actions". The
--    handler now passes the decider and the time (H01) and keeps the row's own state unless the
--    catalogue states one for the step (H01/H02). z00_refund_founder_decision_only on public.refunds
--    refuses status 'approved' unless decided_by is an active founder identity -- every refund needs
--    the founder, at any amount, and a Phase D fixture may never forge that. The only decision a
--    non-founder can lawfully record is therefore a rejection, and that is what this step's fixture
--    states. It is a committed test value, not a judgement the handler makes: in production the row
--    stays 'requested' until the founder decides.
--
-- ROLLBACK: delete from public.phase_d_fixture_catalogue where fixture_id in
-- ('PDF-4101','PDF-4102','PDF-4103','PDF-4104','PDF-4105'). The checksum column recomputes itself.

insert into public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
values
  ('PDF-4101', 1, 'W28', null, 'EFFECT_PAYLOAD', 'title',
   to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — legal risk review of a Phase D fixture subject'::text), 'text', null,
   'free text; public.legal_reviews.title is nullable and the write map points it at this key',
   'W28 legal_risk_review writes carry a title and the write map can use at least one column',
   'Never present as a legal opinion, a review finding or a document title to any customer, supplier or regulator.',
   null),
  ('PDF-4102', 1, 'W28', null, 'EFFECT_PAYLOAD', 'summary',
   to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — a fixture summary stating nothing about any real contract, policy or exposure; it exists to prove the handler receives its content as input'::text), 'text', null,
   'free text; public.legal_reviews.summary is nullable',
   'W28 legal_risk_review writes carry a summary',
   'Never present as legal advice or as a summary of any real document; it summarises nothing.',
   null),
  ('PDF-4103', 1, 'W28', null, 'EFFECT_PAYLOAD', 'doc_kind',
   to_jsonb('phase_d_fixture'::text), 'text', null,
   'a short classifier for public.legal_reviews.doc_kind; the column carries no CHECK',
   'W28 legal_risk_review writes carry a document kind that names itself a fixture',
   'Never use as a real document classification; the value names itself a Phase D fixture.',
   'The value is the literal phase_d_fixture, which names itself a fixture and cannot be confused with a real document kind; an embedded marker would make the classifier unreadable.'),
  ('PDF-4104', 1, 'W28', null, 'EFFECT_PAYLOAD', 'risk_level',
   to_jsonb('fixture_unrated'::text), 'text', null,
   'a short level for public.legal_reviews.risk_level; the column carries no CHECK',
   'W28 legal_risk_review writes carry a risk level that declares itself unrated',
   'Never read as a risk rating of anything; the value declares itself unrated and a fixture.',
   'The value is the literal fixture_unrated, which declares itself unrated and a fixture and cannot be mistaken for a rating; a marker would make the level unreadable.'),
  ('PDF-4105', 1, 'W17', 'W17-S06', 'EFFECT_PAYLOAD', 'state',
   to_jsonb('rejected'::text), 'text', null,
   'a value of public.refunds.status (CHECK: requested, approved, rejected, processing, succeeded, failed, cancelled) that a non-founder may record; approved needs the founder and is refused by z00_refund_founder_decision_only',
   'W17-S06 records a case decision of rejected with the deciding role and time; GATE-020 at W17-S07 then reads a recorded decision; no money moves',
   'Never treat as a decision on any real refund, dispute or fraud case; the founder decides every real refund at any amount.',
   'The value is the literal refunds.status rejected, read by the CHECK constraint and by GATE-020; an embedded marker is not a status and the write would be refused.')
on conflict (fixture_id) do nothing;

do $ctl$
declare n int;
begin
  select count(*) into n from public.phase_d_fixture_catalogue
   where fixture_id in ('PDF-4101','PDF-4102','PDF-4103','PDF-4104','PDF-4105');
  if n <> 5 then
    raise exception 'H07: expected 5 catalogue rows, found %', n;
  end if;
end $ctl$;
