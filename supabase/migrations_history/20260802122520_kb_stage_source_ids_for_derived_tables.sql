-- The corpus is not uniform. Across the 67 packages the same logical field appears under different
-- names (question_id vs field, scenario_id vs test_id, rule_text vs description) and the supplied
-- short IDs - "Q-001-dewa-related-contractors-project_emirate", "V-002-...", "T-002-..." - are only
-- unique WITHIN a package, because the numeric prefix is the package number and the packages were
-- generated independently. Keying the derived tables on those short IDs would silently collide the
-- moment two packages shared a subcategory slug, and a collided question is a question the customer
-- is never asked.
-- So the primary key is the globally unique record_id, and the supplied short ID is kept alongside
-- and indexed, because decision_rules reference it by name:
--   {"action":"ask_question","question_id":"Q-001-dewa-related-contractors-project_emirate"}
-- Resolution at runtime is (category_slug, subcategory_slug, source_question_id), which is unique.
alter table kb_stage.questions         add column if not exists source_question_id   text;
alter table kb_stage.validation_rules  add column if not exists source_validation_id text;
alter table kb_stage.scenario_tests    add column if not exists source_scenario_id   text;

create index if not exists kb_stage_questions_srcid_idx
  on kb_stage.questions (category_slug, subcategory_slug, source_question_id);
create index if not exists kb_stage_validations_srcid_idx
  on kb_stage.validation_rules (category_slug, subcategory_slug, source_validation_id);
create index if not exists kb_stage_scenarios_srcid_idx
  on kb_stage.scenario_tests (category_slug, subcategory_slug, source_scenario_id);

comment on column kb_stage.questions.source_question_id is
  'The question_id as supplied inside the package (unique only within that package). decision_rules.then_json references this value; resolve it together with category_slug + subcategory_slug, never on its own.';
