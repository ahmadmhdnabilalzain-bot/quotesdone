-- F39 - seven committed values the hard rules ask for by name, and the catalogue did not hold
--
-- MEASURED. Of the thirty frozen workflows, seven have their FIRST handler refusal at a hard
-- business rule whose required_context names a key nothing supplies:
--
--   W08-S01, W22-S01, W24-S01  BR-036  artifact_ref + artifact_sha256
--       "artifact_sha256 <id> is not a SHA-256 digest (64 hexadecimal characters), so it was not
--        computed over any artifact"
--   W04-S01, W09-S01           BR-025  terms_version + terms_hash
--       "acceptance must reference the exact displayed version AND hash; one without the other is
--        not an acceptance of anything specific"
--   W20-S01                    BR-035  approved_revision_ref + publishing_revision_ref
--       "the revision being published is not the independently approved revision, or neither was named"
--
-- and two more rules are one step behind them:
--
--   BR-026  acceptance_ref      "no certificate before acceptance"
--   BR-032  provider_event_id   provider event idempotency
--
-- public.phase_d_fixture_catalogue holds a CONTEXT_KEY row for artifact_ref (PDF-0039) and for
-- none of the other six. The founder's ruling of 22 Aug 2026 section 6 names this exact remedy:
-- "The fixture catalogue supplies explicit content... Handlers validate, persist, version and route
-- these values. Handlers do not generate them."
--
-- THE DIGESTS ARE COMPUTED, NOT TYPED. A 64-character string typed into this file would satisfy
-- BR-036's shape test while being a digest of nothing, which is the defect BR-036 exists to catch
-- wearing the fixture's clothes. Both hashes below are computed HERE, in the INSERT, over the
-- fixture body committed beside them -- so artifact_sha256 really is sha256(artifact_body) and
-- terms_hash really is sha256(terms_body), and anyone can recompute them from this file.
--
-- WHAT IS DELIBERATELY NOT ADDED. inquiry_id, supplier_id, transaction_id, comparison_id,
-- caller_customer_id and quote_revision_ref are IDENTITIES OF ROWS, not content. They must resolve
-- from the records the scenario factory actually created, through public.phase_d_scenario_record,
-- and a catalogue row for any of them would be a fixture standing in for a business subject that
-- does not exist -- the precise thing the residue rule and BR-013 exist to refuse. They stay
-- unresolved here and their workflows stay refused until the factory creates the parent.

begin;

INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
SELECT * FROM (VALUES
-- ---- BR-036: the artifact and the digest that is actually of it -------------------------------
('PDF-3101',1,null,null,'CONTEXT_KEY','artifact_body',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture artifact body for Phase D. This text is the artifact. It describes nothing about the real business and exists so that a digest computed over it is a digest of something.'::text),
 'text',null,
 'free text; the artifact BR-036 requires the reviewer to have reviewed',
 'artifact_sha256 below is sha256 of exactly this string, so BR-036 judges a real digest',
 'Never publish, send or attach. It is not a company artifact.',null),

('PDF-3102',1,null,null,'CONTEXT_KEY','artifact_sha256',
 to_jsonb(encode(sha256(convert_to('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture artifact body for Phase D. This text is the artifact. It describes nothing about the real business and exists so that a digest computed over it is a digest of something.','UTF8')),'hex')),
 'text',null,
 'exactly 64 hexadecimal characters; BR-036 refuses anything else',
 'BR-036 accepts the digest and still refuses one that was not computed over an artifact',
 'Never present as the digest of a company document.',
 'A SHA-256 digest cannot carry the text marker and stay a digest. It is computed in this file over PDF-3101, which carries the marker, and is recomputable from it.'),

-- ---- BR-025: the displayed version AND its hash, which must travel together -------------------
('PDF-3103',1,null,null,'CONTEXT_KEY','terms_body',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture terms text for Phase D. No term here binds anyone. It exists so that a terms hash is a hash of the terms that were displayed.'::text),
 'text',null,
 'free text; the terms whose version and hash are accepted',
 'terms_hash below is sha256 of exactly this string',
 'Never display, quote or enforce. These are not the platform terms.',null),

('PDF-3104',1,null,null,'CONTEXT_KEY','terms_version',
 to_jsonb('phase-d-fixture-terms-v1'::text),'text',null,
 'a non-empty version identifier; BR-025 refuses a version without its hash',
 'BR-025 has both halves and judges whether they name the same thing',
 'Never present as a published terms version.',
 'A version identifier is matched against a displayed version and must stay exactly what was displayed; the marker is carried by PDF-3103, the terms body it names.'),

('PDF-3105',1,null,null,'CONTEXT_KEY','terms_hash',
 to_jsonb(encode(sha256(convert_to('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture terms text for Phase D. No term here binds anyone. It exists so that a terms hash is a hash of the terms that were displayed.','UTF8')),'hex')),
 'text',null,
 'exactly 64 hexadecimal characters, over the terms body',
 'BR-025 accepts an acceptance that names the exact version and hash',
 'Never present as the hash of the platform terms.',
 'A SHA-256 digest cannot carry the text marker and stay a digest. It is computed in this file over PDF-3103, which carries the marker, and is recomputable from it.'),

-- ---- BR-035: the approved revision IS the published one --------------------------------------
('PDF-3106',1,null,null,'CONTEXT_KEY','approved_revision_ref',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH revision/phase-d/fixture-revision-v1'::text),'text',null,
 'the revision an independent reviewer approved',
 'BR-035 has an approved revision to compare against',
 'Never publish. No revision of any real asset is named.',null),

('PDF-3107',1,null,null,'CONTEXT_KEY','publishing_revision_ref',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH revision/phase-d/fixture-revision-v1'::text),'text',null,
 'the revision being published; BR-035 refuses when it differs from the approved one',
 'BR-035 passes on the fixture scenario and still refuses a mismatched pair',
 'Never publish. No revision of any real asset is named.',null),

-- ---- BR-026 and BR-032 -----------------------------------------------------------------------
('PDF-3108',1,null,null,'CONTEXT_KEY','acceptance_ref',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH acceptance/phase-d/fixture-acceptance-v1'::text),'text',null,
 'a reference to the acceptance a certificate may rest on',
 'BR-026 can tell an accepted quote from an unaccepted one',
 'Never issue a certificate against it. Nothing was accepted.',null),

('PDF-3109',1,null,null,'CONTEXT_KEY','provider_event_id',
 to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH provider-event/phase-d/fixture-event-v1'::text),'text',null,
 'a stable provider event identifier; BR-032 refuses a replay of one already seen',
 'BR-032 has an event identity to judge, and a second delivery of it is refused',
 'Never reconcile against a payment provider. No provider event exists.',null)
) AS v(fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
       currency, expected_schema, expected_result, prohibited_external_use, marker_exemption)
ON CONFLICT (fixture_id) DO NOTHING;

commit;
