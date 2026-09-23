-- THE LIVE COMPOSERS SAY IT IN NATIVE ARABIC (22 Sep 2026, documents-language audit DL-04).
--
-- SEAT: customer_support. Two routines re-defined from their current canonical files with the Arabic
-- corrected, and one app_secrets row. No table, no column, no grant change, no English word altered.
--
-- WHAT WAS FOUND. scripts/checks/every_arabic_message_is_written_not_translated.test.mjs scans
-- messages/ar.json, src/components, src/app, supabase/functions and the SQL files listed AFTER its own
-- anchor in MANIFEST.txt. Two live routines compose Arabic mail from SQL files that pre-date that
-- anchor, so their text was never scanned, and each carried an artefact the check names:
--   * public.fn_seat_clock_compose ...each_run_on_a_clock.sql:261  'الخاص بكم'  (possessive calque)
--   * public.fn_supplier_registration_reminder_compose ...is_followed.sql:138  'الخاصة بكم'
-- and beside them, read by eye against the register: 'وقد تمّت مطابقة طلبه' and 'إذا تمّ التعاقد'
-- (the past built with تمّ + a verbal noun), 'يتم التحقق منهما' for "verified", and a customer
-- addressed as 'السيد/ة … المحترم/ة'، a form field rather than a salutation.
--
-- A THIRD ROUTINE LOOKED LIKE A THIRD ARTEFACT AND IS NOT HERE. public.fn_supplier_collaboration_incident
-- carries 'نحن نفضّل' at a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql:185 — but that
-- file is not its canonical definition. See the note where part 3 would have been.
--
-- WHY A NEW FILE AND NOT AN EDIT. MANIFEST.txt decides canonicality by position, and it is append-only:
-- the LAST file defining a routine wins. Editing the old file would leave two files claiming the
-- routine with the older one still canonical. Both definitions are therefore re-issued here,
-- copied verbatim from their current canonical files with only the Arabic string literals changed —
-- and because this file sits after the anchor, the check now scans them on every run.
--
-- THE CHECK ITSELF was extended in the same change: it reads the canonical file of EVERY routine the
-- repository defines (the BODY, not the whole file), not only the files after its anchor, so the next composer whose Arabic lives in
-- a pre-anchor file cannot hide the way these did.
--
-- ALSO HERE: app_secrets.invite_body_ar, the supplier invitation body, carried the same
-- 'بوابة الموردين الخاصة بكم'. It is a stored value, not a routine: the owning file inserts it with
-- ON CONFLICT DO NOTHING, so only an update reaches the live text.
--
--   node scripts/apply_sql.mjs scripts/sql/the_live_composers_say_it_in_native_arabic.sql --apply --ddl

-- 1. the seat clock: the RFQ invitation, the quote reminder, the short-of-quotes update, the reveal check
create or replace function public.fn_seat_clock_compose(p_kind text, p_lang text, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_n int := coalesce((p->>'quotes')::int, 0);
  v_due text; v_subj text; v_body text;
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
  v_due := to_char((p->>'deadline')::timestamptz at time zone 'Asia/Dubai', case when v_ar then 'DD/MM/YYYY HH24:MI' else 'DD Mon YYYY, HH24:MI' end);

  if p_kind = 'rfq_invite' then
    if v_ar then
      v_subj := 'طلب عرض سعر جديد: ' || v_where_ar || ' — QuotesDone';
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'يسرّنا إفادتكم بأن أحد العملاء يطلب عروض أسعار في مجال ' || v_where_ar || '، ويتوافق طلبه مع نطاق أعمال شركتكم المسجّل لدينا. '
        || 'ويُرجى الاطّلاع على تفاصيل الطلب وتقديم عرضكم عبر بوابة الموردين:' || E'\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'New request for quotation: ' || v_where || ' — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'A customer is requesting quotations for ' || v_where || ', and the request matches the scope your company registered with us. '
        || 'Please review the details and submit your quotation in your supplier portal:' || E'\n\n' || v_link;
    end if;
  elsif p_kind = 'rfq_quote_reminder' then
    if v_ar then
      v_subj := 'تذكير: العميل بانتظار عرضكم — ' || v_where_ar;
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'نودّ تذكيركم بطلب عرض السعر في مجال ' || v_where_ar || ' الذي أُرسل إليكم عبر QuotesDone، إذ لم يصلنا عرضكم بعد. '
        || 'والعميل بانتظار العروض، ونأمل تقديم عرضكم في أقرب وقت، ويُفضَّل قبل ' || v_due || ' بتوقيت دبي.'
        || E'\n\nيمكنكم تقديم عرضكم عبر بوابة الموردين:\n\n' || v_link
        || E'\n\nوفي حال عدم رغبتكم في التقدّم بعرض لهذا الطلب، يُرجى إبلاغنا بذلك عبر البوابة أو بالرد على هذه الرسالة.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Reminder: the customer is waiting for your quotation — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
        || 'This is a reminder of the request for quotation for ' || v_where || ' sent to you through QuotesDone; we have not yet received your quotation. '
        || 'The customer is waiting for quotations, and we would appreciate yours as soon as possible, ideally before ' || v_due || ' (Dubai time).'
        || E'\n\nSubmit your quotation in your supplier portal:\n\n' || v_link
        || E'\n\nIf you would rather not quote for this request, please let us know in the portal or by replying to this e-mail.';
    end if;
  elsif p_kind = 'rfq_short_of_quotes' then
    if v_ar then
      v_subj := 'مستجدات طلبكم لعروض الأسعار — ' || v_where_ar;
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || case when v_n = 0 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' لم يتلقَّ أي عرض سعر حتى الآن. '
                when v_n = 1 then 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرض سعر واحدًا، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. '
                else 'نفيدكم بأن طلبكم في مجال ' || v_where_ar || ' تلقّى حتى الآن عرضَي سعر، ونسعى إلى أن تصلكم ثلاثة عروض على الأقل للمقارنة. ' end
        || 'وقد دعونا موردين إضافيين مطابقين لطلبكم، وذكّرنا الموردين المدعوين بتقديم عروضهم، وسيبقى طلبكم مفتوحًا لاستلام العروض.'
        || E'\n\nيمكنكم متابعة العروض فور وصولها عبر بوابتكم:\n\n' || v_link
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'An update on your request for quotations — ' || v_where;
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || case when v_n = 0 then 'Your request for ' || v_where || ' has not received a quotation yet. '
                when v_n = 1 then 'Your request for ' || v_where || ' has received one quotation so far; we aim for at least three for you to compare. '
                else 'Your request for ' || v_where || ' has received two quotations so far; we aim for at least three for you to compare. ' end
        || 'We have invited more suppliers who match your request, reminded the suppliers already invited, and your request stays open for quotations.'
        || E'\n\nYou can follow the quotations as they arrive in your portal:\n\n' || v_link;
    end if;
  elsif p_kind = 'reveal_outcome_check' then
    if v_ar then
      v_subj := 'هل تواصلتم مع ' || coalesce(p->>'supplier', 'المورّد') || '؟ — QuotesDone';
      v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
        || 'مضى أسبوع على اطّلاعكم على بيانات التواصل مع ' || coalesce(p->>'supplier', 'المورّد')
        || ' بشأن طلبكم في مجال ' || v_trade_ar || '، ونودّ الاطمئنان على سير الأمور: هل تواصلتم معهم؟ وهل أُسند العمل إليهم؟'
        || E'\n\nوفي حال التعاقد معهم، يُرجى تأكيد ذلك من بوابتكم باختيار «تعاقدتُ مع هذا المورّد» على عرضهم:\n\n' || v_link
        || E'\n\nوإن لم يتواصلوا معكم، أو قرّرتم عدم المضي قدمًا، يكفي الرد على هذه الرسالة وسنتابع الأمر معكم.'
        || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
    else
      v_subj := 'Did you get in touch with ' || coalesce(p->>'supplier', 'the supplier') || '? — QuotesDone';
      v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
        || 'It has been a week since you revealed the contact details of ' || coalesce(p->>'supplier', 'the supplier')
        || ' for your ' || v_trade || ' request. We would like to know how it is going: have you been in touch, and did you award them the work?'
        || E'\n\nIf you hired them, please confirm it in your portal by choosing "I hired this supplier" on their quotation:\n\n' || v_link
        || E'\n\nIf they have not contacted you, or you decided not to go ahead, simply reply to this e-mail and we will follow it up with you.';
    end if;
  else
    raise exception 'fn_seat_clock_compose: unknown kind %', p_kind;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_seat_clock_compose(text, text, jsonb) from public, anon, authenticated;

-- 2. the supplier registration reminder (clicked / started / incomplete, day 2 and day 6)
create or replace function public.fn_supplier_registration_reminder_compose(p public.leads, p_stage text, p_step integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := lower(coalesce(p.locale, '')) like 'ar%';
  v_lang text; v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_items_en text; v_items_ar text; v_due_en text; v_due_ar text; v_last boolean := p_step >= 2;
  v_greet text; v_subj text; v_body text;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورِّد'));
begin
  if p_stage not in ('clicked', 'started', 'incomplete') or p_step not in (1, 2) then
    raise exception 'fn_supplier_registration_reminder_compose: unknown stage % or step %', p_stage, p_step;
  end if;
  v_lang := case when v_ar then 'ar' else 'en' end;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  v_link := v_site || '/' || v_lang || '/portal'
            || case when p_stage = 'clicked' and p.claim_token is not null then '?t=' || p.claim_token::text else '' end;

  if p_stage = 'incomplete' then
    select string_agg(coalesce(v_label->k->>0, k), ', ' order by o), string_agg(coalesce(v_label->k->>1, k), '، ' order by o)
      into v_items_en, v_items_ar from unnest(public.fn_supplier_mandatory_six(p)) with ordinality u(k, o);
    if p.license_expiry is not null and p.license_expiry < current_date then
      v_items_en := concat_ws(', ', v_items_en, 'a trade licence that is in date');
      v_items_ar := concat_ws('، ', v_items_ar, 'رخصة تجارية سارية المفعول');
    end if;
    v_items_en := coalesce(v_items_en, 'the items shown in your portal');
    v_items_ar := coalesce(v_items_ar, 'البنود الموضّحة في بوابتكم');
    v_due_en := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon YYYY');
    v_due_ar := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  end if;

  if v_ar then
    v_greet := case when v_name is null then 'السادة الكرام،' else 'السادة/ ' || v_name || ' المحترمين،' end;
    v_subj := case when v_last then 'تذكير أخير: ' else '' end
      || case p_stage when 'clicked' then 'دعوتكم للانضمام إلى الموردين المؤسِّسين في QuotesDone'
                      else 'استكمال تسجيلكم كمورِّد في QuotesDone' end;
    v_body := v_greet || E'\n\nتحية طيبة وبعد،\n\n'
      || case p_stage
           when 'clicked' then
             'نشكر لكم اطّلاعكم على دعوتنا للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، ونودّ إفادتكم بأن تسجيل شركتكم لم يبدأ بعد. '
             || 'ولا يستغرق التسجيل سوى دقائق معدودة، وهو مجاني دون أي عمولة على الأعمال التي تُرسى عليكم.'
             || E'\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين عبر الرابط التالي:\n\n' || v_link
           when 'started' then
             'نشكر لكم بدء تسجيل شركتكم مورِّدًا على منصة QuotesDone، ونودّ إفادتكم بأن طلب التسجيل لم يُستكمل بعد. '
             || 'ولا يستغرق استكماله سوى دقائق معدودة: بيانات الشركة، ورقم جوال وبريد إلكتروني موثَّقان، والرخصة التجارية، '
             || 'والملف التعريفي للشركة، والموافقة على شروط المورِّد.'
             || E'\n\nيمكنكم متابعة التسجيل من حيث توقفتم عبر الرابط التالي:\n\n' || v_link
           else
             'نفيدكم بأن طلب تسجيل شركتكم محفوظ لدينا، غير أنه ما زال ينقصه: ' || v_items_ar || '. '
             || 'ويُرجى استكماله في موعد أقصاه ' || v_due_ar || '، إذ يُغلق طلب التسجيل تلقائيًا بعد هذا التاريخ، ويمكنكم التسجيل من جديد في أي وقت.'
             || E'\n\nيمكنكم استكمال البنود المطلوبة عبر بوابة الموردين:\n\n' || v_link
         end
      || case when v_last then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
      || E'\n\nوفي حال عدم رغبتكم في تلقي هذه التذكيرات، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_greet := case when v_name is null then 'Dear Sir or Madam,' else 'Dear ' || v_name || ',' end;
    v_subj := case when v_last then 'A last reminder: ' else '' end
      || case p_stage when 'clicked' then 'your invitation to join QuotesDone as a founding supplier'
                      else 'complete your QuotesDone supplier registration' end;
    v_body := v_greet || E'\n\n'
      || case p_stage
           when 'clicked' then
             'Thank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. '
             || 'It takes a few minutes, it is free, and there is no commission on the work you win.'
             || E'\n\nTo register, open your supplier portal here:\n\n' || v_link
           when 'started' then
             'Thank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. '
             || 'It takes a few minutes: company details, a verified mobile number and e-mail address, your trade licence, '
             || 'your company profile and acceptance of the supplier terms.'
             || E'\n\nContinue where you left off:\n\n' || v_link
           else
             'Your registration is saved, but it still needs: ' || v_items_en || '. '
             || 'Please complete it by ' || v_due_en || '; after that date the registration closes automatically, and you are welcome to start again at any time.'
             || E'\n\nComplete the missing items in your supplier portal:\n\n' || v_link
         end
      || case when v_last then E'\n\nThis is the last reminder we will send about it.' else '' end
      || E'\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_supplier_registration_reminder_compose(public.leads, text, integer) from public, anon, authenticated;

-- (There is no part 3. An earlier draft of this file re-issued fn_supplier_collaboration_incident as
-- well, copied from a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql — and that file is
-- NOT the canonical definition: every_arabic_message_is_written_not_translated.sql sits 174 positions
-- later in MANIFEST.txt and rewrote ten Arabic fragments of that routine on 22 Sep. Re-issuing the
-- older body would have rolled all ten back, which is the trap that cost this session hours elsewhere
-- today. The canonical body was then read: it is already native, already formal-plural, and carries no
-- artefact, so that routine needed nothing and is left where it is owned.)

-- 3. the stored invitation body ---------------------------------------------------------------------
-- The needle in this STATEMENT is built from halves rather than spelled, because an executable line
-- is scanned (apply discipline §7: a check that greps for a pattern matches the line repairing it).
-- The header above DOES spell the shapes in full, on purpose — a reader has to see what was wrong —
-- and what keeps those lines out of the scan is that they are comments: arabicLines() drops a line
-- whose first non-space characters are a SQL comment marker. That is the filter, not this note.
update public.app_secrets
   set value = replace(value, 'بوابة الموردين ' || 'الخاصة' || ' بكم', 'بوابة الموردين')
 where key = 'invite_body_ar' and value like '%' || 'الخاصة' || ' بكم%';

-- PROOF. No DDL is rolled back by this probe (it raises only on failure, which is the correct outcome
-- for a file whose whole content is the corrected text), and it composes letters for rows that do not
-- exist outside the transaction, so it can reach no person: fn_*_compose only returns jsonb.
do $probe$
declare
  v jsonb; s text; b text; bad text[] := '{}';
  l public.leads%rowtype;
begin
  v := public.fn_seat_clock_compose('rfq_invite', 'ar', jsonb_build_object('name', 'شركة ZZ DEMO', 'category', 'joinery', 'emirate', 'Dubai', 'deadline', (now() + interval '3 days')::text));
  b := (v->>'subject') || ' ' || (v->>'body');
  v := public.fn_seat_clock_compose('rfq_short_of_quotes', 'ar', jsonb_build_object('name', 'ZZ DEMO', 'category', 'joinery', 'emirate', 'Dubai', 'quotes', 1, 'deadline', (now() + interval '3 days')::text));
  b := b || ' ' || (v->>'subject') || ' ' || (v->>'body');
  v := public.fn_seat_clock_compose('reveal_outcome_check', 'ar', jsonb_build_object('name', 'ZZ DEMO', 'category', 'joinery', 'emirate', 'Dubai', 'supplier', 'ZZ DEMO Supplier', 'deadline', now()::text));
  b := b || ' ' || (v->>'subject') || ' ' || (v->>'body');

  l.company_name := 'ZZ DEMO Supplier'; l.email := 'zz-demo-probe@example.invalid'; l.locale := 'ar';
  v := public.fn_supplier_registration_reminder_compose(l, 'clicked', 1);
  b := b || ' ' || (v->>'subject') || ' ' || (v->>'body');
  v := public.fn_supplier_registration_reminder_compose(l, 'started', 2);
  b := b || ' ' || (v->>'subject') || ' ' || (v->>'body');

  -- Every needle is built from two halves, so this executable line cannot match its own scan
  -- (apply discipline §7). The header spells the same shapes; it is comment text and is filtered out.
  foreach s in array array['الخاص' || ' بك', 'الخاصة' || ' بك', 'سوف' || ' يتم', 'لقد' || ' تم',
                           'بوا' || 'سطة', 'يرجى' || ' ملاحظة', 'يُرجى' || ' ملاحظة', 'نحن' || ' ن',
                           'تمّت' || ' مطابقة', 'يتم' || ' التحقق منهما', 'السيد' || '/ة']
  loop
    if position(s in b) > 0 then bad := bad || s; end if;
  end loop;
  if cardinality(bad) > 0 then raise exception 'PROBE FAILED: composed Arabic still carries %', bad; end if;

  if position('السادة/' in b) = 0 then raise exception 'PROBE FAILED: the formal salutation is gone'; end if;
  if position('موثَّق' in b) = 0 then raise exception 'PROBE FAILED: the verified-contact wording is gone'; end if;
  if exists (select 1 from public.app_secrets where key = 'invite_body_ar' and value like '%' || 'الخاصة' || ' بكم%')
    then raise exception 'PROBE FAILED: the stored invitation body still carries the possessive calque'; end if;

  raise notice 'PROBE OK — five composed Arabic letters carry no artefact, and the stored invitation body is corrected';
end $probe$;
