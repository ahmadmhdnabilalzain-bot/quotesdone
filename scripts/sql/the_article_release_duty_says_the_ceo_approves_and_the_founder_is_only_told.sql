-- THE ARTICLE-RELEASE DUTY SAYS THE CEO APPROVES, AND THE FOUNDER IS ONLY TOLD.        seat: marketing · 10 Nov 2026 · ledger 1058, 1609
-- Assigned: marketing
--
-- Founder, ledger 1058 (29 Sep 2026): "Never send the founder a blog for approval. The CEO seat reviews each article ... The
-- founder only gets an FYI once it is live." Ledger 1609 (10 Nov 2026): no decision goes to him.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   * seat_duty 'marketing.article_release'.what reads: 'One article draft a Dubai week is sent to the founder for "approve";
--     only his approval releases it, on a UAE working day.'
--   * The routine behind it, fn_marketing_article_release_duty (canonical in
--     a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql), checks articles with approved_by = 'ceo';
--     founder_mail_policy says article approval is retired and only marketing_article_live (an FYI) reaches him.
--   So the code obeys 1058 and only the registry text contradicts it. The registry is what the seat audit, the senior
--   verdict and an auditor read as the seat's job; a job description that names the founder as approver is how the
--   approval comes back.
--
-- WHAT THIS CHANGES: the duty text, here and in the file that registers it
-- (the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql), so a re-apply keeps it.
-- WHAT THIS DOES NOT CHANGE: the routine, the release cadence (one a week), the CEO review rounds, the FYI to the founder.
-- Prevented by: scripts/checks/no_seat_duty_names_the_founder_as_an_approver_he_has_retired.test.mjs
-- Apply at merge: node scripts/apply_sql.mjs scripts/sql/the_article_release_duty_says_the_ceo_approves_and_the_founder_is_only_told.sql --apply --ddl --seat marketing

update public.seat_duty
   set what = 'One article draft a Dubai week is reviewed by the CEO seat until it is useful (ledger 1058); the CEO''s approval releases it on a UAE working day and the founder is only told once it is live.'
 where duty = 'marketing.article_release';

select case when (select what from public.seat_duty where duty = 'marketing.article_release') ilike '%reviewed by the CEO seat%'
             and (select what from public.seat_duty where duty = 'marketing.article_release') not ilike '%for "approve"%'
            then 'PROBE OK' else 'PROBE FAILED: the article-release duty still names the founder as its approver' end as verdict;
