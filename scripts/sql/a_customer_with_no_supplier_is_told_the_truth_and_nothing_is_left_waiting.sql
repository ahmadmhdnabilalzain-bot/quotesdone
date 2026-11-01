-- Assigned: sales_engineer. 2 Nov 2026, founder ledger 1456: customers come only once suppliers exist.
-- MEASURED on production and in the code: a request with no supplier was told "we are inviting suppliers", "we will write
-- as soon as one has your request" and "we will let you know as soon as the first quotation arrives", with 0 verified
-- suppliers, and such a request stayed open with nothing ever closing it. Both messages are the live bodies (md5 compared)
-- with only that wording changed: no promise of a quote. fn_sales_engineer_closes_unreached_requests closes a request that
-- reached nobody after 14 days and tells the customer; resilience_ping runs it with the held_registrations duty.
-- Public pages and the request form are untouched. CREATE OR REPLACE keeps the two messages' ACLs. Applied at merge.
-- Prevented by: scripts/checks/a_customer_with_no_supplier_is_promised_no_quote.test.mjs.

create or replace function public.fn_customer_concierge_message(p_inquiry uuid, p_kind text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; c public.customers; g jsonb; h jsonb; v_ar boolean; v_name text; v_ref text; v_held text := ''; v_find text := '';
  v_steps text; v_subj text; v_body text; v_link text;
begin
  if p_kind not in ('first_request', 'held_for_specs', 'finding_suppliers') then
    raise exception 'a concierge message is first_request, held_for_specs or finding_suppliers, not %', p_kind;
  end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then raise exception 'no request %', p_inquiry; end if;
  select * into c from public.customers where id = i.customer_id;
  g := public.fn_customer_concierge(i.customer_id, i.category, null, i.id);
  h := g->'held';
  v_ar := g->>'lang' = 'ar';
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_ref := 'QD-' || public.fn_job_no(i.id);
  v_link := case when v_ar then 'https://quotesdone.com/ar/me' else 'https://quotesdone.com/me' end;

  if coalesce((h->>'held')::boolean, false) then
    v_held := (select string_agg('- ' || (e->>'ask'), chr(10)) from jsonb_array_elements(h->'missing') e) || chr(10) || chr(10)
      || case when v_ar
           then 'يمكنكم تعديل الميزانية والإمارة من حسابكم: ' || v_link || chr(10) || 'ولأي تفاصيل أخرى، يسعدنا أن تردّوا على هذه الرسالة بها.'
           else 'You can change the budget and the emirate from your account: ' || v_link || chr(10) || 'For anything else, reply to this e-mail with the details.' end;
  end if;
  -- NO SUPPLIER HAS IT YET: said as it is, never blamed on the specs (re-review of #1112).
  if coalesce((h->>'finding_suppliers')::boolean, false) and not public.fn_inquiry_awaits_specs(i.id) then
    v_find := case when v_ar
      then 'ما زلنا نسجّل الموردين في تخصصكم. لا يغطي هذا الطلب أيٌّ من الموردين المسجّلين لدينا اليوم، ولذلك لم يصل إلى أي مورّد، ولا يمكننا أن نعدكم بعرض سعر أو بموعد له، فنرجو ألا تؤخروا عملكم انتظارًا لنا. سنبقي طلبكم مفتوحًا 14 يومًا؛ وإذا لم يصل إلى أي مورّد خلالها أغلقناه وأبلغناكم. ولا يُطلب منكم أي إجراء أو مبلغ.'
      else 'We are still registering suppliers for your trade. No supplier registered with us today covers this request, so it has not reached anyone, and we cannot promise a quote or say when one might come. Please do not hold your work for us. We will keep your request open for 14 days; if it has reached no supplier by then, we will close it and tell you. Nothing is needed from you, and there is nothing to pay.' end;
  end if;
  -- The steps, numbered; only the specs step for a later request (the customer has seen the rest before).
  v_steps := (select string_agg(n || '. ' || (e->>'title') || ': ' || (e->>'body'), chr(10) || chr(10) order by n)
                from jsonb_array_elements(g->'steps') with ordinality s(e, n)
               where p_kind = 'first_request' or e->>'key' = 'specs');

  if p_kind = 'first_request' then
    v_subj := case when v_ar then 'استلمنا طلبكم ' || v_ref || ': الخطوات التالية' else 'We have your request ' || v_ref || ': what happens next' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم الأول على QuotesDone، ورقمه ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'وقبل أن يتمكّن الموردون من تسعيره، نحتاج منكم إلى التفاصيل التالية:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || 'وللحصول على عروض دقيقة قابلة للمقارنة، إليكم الخطوات:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your first request on QuotesDone. Its number is ' || v_ref || '.' || chr(10) || chr(10)
        || case when v_held <> '' then 'Before suppliers can price it, we need a few details from you:' || chr(10) || v_held || chr(10) || chr(10) else '' end
        || case when v_find <> '' then v_find || chr(10) || chr(10) else '' end
        || 'Here is how to get exact, comparable quotes, step by step:' || chr(10) || chr(10) || v_steps || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  elsif p_kind = 'finding_suppliers' then
    if v_find = '' then return jsonb_build_object('lang', g->>'lang', 'not_finding', true); end if;
    v_subj := case when v_ar then 'مستجدات طلبكم ' || v_ref else 'An update on your request ' || v_ref end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لطلبكم ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'ويمكنكم متابعة طلبكم من حسابكم: ' || v_link || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for your request ' || v_ref || '.' || chr(10) || chr(10) || v_find || chr(10) || chr(10)
        || 'You can follow your request from your account: ' || v_link || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  else
    if v_held = '' then return jsonb_build_object('lang', g->>'lang', 'not_held', true); end if;
    v_subj := case when v_ar then 'طلبكم ' || v_ref || ' يحتاج إلى بعض التفاصيل' else 'Your request ' || v_ref || ' needs a few details' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'يحتاج الموردون الذين وصلهم طلبكم ' || v_ref || ' إلى التفاصيل التالية ليسعّروه بدقة:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The suppliers who have your request ' || v_ref || ' need the following to price it exactly:' || chr(10) || v_held || chr(10) || chr(10)
        || v_steps || chr(10) || chr(10)
        || 'If anything is unclear, reply to this e-mail.' end;
  end if;
  return jsonb_build_object('lang', g->>'lang', 'subject', v_subj, 'body', v_body, 'held', h, 'first_inquiry', g->'first_inquiry');
end $fn$;

create or replace function public.fn_sales_engineer_stalled_inquiry_notice(p_lang text, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_hours int := coalesce((p->>'hours')::numeric, 48)::int;
  v_pool int := coalesce((p->>'pool')::int, 0);
  v_unreachable boolean := coalesce(p->>'reason', '') = 'no_reachable_supplier';
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');

  if v_ar then
    v_subj := 'مستجدات طلبكم — ' || v_where_ar;
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
      || case when v_unreachable
           then 'لم يصل طلبكم في مجال ' || v_where_ar || ' بعدُ إلى مورّد يستطيع تسعيره، إذ لا يتوفر حاليًا أيٌّ من الموردين المسجّلين في هذا المجال لتولّيه. '
           else 'مضت ' || v_hours || ' ساعة على إرسال طلبكم في مجال ' || v_where_ar
                || ' إلى الموردين المطابقين، ولم يصلنا أي عرض سعر حتى الآن. ' end
      || case when v_pool > 0
           then 'ولذلك قدّمنا مجال طلبكم ومنطقته على غيرهما في دعوة الموردين الجدد، فيكون الموردون الذين ندعوهم تاليًا ممن يستطيعون تسعير طلبكم. '
           else 'وليس في قائمتنا حاليًا موردون آخرون في هذا المجال في ' || coalesce(v_em_ar, 'الإمارات')
                || '، ولذلك نعمل على استقطاب موردين جدد له. ' end
      || case when v_unreachable then 'ولا يمكننا أن نعدكم بعرض سعر، فنرجو ألا تؤخروا عملكم انتظارًا لنا. وإذا لم يصل طلبكم إلى أي مورّد خلال 14 يومًا أغلقناه وأبلغناكم، وليس عليكم أي مبلغ.' else 'ويبقى طلبكم مفتوحًا، وسنُعلمكم فور وصول أول عرض سعر.' end
      || E'\n\nيمكنكم متابعة طلبكم عبر بوابتكم:\n\n' || v_link
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_subj := 'An update on your request — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
      || case when v_unreachable
           then 'Your request for ' || v_where || ' has not yet reached a supplier who can quote it: none of the suppliers registered for it can take it on right now. '
           else 'It has been ' || v_hours || ' hours since your request for ' || v_where
                || ' was sent to the matching suppliers, and no quotation has arrived yet. ' end
      || case when v_pool > 0
           then 'We have therefore put your trade and area first in our supplier recruitment, so the next suppliers we invite are ones who can quote for your request. '
           else 'We have no further suppliers for this trade in ' || coalesce(v_em, 'the UAE')
                || ' on our list yet, so we are sourcing new ones for it. ' end
      || case when v_unreachable then 'We cannot promise a quotation, so please do not hold your work for us. If your request has reached no supplier 14 days after you sent it, we will close it and tell you; there is nothing to pay.' else 'Your request stays open, and we will let you know as soon as the first quotation arrives.' end
      || E'\n\nYou can follow your request in your portal:\n\n' || v_link;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;

create or replace function public.fn_inquiry_awaits_specs(p_inquiry uuid)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.inquiries x
                  where not coalesce(x.rfq_ready, false)
                    and (x.parent_inquiry_id = p_inquiry
                         or (x.id = p_inquiry and not exists (select 1 from public.inquiries c where c.parent_inquiry_id = p_inquiry))))
$fn$;
revoke execute on function public.fn_inquiry_awaits_specs(uuid) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_closes_unreached_requests(p_at timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_ar boolean; v_ref text; v_closed int := 0;
begin
  for r in select i.id, i.lang, c.email from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.parent_inquiry_id is null and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
              and i.created_at <= p_at - interval '14 days'
              and not exists (select 1 from public.inquiry_matches m join public.inquiries k on k.id = m.inquiry_id where k.id = i.id or k.parent_inquiry_id = i.id)
              and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
              -- Held for its own missing specs: the customer owes us an answer, and "no supplier" would be a false reason.
              and not public.fn_inquiry_awaits_specs(i.id)
            order by i.created_at limit 100 loop
    update public.inquiries set status = 'expired' where id = r.id or parent_inquiry_id = r.id;
    update public.stalled_inquiry_rescue set cleared_at = p_at, cleared_why = 'request closed' where inquiry_id = r.id and cleared_at is null;
    v_ar := coalesce(r.lang, '') like 'ar%'; v_ref := 'QD-' || public.fn_job_no(r.id);
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'request_closed_no_supplier', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', lower(btrim(r.email)), 'to_role', 'customer',
      'inquiry_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'request_closed_no_supplier:' || r.id,
      'subject', case when v_ar then 'أغلقنا طلبكم ' || v_ref else 'We have closed your request ' || v_ref end,
      'body', case when v_ar then 'عميلنا الكريم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10) || 'شكرًا لتواصلكم معنا. لم يصل طلبكم ' || v_ref || ' إلى أي مورّد خلال 14 يومًا، لأننا ما زلنا نسجّل الموردين في هذا التخصص، ولذلك أغلقناه. نعتذر عن ذلك، وليس عليكم أي مبلغ. ويسعدنا أن ترسلوا طلبًا جديدًا في أي وقت.' || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
                   else 'Dear Customer,' || chr(10) || chr(10) || 'Thank you for coming to us. Your request ' || v_ref || ' did not reach a supplier in 14 days, because we are still registering suppliers for this trade, so we have closed it. We are sorry, and there is nothing to pay. You are welcome to send a new request at any time.' end)));
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'request_closed_no_supplier', 'auto_done', 'low', 'Request closed: no supplier in 14 days — ' || v_ref, 'No action required. The customer was told.',
            jsonb_build_object('inquiry_id', r.id), 'inquiries', r.id::text);
    v_closed := v_closed + 1;
  end loop;
  return jsonb_build_object('closed', v_closed);
end $fn$;
revoke execute on function public.fn_sales_engineer_closes_unreached_requests(timestamptz) from public, anon, authenticated;

select case when has_function_privilege('anon', 'public.fn_sales_engineer_closes_unreached_requests(timestamptz)', 'execute') then 'PROBE FAILED: anon can run the closer' else 'PROBE OK' end as verdict;
