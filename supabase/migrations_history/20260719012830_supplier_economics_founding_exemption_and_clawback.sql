-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719012830   name: supplier_economics_founding_exemption_and_clawback
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Supplier commercial rules, implemented to the founder's stated terms (19 Jul 2026).
--
-- RULE 1  Annual subscription AED 1,000 from 1 Aug 2027, EXCEPT the first 1,000 registrants,
--         who are exempt permanently.
-- RULE 2  When a customer is refunded, QuotesDone pays the refund from its own balance first so
--         the customer does not wait, then charges the supplier: the 3% reveal fee + AED 250
--         admin fee + monthly interest. After 3 months unpaid the supplier is banned and the
--         matter goes to legal, evidenced by the signed terms & conditions.

-- ---------------------------------------------------------------------------------------------
-- 1. Config (kept in gl_settings so it is auditable and changeable in one place)
-- ---------------------------------------------------------------------------------------------
insert into public.gl_settings(key, num_value, txt_value) values
  ('clawback_admin_fee_aed', 250,
   'Flat administration fee added to a refund clawback at the moment the refund is issued.'),
  ('clawback_interest_monthly_pct', 0.75,
   'Monthly interest on an unpaid refund clawback. 0.75%/month = 9% per annum, the UAE statutory commercial rate - chosen over a higher penalty rate because it is the figure most likely to survive challenge if a case reaches court.'),
  ('clawback_ban_days', 90,
   'Days past the due date before the supplier is banned and the debt is escalated to legal.')
on conflict (key) do update set num_value = excluded.num_value, txt_value = excluded.txt_value;

-- ---------------------------------------------------------------------------------------------
-- 2. RULE 1 - make the founding-1000 exemption actually bind.
--
-- THE BUG: supplier_api.setRegistration() marks the first N registrants
-- registration_status='free', but v_supplier_billing decides who to invoice by reading
-- leads.subscription_exempt - and NOTHING ever set that column. founding_rank was null on all
-- 20,465 leads and founding_free_limit appeared only in the wording of a summary email. Left as
-- it was, the 1 Aug 2027 billing run would have invoiced AED 1,000 to every approved supplier
-- INCLUDING the founding members who were promised lifetime exemption (a promise the WhatsApp
-- assistant states explicitly).
--
-- Fixed in the database rather than in supplier_api so it binds no matter which code path
-- registers a supplier.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_assign_founding_rank()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_limit int; v_rank int;
begin
  -- Only rank a supplier once, and only once they are a real registered supplier.
  if coalesce(new.claimed,false) is not true then return new; end if;
  if new.founding_rank is not null then return new; end if;

  v_limit := coalesce((select nullif(value,'')::int from public.app_secrets where key='founding_free_limit'), 1000);

  -- Serialise rank assignment so two concurrent registrations cannot take the same number.
  perform pg_advisory_xact_lock(hashtext('qd_founding_rank'));
  select coalesce(max(founding_rank),0) + 1 into v_rank from public.leads;

  new.founding_rank := v_rank;
  -- Exemption is permanent: it is stamped at registration and never recalculated, so a supplier
  -- who was inside the first 1,000 stays exempt even as the base grows.
  new.subscription_exempt := (v_rank <= v_limit);
  return new;
end;
$$;

drop trigger if exists trg_assign_founding_rank on public.leads;
create trigger trg_assign_founding_rank
  before insert or update of claimed on public.leads
  for each row execute function public.fn_assign_founding_rank();

-- ---------------------------------------------------------------------------------------------
-- 3. RULE 2 - clawback now carries the AED 250 admin fee from the moment the refund is issued.
-- ---------------------------------------------------------------------------------------------
create or replace function public.qd_on_refund_resolved()
returns trigger
language plpgsql
as $$
declare v_fee numeric; v_admin numeric;
begin
  if NEW.refund_status in ('refunded','approved') and (OLD.refund_status is distinct from NEW.refund_status) then
    v_fee   := coalesce(NEW.reveal_fee, NEW.app_fee, 0);
    v_admin := coalesce((select num_value from public.gl_settings where key='clawback_admin_fee_aed'), 250);

    if not exists (select 1 from public.supplier_dues where transaction_id=NEW.id and coalesce(status,'')<>'cancelled') then
      insert into public.supplier_dues(
        transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
        amount_due, admin_fee, interest_amount, currency,
        reveal_date, due_date, due_date_30, status, created_at)
      values(
        NEW.id, NEW.supplier_id, NEW.quote_id, NEW.quote_amount, 3,
        v_fee,          -- the 3% reveal fee QuotesDone already refunded to the customer
        v_admin,        -- flat administration fee, charged immediately per the supplier terms
        0,              -- interest starts accruing only once the due date passes
        'AED',
        NEW.revealed_at, (now()+interval '7 days'), (now()+interval '30 days'), 'due', now());
    end if;

    update public.leads
      set matching_blocked = true,
          matching_block_reason = 'Unsettled non-response charge (customer refunded due to no response)',
          rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds,0)+1
    where id = NEW.supplier_id;

    if NEW.refund_resolved_at is null then NEW.refund_resolved_at := now(); end if;
  end if;
  return NEW;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. RULE 2 - monthly interest.
--
-- Deliberately RECOMPUTED from the due date each run rather than incremented. An incrementing
-- accrual double-charges if the job runs twice, is retried, or is backfilled; recomputation is
-- idempotent and always defensible as "principal x rate x whole months overdue".
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accrue_dues_interest()
returns integer
language plpgsql
as $$
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
      and coalesce(d.status,'') not in ('paid','settled','waived','cancelled')
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
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. RULE 2 - ban + legal escalation after 3 months unpaid.
--
-- Escalation records whether the signed terms exist, because that document is the evidentiary
-- basis for filing. A missing signature does not stop the ban (the debt is still real) but it is
-- surfaced loudly, so a case is never prepared on evidence that cannot be produced.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ban_overdue_dues()
returns integer
language plpgsql
as $$
declare r record; v_days int; v_n int := 0; v_admin text;
begin
  v_days  := coalesce((select num_value from public.gl_settings where key='clawback_ban_days'), 90)::int;
  v_admin := coalesce((select split_part(value,',',1) from public.app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select d.id, d.supplier_id, d.amount_due, d.admin_fee, d.interest_amount, d.due_date,
           l.company_name, coalesce(l.claimed_by,l.email) as email,
           l.accepted_terms_at, l.accepted_terms_version, l.signed_terms_path, l.banned
    from public.supplier_dues d
    join public.leads l on l.id = d.supplier_id
    where d.paid_at is null
      and coalesce(d.status,'') not in ('paid','settled','waived','cancelled')
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
      and current_date >= (d.due_date::date + v_days)
      and d.legal_escalated_at is null
  loop
    update public.supplier_dues
       set status = 'legal', legal_stage = 'pending_case', legal_escalated_at = now()
     where id = r.id;

    update public.leads
       set banned = true,
           banned_reason = 'Unpaid refund clawback of AED ' ||
                           round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
                           ' more than ' || v_days || ' days past due (due ' || r.due_date::date || ').',
           matching_blocked = true,
           matching_block_reason = 'Banned: unpaid refund clawback escalated to legal'
     where id = r.supplier_id;

    insert into public.founder_alerts(level, event, detail, channel)
    values ('crit', 'supplier_banned_legal',
      coalesce(r.company_name,'Supplier #'||r.supplier_id) || ' has been banned and due #' || r.id ||
      ' escalated to legal: AED ' || round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
      ' unpaid for over ' || v_days || ' days. ' ||
      case when r.accepted_terms_at is null
           then '*** NO SIGNED TERMS ON RECORD - the supplier agreement cannot be produced as evidence, so a filing may not be supportable. Verify before instructing the legal agent. ***'
           else 'Terms accepted ' || r.accepted_terms_at::date || ' (version ' || coalesce(r.accepted_terms_version,'?') || ') - available as supporting evidence.'
      end, 'system');

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- Daily: accrue interest, then ban anything that has crossed the threshold.
select cron.schedule('dues_interest_daily', '15 3 * * *', $$select public.fn_accrue_dues_interest();$$)
where not exists (select 1 from cron.job where jobname = 'dues_interest_daily');

select cron.schedule('dues_ban_overdue_daily', '25 3 * * *', $$select public.fn_ban_overdue_dues();$$)
where not exists (select 1 from cron.job where jobname = 'dues_ban_overdue_daily');
