-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727001754   name: decision_intelligence_impact_layer
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Decision Intelligence: every decision carries impact analysis + evidence.
alter table public.decision_record
  add column if not exists impact_business  text,
  add column if not exists impact_financial text,
  add column if not exists financial_aed    numeric,
  add column if not exists impact_legal     text,
  add column if not exists impact_customer  text,
  add column if not exists impact_supplier  text,
  add column if not exists evidence         jsonb default '[]'::jsonb,
  add column if not exists reversible       boolean,
  add column if not exists decided_at       timestamptz default now();

create or replace view public.v_decision_intelligence as
select d.id,
       d.decided_by,
       d.dept_key,
       left(d.problem, 90) as problem,
       d.confidence,
       d.status,
       d.financial_aed,
       d.reversible,
       (d.impact_business  is not null and length(d.impact_business)  > 20) as has_business,
       (d.impact_financial is not null and length(d.impact_financial) > 20) as has_financial,
       (d.impact_legal     is not null and length(d.impact_legal)     > 10) as has_legal,
       (d.impact_customer  is not null and length(d.impact_customer)  > 20) as has_customer,
       (jsonb_array_length(coalesce(d.evidence, '[]'::jsonb)) > 0)          as has_evidence,
       case
         when (d.impact_business is not null and length(d.impact_business) > 20)
          and (d.impact_financial is not null and length(d.impact_financial) > 20)
          and (d.impact_legal is not null and length(d.impact_legal) > 10)
          and (d.impact_customer is not null and length(d.impact_customer) > 20)
          and jsonb_array_length(coalesce(d.evidence, '[]'::jsonb)) > 0
         then 'COMPLETE' else 'INCOMPLETE'
       end as intelligence_verdict,
       d.created_at
from public.decision_record d;

-- A decision cannot be approved until its impact analysis is complete.
create or replace function public.fn_decision_gate() returns trigger
language plpgsql as $fn$
begin
  if new.status in ('approved','executed') and coalesce(old.status,'') not in ('approved','executed') then
    if coalesce(length(new.impact_business),0)  < 20
    or coalesce(length(new.impact_financial),0) < 20
    or coalesce(length(new.impact_legal),0)     < 10
    or coalesce(length(new.impact_customer),0)  < 20
    or jsonb_array_length(coalesce(new.evidence,'[]'::jsonb)) = 0 then
      raise exception 'decision % cannot be approved: impact analysis incomplete (business/financial/legal/customer + evidence all required)', new.id;
    end if;
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_decision_gate on public.decision_record;
create trigger trg_decision_gate before update on public.decision_record
for each row execute function public.fn_decision_gate();

revoke execute on function public.fn_decision_gate() from anon, authenticated, public;
