-- AUDIT §6, 3 Aug 2026. The founding free slot now turns on VERIFICATION, not on claiming.
--
-- Founder, 3 Aug: "the first 1000 verified supplier, so if someone just registered without filling
-- out the mandatory fields then he is not verified still."
--
-- Before: trg_assign_founding_rank fired BEFORE INSERT OR UPDATE OF claimed and awarded a permanent
-- slot on claimed=true alone. A business could click "claim my listing", take slot #7, never upload
-- a trade licence, and hold a permanent exemption from the AED 1,000/year subscription. The 20,464
-- rows are scraped leads, not a vetted supplier list; claiming proves nothing.
--
-- Two deliberate changes, and they are not redundant:
--   1. The trigger no longer lists columns. The old `UPDATE OF claimed` form fires on the columns
--      NAMED IN THE STATEMENT, not on what the row becomes — so `UPDATE leads SET verified=true`
--      would never have fired a `UPDATE OF claimed` trigger, and switching the list to
--      `UPDATE OF verified` would simply move the same blind spot. Firing on every UPDATE and
--      guarding inside is the only form that cannot be bypassed by the shape of the statement.
--      Cost is two boolean tests per row on bulk jobs; every non-verified and every already-ranked
--      row returns before doing any work.
--   2. founding_rank_daily is re-enabled (separately, via cron.alter_job) as a backstop. It only
--      fills NULLs, so it can never renumber or double-award.
--
-- Zero residue to unwind: founding_rank is NULL on all 20,464 rows and claimed = 0.

CREATE OR REPLACE FUNCTION public.fn_assign_founding_rank()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_limit int; v_rank int;
begin
  -- Rank a supplier once, and only once they are a VERIFIED supplier. Claiming a scraped listing
  -- is not registration; registration without documents is not verification.
  if new.founding_rank is not null then return new; end if;
  if coalesce(new.verified,false) is not true then return new; end if;
  if coalesce(new.banned,false) is true then return new; end if;
  if coalesce(new.approval_status,'') in ('rejected','action_required') then return new; end if;

  v_limit := coalesce((select nullif(value,'')::int from public.app_secrets where key='founding_free_limit'), 1000);

  -- Serialise rank assignment so two concurrent verifications cannot take the same number.
  perform pg_advisory_xact_lock(hashtext('qd_founding_rank'));
  select coalesce(max(founding_rank),0) + 1 into v_rank from public.leads;

  new.founding_rank := v_rank;
  -- Exemption is permanent: it is stamped at verification and never recalculated, so a supplier
  -- who was inside the first 1,000 stays exempt even as the base grows.
  new.subscription_exempt := (v_rank <= v_limit);
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_assign_founding_rank ON public.leads;
CREATE TRIGGER trg_assign_founding_rank
  BEFORE INSERT OR UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.fn_assign_founding_rank();

-- The batch backstop, now agreeing with the trigger. `claimed` is dropped as a condition for the
-- same reason: verification is the rule, and verification implies registration.
CREATE OR REPLACE FUNCTION public.fn_assign_founding_ranks()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_limit int; v_max int; v_assigned int := 0;
begin
  v_limit := coalesce((select nullif(value,'')::int from app_secrets where key='founding_free_limit'), 1000);
  select coalesce(max(founding_rank),0) into v_max from leads;
  with candidates as (
    select id, row_number() over (
             order by coalesce(approved_at, registration_submitted_at, created_at) asc, id asc) + v_max as new_rank
    from leads
    where founding_rank is null
      and coalesce(verified,false) = true
      and coalesce(banned,false) = false
      and coalesce(approval_status,'') not in ('rejected','action_required')
  )
  update leads l set founding_rank = c.new_rank,
                     subscription_exempt = (c.new_rank <= v_limit)
  from candidates c where l.id = c.id;
  get diagnostics v_assigned = row_count;
  return json_build_object('newly_ranked', v_assigned, 'highest_rank', (select coalesce(max(founding_rank),0) from leads),
                           'founding_slots_left', greatest(0, v_limit - (select count(*) from leads where founding_rank is not null)),
                           'free_limit', v_limit);
end $function$;;
