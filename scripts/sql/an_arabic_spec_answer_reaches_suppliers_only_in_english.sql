-- AN ARABIC SPEC ANSWER REACHES SUPPLIERS ONLY IN ENGLISH (5 Oct 2026, sales_engineer; ledger 993 "suppliers always
-- English", founder_instruction 1026). Depends on #1195
-- (a_customers_arabic_is_kept_as_written_and_reaches_suppliers_in_english.sql: rfq_clarification.answer_as_written,
-- english_held_at, and the held-note shape).
--
-- Measured before: fn_inquiry_add_missing_specs wrote a customer's free-text answer into inquiries.spec, noted it on
-- rfq_clarification.answer and handed every matched supplier an e-mail carrying it verbatim. An answer typed in Arabic
-- reached suppliers in Arabic three ways: the addendum e-mail, the Q&A note, and spec_masked (the spec column of
-- inquiries_supplier_safe, which the supplier portal reads).
--
-- Now, the same design #1195 gave clarification answers and notes:
--   * every answer is still written into spec AS WRITTEN, so the hold check (fn_rfq_required_check) sees the spec
--     answered and the request is released as before - never stuck waiting on a model;
--   * EXCEPT budget and emirate: they are request columns every supplier copy reads raw (inquiries_supplier_safe
--     .emirate, the budget in the invitation), so an Arabic-script answer to either is NOT written - it stays missing
--     and the page asks it again (returned as kept_missing). Holding the request there is the safe side;
--   * answers carrying Arabic script are NOT mailed and NOT put on the supplier note. They go on ONE held note
--     (answer null, answer_as_written = the lines as written, english_held_at set) whose English is filed, in the same
--     transaction, in the sales_engineer reasoning queue (fn_reason_hold, surface sales_engineer.supplier_english,
--     dedupe supplier_english:<note id>) - the exact request _shared/supplier_english.ts holdForEnglish files. The
--     replay translates it when the model hold allows, and finishEnglish verifies there is no Arabic left, stores the
--     English as the supplier copy and e-mails every supplier matched AT THAT MOMENT once (so a request released
--     before the English arrives still tells the suppliers it reached);
--   * spec_masked drops every spec value carrying Arabic script (scrub_inquiry_contacts), so the portal copy of the
--     request never shows it. Options chosen from the list are English and pass through unchanged.
-- Answers in English keep the old path exactly (one note, one e-mail per matched supplier).
-- CREATE OR REPLACE on both routines: the ACLs are preserved, no revoke is owed. No new table, no new routine.

create or replace function public.fn_inquiry_add_missing_specs(p_inquiry uuid, p_customer uuid, p_answers jsonb, p_source text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  i public.inquiries; v_missing jsonb; v_add jsonb := '{}'::jsonb; v_lines text := ''; v_held text := ''; e record; v_val text; v_ask text;
  v_note bigint; v_held_note bigint; v_after public.inquiries; v_told int := 0; l record; v_res jsonb; v_head text; v_q text; v_kept jsonb := '[]'::jsonb;
begin
  if p_source not in ('customer_portal', 'email_reply') then raise exception 'missing specs come from customer_portal or email_reply, not %', p_source; end if;
  if p_source = 'customer_portal' and p_customer is null then raise exception 'a portal answer names its customer'; end if;
  select * into i from public.inquiries where id = p_inquiry for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'inquiry_not_found'); end if;
  if p_customer is not null and i.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_inquiry'); end if;
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed') then return jsonb_build_object('ok', false, 'error', 'inquiry_closed'); end if;
  if jsonb_typeof(p_answers) is distinct from 'object' then return jsonb_build_object('ok', false, 'error', 'answers_required'); end if;

  -- Only what is missing NOW, keyed as the check reads it; anything else is not this door's to write.
  v_missing := public.fn_inquiry_missing_specs(i.id, 'en')->'missing';
  for e in select a.key, a.value from jsonb_each_text(p_answers) a loop
    v_val := left(btrim(coalesce(e.value, '')), 300);
    select m->>'ask' into v_ask from jsonb_array_elements(v_missing) m where m->>'key' = lower(btrim(e.key));
    if v_ask is null or not public._rfq_answered(v_val) then continue; end if;
    -- Budget and emirate are columns every supplier copy reads raw (inquiries_supplier_safe.emirate, the invitation):
    -- in Arabic script they are NOT written and stay missing, so the page asks them again; digits and English pass
    -- (Arabic-Indic digits are written as the same Western digits first, so "٥٠٠٠" is 5000).
    if lower(btrim(e.key)) in ('budget', 'emirate') then
      v_val := translate(v_val, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
    end if;
    if lower(btrim(e.key)) in ('budget', 'emirate') and v_val ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then
      v_kept := v_kept || jsonb_build_array(lower(btrim(e.key))); continue;
    end if;
    v_add := v_add || jsonb_build_object(lower(btrim(e.key)), v_val);
    -- Suppliers read English only: an answer in Arabic script waits for its English on the held note.
    if v_val ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then
      v_held := v_held || case when v_held = '' then '' else chr(10) end || v_ask || ' ' || v_val;
    else
      v_lines := v_lines || case when v_lines = '' then '' else chr(10) end || v_ask || ' ' || v_val;
    end if;
  end loop;
  if v_add = '{}'::jsonb then return jsonb_build_object('ok', false, 'error', 'nothing_to_add', 'missing', v_missing, 'kept_missing', v_kept); end if;

  -- The row's own trigger (trg_rfq_complete) re-runs the hold check on this write: every answer, Arabic included,
  -- counts as answered. Budget and emirate are the request's own columns; every other answer is a spec under its key.
  update public.inquiries
     set spec = case when jsonb_typeof(spec) = 'object' then spec else '{}'::jsonb end || (v_add - 'budget' - 'emirate'),
         budget = coalesce(v_add->>'budget', budget),
         emirate = coalesce(v_add->>'emirate', emirate)
   where id = i.id returning * into v_after;

  v_head := case when p_source = 'email_reply' then 'The customer replied with the details this trade needs:' else 'The customer added the details this trade needs:' end;

  if v_held <> '' then
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answer_as_written, english_held_at, answered_at, source)
    values (i.id, null, 'note', null, v_head || chr(10) || v_held, now(), now(), 'missing_specs')
    returning id into v_held_note;
    -- The same request _shared/supplier_english.ts holdForEnglish files (englishQuestion), filed here so the note
    -- and its English can never be separated.
    v_q := 'Translate this message from a customer into clear, professional English for the suppliers quoting the job, '
        || 'as a UAE sales engineer would write it. Keep every measurement, quantity, brand, model and grade code exactly as written. '
        || 'Add nothing and leave nothing out. Put ONLY the English text in "answer".' || chr(10) || chr(10) || v_head || chr(10) || v_held;
    perform public.fn_reason_hold('sales_engineer', 'sales_engineer.supplier_english', left(v_q, 8000),
      jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.supplier_english', 'question', v_q,
        'context', jsonb_build_object('audience', 'internal', 'language', 'en'), 'research', false,
        'subject', jsonb_build_object('clarification_id', v_held_note), 'dedupeKey', 'supplier_english:' || v_held_note),
      '{}'::jsonb, jsonb_build_object('clarification_id', v_held_note), 'filed_from_a_request_path', 'supplier_english:' || v_held_note);
  end if;

  if v_lines <> '' then
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
    values (i.id, null, 'note', v_head || chr(10) || v_lines, now(), 'missing_specs')
    returning id into v_note;

    -- Every supplier already invited is told, through customer_support's door (suppliers are written in English).
    for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email
               from public.inquiry_matches x join public.leads le on le.id = x.supplier_id
              where x.inquiry_id = i.id and not coalesce(le.banned, false)
                and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
      v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'rfq_addendum', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
        'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', i.id, 'lang', 'en',
        'subject', 'The customer added detail to a request you were invited to quote',
        'body', 'The customer added this to the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
                || ' you were invited to quote:' || chr(10) || chr(10) || v_lines || chr(10) || chr(10)
                || 'It is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.',
        'dedupe_key', 'missing_specs:' || v_note || ':' || l.id)));
      v_told := v_told + 1;
    end loop;
  end if;

  v_missing := public.fn_inquiry_missing_specs(i.id, null);
  return jsonb_build_object('ok', true, 'added', (select jsonb_agg(k) from jsonb_object_keys(v_add) k),
    'ready', coalesce(v_after.rfq_ready, false), 'still_missing', v_missing->'missing',
    'reached_suppliers', (v_missing->>'reached_suppliers')::boolean, 'suppliers_told', v_told, 'note_id', v_note,
    'held_for_english', v_held_note is not null, 'held_note_id', v_held_note, 'kept_missing', v_kept);
end $function$;

create or replace function public.scrub_inquiry_contacts()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare changed boolean := false; v_name text; v_spec jsonb;
begin
  new.summary_masked      := public.mask_project_identity(public.mask_contacts(new.summary));
  new.raw_input_masked    := public.mask_project_identity(public.mask_contacts(new.raw_input));
  new.budget_masked       := public.mask_project_identity(public.mask_contacts(new.budget));
  v_spec                  := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.spec));
  -- Suppliers read English only (ledger 993): a spec value in Arabic script never reaches the supplier copy. Its
  -- English reaches them on the held note (fn_inquiry_add_missing_specs, surface sales_engineer.supplier_english).
  new.spec_masked         := case when jsonb_typeof(v_spec) = 'object'
                               then coalesce((select jsonb_object_agg(s.key, s.value) from jsonb_each(v_spec) s
                                               where s.value::text !~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]'), '{}'::jsonb)
                               else v_spec end;
  new.boq_masked          := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.boq));
  new.completeness_masked := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.completeness));

  if new.customer_id is not null then
    begin
      select nullif(btrim(c.full_name), '') into v_name from public.customers c where c.id = new.customer_id;
    exception when others then v_name := null; end;
    if v_name is not null then
      new.summary_masked   := public.mask_name(new.summary_masked, v_name);
      new.raw_input_masked := public.mask_name(new.raw_input_masked, v_name);
      new.budget_masked    := public.mask_name(new.budget_masked, v_name);
    end if;
  end if;

  -- The alert is about contacts and project identity; dropping an Arabic value is not a masking event.
  changed := (new.summary_masked is distinct from new.summary)
          or (new.raw_input_masked is distinct from new.raw_input)
          or (new.budget_masked is distinct from new.budget)
          or (v_spec is distinct from new.spec)
          or (new.boq_masked is distinct from new.boq)
          or (new.completeness_masked is distinct from new.completeness);
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'inquiry_contact_masked',
        'Masked customer contact details and/or project identity (consultant, client, building, '
        || 'location, plot, drawing numbers) in the supplier-facing copy of inquiry '
        || coalesce(new.id::text, '?') || ' from customer ' || coalesce(new.customer_id::text, '?') || '.',
        'system');
    exception when others then null; end;
  end if;
  return new;
end $function$;

select case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'fn_inquiry_add_missing_specs' and p.prosrc like '%supplier_english:%') = 1
             and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'scrub_inquiry_contacts' and p.prosrc like '%v_spec%') = 1
            then 'PROBE OK' else 'PROBE FAILED: the Arabic spec answer is not held for its English' end as verdict;
