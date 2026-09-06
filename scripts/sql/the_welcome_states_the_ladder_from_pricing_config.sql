-- THE WELCOME STATES THE LADDER FROM PRICING_CONFIG (6 Sep 2026). Follows the_customer_welcome_the_product_never_sent.sql.
--
-- The welcome rendered for the customer who registered this morning said "within three working days"
-- (and its Arabic twin said the same): a literal written before the refund ladder moved the same
-- afternoon (founder ruling, 6 Sep 2026: five working days from payment, the chase at three, his final
-- call at five, banks 7-14 working days; pricing_config.refund_window_working_days /
-- chase_after_working_days / bank_settlement_working_days_min/max). Both refund paragraphs now read
-- those four values at render time, so the welcome can never contradict the policy page again.
-- Everything else in the function is unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/the_welcome_states_the_ladder_from_pricing_config.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_customer_welcome(p_customer_id uuid, p_send boolean DEFAULT true)
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

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_welcome_states_the_ladder_from_pricing_config.sql',
       evidence = 'the welcome reads the refund ladder from pricing_config (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_customer_welcome';

-- proof: a dry render for the newest English-locale customer states the ladder, not the old literal
do $$
declare v jsonb;
begin
  select public.fn_customer_welcome(c.id, false) into v from public.customers c where coalesce(c.locale,'en') = 'en' order by c.created_at desc limit 1;
  if v is null then return; end if;   -- no such customer: nothing to render
  if (v->>'body') like '%within three working days%' then raise exception 'welcome still carries the three-day literal'; end if;
  if (v->>'body') not like '%working days from your payment%' then raise exception 'welcome does not state the ladder: %', left(v->>'body', 200); end if;
end $$;
