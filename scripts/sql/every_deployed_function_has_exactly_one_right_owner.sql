-- EVERY DEPLOYED FUNCTION HAS EXACTLY ONE OWNER, AND IT IS THE RIGHT SEAT (22 Sep 2026, ceo).
--
-- Founder instruction 583 (seat tasks), gap 1. Ownership is recorded in public.function_owner
-- (function_slug PRIMARY KEY, so one row = exactly one owner; owner CHECKed against the five seats and
-- 'website'). scripts/checks/every_deployed_function_has_an_owner.mjs compares it with the LIVE deployment
-- list in both directions.
--
-- MEASURED 22 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only, by running that check: EXIT 1.
--   * 67 functions deployed; 2 DEPLOYED WITH NO OWNER: complaint_status, public_site.
--   * 11 OWNED BUT NOT DEPLOYED: about, auth_api, faq, home, home-ar, i18n_get, legal, portal,
--     public_stats, quote_pdf, sup_dob -- ownership rows outliving their subject.
--   * On the wrong seat (staff audit of 21 Sep, section 7, and the founder's rulings):
--       dropbox_backup, login_otp, mobile_otp, voice_otp, voice_otp_capture, role_guard  on sales_engineer
--         -> it_engineer. Founder, 14 Sep 2026: sign-in is a platform service, not agent work; backup is
--            IT work (the audit measured backup re-files waiting in the sales queue since 15 and 18 Sep).
--       ai_gateway on customer_support -> it_engineer: the model switchboard every seat calls.
--       license_extract, doc_extract, extract_text on customer_support -> sales_engineer: interpreting a
--         supplier's documents is supplier verification, the sales engineer's (ruling of 9 Sep).
--
-- WHY IT CAME BACK: the check existed but ran only when somebody remembered -- it needs the management
-- token, so it was in no CI job. This PR adds it to the token-holding parity job
-- (.github/workflows/project-parity.yml), so a deployed function with no owner, or a stale row, fails the
-- merge instead of waiting for an audit.
--
-- WHAT THIS CHANGES: 2 owner rows inserted, 10 moved, 11 stale rows deleted. Nothing else.
-- WHAT IT DOES NOT CHANGE:
--   * backup.refile handoffs are still addressed to sales_engineer by fn_it_backup_check (a literal in the
--     IT engineer's file, with its own handler); moving that conversation needs a handler on the IT side
--     and is left to the it_engineer seat.
--   * fn_it_loop_open sends an IT finding to the function's owner only if an it.finding conversation to
--     that seat exists; there is none to it_engineer, so findings on the functions moved here go to the
--     CEO, as they already do for resilience_ping and it_engineer. Not changed here.
--   * The founder ruling of 7 Sep (two agents) is superseded by the five seats in function_owner_owner_ck.
--
--   node scripts/apply_sql.mjs scripts/sql/every_deployed_function_has_exactly_one_right_owner.sql --apply --ddl
--   node scripts/checks/every_deployed_function_has_an_owner.mjs     -> must EXIT 0

insert into public.function_owner (function_slug, owner, note) values
  ('complaint_status', 'customer_support',
   'Public complaint ticket lookup behind /complaints/status. Owner customer_support from 22 Sep 2026: complaints are support''s, and the clock that watches them (fn_complaint_clock_tick) is support''s too.'),
  ('public_site', 'customer_support',
   'The no-sign-in endpoints behind the public website (counters, route_brief, price_guidance, worked_case). Owner customer_support from 22 Sep 2026: the homepage is support''s surface (the same ruling as home, 15 Sep).')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

update public.function_owner
   set owner = 'it_engineer',
       note  = 'Owner it_engineer from 22 Sep 2026 (founder instruction 583): sign-in codes and roles are a platform service, not agent work (founder, 14 Sep 2026).'
 where function_slug in ('login_otp', 'mobile_otp', 'voice_otp', 'voice_otp_capture', 'role_guard');

update public.function_owner
   set owner = 'it_engineer',
       note  = 'Owner it_engineer from 22 Sep 2026 (founder instruction 583): the nightly Dropbox backup is IT work; on sales_engineer its re-file handoffs waited in the sales queue (staff audit, 21 Sep).'
 where function_slug = 'dropbox_backup';

update public.function_owner
   set owner = 'it_engineer',
       note  = 'Owner it_engineer from 22 Sep 2026 (founder instruction 583): the model switchboard every seat calls is infrastructure. OpenRouter stays on hold; callers stay flag-gated.'
 where function_slug = 'ai_gateway';

update public.function_owner
   set owner = 'sales_engineer',
       note  = 'Owner sales_engineer from 22 Sep 2026 (founder instruction 583): reading a supplier''s licence and documents is supplier verification, the sales engineer''s (ruling of 9 Sep 2026).'
 where function_slug in ('license_extract', 'doc_extract', 'extract_text');

-- Records outliving their subject: none of these is a deployed function (measured above). Website pages
-- are Next.js routes, not edge functions, and have no row here.
delete from public.function_owner
 where function_slug in ('about', 'auth_api', 'faq', 'home', 'home-ar', 'i18n_get', 'legal', 'portal',
                         'public_stats', 'quote_pdf', 'sup_dob');

-- A moves_to that now names the owner would violate function_owner_moves_elsewhere_ck; the updates above
-- would have failed on it. Stated, not assumed: the verdict row below reads the end state.
select case
  when (select count(*) from public.function_owner
         where (function_slug in ('login_otp','mobile_otp','voice_otp','voice_otp_capture','role_guard','dropbox_backup','ai_gateway') and owner <> 'it_engineer')
            or (function_slug in ('license_extract','doc_extract','extract_text') and owner <> 'sales_engineer')
            or (function_slug in ('complaint_status','public_site') and owner <> 'customer_support')) = 0
   and (select count(*) from public.function_owner where function_slug in ('complaint_status','public_site')) = 2
   and not exists (select 1 from public.function_owner where function_slug in
         ('about','auth_api','faq','home','home-ar','i18n_get','legal','portal','public_stats','quote_pdf','sup_dob'))
  then 'PROBE OK: 12 functions on their right seat, 11 stale rows gone'
  else 'PROBE FAILED: the ownership end state is not what this file writes' end as verdict;
