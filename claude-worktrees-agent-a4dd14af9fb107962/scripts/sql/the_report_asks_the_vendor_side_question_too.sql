-- THE REPORT ASKS THE VENDOR-SIDE QUESTION TOO.
--
-- fn_accountant_spend_report decided completeness from four counts: receipts HELD with no readable
-- amount, senders REFUSED as off-allowlist, currencies with no FX rate, and entries not yet posted.
-- Every one of them asks the same thing -- "did we handle everything that arrived" -- and on the
-- morning of 9 September 2026 every one of them was ZERO while the book was short three Anthropic
-- receipts, two ChatGPT months and a vendor it had never heard of. The report said complete. The
-- founder said "anthropic must be much more than than that. i pay 200 usd monthly", and he was
-- right.
--
-- A pipeline that processes 100% of what it receives will always report itself healthy, however
-- much it never receives. fn_accountant_receipt_cadence_gaps was written that same day to ask the
-- other question -- did every vendor that bills on a cadence produce a receipt for every period --
-- and then it was left CALLED BY NOTHING. Which is the identical defect one layer up: a check
-- nobody runs cannot make a report more honest than the report was before it existed. It is the
-- lens this estate already keeps paying for, a finished capability with no entry point, and I built
-- a fresh instance of it while fixing the first.
--
-- So the report now asks both questions and lists whatever either one finds.
--
-- WHAT A CADENCE FINDING CLAIMS. Suspected, never proven. A subscription really can be cancelled,
-- downgraded or paused, and the receipts really can be complete. So a gap is NAMED as a shortfall
-- for somebody to resolve rather than asserted as a missing amount, no figure is invented for it,
-- and it leaves the list the moment the vendor bills again or the receipt is found. The founder can
-- close one by saying "I cancelled that" -- which is a fact only he holds, and exactly the kind of
-- thing a report should be asking him rather than assuming.
--
-- AND IF THE CHECK ITSELF FAILS, that is a shortfall too. The report may not claim completeness on
-- the strength of a check that did not run; it says so and stays incomplete. A guard that fails
-- open is worse than no guard, because it converts an unknown into a clean bill of health.
--
-- Everything else in this definition is byte-identical to what was live: the file was assembled from
-- pg_get_functiondef and only the shortfall block and its three variables were added. No figure moves.

CREATE OR REPLACE FUNCTION public.fn_accountant_spend_report(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz        text := 'Asia/Dubai';
  v_as_of     date;
  v_fx        numeric;
  v_entries   int;
  v_first     date;
  v_last      date;
  v_aed       numeric(18,2);
  v_vat       numeric(18,2);
  v_unconv    jsonb;
  v_unconv_n  int;
  v_by_cur    jsonb;
  v_by_vendor jsonb;
  v_by_month  jsonb;
  v_vendor_rows jsonb;
  v_month_rows  jsonb;
  v_held      jsonb;
  v_held_n    int;
  v_refused_n int;
  v_unposted  int;
  v_sweep     record;
  v_cov       text;
  v_covj      jsonb;
  v_complete  boolean;
  v_cadence   jsonb;
  v_cad_gap   int;
  v_cad_quiet int;
  v_short     text[] := '{}';
  v_subject   text;
  v_body      text;
  v_blocks    jsonb;
  v_money     text;
  v_rcpt      jsonb;
  v_rcpt_rows jsonb;
  v_receipts  jsonb;
  v_rcpt_n    int;
  v_rcpt_doc  int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  v_fx := coalesce(v_fx, 3.6725);

  -- ONE conversion expression, repeated verbatim everywhere below rather than varied, so the report
  -- cannot convert two ways in two places. NULL for a currency with no rate: such an entry then
  -- drops out of every sum BY CONSTRUCTION, rather than by a filter somebody could forget to repeat
  -- in the fifth query. It is counted separately and named on the document.
  select count(*), min(charged_on), max(charged_on),
         sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)),
         sum(round(coalesce(vat_amount,0) * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2))
    into v_entries, v_first, v_last, v_aed, v_vat
    from public.expense_entries;
  v_entries := coalesce(v_entries, 0);
  v_aed := coalesce(v_aed, 0);
  v_vat := coalesce(v_vat, 0);

  -- ---- by currency (every currency, converted or not) ----
  select coalesce(jsonb_agg(x order by x->>'currency'), '[]'::jsonb)
    into v_by_cur
    from (select jsonb_build_object(
                   'currency', upper(currency),
                   'entries', count(*),
                   'total', round(sum(amount), 2),
                   'vat_stated', round(sum(coalesce(vat_amount,0)), 2),
                   'convertible', upper(currency) in ('AED','USD'),
                   'aed', case when upper(currency) in ('AED','USD')
                          then round(sum(round(amount * case upper(currency) when 'USD' then v_fx else 1 end, 2)), 2)
                          else null end) as x
            from public.expense_entries group by upper(currency)) s;

  select coalesce(jsonb_agg(x order by x->>'currency'), '[]'::jsonb), count(*)
    into v_unconv, v_unconv_n
    from (select jsonb_build_object('currency', upper(currency), 'entries', count(*),
                                    'total', round(sum(amount), 2)) as x
            from public.expense_entries
           where upper(currency) not in ('AED','USD')
           group by upper(currency)) s;

  -- ---- by vendor ----
  select coalesce(jsonb_agg(x order by (x->>'aed')::numeric desc nulls last), '[]'::jsonb)
    into v_by_vendor
    from (select jsonb_build_object(
                   'vendor', vendor,
                   'entries', count(*),
                   'first', min(charged_on), 'last', max(charged_on),
                   'currencies', (select string_agg(distinct upper(e2.currency), '/' order by upper(e2.currency))
                                    from public.expense_entries e2 where e2.vendor = e.vendor),
                   'aed', round(sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)), 2)) as x
            from public.expense_entries e group by vendor) s;

  -- ---- by month (calendar month of the charge date, not of the forward) ----
  select coalesce(jsonb_agg(x order by x->>'month'), '[]'::jsonb)
    into v_by_month
    from (select jsonb_build_object(
                   'month', to_char(charged_on, 'YYYY-MM'),
                   'entries', count(*),
                   'aed', round(sum(round(amount * case upper(currency) when 'USD' then v_fx when 'AED' then 1 else null end, 2)), 2)) as x
            from public.expense_entries group by to_char(charged_on, 'YYYY-MM')) s;

  -- ---- what is NOT in the total ----
  -- A held receipt is a receipt the parser refused to guess at. It is NAMED here, with its reason,
  -- because "we could not read this one" is the single most important sentence a spend report can
  -- carry and it must never be reachable only by opening a task queue.
  select coalesce(jsonb_agg(jsonb_build_object(
           'task_id', t.id, 'title', t.title, 'opened', t.created_at::date,
           'assigned', t.assigned_agent,
           'reason', left(regexp_replace(coalesce(t.detail,''), '^\[inbound_message:\d+\]\s*', ''), 400)) order by t.id), '[]'::jsonb),
         count(*)
    into v_held, v_held_n
    from public.org_tasks t
   where t.decided_by = 'fn_receipt_hand_to_bookkeeper'
     and t.status not in ('done', 'cancelled');

  select count(*) into v_refused_n
    from public.inbound_messages
   where to_email ilike 'expenses@%' and body like '[REFUSED%';

  -- An entry that never reached the ledger is money we know about that the accounts do not.
  select count(*) into v_unposted
    from public.expense_entries e
   where not exists (select 1 from public.gl_journal g
                      where g.source = 'expense' and g.source_ref = e.id::text);

  -- ---- COVERAGE. How much was LOOKED AT, not how much was booked. ----
  --
  -- 9 Sep 2026: this block used to quote ONLY the Resend inbound sweep, because that was the only
  -- way an expense had ever reached the book. It is not any more -- 28 of the entries below came
  -- from the founder's own sent-mail record of what he forwarded before Resend's ~1-month inbound
  -- retention aged it out. Quoting one source while totalling two would have made the line that
  -- exists to BOUND the total into one that contradicts it, so both sources are named now.
  -- fn_accountant_spend_report_coverage owns that paragraph and its shortfalls; the arithmetic
  -- below is untouched, and a third source can be added there without reopening this routine.
  v_covj := public.fn_accountant_spend_report_coverage();
  v_cov  := v_covj->>'note';
  select v_short || coalesce(array_agg(s #>> '{}'), '{}')
    into v_short from jsonb_array_elements(coalesce(v_covj->'shortfalls','[]'::jsonb)) s;

  select r.id, r.finished_at, r.counts, r.status into v_sweep
    from public.agent_runs r
   where r.agent = 'accountant' and r.counts->>'action' = 'expense_sweep'
   order by r.id desc limit 1;

  if v_held_n > 0 then v_short := v_short || array[(v_held_n || ' receipt(s) HELD because no amount could be read')]; end if;
  if v_refused_n > 0 then v_short := v_short || array[(v_refused_n || ' message(s) refused because the sender is not on the expense forwarder allowlist')]; end if;
  if v_unconv_n > 0 then v_short := v_short || array[(v_unconv_n || ' currency/currencies with no rate in gl_settings, which are NOT converted and NOT in the AED total')]; end if;
  if v_unposted > 0 then v_short := v_short || array[(v_unposted || ' booked entry/entries that have not reached gl_journal')]; end if;
  -- THE VENDOR-SIDE QUESTION, asked here rather than in a routine nobody calls.
  --
  -- Everything above this line is INTAKE-side: held, refused, unconvertible, unposted. All four ask
  -- "did we handle what arrived", and on 9 Sep 2026 all four were zero while the book was short
  -- three Anthropic receipts. The founder found that, not the report.
  -- fn_accountant_receipt_cadence_gaps was written the same day to ask the other question -- did
  -- every vendor that bills on a cadence produce a receipt for every period -- and was then left
  -- CALLED BY NOTHING, which is the identical defect one layer up: a check nobody runs cannot make
  -- a report more honest than it was before the check existed.
  --
  -- A cadence finding is SUSPECTED, never proven: a subscription can be cancelled, downgraded or
  -- paused. So it is NAMED as a shortfall for somebody to resolve rather than asserted as a missing
  -- amount, no figure is invented for it, and it leaves the list when the vendor bills again, the
  -- receipt is found, or the founder records that the vendor ended.
  begin
    v_cadence   := public.fn_accountant_receipt_cadence_gaps(v_as_of);
    v_cad_gap   := coalesce(jsonb_array_length(v_cadence->'months_with_no_receipt_inside_a_run'), 0);
    v_cad_quiet := coalesce(jsonb_array_length(v_cadence->'vendors_gone_quiet'), 0);

    if v_cad_gap > 0 then
      v_short := v_short || array[(
        v_cad_gap || ' month(s) inside a vendor''s own billing run with no receipt at all ('
        || (select string_agg((x->>'vendor') || ' ' || (x->>'missing_month'), ', ')
              from jsonb_array_elements(v_cadence->'months_with_no_receipt_inside_a_run') x)
        || '), so a receipt for each is probably missing rather than genuinely absent')];
    end if;

    if v_cad_quiet > 0 then
      v_short := v_short || array[(
        v_cad_quiet || ' vendor(s) that billed on a monthly cadence and have gone quiet for more than 45 days ('
        || (select string_agg((x->>'vendor') || ', last billed ' || (x->>'last_month'), '; ')
              from jsonb_array_elements(v_cadence->'vendors_gone_quiet') x)
        || '); either the subscription ended and nobody recorded it, or the later receipts never reached the accountant')];
    end if;
  exception when others then
    -- The cadence check must never take the report down, and must never fail OPEN: a report may not
    -- claim completeness on the strength of a check that did not run.
    v_short := v_short || array['the vendor-side completeness check could not run (' || sqlerrm
      || '), so this total is NOT claiming to be complete'];
  end;

  v_complete := array_length(v_short, 1) is null;

  v_money := 'AED ' || to_char(v_aed, 'FM999,999,990.00');

  -- ---- the table rows the document prints ----
  select coalesce(jsonb_agg(jsonb_build_array(
           v->>'vendor',
           case when v->>'aed' is null then 'not converted' else 'AED ' || to_char((v->>'aed')::numeric, 'FM999,999,990.00') end,
           v->>'entries', coalesce(v->>'currencies',''),
           coalesce(v->>'first','') || ' to ' || coalesce(v->>'last',''))
         ), '[]'::jsonb)
    into v_vendor_rows
    from jsonb_array_elements(v_by_vendor) v;

  select coalesce(jsonb_agg(jsonb_build_array(
           m->>'month',
           case when m->>'aed' is null then 'not converted' else 'AED ' || to_char((m->>'aed')::numeric, 'FM999,999,990.00') end,
           m->>'entries')
         ), '[]'::jsonb)
    into v_month_rows
    from jsonb_array_elements(v_by_month) m;

  -- ---- THE RECEIPT REGISTER: one line per booked receipt, each carrying its own document ----
  -- The founder, 9 Sep 2026: "can the pdf have clickable links for the actual invoices or receipts
  -- or at least a pdf print of the email". Until now this report totalled the spend and named the
  -- vendors, and the evidence for any single line was not reachable from the document at all.
  --
  -- THE ROUTINE DOES NOT MINT THE LINK, AND CANNOT. receipt-files is a PRIVATE bucket; a URL into
  -- it has to be signed with the service role, and there is no pgjwt in this project (`sign` in
  -- pg_catalog is the arithmetic sign function). So each cell that should be clickable is emitted
  -- as {"text": ..., "link_entry": <expense id>} -- a REQUEST for a link, addressed to the seat that
  -- can sign one. supabase/functions/accountant resolves it immediately before rendering. A cell
  -- that is never resolved still prints its text, so the worst case is a report that reads exactly
  -- as it did yesterday rather than one carrying a link to nothing.
  --
  -- A ROW WITH NO DOCUMENT SAYS SO IN THE ROW. It is not blank and it is not a dead link: it reads
  -- NO DOCUMENT, and the count of such rows is printed under the table.
  select coalesce(jsonb_agg(x order by (x->>'charged_on'), (x->>'id')::bigint), '[]'::jsonb),
         count(*), count(*) filter (where (x->>'document_state') <> 'missing')
    into v_rcpt, v_rcpt_n, v_rcpt_doc
    from (select jsonb_build_object(
                   'id',             v.id,
                   'charged_on',     v.charged_on,
                   'vendor',         v.vendor,
                   'billed',         upper(v.currency) || ' ' || to_char(v.amount, 'FM999,999,990.00'),
                   'aed',            case when upper(v.currency) in ('AED','USD')
                                       then round(v.amount * case upper(v.currency) when 'USD' then v_fx else 1 end, 2)
                                       else null end,
                   'document_state', v.document_state,
                   'doc_bucket',     v.doc_bucket,
                   'doc_path',       v.doc_path,
                   'doc_name',       v.doc_name,
                   'doc_note',       v.doc_note) as x
            from public.v_expense_documents v) s;

  select coalesce(jsonb_agg(jsonb_build_array(
           r->>'id',
           to_char((r->>'charged_on')::date, 'DD Mon YYYY'),
           r->>'vendor',
           r->>'billed',
           case when r->>'aed' is null then 'not converted'
                else to_char((r->>'aed')::numeric, 'FM999,999,990.00') end,
           case r->>'document_state'
             when 'vendor_document' then jsonb_build_object('text', coalesce(nullif(r->>'doc_name',''), 'The vendor invoice'),
                                                            'link_entry', (r->>'id')::bigint)
             when 'email_print'     then jsonb_build_object('text', 'Email print',
                                                            'link_entry', (r->>'id')::bigint)
             when 'unclassified'    then jsonb_build_object('text', coalesce(nullif(r->>'doc_name',''), 'The stored document'),
                                                            'link_entry', (r->>'id')::bigint)
             else to_jsonb('NO DOCUMENT'::text)
           end)
         order by (r->>'charged_on'), (r->>'id')::bigint), '[]'::jsonb)
    into v_rcpt_rows
    from jsonb_array_elements(v_rcpt) r;

  v_receipts := jsonb_build_array(
    jsonb_build_object('t','space','h',10),
    jsonb_build_object('t','h3','text','Every receipt, and the document behind it'),
    jsonb_build_object('t','p','text',
      'One line per booked receipt. The Evidence column opens that receipt''s own stored document: '
      || 'the vendor''s invoice where the source email carried one, otherwise a PDF print of the '
      || 'email itself. A line with no stored document reads NO DOCUMENT rather than carrying a link '
      || 'to nothing. ' || v_rcpt_doc || ' of ' || v_rcpt_n || ' receipt(s) have a document.'),
    jsonb_build_object('t','table',
      'head', jsonb_build_array('Record','Charged','Vendor','As billed','AED','Evidence'),
      'rows', v_rcpt_rows,
      'widths', jsonb_build_array(0.08,0.15,0.22,0.15,0.13,0.27)),
    -- WHY THE RECORD NUMBER IS PRINTED, AND WHY IT IS THE FIRST COLUMN.
    -- A signed URL expires. This document is a financial record the founder keeps for years, and a
    -- PDF whose every link has quietly rotted is worse than one that never had links, because it
    -- still LOOKS like it can be opened. So the link is the convenience and the record number is the
    -- permanent handle: it never expires, it is the primary key of public.expense_entries, and both
    -- public.fn_expense_document(<record>) and the accountant seat's document action take it and
    -- return a fresh link on demand. The paragraph below says that in words, on the document,
    -- because a reader in 2028 will have this PDF and not this file.
    jsonb_build_object('t','note','text',
      'HOW LONG THESE LINKS LIVE. The documents are held in the private receipt-files bucket, so each '
      || 'link above is a signed URL with an expiry stamped into it -- the seat prints the exact '
      || 'expiry date under this table when it renders. AFTER THAT DATE THE RECORD NUMBER IN THE '
      || 'FIRST COLUMN IS STILL THE WAY IN: public.fn_expense_document(<record>) names the bucket and '
      || 'object for that receipt, and the accountant seat''s document action returns a fresh link '
      || 'for it. Nothing about this report stops being useful when the links expire.'));

  v_subject := 'QuotesDone - everything spent since day one, to ' || to_char(v_as_of, 'DD Mon YYYY')
            || ' (' || v_money || ')' || case when v_complete then '' else ' - INCOMPLETE, see the report' end;

  v_body := 'Everything the company has spent since day one, read from the receipts forwarded to '
    || 'expenses@mail.quotesdone.com.' || E'\n\n'
    || 'TOTAL: ' || v_money || ' across ' || v_entries || ' booked receipt(s)'
    || case when v_first is null then '.' else ', ' || to_char(v_first,'DD Mon YYYY') || ' to ' || to_char(v_last,'DD Mon YYYY') || '.' end
    || E'\n'
    || 'Input VAT stated on those receipts: AED ' || to_char(v_vat, 'FM999,999,990.00') || '.' || E'\n\n'
    || case when v_complete
         then 'THIS TOTAL IS COMPLETE as far as the mailbox goes: nothing was held, nothing was refused, every currency converted, and every booked entry reached the ledger.'
         else 'THIS TOTAL IS INCOMPLETE, and here is exactly how: ' || array_to_string(v_short, '; ') || '. Each is named in the attached report.' end
    || E'\n\n' || 'COVERAGE. ' || v_cov || E'\n\n'
    || 'CURRENCY. AED is itself. USD is converted at gl_settings.usd_to_aed = ' || v_fx
    || ', the same rate the ledger uses. A currency with no rate is NOT converted and NOT included - '
    || 'an understated total that says so is worth more than a wrong one that does not.' || E'\n\n'
    || 'No model was used to produce any figure in this report. The receipts were read by '
    || 'supabase/functions/_shared/receipt_parse.ts, the ledger posting is public.fn_expense_post_to_gl, '
    || 'and every number above is arithmetic over public.expense_entries.';

  v_blocks := jsonb_build_array(
    jsonb_build_object('t','h2','text','Everything spent since day one'),
    jsonb_build_object('t','p','text','QuotesDone - Dorata Trading Co. L.L.C.   Prepared by the accountant seat   As at ' || to_char(v_as_of,'DD Mon YYYY') || ' (Asia/Dubai)'),
    jsonb_build_object('t','note','text','Source: the receipts forwarded to expenses@mail.quotesdone.com, read deterministically. No model was used to produce any figure in this document.'),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','total','value', v_money),
    jsonb_build_object('t','kv','pairs', jsonb_build_array(
      jsonb_build_array('Booked receipts', v_entries::text),
      jsonb_build_array('Period covered', case when v_first is null then 'nothing booked' else to_char(v_first,'DD Mon YYYY') || ' - ' || to_char(v_last,'DD Mon YYYY') end),
      jsonb_build_array('Input VAT stated on receipts', 'AED ' || to_char(v_vat,'FM999,999,990.00')),
      jsonb_build_array('Is this total complete?', case when v_complete then 'Yes' else 'NO - see "What is not in this total"' end))),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','By vendor'),
    jsonb_build_object('t','table','head', jsonb_build_array('Vendor','Spent (AED)','Receipts','Billed in','First to last'),
                       'rows', v_vendor_rows, 'widths', jsonb_build_array(0.26,0.22,0.12,0.14,0.26)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','By month'),
    jsonb_build_object('t','table','head', jsonb_build_array('Month','Spent (AED)','Receipts'),
                       'rows', v_month_rows, 'widths', jsonb_build_array(0.34,0.4,0.26)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','How currency was handled'),
    jsonb_build_object('t','li','text','AED is itself; no conversion is applied and none is implied.'),
    jsonb_build_object('t','li','text','USD is converted at gl_settings.usd_to_aed = ' || v_fx || ', per entry, rounded to two places - the same rate and the same rounding fn_expense_post_to_gl applies, so this report and the general ledger agree to the fils.'),
    jsonb_build_object('t','li','text', case when v_unconv_n = 0
      then 'Every receipt was billed in AED or USD, so nothing was left out of the total for want of a rate.'
      else 'A currency with no rate in gl_settings is NOT converted and NOT included in the total above. ' || v_unconv_n || ' such currency/currencies appear below, in their own units.' end),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','What is not in this total'),
    jsonb_build_object('t','p','bold',true,'text', case when v_complete
      then 'Nothing. Nothing was held, nothing was refused, every currency converted, and every booked entry reached the ledger.'
      else 'This total is INCOMPLETE. ' || array_to_string(v_short, '; ') || '.' end),
    jsonb_build_object('t','space','h',4),
    jsonb_build_object('t','p','bold',true,'text','Receipts HELD because no amount could be read: ' || v_held_n),
    jsonb_build_object('t','note','text','A held receipt is one the deterministic parser refused to guess at. It is not booked, not estimated and not counted as zero - it is money we know we have spent and cannot yet state.'));

  if v_held_n > 0 then
    select v_blocks || coalesce(jsonb_agg(jsonb_build_object('t','li','text',
             'Task #' || (h->>'task_id') || ' (opened ' || (h->>'opened') || ', owner ' || coalesce(h->>'assigned','none') || '): ' || (h->>'title') || ' - ' || (h->>'reason'))), '[]'::jsonb)
      into v_blocks from jsonb_array_elements(v_held) h;
  end if;

  v_blocks := v_blocks || jsonb_build_array(
    jsonb_build_object('t','space','h',4),
    jsonb_build_object('t','p','bold',true,'text','Messages refused because the sender is not a permitted forwarder: ' || v_refused_n),
    jsonb_build_object('t','p','bold',true,'text','Booked entries that have not reached the general ledger: ' || v_unposted),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Coverage of the mailbox'),
    jsonb_build_object('t','p','text', v_cov),
    jsonb_build_object('t','note','text','This line is what bounds the total. Without it the report could say how much was booked but not how much was looked at, and a total nobody can bound is a guess with a decimal point on it.'));

  v_blocks := v_blocks || v_receipts;

  return jsonb_build_object(
    'as_of', v_as_of,
    'subject', v_subject,
    'body', v_body,
    'blocks', v_blocks,
    'doc_name', 'QuotesDone_Spend_Since_Day_One_' || to_char(v_as_of, 'YYYY-MM-DD'),
    'complete', v_complete,
    -- The same lines the table prints, with the storage path on each, so a caller that is not a PDF
    -- (the OS, a check, the seat's own run record) never has to parse the document to find them.
    'receipt_lines', v_rcpt,
    'receipts_with_document', v_rcpt_doc,
    'receipts_without_document', v_rcpt_n - v_rcpt_doc,
    'shortfalls', to_jsonb(v_short),
    'figures', jsonb_build_object(
      'total_aed', v_aed, 'vat_stated_aed', v_vat, 'entries', v_entries,
      'first_charge', v_first, 'last_charge', v_last,
      'usd_to_aed', v_fx,
      'by_currency', v_by_cur, 'by_vendor', v_by_vendor, 'by_month', v_by_month,
      'unconvertible_currencies', v_unconv,
      'held_receipts', v_held, 'held_count', v_held_n,
      'refused_messages', v_refused_n, 'entries_not_in_ledger', v_unposted),
    'coverage', jsonb_build_object('note', v_cov,
      'last_sweep_run_id', v_sweep.id, 'last_sweep_at', v_sweep.finished_at,
      'last_sweep_counts', v_sweep.counts, 'last_sweep_status', v_sweep.status));
end
$function$
;
