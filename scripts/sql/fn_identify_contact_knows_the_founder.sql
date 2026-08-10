-- fn_identify_contact did not know the founder, so WhatsApp answered him as a stranger.
--
-- The command channel he asked for — "print me last month's revenue", "what social media post do
-- you have for next week" — was reported as blocked on Twilio credentials. It never was. Every
-- Twilio secret is provisioned, wa_templates_ready is true, wa_autoreply_enabled is true and
-- wa_inbound has been answering messages. The gap is identity: this function returns 'supplier',
-- 'customer' or 'unknown', it matched him against `leads` and `customers`, he is in neither, so
-- his own number fell to 'unknown' and wa_inbound handed him the public marketing script.
--
-- Same defect as the OS sign-in an hour earlier, one level down: the founder is not modelled as a
-- person anywhere in the contact graph, only as app_secrets.admin_mfa_phone.
--
-- Checked FIRST and on the same last-nine-digits rule the other two branches use, so +971 50 931
-- 9355, 00971509319355 and 0509319355 all land on the same identity.
create or replace function public.fn_identify_contact(p_phone text)
returns json
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_d text; v_tail text; v_name text; v_sid bigint; v_cid text; v_claimed boolean; v_appr boolean;
begin
  v_d := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(v_d) < 7 then return json_build_object('audience','unknown'); end if;
  v_tail := right(v_d, 9);   -- tolerate +9715..., 05..., 5... variants

  -- THE FOUNDER. Before suppliers and customers: he is neither, and a number that is both his and
  -- a lead's must still be treated as his.
  if exists (
    select 1 from unnest(string_to_array(coalesce((select value from app_secrets where key='admin_mfa_phone'),''), ',')) p
     where length(regexp_replace(p,'[^0-9]','','g')) >= 9
       and right(regexp_replace(p,'[^0-9]','','g'), 9) = v_tail)
  then
    return json_build_object('audience','founder',
      'name', split_part(coalesce((select value from app_secrets where key='admin_emails'),''), ',', 1));
  end if;

  select id, company_name, coalesce(claimed,false), (approval_status='approved')
    into v_sid, v_name, v_claimed, v_appr
   from leads
   where right(regexp_replace(coalesce(phone_e164,''),'[^0-9]','','g'),9) = v_tail
      or right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = v_tail
      or right(regexp_replace(coalesce(whatsapp,''),'[^0-9]','','g'),9) = v_tail
   limit 1;
  if v_sid is not null then
    return json_build_object('audience','supplier','name',v_name,'claimed',v_claimed,'approved',coalesce(v_appr,false));
  end if;

  select id::text, full_name into v_cid, v_name from customers
   where right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = v_tail
   limit 1;
  if v_cid is not null then
    return json_build_object('audience','customer','name',v_name);
  end if;

  return json_build_object('audience','unknown');
end $function$;

-- CREATE OR REPLACE preserves the ACL; grants deliberately untouched.
