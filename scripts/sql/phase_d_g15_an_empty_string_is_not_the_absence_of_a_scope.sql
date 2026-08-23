-- G15 — an empty string is not the absence of a scope, and one key served two objects
--
-- G14 committed twelve EFFECT_PAYLOAD fixtures for the columns fn_phase_d_effect_produce raises
-- 23502 on. None of them was ever returned. fn_phase_d_fixture_input selects with
--
--     and (c.step_id     is null or c.step_id     = sr.step_id)
--     and (c.workflow_id is null or c.workflow_id = v_wf)
--
-- and the twelve rows were written with workflow_id = '' and step_id = '' — empty strings, which
-- are neither null nor equal to any step. The rows existed, the board counted them, and the lookup
-- matched none of them. The existing catalogue rows carry NULL; the committed CSV renders NULL as
-- an empty quoted field, and that rendering is what was copied. MEASURED before and after:
-- fn_phase_d_fixture_input(<W07-S01 step run>, 'EFFECT_PAYLOAD', 'bucket') returned null with the
-- rows present.
--
-- AND A SECOND DEFECT THE SAME PROBE EXPOSED. The effect payload built for W07-S01, which writes an
-- inquiry_document into public.documents, came back as
--
--     {"kind": "PHASE_D_FIXTURE_DO_NOT_PUBLISH partnership"}
--
-- public.documents.kind is NOT NULL and mapped, so the derivation correctly asked for a fixture
-- named "kind" — and the only one committed is PDF-0042, which exists for public.opportunity.kind
-- in W21. One field_key, two relations, no scope, and the partnership's kind was about to be
-- written as a document's kind. It is the same shape as every other defect this session found: an
-- answer supplied for a key without asking what the key was about.
--
-- Both catalogue rows are now SCOPED to the workflow they belong to, so each object gets the
-- fixture written for it, and the document gets one of its own carrying a kind public.documents
-- recognises. A third row would need a third scope; the lookup already supports it.
--
-- ROLLBACK: set workflow_id and step_id back to '' on PDF-4001..4012, clear workflow_id on
-- PDF-0042, and delete PDF-4013. No DDL.

update public.phase_d_fixture_catalogue
   set workflow_id = null, step_id = null
 where fixture_id like 'PDF-40%' and (coalesce(workflow_id,'') = '' or coalesce(step_id,'') = '');

-- PDF-0042 exists for public.opportunity.kind, which only W21 writes. Saying so stops it being
-- handed to every other relation that happens to have a column called kind.
update public.phase_d_fixture_catalogue
   set workflow_id = 'W21',
       expected_schema = 'one of the kinds public.opportunity accepts; the column is NOT NULL and W21 is the only workflow that writes it'
 where fixture_id = 'PDF-0042' and field_key = 'kind';

insert into public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
values
  ('PDF-4013',1,'W07',null,'EFFECT_PAYLOAD','kind','"boq"'::jsonb,'text',
   'a document kind public.documents recognises; the column is NOT NULL with no default',
   'the W07 document effect writes a document of a kind the intake path understands, instead of being handed the partnership kind PDF-0042 exists for',
   'No document is uploaded, parsed or shared; the row is written inside a transaction that is aborted.',
   'public.documents.kind is matched by the intake and extraction paths against a closed set. A marker inside it names no kind, so the write would fail for the marker rather than for the document.')
on conflict (fixture_id) do nothing;
