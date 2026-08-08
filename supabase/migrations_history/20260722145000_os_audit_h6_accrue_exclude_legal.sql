-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722145000   name: os_audit_h6_accrue_exclude_legal
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

CREATE OR REPLACE FUNCTION public.fn_accrue_dues_interest()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rate numeric; v_updated int := 0;
begin
  v_rate := coalesce((select num_value from public.gl_settings where key='clawback_interest_monthly_pct'), 0.75) / 100.0;

  with calc as (
    select d.id,
           round(coalesce(d.amount_due,0) * v_rate *
                 greatest(0, (date_part('year',  age(current_date, d.due_date::date)) * 12
                            + date_part('month', age(current_date, d.due_date::date)))::int), 2) as want
    from public.supplier_dues d
    where d.paid_at is null
      -- H6 (OS audit): once collections_legal has escalated a due it FREEZES the interest; the monthly
      -- accrual must not overwrite that frozen figure, so exclude legal-stage dues here.
      and coalesce(d.status,'') not in ('paid','settled','waived','cancelled','legal')
      and d.legal_stage is null
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
  )
  update public.supplier_dues d
     set interest_amount = c.want
    from calc c
   where c.id = d.id
     and coalesce(d.interest_amount,0) is distinct from c.want;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;
