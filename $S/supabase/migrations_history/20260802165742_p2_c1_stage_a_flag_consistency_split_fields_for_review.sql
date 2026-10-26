-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802165742   name: p2_c1_stage_a_flag_consistency_split_fields_for_review
-- SHA-256 of the applied SQL: e901d6068745664f18fe1e45b8b580fb110fecca83af23d5a4e804e1e7df96e8
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Fields that were split ONLY because the corpus wording or answer type disagreed - not because
-- anyone decided they were different - must not sit quietly as `approved`. They are exactly the
-- "anything ambiguous stays unapproved and comes back as a question" case.
--
-- brand_policy differs by one word ("brand AND approved-equal" vs "brand OR approved-equal") with
-- an identical answer type, and is very likely one field. project_type and governing_documents
-- differ in answer type as well as wording, and the fire/ELV variant of project_type asks about
-- occupancy, which is a life-safety concept - those two are probably correctly split.
-- All three are recorded as questions rather than resolved by this session.

update public.field_definition
   set review_status = 'question_for_founder',
       review_note = coalesce(review_note || ' ', '') ||
         case
           when field_id like '%.brand_policy' then
             'QUESTION FOR FOUNDER: split only because the corpus says "brand and approved-equal policy" in routes 9/10/11 and "brand or approved-equal policy" in 12/13/14. Same answer type. Probably one shared field; merging is a one-line change to the candidate table once confirmed.'
           when field_id like '%.project_type' then
             'QUESTION FOR FOUNDER: two texts ("project type and occupancy" vs "project or facility type") and two answer types (single_select vs text). Occupancy is a life-safety concept, so this may be genuinely two fields.'
           when field_id like '%.governing_documents' then
             'QUESTION FOR FOUNDER: two texts and two answer types (document_list vs documents_or_text). The validation differs, so it fails the identical-validation condition as written.'
         end
 where (field_id like '%.brand_policy' or field_id like '%.project_type' or field_id like '%.governing_documents')
   and scope = 'trade_specific';
;