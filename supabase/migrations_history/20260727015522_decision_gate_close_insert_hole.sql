-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727015522   name: decision_gate_close_insert_hole
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The Layer-4 run found a hole in my own gate: trg_decision_gate was BEFORE UPDATE only,
-- so a row could be INSERTED already marked 'approved' and skip the impact requirement
-- entirely. A gate you can walk around is not a gate.
create or replace function public.fn_decision_gate() returns trigger
language plpgsql as $fn$
declare v_was text;
begin
  v_was := case when tg_op = 'UPDATE' then coalesce(old.status,'') else '' end;

  if new.status in ('approved','executed') and v_was not in ('approved','executed') then
    if coalesce(length(new.impact_business),0)  < 20
    or coalesce(length(new.impact_financial),0) < 20
    or coalesce(length(new.impact_legal),0)     < 10
    or coalesce(length(new.impact_customer),0)  < 20
    or jsonb_array_length(coalesce(new.evidence,'[]'::jsonb)) = 0 then
      raise exception 'decision cannot be % : impact analysis incomplete (business/financial/legal/customer + evidence are all required)', new.status;
    end if;
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_decision_gate on public.decision_record;
create trigger trg_decision_gate before insert or update on public.decision_record
for each row execute function public.fn_decision_gate();

revoke execute on function public.fn_decision_gate() from anon, authenticated, public;
