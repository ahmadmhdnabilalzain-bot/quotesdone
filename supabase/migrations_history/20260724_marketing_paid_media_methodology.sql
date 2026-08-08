-- Paid-media + research methodology distilled into the marketing agent's always-on knowledge.
-- Sources: AgriciDaniel/claude-ads (source-grounded audits, deterministic scoring, hard rules,
-- capability-gated changes) and mvanhorn/last30days-skill (grounded multi-source trend research).
-- These also serve as the blueprint for the boost flow (agent audits+recommends -> founder funds -> configure).
insert into public.agent_knowledge(agent_key,topic,priority,content)
select 'marketing', v.topic, v.priority, v.content from (values
('paid_media_audit_framework',86,'Source-grounded audit before spend/scale: score the account''s own last-30-day data deterministically vs benchmarks (structure, tracking, audience, creative fatigue, budget efficiency), grade A-F, fix tracking/structure before increasing budget.'),
('paid_media_hard_rules',85,'Hard rules: 3x kill rule (pause CPA>3x target); learning-phase budget ~5x target CPA/week per Meta ad set; >=10 distinct Meta creatives; scale only winners, gradually (~20-30%).'),
('paid_media_tracking_gate',84,'Tracking is a gate: verify Pixel+CAPI with event de-dup, clean Google conversion goals, Consent Mode (PDPL) BEFORE optimizing/scaling. Mis-measurement looks like failure.'),
('boost_decision_rules',84,'Boost is capability-gated: agent audits + recommends a specific budget with rationale, kill and scale criteria; founder funds it. Only boost content with organic traction; always a funnel objective + tracked conversion + stop-loss.'),
('platform_priorities_uae',80,'UAE B2B channel priority: LinkedIn + Google Search first, Meta/IG for retargeting, TikTok/YouTube awareness only. Same audit->score->hard-rules->gated-change discipline across all platforms.'),
('trend_research_method',78,'Grounded multi-source trend research: recent (~30d) people-scored signals, merge duplicate narratives, filter off-topic virality, attribute every claim, prefer UAE-B2B-relevant sources; never invent a trend.'),
('paid_media_action_plan',76,'Audits end in a prioritized action plan (severity, financial impact, quick wins, owner, ETA), tracked to completion and re-audited: audit->plan->founder funds->execute->measure->re-audit.')
) as v(topic,priority,content)
where not exists (select 1 from public.agent_knowledge k where k.agent_key='marketing' and k.topic=v.topic);
