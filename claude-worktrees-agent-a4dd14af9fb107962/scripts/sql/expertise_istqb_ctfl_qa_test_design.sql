-- Agent expertise — first real cert knowledge into the runtime context path.
--
-- The measured architecture (28 Aug 2026): agents get domain knowledge through
-- fn_agent_context_v3 -> fn_context_slice, which reads public.ops_knowledge scoped by
-- role_key / dept_key / category_key and RANKS it by the task tsquery. `agent_knowledge` (only
-- experience/validated) and `kb_chunks` (corpus, read by kb_search/kb_match) are NOT on that path.
-- The QA roles carried only a competency MAP (which competencies to master) — not the technique
-- CONTENT itself. This loads that content.
--
-- Four core ISTQB CTFL v4.0.1 black-box test-design concepts, synthesised from the official
-- syllabus (downloaded + extracted, see docs/expertise/PIPELINE_PILOT_ISTQB.md) — structured notes,
-- not copied passages (book-to-skill Quality Rule #7), each citing the syllabus section. Loaded as
-- ops_knowledge role_specific for the four packaged QA role_keys, so fn_context_slice surfaces them
-- task-ranked. Proven: fn_agent_context_v3('ai_qa_specialist','test_design', <EP/BVA task>) returns
-- the EP/BVA row FIRST in role_knowledge. tsv is generated; embeddings backfill later (edge, free).
--
-- Zero cost, no business effect. runtime_eligible=true so it reaches agents when they run; the
-- knowledge is inert until then.

begin;

with concept(slug, title, content, techniques) as (values
  ('test-technique-taxonomy',
   'Test technique taxonomy: black-box, white-box, experience-based (ISTQB CTFL v4.0.1 §4.1)',
   'ISTQB CTFL classifies test techniques into three families. BLACK-BOX (specification-based) techniques analyse the specified behaviour of the test object without reference to its internal structure, so the test cases stay valid when the implementation changes but the required behaviour does not. WHITE-BOX (structure-based) techniques analyse the internal structure and processing, so their test cases depend on the design/implementation and can only be created after it. EXPERIENCE-BASED techniques use the tester''s knowledge and experience; their effectiveness depends on skill, and they are complementary — they can find defects the black-box and white-box techniques miss. Source: ISTQB Certified Tester Foundation Level Syllabus v4.0.1, §4.1.',
   jsonb_build_array('black-box','white-box','experience-based')),
  ('equivalence-partitioning',
   'Equivalence Partitioning (ISTQB CTFL v4.0.1 §4.2.1)',
   'Equivalence Partitioning (EP) divides data into partitions the test object processes identically, so testing one value from a partition is representative and one test per partition suffices. Partitions apply to any data element (inputs, outputs, config, internal, time, interface parameters), must be non-overlapping and non-empty, and each has a valid class and an invalid class. EP coverage = partitions exercised / total identified partitions (including invalid ones), as a percentage; 100% requires covering every partition at least once. When a test item has multiple parameter sets, the simplest criterion is Each Choice coverage: exercise each partition of each set at least once (it does not combine partitions across sets). Source: ISTQB CTFL Syllabus v4.0.1, §4.2.1.',
   jsonb_build_array('equivalence partitioning','each choice coverage')),
  ('boundary-value-analysis',
   'Boundary Value Analysis (ISTQB CTFL v4.0.1 §4.2.2)',
   'Boundary Value Analysis (BVA) exercises the boundaries of ORDERED equivalence partitions (min and max values), because developers are more likely to err there — boundaries misplaced above/below or omitted. 2-value BVA: for each boundary value, two coverage items — the boundary and its nearest neighbour in the adjacent partition. 3-value BVA: three coverage items — the boundary and both neighbours; it is more rigorous and can catch defects 2-value misses (e.g. "if (x < 10)" wrongly coded "if (x = 10)" is undetected by x=10/x=11 but x=9 from 3-value likely detects it). BVA coverage = boundary items exercised / total identified, as a percentage. Source: ISTQB CTFL Syllabus v4.0.1, §4.2.2.',
   jsonb_build_array('boundary value analysis','2-value BVA','3-value BVA')),
  ('decision-table-testing',
   'Decision Table Testing (ISTQB CTFL v4.0.1 §4.2.3)',
   'Decision tables test requirements where combinations of conditions produce different outcomes (business rules). Conditions and resulting actions form the rows; each column is a decision rule — a unique combination of conditions with its actions. Limited-entry tables use Boolean condition values (T true, F false, "-" irrelevant, "N/A" infeasible) and actions (X occurs, blank does not); extended-entry tables allow ranges/partitions/discrete values. A full table has a column for every condition combination; it can be simplified (drop infeasible columns) or minimised (merge columns whose conditions do not affect the outcome). Coverage = feasible columns exercised / total feasible columns. Strength: a systematic way to find all combinations and expose requirement gaps or contradictions; with many conditions the rules grow exponentially, so use a minimised table or a risk-based approach. Source: ISTQB CTFL Syllabus v4.0.1, §4.2.3.',
   jsonb_build_array('decision table testing'))
),
qa_role(role_key) as (values
  ('qa-and-testing-reviewer-auditor'),
  ('qa-and-testing-director'),
  ('qa-and-testing-operations-specialist'),
  ('qa-and-testing-analyst-controller')
)
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, role_key, layer, module, record_type,
  title, content, structured_data, source_ids, keywords, dependencies, escalation_rule,
  jurisdiction, authority_tier, risk_level, version, confidentiality, runtime_eligible,
  deterministic, supersession_state, embedding_status, implementation_status, validation_status,
  source_freshness, source_type, source_authority)
select
  'EXPERTISE:istqb-ctfl-v4:'||c.slug||':'||q.role_key,
  'role', q.role_key, 'qa', q.role_key, 'role_specific', 'knowledge', 'md',
  c.title, c.content,
  jsonb_build_object('cert','ISTQB CTFL v4.0.1','domain','test analysis and design','techniques', c.techniques),
  array['ISTQB Certified Tester Foundation Level Syllabus v4.0.1 (istqb.org)'],
  array['ISTQB','CTFL','test design','black-box','test technique','coverage'] ,
  array[]::text[], '{}'::jsonb,
  'INTL','advisory','low','2026.08.28','internal', true,
  false, 'current','pending','implemented','author_verified','stable','certification_syllabus','istqb'
from concept c cross join qa_role q
on conflict (record_id) do nothing;

-- Verify by measurement, same transaction: the EP/BVA content now surfaces for a QA agent, task-ranked.
do $$
declare v_ctx jsonb; n int;
begin
  v_ctx := public.fn_agent_context_v3('ai_qa_specialist','test_design',
             'design black-box test cases using equivalence partitioning and boundary value analysis', null, 24000);
  select count(*) into n from jsonb_array_elements(coalesce(v_ctx->'role_knowledge','[]'::jsonb)) e
   where e->>'title' ilike '%Equivalence Partitioning%';
  if n < 1 then
    raise exception 'expertise load verify FAILED: EP knowledge did not surface in ai_qa_specialist role_knowledge';
  end if;
end $$;

commit;
