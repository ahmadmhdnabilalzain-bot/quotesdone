-- THE REFERRAL THANKS IS SAID IN THE FORMAL PLURAL (customer_support's customer copy; written by it_engineer, 17 Nov 2026).
--
-- a_referral_is_recorded_counted_and_thanked.sql is APPLIED (MANIFEST, 16 Nov) and production still sends the singular
-- thanks (لتوصيتك). Its in-place edit of 17 Nov changed only the repository. This file carries that change to production
-- alone: fn_customer_referral_record re-issued from its LIVE text (pg_get_functiondef read 17 Nov; md5 of prosrc
-- 37b132561dddfde27d0f9f8b15913dee) with ONLY the two Arabic lines of the thanks changed (prosrc md5 after: 7c248ed7919c328b9505c2d61224274a).
-- Not a re-apply of the whole referral file, which would also re-run its ceo_supplier_channel updates.
-- NOT CHANGED: what the routine records, counts or sends; its English; any other routine. CREATE OR REPLACE keeps the closed
-- ACL; the revoke repeats it.
-- Pending: scripts/sql/pending/the_referral_thanks_is_said_in_the_formal_plural.txt
set local lock_timeout = '3s';
CREATE OR REPLACE FUNCTION public.fn_customer_referral_record(p_customer uuid, p_words text, p_contact text DEFAULT NULL::text, p_source text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_words text := nullif(left(btrim(coalesce(p_words, '')), 500), ''); v_contact text := nullif(left(btrim(coalesce(p_contact, '')), 120), '');
        v_tail text; v_ref uuid; v_n int := 0; v_h bigint; r record;
begin
  if p_customer is null or v_words is null then return jsonb_build_object('ok', false, 'recorded', false, 'code', 'nothing_said'); end if;
  if not exists (select 1 from public.customers where id = p_customer) then return jsonb_build_object('ok', false, 'recorded', false, 'code', 'no_customer'); end if;
  if exists (select 1 from public.customer_referral where customer_id = p_customer) then
    return jsonb_build_object('ok', true, 'recorded', false, 'code', 'already_recorded');
  end if;
  -- HIS FIRST REQUEST ONLY: a customer with an earlier request did not just hear of us
  if exists (select 1 from public.inquiries i where i.customer_id = p_customer and i.created_at < now() - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'recorded', false, 'code', 'not_first_request');
  end if;
  -- THE REFERRER IS A CUSTOMER ONLY ON AN EXACT FACT: his verified address, or his verified number (last nine digits and, when
  -- both name one, the same country). One match or none; never the newcomer himself.
  if v_contact is not null and position('@' in v_contact) > 0 then
    for r in select c.id from public.customers c where lower(c.email) = lower(v_contact) and coalesce(c.email_verified, false) and c.id <> p_customer loop
      v_n := v_n + 1; v_ref := r.id;
    end loop;
  elsif v_contact is not null then
    v_tail := right(regexp_replace(v_contact, '[^0-9]', '', 'g'), 9);
    if length(v_tail) = 9 then
      for r in select c.id from public.customers c
                where coalesce(c.phone_verified, false) and c.id <> p_customer
                  and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
                  and coalesce(public.fn_phone_prefix(c.phone) = public.fn_phone_prefix(v_contact), true) loop
        v_n := v_n + 1; v_ref := r.id;
      end loop;
    end if;
  end if;
  if v_n <> 1 then v_ref := null; end if;

  insert into public.customer_referral (customer_id, words, referrer_contact, referrer_customer_id, source)
  values (p_customer, v_words, v_contact, v_ref, left(p_source, 120))
  on conflict (customer_id) do nothing;
  if not found then return jsonb_build_object('ok', true, 'recorded', false, 'code', 'already_recorded'); end if;

  -- THANKED ONCE, never naming the newcomer (he told us, not the referrer)
  if v_ref is not null then
    v_h := public.fn_sales_engineer_writes('customer_referral_thanks', 'customer', (select email from public.customers where id = v_ref),
      null, v_ref, null, null,
      'Thank you for recommending QuotesDone',
      'Someone you recommended has just come to QuotesDone and named you. Thank you for passing our name on: it is the best '
      || 'thing a customer can do for us.',
      'شكرًا لتوصيتكم بـ QuotesDone',
      'انضمّ إلى QuotesDone للتوّ أحدُ من نصحتموهم بنا، وذكر اسمكم. نشكركم على هذه التوصية، فهي أثمن ما يقدّمه لنا عملاؤنا.',
      '{}'::text[], 'customer_referral_thanks:' || p_customer);
    update public.customer_referral set thanked_at = now(), thanks_handoff = v_h where customer_id = p_customer;
  end if;
  return jsonb_build_object('ok', true, 'recorded', true, 'referrer_is_customer', v_ref is not null, 'thanked', v_ref is not null);
end $function$;
revoke execute on function public.fn_customer_referral_record(uuid, text, text, text) from public, anon, authenticated;
