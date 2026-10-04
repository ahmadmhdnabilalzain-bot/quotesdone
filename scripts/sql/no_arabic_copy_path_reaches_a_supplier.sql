-- NO ARABIC COPY PATH REACHES A SUPPLIER (customer_support, E2E stage 1 D3, 30 Sep 2026).
-- Founder, 28 Sep 2026: suppliers always get English. Measured on production before this file: the live
-- composers already write English (fn_registered_locale('supplier') = 'en'; v_ar := false in the reminder,
-- portfolio, onboarding and documents composers), but two Arabic paths were still reachable:
--   1. fn_supplier_invite_test_send(p_lang => 'ar') queued the stored Arabic invitation (to a fixture address);
--   2. app_secrets invite_subject_ar / invite_body_ar held that copy for anything that asked for it.
-- The test send is now English whatever it is asked (the parameter stays: callers keep their signature), and the
-- two Arabic rows are removed (the text survives in git history). send_outbox holds any supplier-side row queued
-- in Arabic (invitation_copy.ts holdArabicInvitation, supplierSide), so a path added later cannot deliver either.
-- CREATE OR REPLACE on the same signature keeps the existing ACL (no new PUBLIC grant).

create or replace function public.fn_supplier_invite_test_send(p_lang text default 'en'::text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_lang text := 'en';   -- suppliers are always written in English (founder, 28 Sep 2026); p_lang is ignored
  v_site text; v_subj text; v_body text; v_to text; v_id bigint; v_status text; v_err text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  select value into v_subj from app_secrets where key = 'invite_subject';
  select value into v_body from app_secrets where key = 'invite_body';
  v_to := 'zz-demo-supplier-invite-' || v_lang || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || '@example.invalid';
  if not public.fn_is_demo_email(v_to) then raise exception 'test address % is not a fixture address', v_to; end if;
  insert into notifications(type, to_email, to_role, subject, body, lang, status)
  values ('supplier_invite', v_to, 'supplier', v_subj,
          replace(replace(v_body, '{{company}}', 'ZZ DEMO Supplier'),
                  '{{link}}', coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal?t=00000000-0000-0000-0000-000000000000'),
          v_lang, 'queued')
  returning id, status, last_error into v_id, v_status, v_err;
  return jsonb_build_object('id', v_id, 'to', v_to, 'lang', v_lang, 'status', v_status, 'captured_note', v_err,
                            'subject', v_subj, 'never_reaches_resend', v_status = 'suppressed');
end
$function$;

delete from public.app_secrets where key in ('invite_subject_ar', 'invite_body_ar');

select case
  when exists (select 1 from public.app_secrets where key in ('invite_subject_ar', 'invite_body_ar'))
    then 'PROBE FAILED: the Arabic invitation copy is still stored'
  when (select prosrc from pg_proc where oid = 'public.fn_supplier_invite_test_send(text)'::regprocedure) ilike '%_ar''%'
    then 'PROBE FAILED: the test send can still choose Arabic copy'
  else 'PROBE OK' end as verdict;
