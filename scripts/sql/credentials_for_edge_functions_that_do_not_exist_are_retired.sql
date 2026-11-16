-- CREDENTIALS FOR EDGE FUNCTIONS THAT DO NOT EXIST ARE RETIRED, SO THE ROTATION STOPS RENEWING THEM.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. internal_credential holds 97 active rows. For the 14 contexts below, every function the credential is
-- scoped to is absent from supabase/functions on origin/main (79 slugs), the active generation has never been used
-- (last_used_at null, use_count 0), and no generation of the context has been used since 7 Sep 2026. Yet the rotation duty
-- renewed them on 1-10 Nov (fn_it_credential_rotate rotates every row that is active and retired_at is null).
--   context              scope (none of these is a function on main)                                  last use, any generation
--   cron.ads_autopilot   meta_ads                                                                     never
--   cron.monitoring      ai_health, qa_suite, uptime_check                                            7 Sep
--   cron.content         assets_ingest, blog_weekly, content_revise, seo_gen, social_stage            16 Aug
--   cron.finance         collections_legal, cost_snapshot, finance_ingest, money_tests                7 Sep
--   cron.knowledge       gen_category_personas, kb_autofill_gaps, kb_embed, learn_gaps, knowledge_exam,
--                        gen_category_knowledge, kb_deepen, kb_ingest                                 7 Sep
--   cron.marketing       meta_sync                                                                    7 Sep
--   cron.marketplace     enrich_capability, boost_recommend, archive_rfq, match_eval, embed_leads    7 Sep
--   fn.to_agent_brain    agent_brain                                                                  14 Aug
--   fn.to_route_inquiry  route_inquiry                                                                7 Sep
--   fn.to_alert_founder  alert_founder                                                                16 Aug
--   fn.to_make_pdf       make_pdf                                                                     6 Sep
--   fn.kb_autofill_gaps  kb_fill_gap, alert_founder                                                   7 Sep
--   fn.reg_fetch         kb_ingest                                                                    never
--   fn.social_stage      postiz_publish                                                               6 Sep
-- Nothing reads their app_secrets key ('cred_' || context with '.' -> '_') or names the context: no routine body, no cron
-- command, no edge or app code (one comment in _shared/internal_auth.ts says social_stage's uses are historical). No cron
-- job or body posts to any of those function slugs. No rotation is open for them (it_credential_rotation: none in overlap
-- or held). Key names only: no secret value was read.
-- KEPT: fn.pdpl_request (also unused, scoped to alert_founder): it is PDPL, so it waits for the PDPL owner. ops.doc_render
-- was used once on 3 Sep, so it is not "never used". The app_secrets keys are not touched here (another wave owns them);
-- once the rows are retired the rotation no longer writes them.
--
-- WHAT THIS DOES. Uses the table's own retirement columns: active = false and retired_at = now() on the current generation
-- of each context, only while it is still unused. fn_it_credential_rotate, fn_it_safe_fix_credential_rotation and
-- fn_it_engineer_credential_rotation_age all select "active and retired_at is null", so none of them touches these again.
--
-- REVERSAL (one line; the ids are the ones this file retired, recorded in the probe's verdict):
--   update public.internal_credential set active = true, retired_at = null where id in (108, 800, 872, 873, 878, 879, 882, 892, 894, 1109, 1110, 1111, 1116, 1119);

update public.internal_credential
   set active = false, retired_at = now()
 where context in ('cron.ads_autopilot', 'cron.monitoring', 'cron.content', 'cron.finance', 'cron.knowledge', 'cron.marketing',
                   'cron.marketplace', 'fn.to_agent_brain', 'fn.to_route_inquiry', 'fn.to_alert_founder', 'fn.to_make_pdf',
                   'fn.kb_autofill_gaps', 'fn.reg_fetch', 'fn.social_stage')
   and active and retired_at is null
   and last_used_at is null and coalesce(use_count, 0) = 0;

-- PROBE: a verdict row. No credential of the 14 contexts is still a rotation candidate, the ones kept on purpose are
-- untouched, and the count of other active credentials is reported so the reader can compare it with 97 - 14 = 83.
with ctx(c) as (select unnest(array['cron.ads_autopilot', 'cron.monitoring', 'cron.content', 'cron.finance', 'cron.knowledge',
                  'cron.marketing', 'cron.marketplace', 'fn.to_agent_brain', 'fn.to_route_inquiry', 'fn.to_alert_founder',
                  'fn.to_make_pdf', 'fn.kb_autofill_gaps', 'fn.reg_fetch', 'fn.social_stage'])),
v as (select
  (select count(*) from public.internal_credential i join ctx on ctx.c = i.context where i.active and i.retired_at is null) still_rotating,
  (select string_agg(i.id::text, ', ' order by i.id) from public.internal_credential i join ctx on ctx.c = i.context
    where not i.active and i.retired_at > now() - interval '1 hour') retired_now,
  (select count(*) from public.internal_credential where context in ('fn.pdpl_request', 'ops.doc_render') and active) kept_active,
  (select count(*) from public.internal_credential where active and retired_at is null) active_left)
select case when still_rotating = 0
            then 'PROBE OK: no credential of the 14 contexts is active; retired in this hour: ids [' || coalesce(retired_now, '') || ']; '
                 || kept_active || ' kept on purpose still active; ' || active_left || ' active credentials left'
            else 'PROBE FAILED: ' || still_rotating || ' credentials of the 14 contexts are still active (one was used since the file was written?)' end as verdict
  from v;
