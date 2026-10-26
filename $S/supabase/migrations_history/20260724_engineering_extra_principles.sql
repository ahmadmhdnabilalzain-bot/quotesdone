-- 3 genuinely-additive engineering techniques distilled from the engineering-team skills collection
-- (the rest overlapped with the IT agent's existing UAE-IT + gstack knowledge, or was off-stack ML/CV/big-data).
insert into public.agent_knowledge(agent_key,topic,priority,content)
select 'it', v.topic, v.priority, v.content from (values
('code_review_adversarial',76,'Review adversarially: run a hostile devil''s-advocate pass on any significant change/design - try to break it, expose hidden assumptions, edge cases and brittleness, get an independent second look (even a different model) before shipping. Fix critical findings now.'),
('engineering_principles',76,'Meta-principles: observability-first (measure before optimizing, never on a hunch); tradeoff transparency (document why X sacrificed for Y); continuous verification (gates/scans on every change); reproducible/idempotent tests+deploys; layered defense (security, performance, reliability each get their own mitigations).'),
('tech_stack_evaluation',72,'Choose tech by evidence: score candidates on a matrix (maturity, ecosystem, licensing, lock-in/exit, security track record, learning curve, fit with Deno/Supabase/Next) and pilot before committing to anything load-bearing. Prefer boring proven tools; every new dependency is a permanent liability - justify vs reuse.')
) as v(topic,priority,content)
where not exists (select 1 from public.agent_knowledge k where k.agent_key='it' and k.topic=v.topic);
