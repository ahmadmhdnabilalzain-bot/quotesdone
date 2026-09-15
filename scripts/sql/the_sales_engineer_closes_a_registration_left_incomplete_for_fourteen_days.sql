-- THE SALES ENGINEER CLOSES A REGISTRATION LEFT INCOMPLETE FOR FOURTEEN DAYS, AND THE DOCUMENT
-- EXPIRY JOBS RUN EVERY DAY.
--
-- Assigned: sales_engineer. Scheduled on the IT engineer's heartbeat (resilience_ping ->
-- it_duty_schedule), because pg_cron is not coming back; the decisions are the sales engineer's.
--
-- MEASURED 15 SEP 2026 (production, read-only):
--   * supplier_api tells a refused supplier "Please do this within 14 days. If we have not received a
--     readable licence by then this registration closes automatically". Nothing closed anything:
--     fn_supplier_exception_sweep was dropped on 7 Sep (DROPPED.txt line 252). The window opened
--     (trg_leads_exception_invariant, exception_due_at = +14 days) and then nothing read it.
--   * supplier_portal says "fn_reconcile_doc_blocks runs daily". It did not run at all: no cron.job row
--     names it, fn_doc_final_notice or fn_expiring_docs, and no edge function calls them.
--   Both sentences are true after this file; neither text is changed.
--
-- fn_sales_engineer_supplier_documents_tick(), daily:
--   1. fn_reconcile_doc_blocks(0)   pause matching on an expired licence/insurance, restore on renewal
--   2. fn_doc_final_notice(7)       the final 7-day reminder
--   3. every approved supplier is re-verified, so a document removed from storage (not a leads write,
--      so no trigger sees it) still withdraws the approval
--   4. every action_required supplier past exception_due_at is verified once more (a document may have
--      arrived by a path that missed the trigger) and, if still incomplete, REJECTED with the reason,
--      and told so in their language through customer_support's delivery door.
--   5. fn_it_duty_ran('supplier_docs') — the beat fn_it_scheduled_due reads.
--
--   node scripts/apply_sql.mjs scripts/sql/the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql --apply --ddl

insert into public.it_duty_schedule (duty, every, note) values
  ('supplier_docs', interval '1 day',
   'sales_engineer: document expiry reconcile and final notice, approved suppliers re-verified, 14-day incomplete registrations closed (fn_sales_engineer_supplier_documents_tick)')
on conflict (duty) do update set every = excluded.every, note = excluded.note;

create or replace function public.fn_sales_engineer_supplier_documents_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_reconcile json; v_final json; v_rechecked int := 0; v_closed int := 0; v_kept int := 0; r record; v jsonb;
  v_missing text[]; v_items_en text; v_items_ar text; v_ar boolean; v_to text; v_opened text; v_out jsonb;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي تم التحقق منه'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني تم التحقق منه'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورّد'),
    'licence_expired', jsonb_build_array('a trade licence that is in date', 'رخصة تجارية سارية المفعول'));
begin
  v_reconcile := public.fn_reconcile_doc_blocks(0);
  v_final := public.fn_doc_final_notice(7);

  for r in select l.id from public.leads l
            where l.approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(l)) > 0 loop
    perform public.fn_sales_engineer_verifies_supplier(r.id, 'daily_recheck');
    v_rechecked := v_rechecked + 1;
  end loop;

  for r in select l.id, l.company_name, l.claimed_by, l.email, l.locale, l.exception_opened_at
             from public.leads l
            where l.approval_status = 'action_required' and l.exception_closed_at is null
              and l.exception_due_at <= now()
            order by l.id loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'deadline');
    if v->>'approval_status' is distinct from 'action_required' then v_kept := v_kept + 1; continue; end if;

    v_missing := array(select jsonb_array_elements_text(v->'missing'));
    if cardinality(v_missing) = 0 then v_missing := array['licence_expired']; end if;
    select string_agg(v_label->k->>0, ', ' order by o), string_agg(v_label->k->>1, '، ' order by o)
      into v_items_en, v_items_ar from unnest(v_missing) with ordinality u(k, o);

    -- trg_leads_exception_invariant closes the window with outcome closed_rejected.
    update public.leads
       set approval_status = 'rejected', verified = false, approval_decided_by = 'sales_engineer',
           rejection_reason = 'registration incomplete after ' || public.fn_supplier_exception_days() || ' days: ' || array_to_string(v_missing, ', ')
     where id = r.id;

    v_ar := r.locale = 'ar';
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_opened := to_char(r.exception_opened_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
    if v_to is not null then
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'registration_closed', 'requested_by', 'sales_engineer', 'channel', 'email',
        'to_email', v_to, 'to_role', 'supplier', 'lead_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end,
        'dedupe_key', 'registration_closed:' || r.id || ':' || extract(epoch from r.exception_opened_at)::bigint,
        'subject', case when v_ar then 'تم إغلاق طلب تسجيلكم كمورّد في QuotesDone'
                        else 'Your QuotesDone supplier registration has closed' end,
        'body', case when v_ar then
            'السادة ' || coalesce(r.company_name, 'المورّد') || '،' || chr(10) || chr(10)
            || 'فُتح طلب تسجيلكم كمورّد بتاريخ ' || v_opened || '، وما زال ينقصه: ' || v_items_ar || '. '
            || 'أبلغناكم أننا سنبقي الطلب مفتوحًا ' || public.fn_supplier_exception_days() || ' يومًا، وقد انقضت هذه المدة، لذلك أُغلق طلب التسجيل.' || chr(10) || chr(10)
            || 'يمكنكم التسجيل من جديد في أي وقت عبر https://quotesdone.com/portal، ويُفعَّل حسابكم فور اكتمال البنود الستة: '
            || 'اسم الشركة، ورقم جوال تم التحقق منه، وبريد إلكتروني تم التحقق منه، والرخصة التجارية، والملف التعريفي للشركة، والموافقة الموقّعة على شروط المورّد.' || chr(10) || chr(10)
            || 'إذا كنتم ترون أن هذا غير صحيح، يُرجى الرد على هذه الرسالة.'
          else
            'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
            || 'Your supplier registration was opened on ' || v_opened || ' and still needs: ' || v_items_en || '. '
            || 'We said we would keep it open for ' || public.fn_supplier_exception_days() || ' days; that time has passed, so the registration is now closed.' || chr(10) || chr(10)
            || 'You are welcome to register again at any time at https://quotesdone.com/portal. Your account activates as soon as the six required items are complete: '
            || 'company name, a verified mobile number, a verified e-mail address, your trade licence, your company profile and the signed supplier terms.' || chr(10) || chr(10)
            || 'If you believe this is wrong, reply to this e-mail.' end)));
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'low',
            'Registration closed after the ' || public.fn_supplier_exception_days() || '-day window — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required. The supplier was told in their language what was missing and that they may register again.',
            jsonb_build_object('supplier_id', r.id, 'decision', 'rejected', 'missing', v_missing, 'window_opened_at', r.exception_opened_at,
                               'notice', case when v_to is null then 'no e-mail on file' else 'queued through customer_support' end,
                               'source', 'fn_sales_engineer_supplier_documents_tick'),
            'leads', r.id::text);
    v_closed := v_closed + 1;
  end loop;

  v_out := jsonb_build_object('reconcile', v_reconcile, 'final_notice', v_final, 'approved_rechecked', v_rechecked,
                              'registrations_closed', v_closed, 'completed_at_deadline', v_kept);
  perform public.fn_it_duty_ran('supplier_docs', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_documents_tick() from public, anon, authenticated;

-- PROBE. A ZZ DEMO supplier whose window closed yesterday, run through the tick inside a block its own
-- raise rolls back. The delivery door queues into notifications; zzzz_notifications_demo_capture marks
-- an @example.invalid / is_demo row suppressed, and the rollback removes it anyway. Nothing real is read
-- beyond counts. Ends in a notice because this file carries DDL.
do $probe$
declare v_id bigint; v_before bigint; r_out jsonb; r_status text; r_outcome text; r_notices int; r_lang text;
begin
  select count(*) into v_before from public.leads;
  begin
    insert into public.leads (company_name, email, is_demo, source, locale)
    values ('ZZ DEMO fourteen-day probe', 'qd-fourteen-probe@example.invalid', true, 'probe', 'ar')
    returning id into v_id;
    update public.leads set approval_status = 'action_required', licence_gate_reason = 'reg_licence' where id = v_id;
    update public.leads set exception_opened_at = now() - interval '15 days', exception_due_at = now() - interval '1 day' where id = v_id;
    r_out := public.fn_sales_engineer_supplier_documents_tick();
    select approval_status, exception_outcome into r_status, r_outcome from public.leads where id = v_id;
    select count(*), max(lang) into r_notices, r_lang from public.notifications where lead_id = v_id and type = 'registration_closed' and channel = 'email';
    raise exception 'fourteen_probe_done';
  exception when others then
    if sqlerrm <> 'fourteen_probe_done' then raise; end if;
  end;
  if r_status is distinct from 'rejected' or r_outcome is distinct from 'closed_rejected' or r_notices is distinct from 1
     or r_lang is distinct from 'ar' or coalesce((r_out->>'registrations_closed')::int, 0) < 1 then
    raise exception 'fourteen-day probe FAILED: status=% outcome=% notices=% lang=% out=%', r_status, r_outcome, r_notices, r_lang, r_out;
  end if;
  if exists (select 1 from public.leads where id = v_id) or (select count(*) from public.leads) <> v_before then
    raise exception 'fourteen-day probe left a row behind';
  end if;
  raise notice 'fourteen-day probe ok: rejected, window closed_rejected, one Arabic notice queued, all rolled back; tick said %', r_out;
end $probe$;
