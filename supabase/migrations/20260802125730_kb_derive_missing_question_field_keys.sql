-- FIELD KEYS: 13,557 of 16,588 qualification questions arrived without one.
-- Why this is not cosmetic. A question with no stable field key cannot be ANSWERED in a way the
-- system can remember. Without it you cannot tell whether the buyer has already said which emirate
-- the project is in, you cannot collapse the same question asked by seven mapped subcategories of a
-- composite route into one, you cannot build the spec object suppliers quote from, and you cannot
-- compute completeness - which means dispatch_eligible can never be true. The corpus would have been
-- 115,000 rows of text with no working deterministic layer, and every inquiry turn would have fallen
-- straight back to a premium model, which is the cost this whole exercise exists to remove.
--
-- The key IS recoverable, deterministically, because the supplied question_id encodes it:
--   Q-008-gypsum-boards-partitions-and-drywall-project-emirate
--   ^pkg ^subcategory_slug                     ^field
-- Strip 'Q-<digits>-<subcategory_slug>-' and normalise separators. Nothing is invented: where the
-- prefix does not match, the field key is left NULL and the question is reported in the gap register
-- rather than guessed at, because a wrong field key silently merges two different questions.
update kb_stage.questions q
set field_key = regexp_replace(
      lower(regexp_replace(q.source_question_id, '^Q-[0-9]+-' || q.subcategory_slug || '-', '')),
      '[^a-z0-9]+', '_', 'g')
where q.field_key is null
  and q.source_question_id is not null
  and q.source_question_id ~ ('^Q-[0-9]+-' || q.subcategory_slug || '-');

-- Second pass for the handful whose id carries a different package prefix shape.
update kb_stage.questions q
set field_key = regexp_replace(lower(regexp_replace(q.source_question_id, '^Q-[0-9]+-', '')), '[^a-z0-9]+', '_', 'g')
where q.field_key is null and q.source_question_id ~ '^Q-[0-9]+-';

-- Record what could not be recovered, so it is a visible gap rather than a silent hole.
insert into kb_stage.knowledge_gaps (package_id, category_slug, subcategory_slug, gap, severity, raw)
select 'derived', q.category_slug, q.subcategory_slug,
       'Qualification question has no derivable field_key, so its answer cannot be stored, deduplicated or counted towards completeness: ' || q.question_id,
       'high', jsonb_build_object('question_id', q.question_id, 'source_question_id', q.source_question_id)
from kb_stage.questions q
where q.field_key is null
  and not exists (select 1 from kb_stage.knowledge_gaps g
                  where g.raw->>'question_id' = q.question_id);

create index if not exists kb_stage_questions_fieldkey_scope_idx
  on kb_stage.questions (category_slug, subcategory_slug, field_key);
