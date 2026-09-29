-- CUSTOMER SUPPORT GUIDES A FIRST REQUEST STEP BY STEP, AND ASKS A HELD ONE FOR ITS SPECS (29 Sep 2026).
-- Seat: customer_support (the first-inquiry concierge). Founder ledger 1018, round 3: "first-inquiry concierge".
-- Plain code, no model: every sentence is written here, in English and in Arabic, and every spec comes from a
-- verified trade pack.
--
-- WHAT WAS MEASURED (29 Sep 2026, production htdblwldjkcgjvmqkbeh, read-only):
--   * A customer who posts a request from the portal is told "Request sent" on screen and NOTHING else: no
--     notification of any "request received" kind was written to a customer in 60 days (public.notifications,
--     to_role = 'customer'). customer_support's activation duty writes only to a customer with NO request after
--     3 days, and to a request with no quote after 5.
--   * What to attach: the founder's ruling 1000 (28 Sep 2026) - "Drawings are accepted ONLY as PDF and CAD files
--     (DWG/DXF). Revit, IFC, DGN and other formats are not accepted." The portal refuses the rest at upload
--     (NewRequest.tsx REFUSED_DRAWING_RE, _shared/drawing_format.ts) but says so only AFTER a refused file.
--   * Which specs: sales_knowledge holds every verified trade pack's spec checklists in both languages - 295
--     entries in English and 295 in Arabic across 213 trades (tags kind:spec_checklist, trade:<code>, lang:<en|ar>),
--     the English ones listing required_specs. public.customer_spec_guide (#995) is empty by design: its content
--     is held by the founder; this file does not write it.
--   * Held for specs: public.inquiries.rfq_ready is computed by trg_rfq_complete (fn_rfq_score, BEFORE INSERT OR
--     UPDATE) and completeness names what is missing (category_missing: the category's required fields, with a
--     plain question in each language on category_specs.fields), and no customer was ever told which. All 3
--     inquiries on production today read rfq_ready false, each with one supplier matched.
--   * A request that reached NO supplier (no inquiry_matches row on it, or on any of a split request's per-trade
--     children) is a supply gap, not a spec hold: matching reads the trade, the emirate and the value, not the
--     specs, so telling that customer to add specs would blame them for something specs cannot fix (re-review).
--
-- WHAT THIS ADDS
--   1. fn_customer_concierge_checklists(category, lang): the trade's spec checklists from the verified packs,
--      through the taxonomy's own mapping (fn_taxonomy_trades_for). English: the topic and its required specs;
--      Arabic: the pack's Arabic paragraph for the same checklist.
--   2. fn_customer_concierge_held(inquiry): finding_suppliers (no supplier reached, judged through a split
--      request's children), or held (reached, specs missing: exactly what, per trade), in the request's language.
--   3. fn_customer_concierge(customer, category, lang, inquiry): the step-by-step guidance the portal shows -
--      describe the job, attach PDF or CAD (DWG/DXF) only, give these specs, what happens next - and whether this
--      is the customer's first request.
--   4. fn_customer_concierge_message(inquiry, kind): the e-mail, 'first_request' (the first confirmation message:
--      the request number, the held details or the search for suppliers, and the steps), 'held_for_specs' (a later
--      request suppliers have, still missing specs) or 'finding_suppliers' (a later request no supplier has yet, which
--      never mentions specs), in the request's language (fn_inquiry_locale, else the registered one).
--   5. fn_customer_support_concierge_confirm(inquiry): customer_support sends the right one, once per request
--      (fn_customer_support_duty_send, stages concierge.first_request / .held_for_specs / .finding_suppliers), and returns the
--      guidance. customer_api create_inquiry calls it the moment a request is posted.
--   6. customer_support.concierge (every 30 minutes, fn_customer_support_concierge_tick): the same for a request
--      posted by any other door (e-mail, WhatsApp) in the last 3 days. A fixture run (qd.duty_fixtures = 'on')
--      selects only demo customers.
--
-- WHAT THIS DOES NOT DO: it does not change what the portal accepts, what dispatch sends, or rfq_ready; it
-- writes no customer_spec_guide row; it raises no alarm (so it adds nothing to the healthy-day register) and no
-- table (so nothing to the daily export: the messages are rows of customer_support_duty_message and notifications,
-- both already exported).
--
--   node scripts/apply_sql.mjs scripts/sql/customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql --apply --ddl
--   proved before apply by the _probe.sql beside it, in one rolled-back transaction with this file.

-- ── 1. the trade's spec checklists ───────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_concierge_checklists(p_category text, p_lang text)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- ponytail: at most 6 checklists (a trade has 1-5 today); a longer list would bury the steps, so the cap stands
  -- until a trade needs more.
  select coalesce(jsonb_agg(x.item order by x.entry_id), '[]'::jsonb)
    from (select k.structured_data->>'entry_id' as entry_id,
                 jsonb_build_object('topic_id', k.structured_data->>'entry_id',
                   'topic', regexp_replace(coalesce(k.title, ''), '^Spec checklist:\s*', ''),
                   'specs', coalesce(k.structured_data->'required_specs', '[]'::jsonb),
                   'body', k.content) as item
            from public.sales_knowledge k
           where 'kind:spec_checklist' = any(k.tags)
             and k.structured_data->>'lang' = case when p_lang = 'ar' then 'ar' else 'en' end
             and exists (select 1 from unnest(public.fn_taxonomy_trades_for(array[p_category])) c
                          where ('trade:' || c) = any(k.tags))
           order by k.structured_data->>'entry_id'
           limit 6) x
$fn$;
revoke execute on function public.fn_customer_concierge_checklists(text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_concierge_checklists(text, text) to service_role;

-- ── 2. held for specs, finding suppliers, and what is missing ────────────────────────────────────────
-- Re-review of #1112 (29 Sep 2026): a request that reached NO supplier is not held for its specs, and its customer is
-- never told it is: it is 'finding_suppliers' and gets its own honest message. A combined (split) request is judged
-- by its per-trade parts: reached if any part has an inquiry_matches row, held on each part's own missing specs,
-- each named with its trade. Only a request that reached suppliers and still lacks required specs is held.
create or replace function public.fn_customer_concierge_held(p_inquiry uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; u public.inquiries; v_ar boolean; v_units uuid[]; v_split boolean; v_fields jsonb;
  v_missing jsonb := '[]'::jsonb; m jsonb; f jsonb; k text; v_pre text; v_lang text;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('held', false, 'finding_suppliers', false, 'reason', 'no such request'); end if;
  v_ar := coalesce(public.fn_inquiry_locale(i.id), (select c.locale from public.customers c where c.id = i.customer_id)) = 'ar';
  v_lang := case when v_ar then 'ar' else 'en' end;
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed') then
    return jsonb_build_object('held', false, 'finding_suppliers', false, 'lang', v_lang);
  end if;
  v_units := array(select c.id from public.inquiries c where c.parent_inquiry_id = i.id order by c.created_at);
  v_split := cardinality(v_units) > 0;
  if not v_split then v_units := array[i.id]; end if;
  if not exists (select 1 from public.inquiry_matches x where x.inquiry_id = any(v_units) or x.inquiry_id = i.id) then
    return jsonb_build_object('held', false, 'finding_suppliers', true, 'lang', v_lang, 'missing', '[]'::jsonb);
  end if;

  for u in select * from public.inquiries x where x.id = any(v_units) and not coalesce(x.rfq_ready, false)
            order by x.created_at loop
    v_pre := case when v_split then coalesce((select cs.label from public.category_specs cs where cs.category = u.category),
                                             replace(coalesce(u.category, ''), '_', ' ')) || ': ' else '' end;
    -- The category's required fields that are still open, in the plain words the intake asks them with.
    select cs.fields into v_fields from public.category_specs cs where cs.category = u.category;
    for m in select value from jsonb_array_elements(coalesce(u.completeness->'category_missing', '[]'::jsonb)) loop
      f := null;
      select value into f from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) where value->>'key' = m->>'key' limit 1;
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', m->>'key', 'inquiry_id', u.id,
        'ask', v_pre || coalesce(nullif(f->>case when v_ar then 'question_plain_ar' else 'question_plain_en' end, ''),
                                 nullif(m->>'question', ''), m->>'key')));
    end loop;
    -- The general score only holds a request when it is below the bar; then each missing part is named.
    if not coalesce((u.completeness->>'generic_ready')::boolean, true) then
      for k in select value from jsonb_array_elements_text(coalesce(u.completeness->'missing', '[]'::jsonb)) loop
        v_missing := v_missing || coalesce((select jsonb_build_array(jsonb_build_object('key', k, 'inquiry_id', u.id, 'ask', v_pre || case when v_ar then g.ar else g.en end))
          from (values
            ('category', 'What kind of work is it (the trade)?', 'ما نوع العمل المطلوب (التخصص)؟'),
            ('emirate', 'Which emirate and area is the work in?', 'في أي إمارة ومنطقة سيُنفَّذ العمل؟'),
            ('scope_detail', 'A fuller description of the work: what, how much and to what standard.', 'وصف أوفى للعمل: ما المطلوب، وبأي كمية، ووفق أي مواصفة.'),
            ('scope_type', 'Is it one trade, or several trades together?', 'هل يشمل تخصصًا واحدًا أم عدة تخصصات معًا؟'),
            ('budget', 'Your budget for the work (a range is fine).', 'الميزانية المرصودة للعمل (يكفي نطاق تقريبي).'),
            ('supporting_detail', 'A drawing (PDF, DWG or DXF), a bill of quantities, or the trades involved.', 'مخطط (PDF أو DWG أو DXF)، أو جدول كميات، أو التخصصات المعنية.')
          ) g(key, en, ar) where g.key = k), '[]'::jsonb);
      end loop;
    end if;
  end loop;
  return jsonb_build_object('held', jsonb_array_length(v_missing) > 0, 'finding_suppliers', false, 'lang', v_lang,
                            'missing', v_missing);
end $fn$;
revoke execute on function public.fn_customer_concierge_held(uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_concierge_held(uuid) to service_role;

-- ── 3. the guidance ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_concierge(p_customer uuid, p_category text default null,
                                                      p_lang text default null, p_inquiry uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_lang text; v_cat text := nullif(btrim(coalesce(p_category, '')), ''); v_first boolean; v_lists jsonb; v_specs text;
  v_label text;
begin
  if p_inquiry is not null and v_cat is null then select category into v_cat from public.inquiries where id = p_inquiry; end if;
  v_lang := case when p_lang in ('en', 'ar') then p_lang
                 else coalesce(public.fn_inquiry_locale(p_inquiry), (select c.locale from public.customers c where c.id = p_customer), 'en') end;
  if v_lang <> 'ar' then v_lang := 'en'; end if;
  -- First = no OTHER request of this customer's own (a split's per-trade children are the same request).
  v_first := not exists (select 1 from public.inquiries i where i.customer_id = p_customer and i.parent_inquiry_id is null
                                                        and i.id is distinct from p_inquiry);
  v_lists := case when v_cat is null then '[]'::jsonb else public.fn_customer_concierge_checklists(v_cat, v_lang) end;
  v_label := coalesce((select cs.label from public.category_specs cs where cs.category = v_cat), replace(v_cat, '_', ' '));

  if jsonb_array_length(v_lists) = 0 then
    v_specs := case when v_lang = 'ar'
      then 'اذكروا المقاسات والكميات والمواد أو العلامات التجارية المطلوبة، وأي مواصفة قياسية أو اعتماد لازم.'
      else 'State the sizes, the quantities, the materials or brands you need, and any standard or approval the work must meet.' end;
  elsif v_lang = 'ar' then
    v_specs := 'اذكروا هذه المواصفات، فبها يسعّر الموردون بدقة:' || chr(10)
      || (select string_agg('- ' || (e->>'body'), chr(10)) from jsonb_array_elements(v_lists) e);
  else
    v_specs := 'For ' || coalesce(v_label, 'this trade') || ', suppliers price exactly when you state:' || chr(10)
      || (select string_agg('- ' || (e->>'topic') || ': '
                            || (select string_agg(s, '; ') from jsonb_array_elements_text(e->'specs') s), chr(10))
            from jsonb_array_elements(v_lists) e);
  end if;

  return jsonb_build_object('lang', v_lang, 'first_inquiry', v_first, 'category', v_cat, 'checklists', v_lists,
    'held', case when p_inquiry is null then null else public.fn_customer_concierge_held(p_inquiry) end,
    'steps', case when v_lang = 'ar' then jsonb_build_array(
        jsonb_build_object('key', 'describe', 'title', 'صِفوا العمل',
          'body', 'ما المطلوب تنفيذه، وأين (الإمارة والمنطقة)، ومتى. طلب واحد لكل عمل، وإن شمل أكثر من تخصص فاذكروها ليصل كل جزء إلى الموردين المتخصصين فيه.'),
        jsonb_build_object('key', 'attach', 'title', 'أرفقوا المخططات',
          'body', 'بصيغة PDF أو CAD (DWG أو DXF) فقط، ولا تُقبل ملفات Revit وIFC وDGN وغيرها من ملفات النماذج، فصدّروا اللوحات إلى PDF أو DWG أولًا. ويمكن إرفاق جدول الكميات جدولَ بيانات أو ملف PDF، وتفيد صور الموقع أيضًا.'),
        jsonb_build_object('key', 'specs', 'title', 'اذكروا المواصفات', 'body', v_specs),
        jsonb_build_object('key', 'next', 'title', 'الخطوات التالية',
          'body', 'يقدّم الموردون الموثّقون في الإمارات العاملون في هذا التخصص عروضهم دون أن يعرفوا هويتكم، ونقارنها لكم ونوصي بأفضل ثلاثة منها من حيث القيمة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% من قيمة عرضه إلا حينها.'))
      else jsonb_build_array(
        jsonb_build_object('key', 'describe', 'title', 'Describe the job',
          'body', 'Say what you need done, where (the emirate and area) and by when. One request per job; if it covers several trades, name them so each part reaches the suppliers who specialise in it.'),
        jsonb_build_object('key', 'attach', 'title', 'Attach the drawings',
          'body', 'As PDF or CAD (DWG or DXF) only. Revit, IFC, DGN and other model files are not accepted: export the sheets to PDF or DWG first. A bill of quantities can be a spreadsheet or a PDF, and photos of the site help too.'),
        jsonb_build_object('key', 'specs', 'title', 'Give the specifications', 'body', v_specs),
        jsonb_build_object('key', 'next', 'title', 'What happens next',
          'body', 'Verified UAE suppliers in this trade quote without knowing who you are. We compare the quotes and recommend the top three by value. You reveal only the supplier you choose, and pay 3% of that quote only then.'))
      end);
end $fn$;
revoke execute on function public.fn_customer_concierge(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_concierge(uuid, text, text, uuid) to service_role;

-- ── 4. the e-mail ─────────────────────────────────────────────────────────────────────────────────────
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
  if coalesce((h->>'finding_suppliers')::boolean, false) then
    v_find := case when v_ar
      then 'نبحث عن موردين في تخصصكم: لا يغطي هذا الطلب أيٌّ من الموردين المسجّلين لدينا حاليًا، ونعمل على دعوة موردين متخصصين فيه. وسنراسلكم فور وصول طلبكم إلى أحدهم، ولا يلزمكم أي إجراء.'
      else 'We are finding suppliers for your trade. None of the suppliers registered with us today covers this request yet, and we are inviting suppliers who do. We will write as soon as one of them has your request; nothing is needed from you.' end;
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
    v_subj := case when v_ar then 'نبحث عن موردين لطلبكم ' || v_ref else 'We are finding suppliers for your request ' || v_ref end;
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
revoke execute on function public.fn_customer_concierge_message(uuid, text) from public, anon, authenticated;
grant execute on function public.fn_customer_concierge_message(uuid, text) to service_role;

-- ── 5. customer_support sends it ─────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_concierge_confirm(p_inquiry uuid)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; c public.customers; g jsonb; m jsonb; v_kind text; v_sent jsonb;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('sent', false, 'reason', 'no such request'); end if;
  -- A split's per-trade child is part of its parent's request: the customer hears about the request once.
  if i.parent_inquiry_id is not null then return jsonb_build_object('sent', false, 'reason', 'a per-trade part of a combined request'); end if;
  select * into c from public.customers where id = i.customer_id;
  if not found or coalesce(c.banned, false) then return jsonb_build_object('sent', false, 'reason', 'no customer to write to'); end if;
  g := public.fn_customer_concierge(i.customer_id, i.category, null, i.id);
  v_kind := case when coalesce((g->>'first_inquiry')::boolean, false) then 'first_request'
                 when coalesce((g#>>'{held,finding_suppliers}')::boolean, false) then 'finding_suppliers'
                 when coalesce((g#>>'{held,held}')::boolean, false) then 'held_for_specs' end;
  -- The first confirmation already carried the held details or the search for suppliers: one message per request.
  if v_kind in ('held_for_specs', 'finding_suppliers') and exists (select 1 from public.customer_support_duty_message d
       where d.stage = 'concierge.first_request' and d.subject_key = i.id::text) then v_kind := null; end if;
  if v_kind is null then return jsonb_build_object('sent', false, 'reason', 'not a first request, held or waiting for suppliers', 'concierge', g); end if;
  m := public.fn_customer_concierge_message(i.id, v_kind);
  v_sent := public.fn_customer_support_duty_send('concierge.' || v_kind, i.id::text, 'customer', c.email,
    m->>'lang', m->>'subject', m->>'body', c.id, null, i.id);
  return v_sent || jsonb_build_object('stage', 'concierge.' || v_kind, 'concierge', g);
end $fn$;
revoke execute on function public.fn_customer_support_concierge_confirm(uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_support_concierge_confirm(uuid) to service_role;

-- ── 6. the duty: every door, not only the portal ─────────────────────────────────────────────────────
create or replace function public.fn_customer_support_concierge_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_first int := 0; v_held int := 0; v_find int := 0;
begin
  -- ponytail: a 3-day window; a request older than that has had the activation duty's no-quote message (day 5)
  -- and a guide arriving later would read as noise. Widen it if the tick is ever down for longer.
  for r in select i.id from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.parent_inquiry_id is null and i.created_at > now() - interval '3 days'
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.customer_support_duty_message d
                               where d.stage in ('concierge.first_request', 'concierge.held_for_specs', 'concierge.finding_suppliers')
                                 and d.subject_key = i.id::text)
            order by i.created_at limit 200 loop
    v := public.fn_customer_support_concierge_confirm(r.id);
    if v->>'stage' = 'concierge.first_request' then v_first := v_first + 1;
    elsif v->>'stage' = 'concierge.held_for_specs' then v_held := v_held + 1;
    elsif v->>'stage' = 'concierge.finding_suppliers' then v_find := v_find + 1; end if;
  end loop;
  return jsonb_build_object('first_request', v_first, 'held_for_specs', v_held, 'finding_suppliers', v_find);
end $fn$;
revoke execute on function public.fn_customer_support_concierge_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_concierge_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.concierge', 'customer_support', interval '30 minutes', 'fn_customer_support_concierge_tick',
   'a customer''s first request is confirmed with step-by-step guidance (PDF or CAD drawings only, the trade''s specs), and a request held for its specs is asked for exactly what is missing, in the customer''s language',
   'scripts/sql/customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
