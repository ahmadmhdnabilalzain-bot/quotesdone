-- A POST-QUOTE REQUIREMENTS CHANGE LEFT EVERY EXISTING QUOTE LIVE, AND ANSWERING THE OLD QUESTION.
--
-- Spec #7 L1351. The dress rehearsal of 11 Aug called this "the single largest build order the
-- rehearsal produced" and measured it: before=3 quotes, still-live=3. Re-read the function before
-- building anything, and the diagnosis holds exactly.
--
-- fn_edit_inquiry updates spec, boq, trades, budget, scope_type and emirate, and never looks at the
-- quotes table. Its three guards are about the CUSTOMER's right to edit, not about what the edit
-- does to work already done:
--
--   - refuses if a transaction exists (already paid)
--   - refuses if status is revealed/completed/cancelled/closed
--   - refuses more than 1 hour after the inquiry was created
--
-- None of those stops the case that matters. A supplier can submit a quote well inside that
-- one-hour window - the whole product promise is fast quoting - and the customer can then rewrite
-- the BOQ. The quote stays status='submitted', stays comparable, stays revealable, and is priced
-- against requirements that no longer exist. Nothing tells the supplier, nothing marks the quote,
-- nothing asks for a re-quote. The customer can pay to reveal a price for the wrong job.
--
-- WHAT COUNTS AS MATERIAL, STATED. spec, boq, trades, budget, scope_type, emirate - the fields a
-- price is computed FROM. Editing summary, raw_input or keywords is descriptive and does not
-- invalidate a price, so it deliberately does not stale anything: a customer fixing a typo must not
-- destroy three quotes.
--
-- WHY THE STATUS GOES BACK TO 'draft'. Marking stale_at alone is not enough - every existing query
-- that compares or reveals quotes filters on status, so a stale-but-submitted quote would still be
-- offered to the customer. Reverting it to 'draft' removes it from comparison AND is what "ask for
-- a re-quote" means in this data model: the supplier edits and submits again. Verified against the
-- triggers on quotes first: version_quote records the change as an audit trail (wanted), and
-- quote_committed_hash fires only on scope/notes/payment_terms/warranty/committed_items, none of
-- which this touches.

alter table public.quotes
  add column if not exists stale_at     timestamptz,
  add column if not exists stale_reason text;

create index if not exists quotes_stale_idx on public.quotes (inquiry_id) where stale_at is not null;

comment on column public.quotes.stale_at is
  'Set when the customer materially changed the inquiry this quote answers. The quote is reverted to draft at the same moment so it cannot be compared or revealed until the supplier re-submits. Added 11 Aug 2026 - before it, a rewritten BOQ left every existing quote live and priced against requirements that no longer existed.';

create or replace function public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v inquiries%rowtype; v_paid boolean; v_deadline timestamptz;
  v_material boolean := false; v_reason text; v_stale int := 0; v_notified int := 0;
  v_cust_email text; v_admin text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed','cancelled','closed') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  v_deadline := v.created_at + interval '1 hour';
  if now() > v_deadline then
    return jsonb_build_object('error','edit_window_closed','editable_until',v_deadline,
      'message','Inquiries can be edited within 1 hour of submitting. Please create a new request for changes after that.'); end if;

  -- Decide materiality BEFORE the update, while the old row is still in hand.
  v_material :=
       (p_patch ? 'spec'       and (p_patch->'spec')       is distinct from v.spec)
    or (p_patch ? 'boq'        and (p_patch->'boq')        is distinct from v.boq)
    or (p_patch ? 'budget'     and (p_patch->>'budget')    is distinct from v.budget)
    or (p_patch ? 'scope_type' and (p_patch->>'scope_type') is distinct from v.scope_type)
    or (p_patch ? 'emirate'    and (p_patch->>'emirate')   is distinct from v.emirate)
    or (p_patch ? 'trades'     and array(select jsonb_array_elements_text(p_patch->'trades')) is distinct from v.trades);

  update inquiries set
    summary   = coalesce(p_patch->>'summary', summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(p_patch->>'budget', budget),
    emirate   = coalesce(p_patch->>'emirate', emirate),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end
    where id=p_inquiry;

  if v_material then
    v_reason := 'The customer changed the requirements of this request on '
             || to_char(now() at time zone 'Asia/Dubai','DD Mon YYYY HH24:MI')
             || ' (Dubai), after this quote was submitted.';

    -- Stale the live quotes and tell each supplier, in one statement so a quote can never be
    -- reverted without its supplier being told.
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
             'The customer changed this request — please re-quote',
             'Hello ' || coalesce(l.company_name,'') || ',' || chr(10) || chr(10) ||
             'A customer has changed the requirements of a request you had already quoted, so your quote has been set back to draft and is no longer being shown to them.' || chr(10) || chr(10) ||
             v_reason || chr(10) || chr(10) ||
             'Please open the request in your supplier portal, review what changed, and submit an updated quote. Your original figures are still there — nothing has been deleted.' || chr(10) || chr(10) ||
             'QuotesDone',
             'queued'
        from staled s join leads l on l.id = s.supplier_id
       where coalesce(l.claimed_by, l.email) is not null
      returning 1
    )
    select (select count(*) from staled), (select count(*) from told) into v_stale, v_notified;

    if v_stale > 0 then
      select email into v_cust_email from customers where id = v.customer_id;
      v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                          'management@quotesdone.com');

      -- The customer must know their edit cost them their quotes, or they will wait for prices
      -- that are never coming back on their own.
      if v_cust_email is not null then
        insert into notifications(type, to_email, to_role, inquiry_id, channel, subject, body, status)
        values ('inquiry_edit_staled_quotes', v_cust_email, 'customer', p_inquiry, 'email',
                'Your change means we have asked for fresh prices',
                'Hello,' || chr(10) || chr(10) ||
                'You changed the requirements on your request, so the ' || v_stale ||
                ' quote(s) already submitted no longer match what you are asking for. We have asked those suppliers to re-quote against your updated requirements.' || chr(10) || chr(10) ||
                'You do not need to do anything — the new prices will appear as they arrive.' || chr(10) || chr(10) ||
                'QuotesDone', 'queued');
      end if;

      insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('procurement','requote_required','needs_review','medium',
              'Requirements changed after ' || v_stale || ' quote(s) were submitted',
              'Watch that the invited suppliers actually re-quote. If they do not, the customer is left with a request that had prices and now has none.',
              jsonb_build_object('inquiry_id', p_inquiry, 'quotes_staled', v_stale,
                                 'suppliers_notified', v_notified, 'changed_at', now()),
              'inquiries', p_inquiry::text);
    end if;
  end if;

  return jsonb_build_object('ok',true,'edited',true,'editable_until',v_deadline,
                            'material_change', v_material,
                            'quotes_staled', v_stale,
                            'suppliers_notified', v_notified);
end $function$;
