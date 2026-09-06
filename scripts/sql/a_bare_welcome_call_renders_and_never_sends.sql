-- A BARE WELCOME CALL RENDERS AND NEVER SENDS (6 Sep 2026). Follows
-- the_welcome_states_the_ladder_from_pricing_config.sql (integration-2026-09-06e, 87e875d), whose body
-- this file restates byte for byte; the ONLY change is the default of p_send.
--
-- WHAT HAPPENED. public.fn_customer_welcome(p_customer_id uuid, p_send boolean DEFAULT true) was built
-- so that the registration trigger (z55) could pass true explicitly. The default made the bare hand
-- call the sending call: at 19:00:30Z the integrating session (transcript
-- cd432ea4-4602-4dcf-a262-875622bbb1d9, scratchpad/send_welcome.mjs) ran
-- fn_customer_welcome('e0dee407-...'::uuid, true) against the real customer who registered that
-- morning, which queued notifications 20610 (created 19:00:32Z, sent 19:02:02Z). The welcome is the
-- product's own text through the product's own outbox, but it left by hand, inside a build window, and
-- no routine, cron, trigger or edge path could have produced it -- so the founder-facing check "no real
-- email sent by the build" could only be asserted, never measured. The email is delivered and cannot
-- be undone; this file stops it recurring.
--
-- THE CHANGE. p_send now defaults to FALSE: a bare call -- from a hand, a probe, a deliverable's repair
-- hint, a future caller that forgets the flag -- renders the subject and body and queues NOTHING. The
-- one path that is supposed to send, z55_customer_welcome -> fn_customer_welcome_trg, already passes
-- true explicitly (scripts/sql/the_customer_welcome_the_product_never_sent.sql), so registration
-- behaviour is unchanged. Sending is now an act a caller must name, never a default it can fall into.
--
-- Postgres cannot ALTER a parameter default; the function is restated in full (body identical to the
-- live definition read back on 6 Sep 2026 at 19:46Z). No ACL change: CREATE OR REPLACE keeps the
-- existing revoke-from-public / grant-to-service_role grants.
--
--   node scripts/apply_sql.mjs scripts/sql/a_bare_welcome_call_renders_and_never_sends.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_customer_welcome(p_customer_id uuid, p_send boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c            public.customers%rowtype;
  v_rate_pct   int;
  v_ar         boolean;
  v_name       text;
  v_subject    text;
  v_body       text;
  v_exists     boolean;
  v_id         bigint;
  v_refund_url text := 'https://quotesdone.com/refund-policy';
  v_win int; v_chase int; v_bank_min int; v_bank_max int;
  v_app_url    text := 'https://quotesdone.com/me';
begin
  -- 6 SEP 2026: the refund paragraph follows the founder's ladder in pricing_config, never a literal.
  select coalesce(refund_window_working_days, 5), coalesce(chase_after_working_days, 3),
         coalesce(bank_settlement_working_days_min, 7), coalesce(bank_settlement_working_days_max, 14)
    into v_win, v_chase, v_bank_min, v_bank_max
    from public.pricing_config order by id limit 1;
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such customer ' || p_customer_id);
  end if;
  if coalesce(btrim(c.email),'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'customer has no email; nothing to welcome');
  end if;

  -- LIVE facts, never hard-coded: the reveal rate is whatever pricing_config currently says.
  select round(coalesce(standard_reveal_rate, 0.03) * 100)::int into v_rate_pct
    from public.pricing_config order by id limit 1;
  v_rate_pct := coalesce(v_rate_pct, 3);

  v_ar   := lower(coalesce(c.locale,'en')) = 'ar';
  v_name := nullif(btrim(coalesce(c.full_name,'')),'');

  if v_ar then
    v_subject := 'مرحبًا بك في QuotesDone — انشر طلبك الأول';
    v_body :=
      (case when v_name is not null then 'مرحبًا ' || v_name || '،' else 'مرحبًا،' end) || E'\n\n'
      || 'QuotesDone هي سوق عروض الأسعار المجهّل للأعمال في الإمارات: انشر طلبًا واحدًا واحصل على عروض '
      || 'متنافسة من موردين موثّقين، وتبقى هوية المورّد مخفية حتى تختار الكشف عنها.' || E'\n\n'
      || 'انشر طلبك الأول' || E'\n'
      || 'افتح لوحتك على ' || v_app_url || ' واختر «طلب جديد». حدّد الفئة والكمية والإمارة والمدة الزمنية — '
      || 'هذا كل ما يحتاجه المورّد ليقدّم عرضًا.' || E'\n\n'
      || 'التكلفة' || E'\n'
      || 'نشر الطلبات ومقارنة العروض مجاني. عند كشف المورّد صاحب العرض الذي تختاره، الرسوم ' || v_rate_pct
      || '٪ من قيمة ذلك العرض. وترى دائمًا أفضل ثلاثة عروض قابلة للمقارنة قبل اتخاذ قرارك.' || E'\n\n'
      || 'الاسترداد' || E'\n'
      || 'لدى المورّد الذي تم كشفه ' || v_win || ' أيام عمل من تاريخ دفعك للرد. إذا لم يصل رد بحلول يوم العمل '
      || v_chase || ' يتابعه فريقنا، وإذا استمر عدم الرد حتى اليوم ' || v_win || ' تُسترد رسوم الكشف البالغة '
      || v_rate_pct || '٪ كاملة؛ وتستغرق البنوك عادةً ' || v_bank_min || '-' || v_bank_max || ' يوم عمل لإظهارها. '
      || 'السياسة الكاملة: ' || v_refund_url || E'\n\n'
      || 'يمكنك الرد على هذه الرسالة في أي وقت وسيساعدك فريقنا.';
  else
    v_subject := 'Welcome to QuotesDone — post your first request';
    v_body :=
      (case when v_name is not null then 'Welcome to QuotesDone, ' || v_name || '.' else 'Welcome to QuotesDone.' end) || E'\n\n'
      || 'QuotesDone is the UAE''s anonymous B2B quotation marketplace: post one request and receive '
      || 'competing quotes from verified suppliers, with each supplier''s identity hidden until you '
      || 'choose to reveal it.' || E'\n\n'
      || 'Post your first request' || E'\n'
      || 'Open your dashboard at ' || v_app_url || ' and choose New request. Tell us the category, the '
      || 'quantity, your emirate and your timeline — that is all a supplier needs to quote.' || E'\n\n'
      || 'What it costs' || E'\n'
      || 'Posting requests and comparing quotes is free. When you reveal the supplier behind a quote '
      || 'you want, the fee is ' || v_rate_pct || '% of that quote. You always see the top three '
      || 'comparable quotes before you decide.' || E'\n\n'
      || 'Refunds' || E'\n'
      || 'A revealed supplier has ' || v_win || ' working days from your payment to respond. If nothing '
      || 'comes by working day ' || v_chase || ' our team chases them, and if there is still no response by '
      || 'day ' || v_win || ' your ' || v_rate_pct || '% reveal fee is refunded in full; banks usually take '
      || v_bank_min || '-' || v_bank_max || ' working days to show it. '
      || 'Full policy: ' || v_refund_url || E'\n\n'
      || 'Reply to this email any time and our team will help.';
  end if;

  if not p_send then
    return jsonb_build_object('ok', true, 'sent', false, 'subject', v_subject, 'body', v_body,
                             'to_email', c.email, 'locale', coalesce(c.locale,'en'), 'reveal_pct', v_rate_pct);
  end if;

  -- One welcome per address. A re-registration or a repeated trigger never doubles it.
  select exists (select 1 from public.notifications n
                  where n.kind = 'customer_welcome' and lower(n.to_email) = lower(c.email))
    into v_exists;
  if v_exists then
    return jsonb_build_object('ok', true, 'sent', false, 'reason', 'already welcomed', 'to_email', c.email);
  end if;

  insert into public.notifications (type, kind, channel, to_email, to_role, subject, body)
  values ('customer_welcome', 'customer_welcome', 'email', c.email, 'customer', v_subject, v_body)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'sent', true, 'notification_id', v_id, 'to_email', c.email,
                           'reveal_pct', v_rate_pct);
end $function$;

-- Ownership ledger follows the manifest (conventions step 4): this file is now canonical for the routine.
update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/a_bare_welcome_call_renders_and_never_sends.sql',
       evidence = 'a bare fn_customer_welcome call renders and never sends: p_send defaults to false (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_customer_welcome';

do $proof$
declare v_args text; v_before bigint; v_after bigint; v jsonb; v_trg text;
begin
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_customer_welcome';
  if v_args is distinct from 'p_customer_id uuid, p_send boolean DEFAULT false' then
    raise exception 'fn_customer_welcome signature is "%" (expected p_send boolean DEFAULT false)', v_args;
  end if;
  -- The exact bare call that sent the real email at 19:00:30Z, against the same real customer, now
  -- renders and queues nothing: the notification count is identical before and after.
  select count(*) into v_before from public.notifications where kind = 'customer_welcome';
  v := public.fn_customer_welcome('e0dee407-456c-4d8d-be52-2512bd4b1074');
  select count(*) into v_after from public.notifications where kind = 'customer_welcome';
  if coalesce((v->>'ok')::boolean, false) is not true or coalesce((v->>'sent')::boolean, true) is not false
     or coalesce(v->>'body','') = '' then
    raise exception 'bare call did not render-only: %', left(v::text, 300);
  end if;
  if v_after <> v_before then
    raise exception 'bare call queued a welcome (% -> %)', v_before, v_after;
  end if;
  -- The one sending path still names its intent explicitly.
  select p.prosrc into v_trg from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_customer_welcome_trg';
  if position('fn_customer_welcome(new.id, true)' in v_trg) = 0 then
    raise exception 'fn_customer_welcome_trg no longer passes p_send => true explicitly';
  end if;
  if has_function_privilege('anon', 'public.fn_customer_welcome(uuid, boolean)', 'EXECUTE') then
    raise exception 'fn_customer_welcome is executable by anon';
  end if;
  raise notice 'proof: bare fn_customer_welcome(id) rendered % chars and queued nothing (% welcomes before and after); z55 still passes true', length(v->>'body'), v_after;
end $proof$;

commit;
