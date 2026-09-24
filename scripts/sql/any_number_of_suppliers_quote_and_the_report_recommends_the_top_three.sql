-- customer_support, 24 Sep 2026. Two wrong things in the customer messages of #904, found by the founder
-- registering as a test customer:
--  1. They capped the number of quotes at three, in English and in Arabic, in the activation and win-back texts.
--     The founder's rule: ANY number of verified suppliers in the trade may quote. "Top three" is only the
--     comparison report, which recommends the three best by value; every other quote is listed too.
--  2. Every customer link went to /portal, the SUPPLIER entry. A customer's link is the customer sign-in,
--     /me (Arabic /ar/me), on the canonical origin quotesdone.com (UAE visitors are 308'd to .ae by the
--     middleware, see src/lib/domains.ts).
-- The three routines below supersede their bodies in customer_support_activates_wins_back_and_settles_disputes.sql;
-- only the message text and the links change. The seat's marketing knowledge said to write "compare ...
-- three quotes" as the safe claim; it is corrected here in both languages.
-- prevented by: scripts/checks/customer_messages_state_the_quote_rule_and_link_the_customer_sign_in.test.mjs

create or replace function public.fn_customer_support_activation_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_ar boolean; v_name text; v_signup int := 0; v_noquote int := 0; v_stalled int := 0;
begin
  -- a) signed up three days ago or more, never posted a request
  for r in select c.id, c.full_name, c.email, c.locale from public.customers c
            where c.created_at < now() - interval '3 days' and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.inquiries i where i.customer_id = c.id)
            order by c.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.first_request', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم الأول على QuotesDone' else 'Your first request on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لانضمامكم إلى QuotesDone. لم تنشروا طلبكم الأول بعد، انشروا طلبكم مرة واحدة، وأرفقوا المخطط أو جدول الكميات إن توفّر، فيقدّم الموردون الموثّقون في الإمارات العاملون في هذا التخصص عروضهم، ونقارنها لكم ونوصي بأفضل ثلاثة منها من حيث القيمة في تقرير المقارنة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها.' || chr(10) || chr(10)
        || 'ابدؤوا من هنا: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'وإن واجهتم ما يمنعكم من البدء، يسعدنا أن تردّوا على هذه الرسالة لنساعدكم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for joining QuotesDone. You have not posted a request yet. Post your request once, with a drawing or a bill of quantities if you have one; verified UAE suppliers in that trade quote, and we compare them and recommend the top three by value in your comparison report. You reveal only the one you choose, and pay 3% only then.' || chr(10) || chr(10)
        || 'Start here: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'If something stopped you, reply to this e-mail and we will help.' end,
      r.id);
    if (v->>'sent')::boolean then v_signup := v_signup + 1; end if;
  end loop;

  -- b) a request five days old with no quote, and c) ten days old with none: the second is a judgement
  for r in select i.id, i.rfq_no, i.created_at, i.category, i.emirate, i.trades, i.rfq_ready, i.completeness,
                  i.summary_masked, c.id as cid, c.full_name, c.email, c.locale
             from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.created_at < now() - interval '5 days' and i.created_at > now() - interval '60 days'
              and i.completed_at is null and i.hired_supplier_id is null and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
            order by i.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.no_quote', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم لم يصله عرض سعر بعد' else 'Your request has no quote yet' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'لم يصل بعدُ أي عرض سعر على طلبكم المنشور بتاريخ ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY')
        || '، وما زلنا ندعو الموردين العاملين في هذا المجال. ويساعد الموردين على التسعير بسرعة أن يتضمّن الطلب نطاق العمل والكميات والمخطط، ويمكنكم إضافتها من حسابكم: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'ولأي مساعدة، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Your request posted on ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ' has not received a quote yet, and we are still inviting suppliers who work in this trade. A clear scope, quantities and a drawing help suppliers price quickly; you can add them from your account: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Reply to this e-mail if you would like help.' end,
      r.cid, null, r.id);
    if (v->>'sent')::boolean then v_noquote := v_noquote + 1; end if;

    if r.created_at < now() - interval '10 days'
       and not exists (select 1 from public.customer_support_duty_message m where m.stage = 'activation.stalled' and m.subject_key = r.id::text)
       and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'stalled_request:' || r.id) then
      perform public.fn_seat_duty_reason('customer_support', 'customer_support.stalled_request',
        case when v_fx then 'ZZ DEMO ' else '' end
        || 'A customer''s request has had no quote for ' || extract(day from now() - r.created_at)::int
        || ' days. From the facts of the request, which message should customer support send the customer?',
        jsonb_build_array(
          jsonb_build_object('id', 'add_details', 'meaning', 'the request lacks what a supplier needs to price it; ask the customer for the missing scope, quantities or drawing'),
          jsonb_build_object('id', 'widen_scope', 'meaning', 'the request is priceable but too narrow for the suppliers available; suggest widening the emirate, the trade or the delivery window'),
          jsonb_build_object('id', 'keep_waiting', 'meaning', 'the request is sound; tell the customer it is still with suppliers and when to expect news')),
        jsonb_build_object('inquiry_id', r.id, 'rfq_no', r.rfq_no, 'posted_at', r.created_at, 'category', r.category,
          'emirate', r.emirate, 'trades', to_jsonb(r.trades), 'rfq_ready', r.rfq_ready, 'completeness', r.completeness,
          'summary', r.summary_masked, 'quotes', 0),
        jsonb_build_object('inquiry_id', r.id), 'stalled_request:' || r.id);
      v_stalled := v_stalled + 1;
    end if;
  end loop;
  return jsonb_build_object('first_request', v_signup, 'no_quote', v_noquote, 'stalled_filed', v_stalled);
end $fn$;
revoke execute on function public.fn_customer_support_activation_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_activation_tick() to service_role;

create or replace function public.fn_reason_apply_customer_support__stalled_request(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; r record; v_ar boolean; v_name text;
  v_en text; v_arb text;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not exists (select 1 from jsonb_array_elements(h.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select i.id, i.created_at, c.id as cid, c.full_name, c.email, c.locale into r
    from public.inquiries i join public.customers c on c.id = i.customer_id where i.id::text = h.subject->>'inquiry_id';
  if not found then return jsonb_build_object('applied', false, 'reason', 'the request no longer exists'); end if;
  if exists (select 1 from public.quotes q where q.inquiry_id = r.id) then
    return jsonb_build_object('applied', true, 'sent', false, 'reason', 'a quote arrived while the question was held');
  end if;
  v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_en := case v_choice
    when 'add_details' then 'Suppliers have looked at your request but need more to price it. Please add the scope of work, the quantities and, if you have one, a drawing or bill of quantities from your account: https://quotesdone.com/me'
    when 'widen_scope' then 'Few suppliers cover this request exactly as it stands. Widening it, for example to a neighbouring emirate, a related trade or a later delivery date, usually brings quotes in. You can change it from your account: https://quotesdone.com/me'
    else 'Your request is complete and is still with suppliers in this trade. We will write as soon as the first quote arrives; nothing is needed from you now.' end;
  v_arb := case v_choice
    when 'add_details' then 'اطّلع الموردون على طلبكم، ويحتاجون إلى تفاصيل أكثر لتسعيره. نرجو إضافة نطاق العمل والكميات، والمخطط أو جدول الكميات إن توفّر، من حسابكم: https://quotesdone.com/ar/me'
    when 'widen_scope' then 'عدد الموردين الذين يغطّون طلبكم بصيغته الحالية محدود، وتوسيعه عادةً يجلب العروض، كأن يشمل إمارة مجاورة أو تخصصًا قريبًا أو موعد تسليم لاحقًا. ويمكنكم تعديله من حسابكم: https://quotesdone.com/ar/me'
    else 'طلبكم مكتمل، وما زال لدى الموردين العاملين في هذا المجال. سنبلغكم فور وصول أول عرض سعر، ولا يلزمكم أي إجراء الآن.' end;
  return jsonb_build_object('applied', true, 'choice', v_choice, 'send',
    public.fn_customer_support_duty_send('activation.stalled', r.id::text, 'customer', r.email, case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'مستجدات طلبكم على QuotesDone' else 'An update on your QuotesDone request' end,
      case when v_ar then 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10) || v_arb
                          || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
           else 'Dear ' || v_name || ',' || chr(10) || chr(10) || v_en end,
      r.cid, null, r.id));
end $fn$;
revoke execute on function public.fn_reason_apply_customer_support__stalled_request(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__stalled_request(bigint, jsonb) to service_role;

-- ── 2. win-back ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_winback_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb; v_ar boolean;
  v_name text; v_sent int := 0; v_seen int := 0;
begin
  for r in select c.id, c.full_name, c.email, c.locale, x.last_reveal
             from public.customers c
             cross join lateral (select max(t.revealed_at) as last_reveal from public.transactions t
                                  where t.customer_id = c.id and t.revealed_at is not null) x
            where x.last_reveal between now() - interval '90 days' and now() - interval '60 days'
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              -- dormant: nothing posted since the last reveal
              and not exists (select 1 from public.inquiries i where i.customer_id = c.id and i.created_at > x.last_reveal)
            order by x.last_reveal limit 200 loop
    v_seen := v_seen + 1;
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    -- one message per dormant spell: the key carries the reveal that started it
    v := public.fn_customer_support_duty_send('winback.dormant', r.id || ':' || to_char(r.last_reveal, 'YYYYMMDD'), 'customer',
      r.email, case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'مشروعكم القادم على QuotesDone' else 'Your next project on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'مضى بعض الوقت على مشروعكم الأخير معنا. وحين يحين مشروعكم القادم، يكفي أن تنشروه مرة واحدة، فيقدّم الموردون الموثّقون في الإمارات العاملون في هذا التخصص عروضهم، ونقارنها لكم ونوصي بأفضل ثلاثة منها من حيث القيمة في تقرير المقارنة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'It has been a while since your last project with us. When the next one comes up, post it once; verified UAE suppliers in that trade quote, and we compare them and recommend the top three by value in your comparison report. You reveal only the one you choose, and pay 3% only then: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.' end,
      r.id);
    if (v->>'sent')::boolean then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('dormant', v_seen, 'written', v_sent);
end $fn$;
revoke execute on function public.fn_customer_support_winback_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_winback_tick() to service_role;


update public.marketing_knowledge
   set content = replace(content, 'say "compare up to ' || 'three quotes"',
                         'say "compare every quote in one report, with the top three recommended by value"'),
       body_sha256 = encode(sha256(convert_to(replace(content, 'say "compare up to ' || 'three quotes"',
                         'say "compare every quote in one report, with the top three recommended by value"'), 'UTF8')), 'hex')
 where record_id = 'marketing:consumer-protection-advertising';
update public.marketing_knowledge
   set content = replace(content, '«قارن حتى ' || 'ثلاثة عروض»', '«قارن كل العروض في تقرير واحد، مع توصية بأفضل ثلاثة من حيث القيمة»'),
       body_sha256 = encode(sha256(convert_to(replace(content, '«قارن حتى ' || 'ثلاثة عروض»',
                         '«قارن كل العروض في تقرير واحد، مع توصية بأفضل ثلاثة من حيث القيمة»'), 'UTF8')), 'hex')
 where record_id = 'marketing:consumer-protection-advertising@ar';

select case
  when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname in ('fn_customer_support_activation_tick',
                      'fn_customer_support_winback_tick', 'fn_reason_apply_customer_support__stalled_request')
                  and (pg_get_functiondef(p.oid) ~* ('up to ' || '(three|3)|حتى ' || 'ثلاثة') or pg_get_functiondef(p.oid) ~ 'quotesdone\.(com|ae)/(ar/)?portal'))
    then 'PROBE FAILED: a customer routine still limits the quotes or links the supplier portal'
  when exists (select 1 from public.marketing_knowledge where content ~* ('up to ' || 'three quotes|حتى ' || 'ثلاثة عروض'))
    then 'PROBE FAILED: the marketing knowledge still caps the quotes'
  else 'PROBE OK' end as verdict;
