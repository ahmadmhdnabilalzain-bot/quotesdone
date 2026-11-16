-- every_one_time_code_the_database_makes_is_unguessable_probe.sql (it_engineer, 16 Nov 2026)
-- A pure probe of every_one_time_code_the_database_makes_is_unguessable.sql. It answers with ONE ROW, never a raise:
-- 'PROBE OK' or 'PROBE FAILED: <why>', with the measurements in `detail`.
--   1. neither code-making routine (fn_pdpl_open, fn_support_open_identity_challenge) calls Postgres's built-in
--      pseudo-random generator any more, and each calls fn_one_time_code_six_digits     (READ of pg_get_functiondef)
--   2. 2,000 codes from fn_one_time_code_six_digits: every one is exactly six digits, some start with 0 (leading zeros
--      are kept), every first digit 0-9 appears, and no code repeats more than 3 times (at 2,000 draws from a million a
--      uniform source repeats a code about twice in total; a stuck or narrow source repeats far more)  (writes nothing)
--   3. LOCAL DATABASE ONLY (app_secrets.project_ref is the local seed; anywhere else it is skipped and says so):
--      a. fn_pdpl_open for a ZZ DEMO address: the code in the message it writes is six digits and its sha256 is the
--         request's code_sha, the hash fn_pdpl_verify compares;
--      b. fn_support_open_identity_challenge for a ZZ DEMO lead (with a ZZ DEMO standing grant): the code in the
--         notification it writes is six digits and sha256(code|lead) is the challenge's code_hash, the hash
--         fn_support_answer_identity_challenge compares.
--      Both run inside a block that always rolls itself back, on ZZ DEMO rows only, so no request, lead, grant, message
--      or notification survives; the ZZ DEMO address makes the message a suppressed demo record, never a send.
-- Run on a local Postgres 16 (scripts/db/local_pg16.mjs) twice; production's bodies before the fix fail check 1 and,
-- having no fn_one_time_code_six_digits, check 2.
create temp table if not exists zz_probe_verdict (verdict text, detail text) on commit drop;
truncate zz_probe_verdict;
do $probe$
declare
  v_fail text := ''; v_detail jsonb := '{}'::jsonb; v_r text; v_def text; v_left int;
  v_local boolean := coalesce((select value from public.app_secrets where key = 'project_ref'), '') = 'localpg16localpg16lo';
  v_tag constant text := 'zzdemo-otp-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
  v_email text; v_out jsonb; v_req uuid; v_lead bigint; v_code text; v_body text; v_sha text;
  v_n int; v_bad int; v_lead0 int; v_firsts int; v_maxrep int;
begin
  -- 1. the bodies
  foreach v_r in array array['public.fn_pdpl_open(text,text,text)', 'public.fn_support_open_identity_challenge(text,text,text)'] loop
    if to_regprocedure(v_r) is null then v_fail := v_fail || ' ' || v_r || ' is missing;'; continue; end if;
    v_def := pg_get_functiondef(to_regprocedure(v_r));
    if v_def ~* '(^|[^a-z_])random\s*\(' then v_fail := v_fail || ' ' || v_r || ' still calls the built-in pseudo-random generator;'; end if;
    if v_def !~ 'fn_one_time_code_six_digits\(\)' then v_fail := v_fail || ' ' || v_r || ' does not call fn_one_time_code_six_digits;'; end if;
  end loop;

  -- 2. 2,000 codes
  if to_regprocedure('public.fn_one_time_code_six_digits()') is null then
    v_fail := v_fail || ' fn_one_time_code_six_digits does not exist;';
  else
    create temp table zz_probe_codes on commit drop as
      select public.fn_one_time_code_six_digits() as c from generate_series(1, 2000);
    select count(*), count(*) filter (where c !~ '^[0-9]{6}$' or c is null), count(*) filter (where c like '0%'),
           count(distinct left(c, 1)) filter (where c ~ '^[0-9]{6}$')
      into v_n, v_bad, v_lead0, v_firsts from zz_probe_codes;
    select coalesce(max(k), 0) into v_maxrep from (select count(*) k from zz_probe_codes group by c) x;
    v_detail := v_detail || jsonb_build_object('codes', v_n, 'not_six_digits', v_bad, 'leading_zero', v_lead0,
                                               'first_digits_seen', v_firsts, 'max_repeats_of_one_code', v_maxrep);
    if v_n <> 2000 then v_fail := v_fail || ' made ' || v_n || ' codes, not 2000;'; end if;
    if v_bad <> 0 then v_fail := v_fail || ' ' || v_bad || ' code(s) are not exactly six digits;'; end if;
    if v_lead0 = 0 then v_fail := v_fail || ' no code starts with 0 (leading zeros lost?);'; end if;
    if v_firsts <> 10 then v_fail := v_fail || ' only ' || v_firsts || ' of the 10 first digits appear;'; end if;
    if v_maxrep > 3 then v_fail := v_fail || ' one code came ' || v_maxrep || ' times in 2,000;'; end if;
    drop table zz_probe_codes;
  end if;

  -- 3. what each routine really sends, on the local database only
  if not v_local then
    v_detail := v_detail || jsonb_build_object('end_to_end', 'skipped: not the local database');
  elsif v_fail = '' then
    begin
      -- a. the PDPL confirmation code
      v_email := v_tag || '@example.invalid';
      v_out := public.fn_pdpl_open(v_email, 'export', 'zz_probe');
      v_req := (v_out->>'request_id')::uuid;
      select r.code_sha into v_sha from public.pdpl_requests r where r.id = v_req;
      select n.body into v_body from public.notifications n where n.to_email = v_email order by n.id desc limit 1;
      v_code := substring(v_body from 'give us this code: ([^.]*)\. It expires');
      v_detail := v_detail || jsonb_build_object('pdpl_open', jsonb_build_object('ok', v_out->'ok', 'code_six_digits', v_code ~ '^[0-9]{6}$',
                    'hash_matches', v_sha = encode(sha256(convert_to(v_code, 'UTF8')), 'hex')));
      if v_req is null then v_fail := v_fail || ' fn_pdpl_open opened no request: ' || v_out::text || ';';
      elsif v_code is null or v_code !~ '^[0-9]{6}$' then v_fail := v_fail || ' fn_pdpl_open sent no six-digit code;';
      elsif v_sha is distinct from encode(sha256(convert_to(v_code, 'UTF8')), 'hex') then
        v_fail := v_fail || ' fn_pdpl_open stored a hash that is not the sent code''s;';
      end if;

      -- b. the identity-challenge code
      insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, issued_by, issued_at)
      values (v_tag, 'customer_support', 'document', 'ZZ DEMO probe grant', 'ceo', clock_timestamp());
      insert into public.leads (email, company_name) values (v_tag || '-lead@example.invalid', 'ZZ DEMO OTP probe') returning id into v_lead;
      v_out := public.fn_support_open_identity_challenge('email', v_tag, v_tag || '-lead@example.invalid');
      select c.code_hash into v_sha from public.support_identity_challenge c where c.sender_ref = v_tag order by c.challenge_id desc limit 1;
      select s.body into v_body from public.support_notification s where s.recipient = v_tag || '-lead@example.invalid' order by 1 desc limit 1;
      v_code := substring(v_body from 'Your confirmation code is ([^.]*)\. It expires');
      v_detail := v_detail || jsonb_build_object('identity_challenge', jsonb_build_object('opened', v_out->'challenge_opened',
                    'code_six_digits', v_code ~ '^[0-9]{6}$',
                    'hash_matches', v_sha = encode(sha256(convert_to(v_code || '|' || v_lead::text, 'UTF8')), 'hex')));
      if coalesce((v_out->>'challenge_opened')::boolean, false) is not true then
        v_fail := v_fail || ' fn_support_open_identity_challenge opened no challenge: ' || v_out::text || ';';
      elsif v_code is null or v_code !~ '^[0-9]{6}$' then v_fail := v_fail || ' fn_support_open_identity_challenge sent no six-digit code;';
      elsif v_sha is distinct from encode(sha256(convert_to(v_code || '|' || v_lead::text, 'UTF8')), 'hex') then
        v_fail := v_fail || ' fn_support_open_identity_challenge stored a hash that is not the sent code''s;';
      end if;

      raise exception 'zz_probe_rollback';
    exception when others then
      if sqlerrm <> 'zz_probe_rollback' then v_fail := v_fail || ' a routine raised: ' || sqlerrm || ';'; end if;
    end;

    select (select count(*) from public.pdpl_requests where email like v_tag || '%')
         + (select count(*) from public.notifications where to_email like v_tag || '%')
         + (select count(*) from public.ceo_standing_grant where grant_key = v_tag)
         + (select count(*) from public.leads where email like v_tag || '%')
         + (select count(*) from public.support_identity_challenge where sender_ref = v_tag)
         + (select count(*) from public.support_notification where recipient like v_tag || '%')
      into v_left;
    if v_left <> 0 then v_fail := v_fail || ' ' || v_left || ' probe row(s) survived;'; end if;
  else
    v_detail := v_detail || jsonb_build_object('end_to_end', 'not run: checks 1-2 failed');
  end if;

  insert into zz_probe_verdict values (case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end, v_detail::text);
end $probe$;
select verdict, detail from zz_probe_verdict;
