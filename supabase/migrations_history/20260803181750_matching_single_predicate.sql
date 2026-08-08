-- AUDIT §3, 3 Aug 2026. ONE definition of matchability.
--
-- Before this migration four functions decided matchability and all four disagreed. Verified live,
-- not from the code alone:
--   match_suppliers        pool = 516   (blocked/approval only  -> served unregistered scraped leads)
--   match_suppliers_kw     pool = 0     (extra registration gate no lead can satisfy)
--   fn_match_capability    pool = 0     (supplier_capabilities is empty)
--   fn_supplier_matchable  pool = 20464 (approval_status only)
-- Note in particular that NO function gated on `verified` at all. match_suppliers_kw referenced it
-- only as a +2 SCORING bonus, never as a filter, so an unverified supplier ranked lower and still
-- matched. Which rule an enquiry met depended on which code path it took.
--
-- Founder's rule, 3 Aug: "as long as the supplier is verified and he is able to do the scope then
-- it's a match; the exceptions are that he is blocked for several no-response occasions with a
-- customer, or his documents are expired and he still hasn't shared the updated ones."
--
-- Which column means "verified" was settled by evidence, not preference: the ONLY writer of either
-- column is fn_supplier_autoapprove_clean, and it sets approval_status='approved', verified=true and
-- verification_status='verified' in a single UPDATE. They cannot drift. `verified` (boolean) is the
-- gate; approval_status is kept as defence in depth because a later document expiry can move it to
-- 'action_required' without touching `verified`.
--
-- Safe to apply now and only now: 0 verified suppliers, 0 inquiries ever, 0 inquiry_matches.
-- After the first customer enquiry this change has consequences every single day.

-- 1. The threshold, in the policy table where the other matching knobs already live.
insert into public.decision_policy(key, value, description, updated_at)
values ('matching_strike_limit', '3'::jsonb,
        'Consecutive unanswered RFQs before a supplier stops receiving them. Founder decision, 3 Aug 2026.',
        now())
on conflict (key) do update set value = excluded.value,
                                description = excluded.description,
                                updated_at = now();

create or replace function public.fn_matching_strike_limit()
 returns integer
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $$
  select coalesce((select value::text::int from public.decision_policy where key='matching_strike_limit'), 3);
$$;

-- 2. THE definition. Everything else delegates here. Column-taking rather than id-taking so the
--    planner can inline it into a set query instead of running it per row.
create or replace function public.fn_is_matchable(
  p_verified            boolean,
  p_banned              boolean,
  p_matching_blocked    boolean,
  p_approval_status     text,
  p_permanently_closed  boolean,
  p_chat_strikes        integer
) returns boolean
 language sql
 stable
 parallel safe
 set search_path to 'public', 'pg_temp'
as $$
  select coalesce(p_verified, false)                                        -- the rule: verified
     and coalesce(p_banned, false) = false
     and coalesce(p_matching_blocked, false) = false                        -- carries expired documents,
                                                                            -- reconciled daily by
                                                                            -- fn_reconcile_doc_blocks(0)
     and coalesce(p_permanently_closed, false) = false                      -- never RFQ a closed business
     and coalesce(p_approval_status, '') not in ('action_required','rejected')
     and coalesce(p_chat_strikes, 0) < public.fn_matching_strike_limit();   -- the no-response exception
$$;

comment on function public.fn_is_matchable(boolean,boolean,boolean,text,boolean,integer) is
  'AUDIT 3 Aug 2026. The single definition of supplier matchability. Every matching path must '
  'delegate to this. If you are about to write a matchability condition anywhere else, do not.';

-- 3. Existing id-taking entry point kept (edge functions call it by this signature) and delegated.
create or replace function public.fn_supplier_matchable(p_lead_id bigint)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $$
  select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                l.approval_status, l.permanently_closed, l.chat_strikes)
    from public.leads l where l.id = p_lead_id;
$$;;
