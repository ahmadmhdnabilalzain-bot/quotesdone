-- A PHONE NUMBER IS NOT AN IDENTITY, AND NOTHING IN THE SCHEMA SAID SO.
--
-- 13 Aug 2026. The founder registered as a customer with djzaino@outlook.com, signed in on his
-- mobile, opened /me -> Account and was shown management@quotesdone.com. He read it correctly as
-- an identity bug rather than a display bug, and it is one.
--
-- WHAT WAS MEASURED ON PRODUCTION BEFORE ANY CHANGE:
--
--   customers: only customers_pkey on id. No unique index on email. No unique index on phone.
--   70f15bc3  ahmad test    djzaino@outlook.com        +971509319355  13 Aug 00:56
--   a6d900ab  ahmad test 2  management@quotesdone.com  +971509319355  13 Aug 02:33   <- same phone
--
--   app_secrets.admin_mfa_phone = +971509319355          (his mobile)
--   app_secrets.admin_emails[0] = management@quotesdone.com
--
-- THREE PHONE-KEYED IDENTITY PATHS EXISTED IN login_otp, AND EVERY ONE COULD RETURN SOMEONE ELSE:
--
--   1. resolveEmailByPhone() called resolveAdminEmailByPhone() FIRST and UNCONDITIONALLY, before
--      it ever looked at `kind`. Any CUSTOMER signing in by SMS from a number listed in
--      admin_mfa_phone was handed admin_emails[0]. It fires deterministically, every time.
--   2. Both remaining branches were `ilike '%'||last9` + limit(1) with NO ORDER BY, so with two
--      rows on one number Postgres returned whichever it liked.
--   3. The verify branch resolved the account from the newest phone_verifications row for the
--      number - i.e. whoever last asked for a code on that handset - in preference to the account
--      tables themselves.
--
-- THE RECORDED EXECUTION, not an inference. phone_verifications stores the resolver's own output
-- at the moment the code is sent:
--   19:44:14  +971509319355 -> management@quotesdone.com   (login_otp wrote this; no customers
--                                                           row was created at 19:44, so it was a
--                                                           sign-in, not a registration)
--   auth.users.last_sign_in_at for management@quotesdone.com = 19:44:27
-- He then opened /me and saw that address. Three records agree.
--
-- THE IDENTITY RULE, DECIDED AND NOW ENFORCED IN THE SCHEMA RATHER THAN ONLY IN CODE:
--
--   EMAIL IS THE IDENTITY. It is what the customer types, what the OTP is delivered to, and what
--   every one of the ~20 server-side lookups already keys on. Unique on lower(btrim(email)).
--
--   PHONE MAY REPEAT, DELIBERATELY, AND IS THEREFORE NOT AN IDENTITY. In the UAE one number is
--   routinely shared by a family, by colleagues, and by a whole company through a single office
--   landline - this estate already holds the founder's office landline on one customer record and
--   his mobile on another. A unique index on phone would lock out real buyers to fix a defect that
--   is not theirs. So phone stays repeatable, and the consequence is written down here and
--   enforced in login_otp: a phone may CONFIRM an identity, never SELECT one. Where a number maps
--   to more than one account the sign-in is refused (HTTP 409) and the caller is asked for their
--   email. Refusing is correct; guessing is how you hand someone another person's account.
--
-- WHY AN EXPRESSION INDEX AND NOT `UNIQUE (email)`: 'Ahmad@X.com' and 'ahmad@x.com' are the same
-- mailbox, every reader already lowercases before comparing, and a plain UNIQUE would let both
-- rows exist and leave the readers to fight over which is real - which is the defect above, one
-- layer down.
--
-- WHY PARTIAL: NULL email is legitimate (a lead-shaped row that has not signed in). NULLs are
-- already distinct under a unique index; the btrim(email) <> '' arm is the one that matters,
-- because an empty string is NOT distinct from another empty string and two of them would take
-- this migration down on a future insert rather than here.

begin;

-- Fail loudly rather than silently skipping. A migration that quietly does nothing because its
-- precondition was violated is worse than one that stops: it leaves the estate looking guarded.
do $$
declare n int;
begin
  select count(*) into n from (
    select 1 from public.customers
    where email is not null and btrim(email) <> ''
    group by lower(btrim(email)) having count(*) > 1
  ) d;
  if n > 0 then
    raise exception 'REFUSING: % duplicate lower(email) group(s) in public.customers. Merge them before adding the unique index - do not widen the index to accommodate them.', n;
  end if;

  select count(*) into n from (
    select 1 from public.leads
    where claimed_by is not null and btrim(claimed_by) <> ''
    group by lower(btrim(claimed_by)) having count(*) > 1
  ) d;
  if n > 0 then
    raise exception 'REFUSING: % duplicate lower(claimed_by) group(s) in public.leads.', n;
  end if;
end $$;

create unique index if not exists customers_email_lower_uidx
  on public.customers (lower(btrim(email)))
  where email is not null and btrim(email) <> '';

-- THE SUPPLIER SIDE HAS THE SAME SHAPE AND THE SAME RESOLVER. leads.claimed_by is the supplier's
-- identity exactly as customers.email is the buyer's, and resolveEmailByPhone's supplier branch
-- carried the identical ilike + limit(1). Fixing one and leaving the other would leave the same
-- defect live on the half of the marketplace that is currently being invited to register.
create unique index if not exists leads_claimed_by_lower_uidx
  on public.leads (lower(btrim(claimed_by)))
  where claimed_by is not null and btrim(claimed_by) <> '';

comment on column public.customers.email is
  'IDENTITY. Unique on lower(btrim(email)) via customers_email_lower_uidx. Every customer lookup in the estate keys on this column; nothing may key on phone.';

comment on column public.customers.phone is
  'NOT an identity, and deliberately NOT unique: in the UAE one number is shared by families, colleagues and whole companies through a single office landline, and this table already holds two accounts on +971509319355. A phone may CONFIRM an identity (SMS OTP proves possession of the handset) but must never SELECT one. login_otp refuses an SMS sign-in with HTTP 409 when a number maps to more than one account. See scripts/sql/a_phone_number_is_not_an_identity.sql.';

comment on column public.leads.claimed_by is
  'IDENTITY of the supplier who claimed this lead. Unique on lower(btrim(claimed_by)) via leads_claimed_by_lower_uidx. Same rule as customers.email: phone may confirm, never select.';

commit;
