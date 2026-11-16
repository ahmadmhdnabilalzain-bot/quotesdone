-- EVERY ONE-TIME CODE THE DATABASE MAKES IS UNGUESSABLE.
--
-- Assigned: it_engineer (16 Nov 2026, founder ledgers 1714/1715; the independent review of 16 Nov). Redefines two
-- routines from their PRODUCTION bodies (pg_get_functiondef read 16 Nov 2026, each the only overload of its name):
--   public.fn_pdpl_open(text,text,text)                        md5 759b800d78c6ad8724d689cdc9505173
--   public.fn_support_open_identity_challenge(text,text,text)  md5 c67e11fea954d8171e5975260ff0fb1d
-- In each, ONE line changes: the line that made the six-digit code. Nothing else in either body changes.
--
-- WHAT WAS WRONG (SELECT, 16 Nov 2026). Both made their code from Postgres's built-in pseudo-random generator, which
-- is not a cryptographic source: its sequence follows from a 48-bit state, and whoever sees enough of its output on
-- the same backend can work out what comes next. These two codes are the only thing standing between a stranger and
--   - fn_pdpl_open: a person's whole data copy or the erasure of their records (PDPL request confirmation, emailed);
--   - fn_support_open_identity_challenge: filing a document against someone else's supplier account (emailed).
-- fn_supplier_member_phone_code already drew its code from gen_random_uuid (a cryptographic source) and is unchanged.
--
-- EVERY ROUTINE THAT USES THE GENERATOR (SELECT on production, 16 Nov 2026: every public, and every non-platform
-- schema's, function and procedure whose body calls it; no column default calls it):
--   makes a code a person must not guess -> fixed here
--     fn_pdpl_open                         the PDPL confirmation code
--     fn_support_open_identity_challenge   the identity-challenge code
--   left alone, nobody has to guess them
--     fn_dropbox_reconcile_sample(integer)  orders rows to sample which backups to re-check
--     fn_inbound_mail_retry_at(integer)     jitter on an inbound mail retry time
--     fn_it_restore_table_pick()            picks a table for the restore drill
--     fn_supplier_member_phone_code(text)   only a comment names the generator; its code comes from gen_random_uuid
--
-- THE CODE NOW. public.fn_one_time_code_six_digits() reads 4 bytes from pgcrypto's gen_random_bytes (the operating
-- system's CSPRNG; pgcrypto lives in schema extensions, so the call is schema-qualified). 4 bytes are 0..4,294,967,295;
-- a draw of 4,294,000,000 or more (967,296 values, 0.02% of draws) is thrown away and drawn again, so every accepted
-- value is one of exactly 4,294 copies of each code and every code from 000000 to 999999 is equally likely (no modulo
-- bias). It returns TEXT of exactly six digits, leading zeros kept: the same type and format the old line made.
-- Every reader treats it as text: fn_pdpl_verify compares sha256(btrim(code)); fn_support_answer_identity_challenge
-- compares sha256(btrim(code) || '|' || lead_id); the emails print it as text. No edge function makes or reads either code
-- (READ, supabase/functions); callers fn_customer_support_data_request_tick and pdpl_request_me take only the jsonb.
--
-- Prevented by: scripts/sql/every_one_time_code_the_database_makes_is_unguessable_probe.sql (no listed routine body
-- calls the generator, both call the CSPRNG routine; 2,000 codes are six digits, leading zeros included, every first digit
-- 0-9 appears; fn_pdpl_open's emailed code matches the stored hash). Production's bodies fail it.

create or replace function public.fn_one_time_code_six_digits()
returns text
language plpgsql
volatile
set search_path to 'public', 'pg_temp'
as $fn$
declare v_n bigint;
begin
  -- rejection sampling: only a draw below 4,294,000,000 (= 4,294 x 1,000,000) is used, so the remainder is uniform
  loop
    v_n := ('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint;   -- 0 .. 4,294,967,295, unsigned
    exit when v_n < 4294000000;
  end loop;
  return lpad((v_n % 1000000)::text, 6, '0');
end $fn$;
comment on function public.fn_one_time_code_six_digits() is
  'A six-digit one-time code (text, leading zeros kept), uniform over 000000-999999, from pgcrypto gen_random_bytes (CSPRNG). every_one_time_code_the_database_makes_is_unguessable.sql, it_engineer, 16 Nov 2026.';
-- CREATE grants EXECUTE to PUBLIC: closed here; only the definer routines that make a code call it.
revoke execute on function public.fn_one_time_code_six_digits() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_pdpl_open(p_email text, p_kind text, p_operator text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_em text := lower(btrim(coalesce(p_email, ''))); v_code text; v_id uuid; v_out jsonb;
begin
  if v_em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or p_kind not in ('export', 'delete') or coalesce(btrim(p_operator), '') = '' then
    v_out := jsonb_build_object('ok', false, 'error', 'an email, a kind (export|delete) and the operator are required');
  else
    v_code := public.fn_one_time_code_six_digits();
    insert into public.pdpl_requests (kind, email, role, details, status, code_sha, code_expires, handled_by)
    values (p_kind, v_em, 'operator', 'opened by ' || p_operator, 'received', encode(sha256(convert_to(v_code, 'UTF8')), 'hex'),
            now() + interval '24 hours', p_operator)
    returning id into v_id;
    perform public.fn_sales_engineer_writes('pdpl_verification', 'customer', v_em, null, null, null, null,
      'Your QuotesDone data request: confirmation code',
      'We received a request to ' || case when p_kind = 'export' then 'send you a copy of' else 'erase' end
        || ' the personal data we hold for this address. If you made it, give us this code: ' || v_code
        || E'. It expires in 24 hours.\nIf you did not make this request, ignore this email; nothing will change.',
      'طلب بياناتكم لدى QuotesDone: رمز التأكيد',
      'تلقّينا طلبًا ' || case when p_kind = 'export' then 'بتزويدكم بنسخة من' else 'بحذف' end
        || ' البيانات الشخصية المحفوظة لهذا العنوان. إن كنتم قد قدّمتم الطلب، فيُرجى تزويدنا بهذا الرمز: ' || v_code
        || E'، وتنتهي صلاحيته خلال 24 ساعة.\nوإن لم تقدّموا هذا الطلب، فلا داعي لأي إجراء ولن يتغيّر شيء.',
      '{}', 'pdpl_verification:' || v_id::text);
    v_out := jsonb_build_object('ok', true, 'request_id', v_id, 'code_sent_to', v_em);
  end if;
  insert into public.pdpl_operator_log (caller, operator, action, email, request_id, result) values ('fn_pdpl_open', p_operator, 'open:' || coalesce(p_kind, ''), v_em, v_id, v_out);
  return v_out;
end $function$
;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the one signature (no other overload exists).
revoke execute on function public.fn_pdpl_open(text,text,text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_support_open_identity_challenge(p_channel text, p_sender_ref text, p_claimed_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lead bigint; v_to text; v_code text; v_id bigint; v_grant jsonb; v_open int;
begin
  v_grant := public.fn_support_may_act('document');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;

  -- RATE LIMIT PER SENDER, not per account. Limiting per account would let a stranger lock a real
  -- supplier out of their own verification by spamming challenges at them.
  select count(*) into v_open from public.support_identity_challenge
   where sender_ref = p_sender_ref and created_at > now() - interval '1 hour';
  if v_open >= 5 then
    return jsonb_build_object('ok', true, 'challenge_opened', false, 'reason', 'rate_limited',
      'message', 'I have sent several codes to this account recently. Please use the most recent one, or try again in an hour.');
  end if;

  select id, email into v_lead, v_to from public.leads
   where lower(email) = lower(btrim(p_claimed_email)) order by id limit 1;

  v_code := public.fn_one_time_code_six_digits();

  if v_lead is not null then
    insert into public.support_identity_challenge
      (channel, sender_ref, claimed_email, lead_id, sent_to, code_hash, expires_at)
    values (p_channel, p_sender_ref, p_claimed_email, v_lead, v_to,
            encode(sha256(convert_to(v_code || '|' || v_lead::text, 'UTF8')), 'hex'), now() + interval '15 minutes')
    returning challenge_id into v_id;

    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      subject, body, anonymity_checked_at, anonymity_result)
    values ('idchallenge|' || v_id::text, null, 'identity_challenge', 'email', v_to,
            'Your QuotesDone confirmation code',
            'Your confirmation code is ' || v_code || '. It expires in 15 minutes. If you did not ask '
            || 'to confirm a document upload, you can ignore this message and nothing will be filed.',
            now(), jsonb_build_object('safe', true, 'note', 'code to the address of record; no counterparty data'));
  end if;

  -- THE SAME ANSWER EITHER WAY. Whether or not that account exists, the sender is told a code was
  -- sent to the address they named. Saying "no account with that email" would turn this into a
  -- free tool for discovering who is registered with us.
  return jsonb_build_object('ok', true, 'challenge_opened', v_lead is not null,
    'message', 'I have sent a 6-digit code to ' || p_claimed_email || '. Reply with the code and I '
            || 'will file your document against that account. The code expires in 15 minutes.');
end $function$
;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the one signature (no other overload exists).
revoke execute on function public.fn_support_open_identity_challenge(text,text,text) from public, anon, authenticated;
