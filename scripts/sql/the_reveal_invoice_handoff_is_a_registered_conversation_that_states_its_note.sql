-- THE REVEAL INVOICE HANDOFF IS A REGISTERED CONVERSATION THAT STATES ITS NOTE, AND ITS RECEIVER CITES IT.
-- 27 Oct 2026. Seat: accountant (sender) -> sales_engineer (receiver; the customer's voice).
--
-- MEASURED 27 Oct 2026 (production, rolled-back replays only):
--   * fn_accountant_files_reveal_invoice (the_accountant_files_the_reveal_invoice_and_the_sales_engineer_tells_the_customer.sql)
--     inserts a raw agent_actions handoff to sales_engineer with detail {from:'accountant', subject:'reveal_invoice'}
--     and NO detail.type, and public.seat_handoff_kind has no row for it. The conversation is therefore
--     unregistered: its note says "no registered conversation", its deadline is the 24-hour default, and the
--     receiver (trg_sales_engineer_tells_customer_invoice_ready) closes it with a bare UPDATE - never through
--     fn_seat_handoff_complete - so the answer cites no note (founder ledger 1013): every such row is counted
--     by fn_handoff_citation_gaps as closed-with-a-note-but-uncited.
--   * Any error on that path (the note builder refusing, the notice insert failing) raised inside the AFTER
--     trigger of the doc_path update, so it would roll back the invoice being filed at all.
--   * A real attach (doc_path 'invoices/...' on a ZZ DEMO transaction) did NOT raise: the sender's 'from' lets
--     fn_handoff_summary state a decision. The refusal "handoff reveal_invoice on transactions#... cannot state
--     its context, decision, open asks and deadline" that scripts/checks/language_follows_registration.mjs
--     reports came from the CHECK's own hand-written handoff, which carried no 'from', so no decision could be
--     stated. That walk now drives the real door (it sets doc_path on a ZZ DEMO transaction) instead of
--     imitating the handoff, so it fails if the real door stops producing the notice.
--
-- WHAT THIS CHANGES
--   1. The conversation is registered: invoice.issued (the event's own name; a kind is dotted), accountant ->
--      sales_engineer, handler
--      fn_sales_engineer_answers_reveal_invoice(bigint), reply within 24 hours, the sales engineer closes it
--      (it is a notice to pass on, like refund.paid - nothing comes back for the accountant to re-verify).
--   2. The accountant's handoff states itself: type, from, to, subject_table/subject_id, its decision and its
--      ask. It is still filed directly, not through fn_seat_handoff, on purpose: the invoice of a demo
--      transaction is filed and its notice captured (the_reveal_invoice_is_the_accountants_and_reaches_the_
--      sales_engineer.test.mjs proves the whole path on a ZZ DEMO customer), and fn_seat_handoff files
--      nothing for demo work (ruling 1199) - routing through it would leave the sandbox unable to prove it.
--   3. The receiver answers through the one dispatcher, fn_seat_handoff_act, so its answer cites the note
--      and the close goes through fn_seat_handoff_complete. The notice itself is unchanged: same words, same
--      language choice (fn_customer_notice_locale: the inquiry's language, else the registered one).
--   4. A failure of the handoff or the notice is recorded on the handoff row, the handoff stream and an IT
--      finding - it never rolls back the invoice the accountant filed.
--
-- Prevented by: scripts/checks/the_reveal_invoice_handoff_states_its_note_and_is_cited.test.mjs
-- Pending: scripts/sql/pending/the_reveal_invoice_handoff_is_a_registered_conversation_that_states_its_note.txt

-- ── 1. THE CONVERSATION ──────────────────────────────────────────────────────────────────────────
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('invoice.issued', 'accountant', 'sales_engineer',
        'The Stripe reveal invoice is filed in the customer''s Documents and on the revealed quote: tell the customer it is ready, in their language.',
        'fn_sales_engineer_answers_reveal_invoice', interval '24 hours', false,
        'scripts/sql/the_reveal_invoice_handoff_is_a_registered_conversation_that_states_its_note.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 2. THE RECEIVER'S ANSWER (sales_engineer) ────────────────────────────────────────────────────
-- The body of the notice is the one fn_sales_engineer_tells_customer_invoice_ready wrote
-- (a_customer_hears_the_reveal_and_its_invoice_in_the_inquiry_language.sql), word for word.
create or replace function public.fn_sales_engineer_answers_reveal_invoice(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  a public.agent_actions;
  c record;
  v_ar boolean;
  v_nid bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'invoice.issued' then
    raise exception 'fn_sales_engineer_answers_reveal_invoice: % is not an invoice.issued handoff', p_id;
  end if;
  select id, email into c from public.customers where id = (a.detail->>'customer_id')::uuid;
  if c.email is null or c.email !~ '@' then
    return jsonb_build_object('told', false, 'reason', 'no email address on file for the customer');
  end if;
  v_ar := public.fn_customer_notice_locale((a.detail->>'inquiry_id')::uuid, c.id) = 'ar';
  insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
  values ('invoice_ready', c.email, 'customer',
          (a.detail->>'inquiry_id')::uuid, (a.detail->>'quote_id')::uuid,
          case when v_ar then 'فاتورتكم جاهزة' else 'Your invoice is ready' end,
          case when v_ar
            then 'أصبحت فاتورة رسوم الكشف التي سددتموها متاحة في حسابكم على QuotesDone، ويمكنكم فتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفتموه، أو من «المستندات» ضمن «الفواتير».'
            else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
          end,
          case when v_ar then 'ar' else 'en' end)
  returning id into v_nid;
  return jsonb_build_object('told', true, 'notification_id', v_nid, 'language', case when v_ar then 'ar' else 'en' end);
end
$fn$;

revoke execute on function public.fn_sales_engineer_answers_reveal_invoice(bigint) from public, anon, authenticated;

comment on function public.fn_sales_engineer_answers_reveal_invoice(bigint) is
  'Owner: sales_engineer. Handler of the invoice.issued conversation (seat_handoff_kind): queues the customer''s '
  '"your invoice is ready" notice in the inquiry''s language. Reached only through fn_seat_handoff_act.';

-- The trigger stays the receiver's door (it is how the handoff reaches the seat at once), and now only
-- dispatches: fn_seat_handoff_act runs the registered handler, cites the note and closes the handoff.
create or replace function public.fn_sales_engineer_tells_customer_invoice_ready()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.kind <> 'handoff' or new.detail->>'type' is distinct from 'invoice.issued' then return new; end if;
  -- A failed answer is recorded on the row and in the stream; it never rolls back the filed invoice.
  begin
    perform public.fn_seat_handoff_act(new.id);
  exception when others then
    update public.agent_actions
       set status = 'failed', decided_at = now(),
           detail = detail || jsonb_build_object('error', left(sqlerrm, 500))
     where id = new.id;
    perform public.fn_seat_handoff_event(new.id, 'failed');
  end;
  return new;
end
$fn$;

-- ── 3. THE SENDER STATES ITS HANDOFF (accountant) ────────────────────────────────────────────────
create or replace function public.fn_accountant_files_reveal_invoice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_doc bigint;
  v_h   bigint;
begin
  if new.doc_path is null or new.doc_path !~ '^invoices/' then return new; end if;
  if tg_op = 'UPDATE' and old.doc_path is not distinct from new.doc_path then return new; end if;

  -- (bucket, path) is UNIQUE, so a replayed attach files nothing twice and hands off nothing twice.
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, mime, status)
  values ('finance-docs', new.doc_path,
          coalesce(nullif(new.doc_name, ''), 'Invoice ' || coalesce(new.stripe_invoice_number, '') || '.pdf'),
          'invoice', 'inquiries', new.inquiry_id::text, 'application/pdf', 'done')
  on conflict (bucket, path) do nothing
  returning id into v_doc;
  if v_doc is null then return new; end if;

  perform public.fn_emit('invoice.issued', 'transaction', new.id::text, 'accountant',
    jsonb_build_object('document_id', v_doc, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                       'customer_id', new.customer_id, 'invoice_id', new.stripe_invoice_id,
                       'invoice_number', new.stripe_invoice_number, 'total_charged', new.total_charged));

  -- The handoff names its conversation, its case, its decision and its ask, so its note can be stated.
  -- If it still cannot be filed, the invoice stays filed and the IT engineer is told which case lost it.
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'handoff', 'pending', 'low',
            'Reveal invoice filed - tell the customer it is ready',
            'The Stripe invoice is in the customer''s Documents and on the revealed quote card.',
            jsonb_build_object('type', 'invoice.issued', 'from', 'accountant', 'from_name', 'Accountant', 'to', 'sales_engineer',
                               'subject', 'reveal_invoice', 'subject_table', 'transactions', 'subject_id', new.id::text,
                               'decision', 'accountant filed the Stripe reveal invoice into the customer''s Documents (document '
                                           || v_doc || ') and hands the notice to the sales engineer',
                               'question', 'Tell the customer their reveal invoice is ready, in the inquiry''s language.',
                               'transaction_id', new.id, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                               'customer_id', new.customer_id, 'document_id', v_doc,
                               'invoice_number', new.stripe_invoice_number),
            'transactions', new.id::text)
    returning id into v_h;
    perform public.fn_seat_handoff_event(v_h, 'sent');
  exception when others then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:reveal_invoice_handoff_not_filed:' || new.id,
      'Reveal invoice filed but its handoff to the sales engineer was refused: ' || left(sqlerrm, 200),
      'public.fn_accountant_files_reveal_invoice (caller: accountant)', 'customer_facing', 1,
      jsonb_build_object('transaction_id', new.id, 'document_id', v_doc, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
      '{}'::text[], array['why the reveal_invoice handoff could not be filed for this transaction'], 'fn_accountant_files_reveal_invoice');
  end;
  return new;
end
$fn$;

-- CREATE OR REPLACE keeps the ACL these two had (revoked in the file that created them); repeated so this file stands alone.
revoke execute on function public.fn_accountant_files_reveal_invoice() from public, anon, authenticated;
revoke execute on function public.fn_sales_engineer_tells_customer_invoice_ready() from public, anon, authenticated;

comment on function public.fn_accountant_files_reveal_invoice() is
  'Owner: accountant. Files the stored Stripe reveal invoice into the customer''s Documents (kind invoice), records '
  'invoice.issued, and hands the registered invoice.issued conversation to sales_engineer. A refused handoff is an IT '
  'finding and never un-files the invoice.';
comment on function public.fn_sales_engineer_tells_customer_invoice_ready() is
  'Owner: sales_engineer. The door an invoice.issued handoff reaches the seat through: dispatches it to its registered '
  'handler via fn_seat_handoff_act (which cites the note and closes it). A failure marks the handoff failed.';
