-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629221309   name: fraud_guard_disposable_signup
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function block_disposable_signup()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare em text;
begin
  if TG_TABLE_NAME = 'customers' then
    em := NEW.email;
  else
    -- only gate genuine supplier signups; leave scraped leads (claimed false/null) untouched
    if NEW.claimed is distinct from true then return NEW; end if;
    em := coalesce(NEW.claimed_by, NEW.email);
  end if;
  if em is not null and is_disposable_email(em) then
    raise exception 'Please use a permanent email address; temporary inboxes are not allowed.' using errcode = '23514';
  end if;
  return NEW;
end$$;

drop trigger if exists trg_block_disposable_customers on customers;
create trigger trg_block_disposable_customers before insert on customers
  for each row execute function block_disposable_signup();

drop trigger if exists trg_block_disposable_leads on leads;
create trigger trg_block_disposable_leads before insert on leads
  for each row execute function block_disposable_signup();

