-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727021708   name: ap_bills_allow_duplicate_hold_status
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.ap_bills drop constraint if exists ap_bills_status_check;
alter table public.ap_bills add constraint ap_bills_status_check
  check (status = any (array['open','partial','paid','void','duplicate_hold']));

create or replace function public.fn_ap_pay_block_held() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.status in ('paid','partial') and coalesce(old.status,'') = 'duplicate_hold' then
    raise exception 'bill % is held as a duplicate and cannot be paid until a person clears the hold',
      coalesce(new.bill_no, new.id::text);
  end if;
  return new;
end; $fn$;

drop trigger if exists trg_ap_pay_block_held on public.ap_bills;
create trigger trg_ap_pay_block_held before update on public.ap_bills
for each row execute function public.fn_ap_pay_block_held();

revoke execute on function public.fn_ap_pay_block_held() from anon, authenticated, public;
