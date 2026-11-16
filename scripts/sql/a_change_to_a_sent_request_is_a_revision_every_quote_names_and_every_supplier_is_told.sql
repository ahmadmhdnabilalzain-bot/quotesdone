-- A CHANGE TO A SENT REQUEST IS A REVISION: THE RECORD IS REVISED, EVERY QUOTE NAMES THE REVISION IT PRICED, AND EVERY
-- SUPPLIER IS TOLD WHAT CHANGED.
-- Seat: sales_engineer. Agent: CUSTOMER_W2 (wave 2 of the real-company hole hunt, 16 Nov 2026; founder ledgers 1711-1713;
-- scratchpad holes/CUSTOMER.md item 5).
--
-- MEASURED on origin/main 27969740b and production (SELECT, 16 Nov 2026; fn_edit_inquiry md5 a31758e75da2e5220699f2e8fc7f620d
-- on production equals the canonical body in a_closed_request_is_not_cancelled_edited_or_completed_again_..., the body this
-- file starts from):
--   * fn_edit_inquiry refused every edit later than created_at + 1 hour ("Please create a new request for changes after that").
--   * required_by was editable nowhere, while customer_api/repeat.ts tells a customer who wants another date to edit the request.
--   * After the hour, the portal note (customer_api rfq_note) and WhatsApp (fn_inquiry_change_from_customer) wrote only an
--     rfq_clarification note: inquiries.budget, required_by and emirate kept the old values, no quote was marked, and every later
--     reader (the comparison, the deadline sweeps, fn_customer_inquiry_facts) used the old record. Inside the hour the same budget
--     change staled every quote. Two opposite effects from one intent.
--   * No quote said which version of the request it priced.
--
-- WHAT THIS CHANGES
--   1. inquiries.revision (1 at posting) and quotes.priced_revision. A quote takes the request's revision when it is written and
--      again whenever it is submitted (a02_quote_names_the_revision_it_priced); a staled quote that is submitted again answers
--      the current revision, so its stale mark is cleared at that moment (until now it stayed set and fn_customer_inquiry_facts
--      left a re-submitted quote out for good). No backfill: a null priced_revision reads as revision 1 (a write to quotes fires
--      the quality gate, the version trail and the hash triggers, so nothing here rewrites old quotes).
--   2. fn_edit_inquiry: the one-hour clock is gone (a request is editable until it is revealed, paid or closed, the list it
--      already had). required_by is editable. Any change that differs from the record makes a new revision, recorded in
--      public.inquiry_revision with each field's old and new value. A material change (spec, boq, budget, scope, emirate,
--      trades, and now the needed-by date) stales the live quotes exactly as before; every supplier with a live quote is told
--      WHAT changed (field: old -> new) and that the change is revision N; a description-only change asks the quoting suppliers to
--      confirm their quote still stands. Suppliers invited who have not quoted are told the request changed. A change the
--      customer made by message (not on the edit form) is confirmed to him in his language with what was recorded.
--   3. THE SALES ENGINEER'S MODEL TURNS A MESSAGE INTO A REVISION. Every customer note on a sent request (portal rfq_note and the
--      WhatsApp change, both stored as rfq_clarification source rfq_note) files one reasoning question,
--      sales_engineer.request_revision: the model reads the message against the current record and decides 'revise' or
--      'addendum_only', and for 'revise' writes the new budget, needed-by date, emirate or description (its own writing, so
--      authored fields). fn_reason_apply_sales_engineer__request_revision checks only what must be exact (a real future date,
--      one of the seven emirates, English digits for a budget suppliers read) and applies the revision through fn_edit_inquiry.
--      Code never decides what a message means. A fixture's note files nothing (fn_reason_hold).
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Probe: a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told_probe.sql (local Postgres 16).
-- Pending until the release applies it: scripts/sql/pending/<this file>.txt
-- Deploy order: apply this file, then deploy customer_api (the edit form's date and the "editable" flag read it).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. THE REVISION OF A REQUEST, AND THE REVISION EACH QUOTE PRICED
alter table public.inquiries add column if not exists revision integer not null default 1;
alter table public.quotes add column if not exists priced_revision integer;
comment on column public.inquiries.revision is
  'The request''s revision: 1 at posting, +1 for every change the customer makes after (fn_edit_inquiry, inquiry_revision). Sales engineer, 16 Nov 2026.';
comment on column public.quotes.priced_revision is
  'The request revision this quote priced (inquiries.revision when it was written or last submitted); null reads as 1. Sales engineer, 16 Nov 2026.';

create table if not exists public.inquiry_revision (
  id bigint generated always as identity primary key,
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  revision integer not null,
  changes jsonb not null,
  change_en text,
  source text not null check (source in ('portal_edit', 'sales_engineer')),
  note_id bigint,
  held_id bigint,
  quotes_staled integer not null default 0,
  suppliers_told integer not null default 0,
  customer_told boolean not null default false,
  created_at timestamptz not null default now(),
  unique (inquiry_id, revision)
);
comment on table public.inquiry_revision is
  'One row per revision of a request after posting: each changed field with its old and new value, who made it (the edit form, or the sales engineer from a customer message), and how many quotes went back and suppliers were told. Sales engineer, 16 Nov 2026.';
alter table public.inquiry_revision enable row level security;
drop policy if exists inquiry_revision_service_role_only on public.inquiry_revision;
create policy inquiry_revision_service_role_only on public.inquiry_revision as permissive for all to public using (false) with check (false);
revoke all on public.inquiry_revision from anon, authenticated;

create or replace function public.fn_quote_names_the_revision_it_priced()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_op = 'INSERT'
     or (coalesce(new.status, '') = 'submitted' and coalesce(old.status, '') <> 'submitted')
     or (coalesce(new.status, '') = 'submitted' and new.quote_amount is distinct from old.quote_amount) then
    select i.revision into new.priced_revision from public.inquiries i where i.id = new.inquiry_id;
    -- submitted again after a revision staled it: it now answers the current revision
    if tg_op = 'UPDATE' and coalesce(new.status, '') = 'submitted' and new.stale_at is not null and old.stale_at is not null then
      new.stale_at := null;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_quote_names_the_revision_it_priced() from public, anon, authenticated;
drop trigger if exists a02_quote_names_the_revision_it_priced on public.quotes;
create trigger a02_quote_names_the_revision_it_priced before insert or update of status, quote_amount on public.quotes
  for each row execute function public.fn_quote_names_the_revision_it_priced();

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. fn_edit_inquiry: no one-hour clock, the date is editable, every change is a revision and every supplier is told what
create or replace function public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v inquiries%rowtype; v_paid boolean;
  v_material boolean := false; v_reason text; v_stale int := 0; v_notified int := 0; v_told int := 0;
  v_cust_email text; v_cust_locale text; v_ar boolean;
  v_req date; v_changes jsonb := '{}'::jsonb; v_rev int; v_lines text := ''; v_lines_ar text := '';
  v_source text := case when p_patch->>'_source' = 'sales_engineer' then 'sales_engineer' else 'portal_edit' end;
  v_change_en text := nullif(btrim(left(coalesce(p_patch->>'_change_en', ''), 600)), '');
  sp record; v_d jsonb; v_cust_told boolean := false; v_body text;
begin
  select * into v from inquiries where id=p_inquiry for update;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  -- 10 Nov 2026: expired and lost are ends too (one list with _shared/request_closed.ts)
  if v_paid or v.status in ('revealed','completed','cancelled','closed','expired','lost') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  -- 16 Nov 2026: NO ONE-HOUR CLOCK. A request is revised until it is revealed, paid or closed (the list above).

  if p_patch ? 'required_by' and nullif(btrim(coalesce(p_patch->>'required_by', '')), '') is not null then
    if (p_patch->>'required_by') !~ '^\d{4}-\d{2}-\d{2}$' then
      return jsonb_build_object('error','date_invalid','message','Choose the date the work is needed by.'); end if;
    begin v_req := (p_patch->>'required_by')::date;
    exception when others then return jsonb_build_object('error','date_invalid','message','Choose the date the work is needed by.'); end;
    if v_req < (now() at time zone 'Asia/Dubai')::date then
      return jsonb_build_object('error','date_in_past','message','The date the work is needed by cannot be in the past.'); end if;
  end if;

  -- WHAT CHANGED, field by field, while the old row is still in hand (old -> new). Only a real difference counts.
  if p_patch ? 'summary' and btrim(coalesce(p_patch->>'summary', '')) <> '' and btrim(p_patch->>'summary') is distinct from btrim(coalesce(v.summary, '')) then
    v_changes := v_changes || jsonb_build_object('summary', jsonb_build_object('from', v.summary, 'to', p_patch->>'summary')); end if;
  if p_patch ? 'budget' and (p_patch->>'budget') is distinct from v.budget and coalesce(p_patch->>'budget', '') <> '' then
    v_changes := v_changes || jsonb_build_object('budget', jsonb_build_object('from', v.budget, 'to', p_patch->>'budget')); end if;
  if p_patch ? 'emirate' and coalesce(p_patch->>'emirate', '') <> '' and (p_patch->>'emirate') is distinct from v.emirate then
    v_changes := v_changes || jsonb_build_object('emirate', jsonb_build_object('from', v.emirate, 'to', p_patch->>'emirate')); end if;
  if v_req is not null and v_req is distinct from v.required_by then
    v_changes := v_changes || jsonb_build_object('required_by', jsonb_build_object('from', v.required_by, 'to', v_req)); end if;
  if p_patch ? 'scope_type' and (p_patch->>'scope_type') is distinct from v.scope_type then
    v_changes := v_changes || jsonb_build_object('scope_type', jsonb_build_object('from', v.scope_type, 'to', p_patch->>'scope_type')); end if;
  if p_patch ? 'spec' and (p_patch->'spec') is distinct from v.spec then
    v_changes := v_changes || jsonb_build_object('spec', jsonb_build_object('changed', true)); end if;
  if p_patch ? 'boq' and (p_patch->'boq') is distinct from v.boq then
    v_changes := v_changes || jsonb_build_object('boq', jsonb_build_object('changed', true)); end if;
  if p_patch ? 'trades' and array(select jsonb_array_elements_text(p_patch->'trades')) is distinct from v.trades then
    v_changes := v_changes || jsonb_build_object('trades', jsonb_build_object('from', to_jsonb(v.trades), 'to', p_patch->'trades')); end if;

  if v_changes = '{}'::jsonb then
    return jsonb_build_object('ok', true, 'edited', false, 'revision', v.revision, 'material_change', false,
                              'quotes_staled', 0, 'suppliers_notified', 0, 'editable_until', null);
  end if;

  -- Material: the fields a price is computed from (11 Aug 2026), and since 16 Nov the date it is needed by. The description
  -- alone is not: a typo fixed must not send three quotes back; the quoting suppliers are asked to confirm instead.
  v_material := v_changes ?| array['spec', 'boq', 'budget', 'scope_type', 'emirate', 'trades', 'required_by'];
  v_rev := coalesce(v.revision, 1) + 1;

  update inquiries set
    summary   = coalesce(nullif(btrim(coalesce(p_patch->>'summary', '')), ''), summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(nullif(p_patch->>'budget', ''), budget),
    emirate   = coalesce(nullif(p_patch->>'emirate', ''), emirate),
    required_by = coalesce(v_req, required_by),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end,
    revision  = v_rev
    where id=p_inquiry;

  -- The change in words a supplier reads (English; suppliers see the budget, the emirate and the date, never the customer).
  v_lines := concat_ws(chr(10),
    -- the budget is his free text and this line reaches suppliers by e-mail, outside the supplier gate: his contacts and name come out
    case when v_changes ? 'budget' then '- Budget: ' || coalesce(public.fn_scrub_customer_identity(v_changes->'budget'->>'from', v.customer_id), 'not stated') || ' -> ' || public.fn_scrub_customer_identity(v_changes->'budget'->>'to', v.customer_id) end,
    case when v_changes ? 'required_by' then '- Needed by: ' || coalesce(to_char((v_changes->'required_by'->>'from')::date, 'DD Mon YYYY'), 'not stated') || ' -> ' || to_char((v_changes->'required_by'->>'to')::date, 'DD Mon YYYY') end,
    case when v_changes ? 'emirate' then '- Emirate: ' || coalesce(v_changes->'emirate'->>'from', 'not stated') || ' -> ' || (v_changes->'emirate'->>'to') end,
    case when v_changes ? 'summary' then '- The description of the work was updated (open the request to read it).' end,
    case when v_changes ?| array['spec', 'boq', 'trades', 'scope_type'] then '- The specification or items changed (open the request to read them).' end);
  v_lines_ar := concat_ws(chr(10),
    case when v_changes ? 'budget' then '- الميزانية: ' || public.fn_scrub_customer_identity(v_changes->'budget'->>'to', v.customer_id) end,
    case when v_changes ? 'required_by' then '- التاريخ المطلوب: ' || to_char((v_changes->'required_by'->>'to')::date, 'YYYY-MM-DD') end,
    case when v_changes ? 'emirate' then '- الإمارة: ' || (v_changes->'emirate'->>'to') end,
    case when v_changes ? 'summary' then '- وصف العمل' end);
  v_reason := 'The customer changed this request on ' || to_char(now() at time zone 'Asia/Dubai','DD Mon YYYY HH24:MI')
           || ' (Dubai), after this quote was submitted. It is now revision ' || v_rev || ' of the request.' || chr(10) || v_lines;

  if v_material then
    -- Stale the live quotes and tell each supplier what changed, in one statement so a quote can never be reverted
    -- without its supplier being told (11 Aug 2026). The quote keeps the revision it priced (priced_revision).
    with staled as (
      update quotes q
         set stale_at = now(), stale_reason = v_reason, status = 'draft'
       where q.inquiry_id = p_inquiry
         and q.stale_at is null
         and coalesce(q.status,'') in ('submitted','draft')
      returning q.id, q.supplier_id
    ),
    told as (
      insert into notifications(type, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      select 'quote_requirements_changed',
             coalesce(l.claimed_by, l.email), 'supplier', s.supplier_id, p_inquiry, s.id, 'email',
             'The customer changed this request (revision ' || v_rev || ') — please re-quote',
             'Hello ' || coalesce(l.company_name,'') || ',' || chr(10) || chr(10) ||
             'A customer has changed the requirements of a request you had already quoted, so your quote has been set back to draft and is no longer being shown to them.' || chr(10) || chr(10) ||
             'What changed (revision ' || v_rev || ' of request ' || coalesce(v.rfq_no::text, '') || '):' || chr(10) || v_lines || chr(10) ||
             coalesce(chr(10) || 'In the sales engineer''s words: ' || v_change_en || chr(10), '') || chr(10) ||
             'Please open the request in your supplier portal, review what changed, and submit an updated quote. Your original figures are still there — nothing has been deleted.' || chr(10) || chr(10) ||
             'QuotesDone',
             'queued'
        from staled s join leads l on l.id = s.supplier_id
       where coalesce(l.claimed_by, l.email) is not null
      returning 1
    )
    select (select count(*) from staled), (select count(*) from told) into v_stale, v_notified;
  end if;

  -- Every other invited supplier is told too: one who quoted (description only) confirms his quote still stands; one who has
  -- not quoted quotes the revised request. Through customer_support's door, once per revision and supplier.
  for sp in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email,
                  exists (select 1 from quotes q where q.inquiry_id = p_inquiry and q.supplier_id = le.id
                           and coalesce(q.status, '') = 'submitted' and q.stale_at is null) as quoted
             from inquiry_matches x join leads le on le.id = x.supplier_id
            where x.inquiry_id = p_inquiry and not coalesce(le.banned, false)
              and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%'
              and not exists (select 1 from quotes q2 where q2.inquiry_id = p_inquiry and q2.supplier_id = le.id and q2.stale_at >= now() - interval '1 minute') loop
    v_body := 'The customer changed the ' || coalesce(v.category, '') || coalesce(' job in ' || nullif(coalesce(nullif(p_patch->>'emirate', ''), v.emirate), ''), ' job')
           || ' (request ' || coalesce(v.rfq_no::text, '') || '). It is now revision ' || v_rev || '.' || chr(10) || chr(10)
           || 'What changed:' || chr(10) || v_lines || chr(10)
           || coalesce(chr(10) || 'In the sales engineer''s words: ' || v_change_en || chr(10), '') || chr(10)
           || case when sp.quoted then 'You have already quoted: please confirm your quote still stands for revision ' || v_rev || ', or revise it, in your QuotesDone supplier portal.'
                   else 'Please quote the revised request in your QuotesDone supplier portal.' end;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_addendum', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', sp.to_email,
      'to_role', 'supplier', 'lead_id', sp.id, 'inquiry_id', p_inquiry, 'lang', 'en',
      'subject', 'The customer changed a request you were invited to quote (revision ' || v_rev || ')', 'body', v_body,
      'dedupe_key', 'request_revision:' || p_inquiry || ':' || v_rev || ':' || sp.id)));
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'needs_review') then v_told := v_told + 1; end if;
  end loop;

  select email, locale into v_cust_email, v_cust_locale from customers where id = v.customer_id;
  v_ar := coalesce(v.lang, v_cust_locale) = 'ar';
  if v_cust_email is not null and position('@' in v_cust_email) > 1 and (v_stale > 0 or v_source = 'sales_engineer') then
    -- The customer knows what his change did: his quotes went back for fresh prices, and (a change sent by message, which he
    -- did not see recorded on a form) what the record now says. In the request's language.
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'inquiry_edit_staled_quotes', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_cust_email,
      'to_role', 'customer', 'inquiry_id', p_inquiry, 'lang', case when v_ar then 'ar' else 'en' end,
      'subject', case when v_ar then 'حدّثنا طلبكم رقم ' || coalesce(v.rfq_no::text, '') else 'Your request ' || coalesce(v.rfq_no::text, '') || ' is updated' end,
      'body', case when v_ar
        then 'حدّثنا طلبكم رقم ' || coalesce(v.rfq_no::text, '') || ' بالتغيير الذي أرسلتموه، وهو الآن النسخة ' || v_rev || ':' || chr(10) || v_lines_ar || chr(10) || chr(10)
             || case when v_stale > 0 then 'أعدنا ' || v_stale || ' من العروض المقدَّمة إلى أصحابها ليسعّروا الطلب المعدَّل، وستظهر الأسعار الجديدة عند وصولها.'
                     else 'وأبلغنا المورّدين المدعوّين بالتغيير.' end
             || chr(10) || chr(10) || 'QuotesDone'
        else 'We have updated your request ' || coalesce(v.rfq_no::text, '') || ' with your change. It is now revision ' || v_rev || ':' || chr(10) || v_lines || chr(10) || chr(10)
             || case when v_stale > 0 then 'The ' || v_stale || ' quote(s) already submitted no longer match it, so we have asked those suppliers to re-quote. The new prices will appear as they arrive; you do not need to do anything.'
                     else 'The invited suppliers have been told.' end
             || chr(10) || chr(10) || 'QuotesDone' end,
      'dedupe_key', 'request_revision_customer:' || p_inquiry || ':' || v_rev)));
    v_cust_told := coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'needs_review');
  end if;

  if v_stale > 0 then
    -- THE SALES ENGINEER OWNS AN RFQ WHOSE QUOTES WENT BACK (CP-04).
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer','requote_required','needs_review','medium',
            'Requirements changed after ' || v_stale || ' quote(s) were submitted (revision ' || v_rev || ')',
            'Watch that the invited suppliers actually re-quote. If they do not, the customer is left with a request that had prices and now has none.',
            jsonb_build_object('inquiry_id', p_inquiry, 'quotes_staled', v_stale, 'revision', v_rev, 'changes', v_changes,
                               'suppliers_notified', v_notified, 'changed_at', now()),
            'inquiries', p_inquiry::text);
  end if;

  insert into inquiry_revision (inquiry_id, revision, changes, change_en, source, note_id, held_id, quotes_staled, suppliers_told, customer_told)
  values (p_inquiry, v_rev, v_changes, v_change_en, v_source,
          case when (p_patch->>'_note_id') ~ '^\d+$' then (p_patch->>'_note_id')::bigint end,
          case when (p_patch->>'_held_id') ~ '^\d+$' then (p_patch->>'_held_id')::bigint end,
          v_stale, v_notified + v_told, v_cust_told);

  return jsonb_build_object('ok',true,'edited',true,'editable_until',null, 'revision', v_rev, 'changes', v_changes,
                            'material_change', v_material,
                            'quotes_staled', v_stale,
                            'suppliers_notified', v_notified + v_told,
                            'customer_told', v_cust_told);
end $function$;
revoke execute on function public.fn_edit_inquiry(uuid, uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. A CUSTOMER'S MESSAGE ON A SENT REQUEST IS READ BY THE SALES ENGINEER'S MODEL AGAINST THE RECORD
create or replace function public.fn_sales_engineer_reads_a_change(p_note bigint)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.rfq_clarification; i public.inquiries; v_text text; v_q text; v_today date := (now() at time zone 'Asia/Dubai')::date;
        v_subject jsonb;
begin
  select * into r from public.rfq_clarification where id = p_note;
  if not found or r.kind <> 'note' or r.source <> 'rfq_note' then return null; end if;
  select * into i from public.inquiries where id = r.inquiry_id;
  if not found or coalesce(i.status, '') in ('revealed', 'completed', 'cancelled', 'closed', 'expired', 'lost') then return null; end if;
  v_text := left(btrim(coalesce(r.answer_as_written, r.answer, '')), 1500);
  if v_text = '' then return null; end if;
  -- a demo customer's note is test traffic: fn_reason_hold files nothing for a fixture subject, so nothing is ever paid for
  v_subject := jsonb_build_object('inquiry_id', i.id, 'clarification_id', r.id, 'customer_id', i.customer_id)
            || case when exists (select 1 from public.customers c where c.id = i.customer_id and c.is_demo) then '{"fixture": true}'::jsonb else '{}'::jsonb end;
  v_q := 'A customer sent this message about his request AFTER it went out to suppliers. As the sales engineer, read it against the '
      || 'current request and decide whether it CHANGES the record (the budget, the date the work is needed by, the emirate, or the '
      || 'description of the work such as rooms, quantities or items) or only adds detail, asks something, or repeats what the request '
      || 'already says. For "revise", write the NEW values only for what he changed. Today is ' || to_char(v_today, 'YYYY-MM-DD') || ' (Dubai).'
      || chr(10) || chr(10) || 'CURRENT REQUEST (revision ' || coalesce(i.revision, 1) || '):' || chr(10)
      || 'Trade: ' || coalesce(i.category, 'not stated') || chr(10)
      || 'Description: ' || coalesce(left(i.summary, 800), 'not stated') || chr(10)
      || 'Budget: ' || coalesce(nullif(btrim(i.budget), ''), 'not stated') || chr(10)
      || 'Needed by: ' || coalesce(to_char(i.required_by, 'YYYY-MM-DD'), 'not stated')
      || coalesce(' (he said: ' || nullif(btrim(i.delivery_window), '') || ')', '') || chr(10)
      || 'Emirate: ' || coalesce(i.emirate, 'not stated') || chr(10) || chr(10)
      || 'HIS MESSAGE:' || chr(10) || v_text;
  return public.fn_reason_hold('sales_engineer', 'sales_engineer.request_revision', left(v_q, 8000),
    jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.request_revision', 'question', v_q, 'research', false,
      'context', jsonb_build_object('audience', 'internal', 'language', 'en'),
      'decision', jsonb_build_object('name', 'request_revision', 'authored', true,
        'options', jsonb_build_array(
          jsonb_build_object('id', 'revise', 'meaning', 'The message changes one or more of: the budget, the date the work is needed by, the emirate, the description of the work.'),
          jsonb_build_object('id', 'addendum_only', 'meaning', 'The message adds detail, asks a question, or repeats what the request already says; the record stays as it is.')),
        'fields', jsonb_build_array(
          jsonb_build_object('key', 'budget', 'question', 'Only if he changed the budget: the new budget in English with digits, as he now states it (for example "AED 30,000" or "around AED 7,000").'),
          jsonb_build_object('key', 'required_by', 'question', 'Only if he changed when the work is needed: the new date as YYYY-MM-DD, worked out from today''s date.'),
          jsonb_build_object('key', 'emirate', 'question', 'Only if he moved the job: one of Abu Dhabi, Dubai, Sharjah, Ajman, Umm Al Quwain, Ras Al Khaimah, Fujairah.'),
          jsonb_build_object('key', 'summary', 'question', 'Only if the work itself changed: the full new description in English, one paragraph, naming no person, phone, e-mail, villa or building.'),
          jsonb_build_object('key', 'change_en', 'question', 'For "revise": one or two plain English sentences for the suppliers saying what changed, naming no person, phone, e-mail or address.'))),
      'subject', v_subject, 'dedupeKey', 'request_revision:' || r.id),
    '{}'::jsonb, v_subject,
    'a_customer_message_on_a_sent_request', 'request_revision:' || r.id);
end $fn$;
revoke execute on function public.fn_sales_engineer_reads_a_change(bigint) from public, anon, authenticated;

create or replace function public.fn_rfq_note_is_read_for_a_revision()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.kind = 'note' and new.source = 'rfq_note' then
    perform public.fn_sales_engineer_reads_a_change(new.id);
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_rfq_note_is_read_for_a_revision() from public, anon, authenticated;
drop trigger if exists z10_a_customer_note_is_read_for_a_revision on public.rfq_clarification;
create trigger z10_a_customer_note_is_read_for_a_revision after insert on public.rfq_clarification
  for each row execute function public.fn_rfq_note_is_read_for_a_revision();

-- The model's reading, applied: code checks only what must be exact, then fn_edit_inquiry makes the revision.
create or replace function public.fn_reason_apply_sales_engineer__request_revision(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; f jsonb := coalesce(p_result->'decision'->'fields', '{}'::jsonb);
        i public.inquiries; v_patch jsonb := '{}'::jsonb; v_val text; v_date date; v_em text; v_res jsonb; v_dropped jsonb := '[]'::jsonb;
        v_cust uuid;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if v_choice is null or v_choice not in ('revise', 'addendum_only') then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  if v_choice = 'addendum_only' then
    return jsonb_build_object('applied', true, 'revised', false, 'reading', 'addendum_only');
  end if;
  select * into i from public.inquiries where id::text = h.subject->>'inquiry_id';
  if not found then return jsonb_build_object('applied', true, 'revised', false, 'why', 'the request is gone'); end if;
  v_cust := i.customer_id;

  v_val := nullif(btrim(left(coalesce(f->'budget'->>'value', ''), 80)), '');
  if v_val is not null then
    v_val := translate(v_val, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
    -- suppliers read the budget as written and read English only (fn_inquiry_add_missing_specs keeps the same rule)
    if v_val ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' or v_val !~ '[0-9]' then v_dropped := v_dropped || '["budget"]'::jsonb;
    else v_patch := v_patch || jsonb_build_object('budget', v_val); end if;
  end if;
  v_val := nullif(btrim(coalesce(f->'required_by'->>'value', '')), '');
  if v_val is not null then
    begin v_date := case when v_val ~ '^\d{4}-\d{2}-\d{2}$' then v_val::date end; exception when others then v_date := null; end;
    if v_date is null or v_date < (now() at time zone 'Asia/Dubai')::date or v_date > (now() at time zone 'Asia/Dubai')::date + 730 then
      v_dropped := v_dropped || '["required_by"]'::jsonb;
    else v_patch := v_patch || jsonb_build_object('required_by', to_char(v_date, 'YYYY-MM-DD')); end if;
  end if;
  v_val := lower(regexp_replace(btrim(coalesce(f->'emirate'->>'value', '')), '\s+', ' ', 'g'));
  if v_val <> '' then
    select e into v_em from unnest(array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah']) e
     where lower(e) = v_val;
    if v_em is null then v_dropped := v_dropped || '["emirate"]'::jsonb; else v_patch := v_patch || jsonb_build_object('emirate', v_em); end if;
  end if;
  v_val := nullif(btrim(left(coalesce(f->'summary'->>'value', ''), 500)), '');
  if v_val is not null then
    -- the record is read by every supplier door: the customer's own contact details and name never go in
    v_patch := v_patch || jsonb_build_object('summary', public.fn_scrub_customer_identity(v_val, v_cust));
  end if;
  if v_patch = '{}'::jsonb then
    return jsonb_build_object('applied', true, 'revised', false, 'why', 'no field could be recorded', 'dropped', v_dropped);
  end if;
  v_patch := v_patch || jsonb_build_object('_source', 'sales_engineer', '_held_id', p_id::text,
    '_note_id', h.subject->>'clarification_id',
    '_change_en', public.fn_scrub_customer_identity(left(btrim(coalesce(f->'change_en'->>'value', '')), 600), v_cust));
  v_res := public.fn_edit_inquiry(i.id, v_cust, v_patch);
  return jsonb_build_object('applied', true, 'revised', coalesce((v_res->>'edited')::boolean, false), 'result', v_res, 'dropped', v_dropped);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__request_revision(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__request_revision(bigint, jsonb) to service_role;

select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'quotes' and column_name = 'priced_revision')
    then 'PROBE FAILED: quotes.priced_revision is missing'
  when position('interval ''1 hour''' in pg_get_functiondef('public.fn_edit_inquiry(uuid, uuid, jsonb)'::regprocedure)) > 0
    then 'PROBE FAILED: fn_edit_inquiry still has the one-hour clock'
  when has_function_privilege('anon', 'public.fn_reason_apply_sales_engineer__request_revision(bigint, jsonb)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_edit_inquiry(uuid, uuid, jsonb)', 'execute')
    then 'PROBE FAILED: a client can run the revision routines'
  else 'PROBE OK' end as verdict;
