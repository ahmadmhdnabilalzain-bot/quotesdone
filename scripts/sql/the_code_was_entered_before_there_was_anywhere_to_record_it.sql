-- The code was entered before there was anywhere to record it — 12 Aug 2026
--
-- login_otp proved email ownership with an UPDATE against public.customers. A first-time customer
-- has no row yet: login_otp never created one, and the row that appears seconds later (kyc
-- save_customer, customer_api 'me', mobile_otp) inserts with email_verified defaulting to false.
-- Nothing repaired it afterwards, so every genuinely new customer was permanently unverified and
-- create_inquiry's first gate refused them with "enter the 6-digit code we email you" — the code
-- they had just entered. Production evidence: code used 15:04:40, row inserted by kyc 15:05:26,
-- email_verified false, 0 inquiries ever created, 0 intakes ever consumed.
--
-- The routine is fixed in supabase/functions/login_otp/index.ts (insert-then-fall-back-to-update,
-- the same shape kyc verify_email already used). This file repairs the rows that were already lost.
--
-- THIS IS REPAIR, NOT FABRICATION. A row is only flipped where email_verifications already holds a
-- used, customer-kind login code for that exact address — the verification demonstrably happened
-- and the flag is the only thing that failed to record it. A customer who never entered a code is
-- untouched, and no other gate (tos_accepted_at, phone) is granted here.
update public.customers c
   set email_verified = true
 where c.email_verified = false
   and exists (
     select 1
       from public.email_verifications ev
      where lower(ev.email) = lower(c.email)
        and ev.purpose   = 'login'
        and ev.user_kind = 'customer'
        and ev.used_at is not null);
