-- A COMPANY REGISTERED BY A COLLEAGUE IS NOT NUDGED AT ITS INVITED ADDRESS (28 Oct 2026, sales_engineer; founder ledger
-- 1401, the supplier-journey audit, browser half, scenario S7).
--
-- MEASURED on production, 28 Oct 2026, run b4e8a7fe, ZZ DEMO only, 390 px: an invited lead (unclaimed, never clicked) and
-- a colleague of the same company who signs up on quotesdone.com with HIS OWN address and types the same company name.
-- supplier_api create_company answered HTTP 200 and inserted a second lead, claimed by the colleague (lead 151797 beside
-- the invited 151781). #1712 (the invited ADDRESS claims its own listing) does not cover it: its insert path refuses only
-- a CLAIMED twin, and here the twin was unclaimed. Linking by name alone is not safe (anyone could type a competitor's
-- name), so the second row stays. What is wrong is what happens next:
--   * the invited row stays unclaimed and unclicked, so fn_supplier_invite_nudges_due nudges the company on day 3, 7 and
--     14 to register, after it has registered; and a reply "yes" earns a claim link that cannot work, because
--     leads_claimed_company_name_uidx (one CLAIMED lead per fn_company_registration_name_key) refuses the claim;
--   * the same for the registration reminders of a twin that had clicked.
--
-- WHAT THIS CHANGES: fn_supplier_name_registered_by_another(lead) is true when ANOTHER lead already holds this lead's
-- company name as a registered (claimed) company, by the very key the unique index enforces. Such a lead can never be
-- claimed, so fn_supplier_outreach_reachable (the gate of the nudges, the registration reminders and their send) now
-- treats it as unreachable. A claimed lead is never its own twin (the index allows one claimed lead per key), so no
-- registered supplier loses a reminder. Measured before the change: of the 25 leads in outreach today (invited,
-- nudged, reminded or clicked), 0 have a registered twin, so no real list moves on the day this is applied.
--
-- WHAT IT DOES NOT CHANGE:
--   * the FIRST invitation (fn_supplier_invite_eligible / fn_supplier_invite_eligible_ids). The set form reads ~20,083
--     uninvited leads, and computing the name key over them costs about 2.5 s (measured 28 Oct, read-only), on a batch
--     that has already hit a time limit once; and the per-row form is the a07 guard's test, so the two must change
--     together. A company that self-registered before its directory row was invited can still be invited once. That is
--     a separate change, with the key stored on the row first.
--   * create_company. The colleague's row stays: merging two rows without proof that he controls the invited address
--     is a takeover door, and the merge belongs to the sales engineer.
--   * fn_supplier_invite_nudges_due itself (#1713 redefines it; the gate it calls is changed instead).
--
-- Prevented by scripts/checks/a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.test.mjs (the
-- definition that wins the apply order must call the twin rule, and the rule must compare the unique index's key with
-- another CLAIMED lead), and proved on production by the probe file of the same name (rolled back).

create or replace function public.fn_supplier_name_registered_by_another(p public.leads)
returns boolean
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- the same key, and the same CLAIMED predicate, as leads_claimed_company_name_uidx: the index answers the lookup
  select public.fn_company_registration_name_key(p.company_name) is not null
     and exists (select 1 from public.leads t
                  where t.claimed
                    and t.id <> p.id
                    and public.fn_company_registration_name_key(t.company_name) = public.fn_company_registration_name_key(p.company_name))
$fn$;
revoke execute on function public.fn_supplier_name_registered_by_another(public.leads) from public, anon, authenticated;

create or replace function public.fn_supplier_outreach_reachable(p public.leads, p_to text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p_to), '') <> ''
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p_to)
     and not public.fn_is_demo_email(p.email)
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.invite_status, '') <> 'bounced'
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     and coalesce((public.fn_email_sendable(p_to)->>'ok')::boolean, false)
     -- the company is already registered under this name by another account: this row can never be claimed
     and not public.fn_supplier_name_registered_by_another(p)
$fn$;
