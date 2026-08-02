-- Field-key recovery, passes 2 and 3. A third id shape exists - lower-case
-- 'q-<subcategory_slug>-<field>' (e.g. q-holiday-homes-exact_requirement) - which the first pattern
-- missed because it only matched 'Q-<digits>-'. Same principle: strip the prefix the generator
-- built, never invent.
update kb_stage.questions q
set field_key = regexp_replace(
      lower(regexp_replace(q.source_question_id, '^[Qq]-' || q.subcategory_slug || '-', '')),
      '[^a-z0-9]+', '_', 'g')
where q.field_key is null
  and q.source_question_id is not null
  and q.source_question_id ~* ('^q-' || q.subcategory_slug || '-');

-- Pass 3: no usable id at all (3,031 rows). Here the ONLY stable identifier left is the question's
-- own internal label, which the generator wrote consistently ("scope type", "intended use",
-- "operating conditions"). Slugifying it is a real derivation, not a guess - two questions with the
-- same label inside one subcategory ARE the same question, which is exactly the dedup we want.
-- Marked in payload so a reviewer can tell derived keys from supplied ones.
update kb_stage.questions q
set field_key = regexp_replace(lower(btrim(coalesce(q.payload->>'internal_label_en', q.question_en))), '[^a-z0-9]+', '_', 'g'),
    payload = q.payload || jsonb_build_object('field_key_derived_from', 'internal_label_en')
where q.field_key is null
  and coalesce(nullif(btrim(coalesce(q.payload->>'internal_label_en', q.question_en)), ''), '') <> ''
  and length(regexp_replace(lower(btrim(coalesce(q.payload->>'internal_label_en', q.question_en))), '[^a-z0-9]+', '_', 'g')) between 2 and 80;

-- Trim leading/trailing separators left by the regexes.
update kb_stage.questions set field_key = btrim(field_key, '_')
where field_key like '\_%' or field_key like '%\_';
