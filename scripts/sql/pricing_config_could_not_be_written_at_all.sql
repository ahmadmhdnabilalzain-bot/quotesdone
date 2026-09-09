-- PRICING_CONFIG COULD NOT BE WRITTEN AT ALL, AND NOTHING SAID SO.
--
-- Found 9 September 2026 by the positive control in
-- scripts/checks/every_seat_carries_the_company_knowledge.test.mjs, which changes the reveal rate
-- inside an aborted transaction to prove the company block READS pricing_config rather than carrying
-- the figures as literals. The update never got as far as being rolled back:
--
--   ERROR: 42883: function fn_company_facts_sync() does not exist
--   CONTEXT: PL/pgSQL function trg_pricing_facts() line 2 at PERFORM
--   SQL statement "update public.pricing_config set standard_reveal_rate = ..."
--
-- fn_company_facts_sync() was DROPPED on 7 September 2026 with the rest of the structure the founder
-- removed (scripts/sql/DROPPED.txt line 319). Its trigger was not. trg_pricing_config_facts is an
-- AFTER INSERT OR UPDATE FOR EACH STATEMENT trigger whose whole body is `perform
-- fn_company_facts_sync()`, so since that day EVERY insert and EVERY update to public.pricing_config
-- has thrown.
--
-- WHAT THAT MEANS IN PRACTICE. pricing_config is where the reveal rate, the supplier registration fee
-- and free count, the refund window and chase day, the bank settlement range and the category-open
-- threshold live -- the numbers the founder actually changes when he changes commercial policy. Not
-- one of them could be changed. Nothing surfaced it because nobody had written to the table since
-- 6 September, and a table that is only read never exercises its own triggers. This is the estate's
-- "guarded by a condition that cannot occur" lens inverted: a hook that CANNOT NOT fire, pointed at
-- a routine that no longer exists.
--
-- THE FIX IS DELETION, NOT RESURRECTION. fn_company_facts_sync existed to PUSH the pricing facts into
-- agent_knowledge '_global' whenever they changed -- a cache, kept in step by a trigger. As of today
-- public.fn_company_context() READS pricing_config at call time and pins the result into all five
-- seats on every answer, so there is nothing left to push and nothing left to drift. The trigger and
-- its function go; the facts reach the seats by being read, which is the stronger arrangement.
--
-- PROVED BY EXECUTION at the end of this file: an update to pricing_config that is rolled back. It
-- raises if the write is still refused.
--
--   node scripts/apply_sql.mjs scripts/sql/pricing_config_could_not_be_written_at_all.sql --apply --ddl

drop trigger if exists trg_pricing_config_facts on public.pricing_config;
drop function if exists public.trg_pricing_facts();

-- THE WRITE IS PROVED, AND NOTHING IS LEFT BEHIND. The row is changed, counted and rolled back by
-- the raise, so a re-run of this file measures the same thing again rather than a residue.
-- The inner BEGIN/EXCEPTION is a subtransaction: raising inside it undoes the write and lets the
-- file's own DDL commit. A bare `raise` at the end would have taken the two DROPs down with it.
do $proof$
declare v_rate numeric;
begin
  begin
    update public.pricing_config
       set standard_reveal_rate = 0.077, promo_reveal_rate = 0.077
     where id = (select id from public.pricing_config order by id limit 1);
    select standard_reveal_rate into v_rate from public.pricing_config order by id limit 1;
    if v_rate is distinct from 0.077 then
      raise exception 'pricing_config accepted the write but did not take it: %', v_rate;
    end if;
    raise exception 'ZZ_PROBE_ROLLBACK rate=%', v_rate;
  exception when raise_exception then
    if position('ZZ_PROBE_ROLLBACK' in sqlerrm) = 0 then raise; end if;
    raise notice 'PROOF: pricing_config is writable again (%). The probe rolled back.', sqlerrm;
  end;
  select standard_reveal_rate into v_rate from public.pricing_config order by id limit 1;
  if v_rate = 0.077 then
    raise exception 'the probe did NOT roll back: the live reveal rate is 0.077';
  end if;
end $proof$;
