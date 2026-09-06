-- THE CUSTOMER WELCOME THE PRODUCT NEVER SENT (6 Sep 2026).
--
-- A real person registered on the live site at 07:38 UTC today (public.customers
-- e0dee407-456c-4d8d-be52-2512bd4b1074, email verified). The company opened W04 (customer
-- registration and onboarding), routed customer.registered to cs_onboarding, and the org_task lane
-- "determined" the task with executor NONE -- so NOTHING reached the customer. QuotesDone has never
-- sent a customer a welcome. That is the acting half of the founder's rule (2 Sep 2026): an
-- onboarding specialist who only *knows* a customer registered, and does nothing, is not doing the
-- job. A real onboarding specialist sends the first-request guidance the moment someone registers.
--
-- THE OWNER is cs_onboarding (org_role customer_onboarding, "Customer Onboarding Specialist";
-- event_subscription customer.registered -> cs_onboarding; docs/knowledge_audit/customer_experience.md
-- §4 "first-inquiry guidance"). This is that employee's deterministic act -- no model, no founder.
--
-- WHAT IT DOES. On every customer registration (AFTER INSERT on public.customers, which is where
-- customer.registered is emitted), fn_customer_welcome renders a branded welcome from LIVE facts --
-- the reveal rate from pricing_config, the refund rule linked to the published policy -- and queues
-- ONE notification. The shared renderer (send_outbox, email_customer template) applies the brand and
-- signature; this function supplies only the body, so a brand change made elsewhere flows through.
-- It routes to the CUSTOMER (to_role 'customer'), never the founder, and send_outbox refuses the
-- reserved @example.invalid demo domain before any provider call, so a rehearsal never emails anyone.
--
-- IDEMPOTENT: one welcome per address. FAIL-SAFE: the trigger can never abort a registration -- a
-- welcome that errors is swallowed, because a customer who could not be greeted must still be
-- created. The founder_mail_policy row registers the kind defensively so it can never be routed to
-- him even if a future path addressed one to an admin address.
--
--   node scripts/apply_sql.mjs scripts/sql/the_customer_welcome_the_product_never_sent.sql --apply --ddl

begin;

-- The kind is registered where notification kinds are enumerated. allowed_to_email=false means: if a
-- customer_welcome were ever addressed to the founder, it is NOT emailed to him -- it routes to an
-- owned task. A customer-facing welcome never reaches that path (it is to_role 'customer'), so this
-- is a belt-and-braces guarantee that this kind can never land in his inbox.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('customer_welcome', false,
        'Customer-facing onboarding welcome; owned by customer onboarding, never routed to the founder.',
        'customer_onboarding')
on conflict (kind) do update set
  allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

create or replace function public.fn_customer_welcome(p_customer_id uuid, p_send boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
  v_app_url    text := 'https://quotesdone.com/me';
begin
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
      || 'إذا لم يستجب المورّد الذي تم كشفه لمحاولة تواصل معقولة خلال ثلاثة أيام عمل، تُسترد رسوم الكشف '
      || 'البالغة ' || v_rate_pct || '٪ مع إثبات محاولتك. السياسة الكاملة: ' || v_refund_url || E'\n\n'
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
      || 'If a revealed supplier does not respond to your reasonable contact attempt within three '
      || 'working days, the ' || v_rate_pct || '% reveal fee is refundable with proof of your attempt. '
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

revoke all on function public.fn_customer_welcome(uuid, boolean) from public, anon, authenticated;
grant execute on function public.fn_customer_welcome(uuid, boolean) to service_role;

-- The deterministic act: greet every new registration. AFTER INSERT so the customer row is committed
-- to the row before the welcome is queued; a welcome that fails is swallowed so it can never abort a
-- registration (a customer who cannot be greeted must still be created).
create or replace function public.fn_customer_welcome_trg()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if coalesce(btrim(new.email),'') <> '' then
    begin
      perform public.fn_customer_welcome(new.id, true);
    exception when others then
      -- Never let onboarding courtesy break account creation.
      null;
    end;
  end if;
  return new;
end $function$;

revoke all on function public.fn_customer_welcome_trg() from public, anon, authenticated;

-- z55: after the kernel emit (z50) so the run exists first; the welcome is a courtesy, not a gate.
drop trigger if exists z55_customer_welcome on public.customers;
create trigger z55_customer_welcome
  after insert on public.customers
  for each row execute function public.fn_customer_welcome_trg();

-- Ownership ledger follows the manifest (conventions step 4).
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification)
values
  ('public','fn_customer_welcome','p_customer_id uuid, p_send boolean','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_customer_welcome_the_product_never_sent.sql','MANIFEST',
   'scripts/sql/the_customer_welcome_the_product_never_sent.sql', null),
  ('public','fn_customer_welcome_trg','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_customer_welcome_the_product_never_sent.sql','MANIFEST',
   'scripts/sql/the_customer_welcome_the_product_never_sent.sql', null)
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  justification = excluded.justification;

do $proof$
declare v_sub text; v_body text; v jsonb;
begin
  -- Render (do not send) proves the body carries the four required elements.
  v := public.fn_customer_welcome('e0dee407-456c-4d8d-be52-2512bd4b1074', false);
  if coalesce((v->>'ok')::boolean,false) is not true then
    raise exception 'welcome render failed: %', v::text;
  end if;
  v_body := v->>'body';
  if position('quotesdone.com/me' in v_body) = 0 then raise exception 'welcome omits the new-request link'; end if;
  if position('% of that quote' in v_body) = 0 and position('٪' in v_body) = 0 then raise exception 'welcome omits the reveal fee'; end if;
  if position('refund-policy' in v_body) = 0 then raise exception 'welcome omits the refund policy link'; end if;
  if position('top three' in v_body) = 0 and position('ثلاثة' in v_body) = 0 then raise exception 'welcome omits the top-3 rule'; end if;
  raise notice 'proof: welcome renders with new-request link, reveal fee, top-3 and refund link';
end $proof$;

commit;
