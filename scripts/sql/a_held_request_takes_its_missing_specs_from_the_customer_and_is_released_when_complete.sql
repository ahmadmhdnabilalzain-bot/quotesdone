-- A HELD REQUEST TAKES ITS MISSING SPECS FROM THE CUSTOMER, AND IS RELEASED WHEN COMPLETE (29 Sep 2026).
-- Seat: customer_support. Follow-up to the first-inquiry concierge (founder ledger 1018): "customers can't fix a
-- request held for specs themselves".
--
-- WHAT WAS MEASURED (29 Sep 2026, production htdblwldjkcgjvmqkbeh, read-only):
--   * A request is held for its specs when fn_rfq_required_check(inquiries) finds a required field of its
--     category (category_specs.fields, required = true) with no answer. It reads answers from inquiries.spec by
--     KEY (plus the emirate, scope, budget, trades and drawing columns), and trg_rfq_complete (BEFORE INSERT OR
--     UPDATE) turns that into inquiries.rfq_ready and completeness on every write of the row.
--   * All 3 inquiries on production read rfq_ready false, each missing one required field ('work' twice,
--     'surface_prep' once) that the customer was never asked for again.
--   * The customer could not supply it: customer_api edit_inquiry writes summary, budget and emirate only; an
--     rfq_note is free text in rfq_clarification that no check reads, so the request stayed held for ever.
--   * Nothing at runtime dispatches on the rfq_ready transition any more (trg_autodispatch_inquiry and
--     dispatch_inquiry are gone): customer_api create_inquiry offers every request to the sales engineer's
--     matcher when it is posted.
--
-- WHAT THIS ADDS
--   1. fn_inquiry_missing_specs(inquiry, lang): the request's missing required specs, LIVE (fn_rfq_required_check,
--      not the stored completeness), one per field, each with the intake's own plain question in the customer's
--      language and the field's options.
--   2. fn_inquiry_add_missing_specs(inquiry, customer, answers, source): the ONE door both ways in:
--        'customer_portal' - the customer, on the held request (customer_api add_missing_specs);
--        'email_reply'     - customer_support, recording what the customer replied to the held-for-specs e-mail.
--      It takes only keys that are missing now, each a real answer (_rfq_answered, at most 300 characters),
--      writes them into inquiries.spec under the key the check reads, and the row's own trigger re-runs the hold
--      check. The answers are recorded as a born-answered note in rfq_clarification (source 'missing_specs'),
--      which the matched suppliers read with the request, and each matched supplier is told through
--      customer_support's delivery door. It answers ready / still missing / whether any supplier has the request.
--      Released: rfq_ready is true. A request that reached no supplier yet is offered to the matcher again by
--      customer_api when the customer completes it in the portal.
--   3. rfq_clarification.source accepts 'missing_specs'.
--
-- WHAT THIS DOES NOT DO: it does not change the hold rule, the category fields or the matcher; it does not stale
-- quotes already submitted (suppliers are told what was added and may revise); it parses no e-mail - on the
-- e-mail path customer_support supplies the keyed answers it read.
--
--   node scripts/apply_sql.mjs scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql --apply --ddl
--   proved before apply by the _probe.sql beside it, in one rolled-back transaction with this file.

set local lock_timeout = '5s';

-- ── 3. the note's source ─────────────────────────────────────────────────────────────────────────────
do $src$
declare c text;
begin
  select conname into c from pg_constraint
   where conrelid = 'public.rfq_clarification'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%source = ANY%';
  if c is not null then execute format('alter table public.rfq_clarification drop constraint %I', c); end if;
end $src$;
alter table public.rfq_clarification add constraint rfq_clarification_source_check
  check (source in ('portal', 'rfq_flag', 'rfq_note', 'missing_specs'));

-- ── 1. what is missing, live ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_inquiry_missing_specs(p_inquiry uuid, p_lang text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; v_ar boolean; v_chk jsonb; v_fields jsonb; v_missing jsonb := '[]'::jsonb; m jsonb; f jsonb;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('held', false, 'reason', 'no such request'); end if;
  v_ar := coalesce(case when p_lang in ('en', 'ar') then p_lang end, public.fn_inquiry_locale(i.id),
                   (select c.locale from public.customers c where c.id = i.customer_id)) = 'ar';
  -- A combined (split) request's specs belong to its per-trade parts, each checked and completed on its own; the
  -- parent carries none (the concierge re-review of #1112 judges a parent by its children the same way).
  if exists (select 1 from public.inquiries c where c.parent_inquiry_id = i.id) then
    return jsonb_build_object('held', false, 'lang', case when v_ar then 'ar' else 'en' end, 'missing', '[]'::jsonb,
                              'reason', 'a combined request: each trade is completed on its own part');
  end if;
  v_chk := public.fn_rfq_required_check(i);
  select cs.fields into v_fields from public.category_specs cs where lower(cs.category) = lower(coalesce(i.category, '')) limit 1;
  for m in select value from jsonb_array_elements(coalesce(v_chk->'missing', '[]'::jsonb)) loop
    f := null;
    select value into f from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) where lower(value->>'key') = m->>'key' limit 1;
    v_missing := v_missing || jsonb_build_array(jsonb_build_object(
      'key', m->>'key',
      'ask', coalesce(nullif(f->>case when v_ar then 'question_plain_ar' else 'question_plain_en' end, ''), nullif(m->>'question', ''), m->>'key'),
      'type', coalesce(f->>'type', m->>'type', 'text'),
      'options', coalesce(f->'options', '[]'::jsonb)));
  end loop;
  -- The general score also holds a request below its bar (fn_rfq_score: generic_ready). Of its parts, the two a
  -- customer can state in a field are asked too, so completing the page can release the request.
  if not coalesce((public.fn_rfq_score(i)->>'generic_ready')::boolean, true) then
    if i.budget is null then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', 'budget', 'type', 'text', 'options', '[]'::jsonb,
        'ask', case when v_ar then 'الميزانية المرصودة للعمل (يكفي نطاق تقريبي).' else 'Your budget for the work (a range is fine).' end));
    end if;
    if coalesce(i.emirate, '') = '' then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('key', 'emirate', 'type', 'text', 'options', '[]'::jsonb,
        'ask', case when v_ar then 'في أي إمارة ومنطقة سيُنفَّذ العمل؟' else 'Which emirate and area is the work in?' end));
    end if;
  end if;
  return jsonb_build_object(
    'held', coalesce(i.status, '') not in ('cancelled', 'closed', 'completed') and jsonb_array_length(v_missing) > 0,
    'lang', case when v_ar then 'ar' else 'en' end, 'ready', coalesce(i.rfq_ready, false), 'missing', v_missing,
    'reached_suppliers', exists (select 1 from public.inquiry_matches x where x.inquiry_id = i.id));
end $fn$;
revoke execute on function public.fn_inquiry_missing_specs(uuid, text) from public, anon, authenticated;
grant execute on function public.fn_inquiry_missing_specs(uuid, text) to service_role;

-- ── 2. the one door the answers come in by ────────────────────────────────────────────────────────────
create or replace function public.fn_inquiry_add_missing_specs(p_inquiry uuid, p_customer uuid, p_answers jsonb, p_source text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; v_missing jsonb; v_add jsonb := '{}'::jsonb; v_lines text := ''; e record; v_val text; v_ask text;
  v_note bigint; v_after public.inquiries; v_told int := 0; l record; v_res jsonb;
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
    v_add := v_add || jsonb_build_object(lower(btrim(e.key)), v_val);
    v_lines := v_lines || case when v_lines = '' then '' else chr(10) end || v_ask || ' ' || v_val;
  end loop;
  if v_add = '{}'::jsonb then return jsonb_build_object('ok', false, 'error', 'nothing_to_add', 'missing', v_missing); end if;

  -- The row's own trigger (trg_rfq_complete) re-runs the hold check on this write. Budget and emirate are the
  -- request's own columns; every other answer is a spec under its key.
  update public.inquiries
     set spec = case when jsonb_typeof(spec) = 'object' then spec else '{}'::jsonb end || (v_add - 'budget' - 'emirate'),
         budget = coalesce(v_add->>'budget', budget),
         emirate = coalesce(v_add->>'emirate', emirate)
   where id = i.id returning * into v_after;

  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
  values (i.id, null, 'note',
          case when p_source = 'email_reply' then 'The customer replied with the details this trade needs:' else 'The customer added the details this trade needs:' end
          || chr(10) || v_lines, now(), 'missing_specs')
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

  v_missing := public.fn_inquiry_missing_specs(i.id, null);
  return jsonb_build_object('ok', true, 'added', (select jsonb_agg(k) from jsonb_object_keys(v_add) k),
    'ready', coalesce(v_after.rfq_ready, false), 'still_missing', v_missing->'missing',
    'reached_suppliers', (v_missing->>'reached_suppliers')::boolean, 'suppliers_told', v_told, 'note_id', v_note);
end $fn$;
revoke execute on function public.fn_inquiry_add_missing_specs(uuid, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_inquiry_add_missing_specs(uuid, uuid, jsonb, text) to service_role;
