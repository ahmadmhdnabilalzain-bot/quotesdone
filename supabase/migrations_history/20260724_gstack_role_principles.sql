-- Additive role operating-principles distilled from garrytan/gstack (the interactive slash-commands don't
-- run in the autonomous stack; these 5 principles filled genuine gaps, redundant ones like the 3-fix rule skipped).
insert into public.agent_knowledge(agent_key,topic,priority,content)
select v.agent_key, v.topic, v.priority, v.content from (values
('brief','product:reframe_before_build',82,'Reframe before building: interrogate the underlying pain first, not just the proposed solution - what problem, for whom, and what does the 10-star version look like? Generate 2-3 alternatives, pick the highest-leverage scope (expand/hold/reduce). Problem discovery precedes solution design; a short spec becomes the contract.'),
('it','release_discipline',82,'A release is merge + CI green + deploy + PRODUCTION VERIFICATION - not just merge. Never mark done until verified live (headless render/smoke check). Coverage gaps block shipping; health verification is the handoff. Keep a rollback path.'),
('it','qa_real_browser',78,'CI passing != production works - the bug that matters only shows in a real browser/live env. Test critical flows with real interactions; every bug fixed gets a regression test; capture baseline metrics (Web Vitals, latency, errors) before/after so regressions are visible.'),
('docs','documentation_diataxis',78,'Diataxis docs: reference / how-to / tutorial / explanation - four types for four needs; a missing type is a structural gap. Tie every meaningful code change to a doc update so the brain never goes stale; prefer diagrams-as-code (mermaid).'),
('marketing','design_quality_measurable',74,'Judge design by a measurable bar: rate each dimension (hierarchy, whitespace, type, colour, consistency, on-brand) 0-10 with an explicit 10-definition, iterate until it clears. Visual exploration + variants beat verbal one-shots; taste compounds. Applies to posts, cards, website.')
) as v(agent_key,topic,priority,content)
where not exists (select 1 from public.agent_knowledge k where k.agent_key=v.agent_key and k.topic=v.topic);
