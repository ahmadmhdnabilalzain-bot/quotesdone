-- ============================================================================
-- MARKETING department: content_draft execution (autonomous), publishing stays gated.
-- The marketing_draft edge function (deployed separately) generates on-brand content and saves it as
-- a DRAFT (content_drafts, status='draft'). content_publish and ad_spend are NOT wired — they stay
-- gated, so nothing goes public or spends money without the founder.
-- ============================================================================
insert into public.org_action_executor(action_class, kind, target, params, advisory_safe, note) values
('content_draft','edge','marketing_draft','{}', false, 'Generate on-brand content and save as a draft (content_drafts, status=draft). Never publishes; content_publish/ad_spend stay gated.')
on conflict (action_class) do update set kind=excluded.kind, target=excluded.target, params=excluded.params, advisory_safe=excluded.advisory_safe, note=excluded.note, active=true;

insert into public.org_memory(scope,kind,content,source) values
('marketing','policy','Marketing executes content_draft (autonomous): generates on-brand content and saves it as a DRAFT (never published). content_publish and ad_spend stay gated — nothing goes public or spends money without the founder.','founder_directive')
on conflict do nothing;