-- THE FOUNDER IS RECOGNISED BY HIS WHOLE NUMBER, NOT ITS LAST NINE DIGITS.
--
-- Assigned: ceo (who may command the company by WhatsApp) + customer_support (the seat whose channel it is).
-- Release qualification gap #10 (docs/release/qualification_matrix.md, F07.02 and F07.05), 3 Nov 2026.
--
-- THE DEFECT. fn_identify_contact decides who the founder is for the whole WhatsApp command channel: the FIGURES reading
-- (fn_founder_whatsapp_figures asks it too) and every setting change by text. It compared only the LAST NINE DIGITS of the
-- sender with app_secrets.admin_mfa_phone ("tolerate +9715..., 05..., 5... variants"). A UAE mobile's national number is
-- nine digits, and so is a Saudi mobile's (5X XXX XXXX): +966 followed by the same nine digits as his +971 number is a
-- different handset, owned by a different person in a different country, and it was answered as the founder. Twilio
-- signs the webhook, so a sender cannot forge the From; but whoever HOLDS that number abroad needs to forge nothing.
-- The same holds for any country whose national numbers are nine digits long.
--
-- THE FIX. The comparison is on the whole international number. The local forms the old comment wanted to tolerate are
-- still read, as UAE numbers, on BOTH sides: 05XXXXXXXX (ten digits) and 5XXXXXXXX (nine) mean +971 5XXXXXXXX, and a
-- leading 00 is the international prefix. Anything else is compared as written. Entries in admin_mfa_phone shorter than
-- nine digits are ignored, as before. Nothing else in the routine changes: the supplier and customer branches below are
-- the canonical body of scripts/sql/the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used.sql verbatim.
--
-- NOT CHANGED, AND RECORDED AS A FINDING: fn_whatsapp_owner (suppliers and customers) matches on the last nine digits the
-- same way (scripts/sql/a_sanctioned_party_is_banned_for_good_not_deleted.sql). It decides which supplier or customer a
-- number is, not who may command the company, and it has many callers; it is customer_support's to change on its own.
--
-- PROVED, WITHOUT PRODUCTION: scripts/e2e/founder_command_channel_sql.mjs loads this body and the previous one into a
-- throwaway local Postgres and asserts, for a fixture founder in the reserved block: the whole number, 05.. and 5.. forms
-- and the 00 prefix are the founder; the same nine digits under +966 are NOT (and ARE under the previous body, the
-- known-bad control); another fixture number is not.
--
-- CREATE OR REPLACE keeps the routine's ACL (it is not re-granted to PUBLIC), so no revoke is written here.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_is_recognised_by_his_whole_number_not_its_last_nine_digits.sql --apply --ddl

create or replace function public.fn_identify_contact(p_phone text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_d text; v_me text; v_name text; v_sid bigint; v_cid text; v_claimed boolean; v_appr boolean; v_kind text; v_cuid uuid;
begin
  v_d := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(v_d) < 7 then return json_build_object('audience','unknown'); end if;

  -- THE FOUNDER. Before suppliers and customers: he is neither, and a number that is both his and
  -- a lead's must still be treated as his. The WHOLE international number is compared (see the header):
  -- 00 is the international prefix, and 05XXXXXXXX / 5XXXXXXXX are UAE local forms of +971 5XXXXXXXX.
  v_me := case when v_d like '00%' then substr(v_d, 3) else v_d end;
  v_me := case when length(v_me) = 10 and v_me like '05%' then '971' || substr(v_me, 2)
               when length(v_me) = 9  and v_me like '5%'  then '971' || v_me
               else v_me end;
  if exists (
    select 1
      from unnest(string_to_array(coalesce((select value from app_secrets where key='admin_mfa_phone'),''), ',')) p,
           lateral (select regexp_replace(p, '[^0-9]', '', 'g') as d) a,
           lateral (select case when a.d like '00%' then substr(a.d, 3) else a.d end as d) b,
           lateral (select case when length(b.d) = 10 and b.d like '05%' then '971' || substr(b.d, 2)
                                when length(b.d) = 9  and b.d like '5%'  then '971' || b.d
                                else b.d end as intl) c
     where length(a.d) >= 9
       and c.intl = v_me)
  then
    return json_build_object('audience','founder',
      'name', split_part(coalesce((select value from app_secrets where key='admin_emails'),''), ',', 1));
  end if;

  -- 14 Sep 2026 (#322): a supplier or customer is recognised only by a CONFIRMED WhatsApp number.
  select o.party_kind, o.lead_id, o.customer_id into v_kind, v_sid, v_cuid from public.fn_whatsapp_owner(p_phone) o;
  if v_kind = 'supplier' then
    select company_name, coalesce(claimed,false), (approval_status='approved') into v_name, v_claimed, v_appr from leads where id = v_sid;
  end if;
  if v_sid is not null then
    return json_build_object('audience','supplier','name',v_name,'claimed',v_claimed,'approved',coalesce(v_appr,false));
  end if;

  if v_kind = 'customer' then select id::text, full_name into v_cid, v_name from customers where id = v_cuid; end if;
  if v_cid is not null then
    return json_build_object('audience','customer','name',v_name);
  end if;

  return json_build_object('audience','unknown');
end $function$;
