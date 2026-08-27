-- SPEC FILE #3 — three capabilities that exist in code and had no row to stand on.
--
-- Each of these is a GENUINELY_ABSENT line from docs/phase-d/SPEC3_MISSING_CLASSIFICATION.csv, and
-- each is a row rather than a routine, because in all three cases the routine was already written
-- and reachable and the thing missing was the record it reads.
--
--   1. agent_knowledge for product_ux_designer — 1 of 90 active employees held no knowledge at all.
--   2. cron_registry for phase_c_outbox_deliver_1min — 1 of 23 active jobs was undocumented.
--   3. supplier_negotiation_policy scope 'default' — the table was empty and its only consumer,
--      fn_negotiation_guidance, returns 'no_policy' and proposes nothing when it is.
--
-- Every insert is idempotent on the key it is about, so re-applying this file is a no-op rather
-- than a duplicate.

begin;

-- ── 1. THE EMPLOYEE HIRED AFTER THE BACKFILL ────────────────────────────────────────────────────
-- product_ux_designer was hired 2026-08-15, after session16's profession backfill had already run,
-- so it inherited none of it: every other active employee holds at least one profession-layer row
-- and this one held zero. Measured:
--   select count(*) from org_agents a where a.active
--    and not exists (select 1 from agent_knowledge x where x.agent_key = a.agent_key);  -- 1
--
-- The row is written in the same shape as its peers in product_eng — one profession-layer entry,
-- owned by knowledge_director — so the metadata trigger a00_agent_knowledge_metadata stamps the
-- seven fields s27-knowledge-seven-fields asks for exactly as it does for the other eighty-nine.
-- source_ref names THIS session rather than borrowing session16's, because it was not written then.
insert into public.agent_knowledge (agent_key, topic, content, priority, layer, source_ref, owner_agent)
select 'product_ux_designer',
       'Designing an interface for a marketplace where the parties are anonymous until they pay',
       'The screens you design carry the anonymity rule, not just the backend. Until a reveal is paid '
       || 'for, a customer must not be able to identify a supplier and a supplier must not be able to '
       || 'identify a customer — that includes avatars, initials, company logos, file names on '
       || 'attachments, email addresses quoted inside message bodies, and anything a browser caches or '
       || 'a screen reader announces. Design the pre-reveal state first and treat the revealed state as '
       || 'the exception, because the reverse order is how identifying detail leaks into a component '
       || 'that was only ever tested after a reveal. Accessibility is part of the same job: a masked '
       || 'field still needs a label that says what it is and why it is masked, or the interface reads '
       || 'as broken rather than as deliberate.',
       74, 'profession', 'spec3:2026-08-27:employee-knowledge', 'knowledge_director'
where exists (select 1 from public.org_agents where agent_key = 'product_ux_designer' and active)
  and not exists (select 1 from public.agent_knowledge where agent_key = 'product_ux_designer');

-- ── 2. THE ACTIVE JOB THE MANUAL DID NOT KNOW ABOUT ─────────────────────────────────────────────
-- s38-manual-always-current measures drift in both directions. Ghost direction: 0. Undocumented
-- direction: 1, and it is phase_c_outbox_deliver_1min, added with the Phase C outbox and never
-- registered. Measured:
--   select j.jobname from cron.job j where j.active
--    and not exists (select 1 from cron_registry r where r.jobname = j.jobname);
--
-- This does NOT turn s38 green on its own: the check also asks that fn_sop_update has succeeded in
-- the last fortnight, and sop_update_weekly is paused under the founder's stand-down. The drift half
-- is a real gap and is fixed here; the liveness half stays red, correctly.
insert into public.cron_registry (jobname, human_name, category, purpose)
select 'phase_c_outbox_deliver_1min', 'Phase C Outbox Delivery', 'Operations',
       'fn_kernel_outbox_deliver(25, ''cron:phase_c_outbox_deliver_1min'') — drains the Phase C kernel '
       || 'outbox in batches of 25 every minute, so an effect committed inside a kernel transaction is '
       || 'delivered outside it. Registered 27 Aug 2026; the job has been running since Phase C and was '
       || 'the only active job with no entry in this table.'
where not exists (select 1 from public.cron_registry where jobname = 'phase_c_outbox_deliver_1min');

-- ── 3. THE HOUSE NEGOTIATION POLICY ─────────────────────────────────────────────────────────────
-- fn_negotiation_guidance looks for a per-supplier override, then for scope='default', and returns
-- recommended_action 'no_policy' with a null target price when it finds neither. The table held zero
-- rows, so the AI could not negotiate inside limits because no limits had ever been written down.
--
-- NOTHING COMMERCIAL IS INVENTED HERE. Every number below is one the consumer already falls back to
-- in code — min_sample 4 (which is also fn_price_confidence's own n<4 cutoff) and
-- never_target_below_pct_of_median 80 — and the band names are exactly the five fn_price_confidence
-- returns: insufficient_data, suspiciously_low, suspiciously_high, fair, within_range.
--
-- ask_discount_pct is 0 in every band, deliberately. What discount this company asks a supplier for
-- is a commercial decision and it belongs to the founder, not to this migration. So the house stance
-- is the conservative one that can be stated without holding his intent: below-market and in-range
-- quotes are accepted, above-market quotes are escalated to a human rather than countered with a
-- number nobody authorised. To let the AI counter on its own, raise ask_discount_pct and
-- max_ask_discount_pct on the suspiciously_high band; the floor at 80% of the measured median then
-- bounds whatever is set there.
insert into public.supplier_negotiation_policy (supplier_id, scope, policy, approved_by, approved_at)
select null, 'default',
  jsonb_build_object(
    'min_sample', 4,
    'never_target_below_pct_of_median', 80,
    'authority_source', 'employee_authority.threshold_aed — a negotiator may commit only up to its own '
                     || 'approved threshold; anything above it escalates through the normal approval path',
    'escalate_above_band', 'suspiciously_high',
    'bands', jsonb_build_object(
      'insufficient_data',  jsonb_build_object('action','no_benchmark_yet','ask_discount_pct',0,'max_ask_discount_pct',0),
      'suspiciously_low',   jsonb_build_object('action','confirm_scope','ask_discount_pct',0,'max_ask_discount_pct',0),
      'fair',               jsonb_build_object('action','accept','ask_discount_pct',0,'max_ask_discount_pct',0),
      'within_range',       jsonb_build_object('action','accept','ask_discount_pct',0,'max_ask_discount_pct',0),
      'suspiciously_high',  jsonb_build_object('action','escalate_to_human','ask_discount_pct',0,'max_ask_discount_pct',0)),
    'note', 'Written 27 Aug 2026 for spec file #3 s26-negotiate-limits. Every value here is one the '
         || 'consumer already defaulted to in code. The discount percentages are 0 because the size of '
         || 'a discount this company asks for is the founder''s commercial call.'),
  'spec3:2026-08-27', now()
where not exists (select 1 from public.supplier_negotiation_policy where scope = 'default');

commit;
