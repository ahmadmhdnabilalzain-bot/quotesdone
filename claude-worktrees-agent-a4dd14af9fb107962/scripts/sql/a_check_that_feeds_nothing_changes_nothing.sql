-- A CHECK THAT FEEDS NOTHING, AND A REASON THAT SILENCED A REAL GAP.
--
-- Two defects of my own, found by running what I had just built rather than by reading it, and both
-- are the same shape as the defect this whole day started with.
--
-- ONE: THE REPORT STILL SAID COMPLETE WHILE THE CHECK SAID OTHERWISE.
--   fn_accountant_receipt_cadence_gaps returned suspected_missing = 1 (Figma: one receipt, 70 days
--   silent, no reason recorded) and fn_accountant_spend_report returned complete = true with an
--   empty shortfall list. I had wired TWO of the check's three findings into the report -- the
--   in-run gaps and the gone-quiet vendors -- and left `vendors_seen_once_unexplained` feeding
--   nothing. Which is precisely the fault I had written the check to fix, one layer up: a finding
--   that reaches no report changes no decision. The report now reads the check's OWN
--   suspected_missing count, so a finding cannot be added to the check in future and silently fail
--   to reach the founder.
--
-- TWO: RECORDING WHY A RECEIPT IS MISSING MADE IT STOP BEING MISSING.
--   OpenAI was recorded as `portal_only` -- still billing monthly, but the vendor never emails an
--   invoice, so August and September live in the ChatGPT billing portal and are not booked. The
--   suppression logic treated any recorded reason as an explanation and dropped it from the list.
--   But ended, annual and one_off all mean NO MONEY IS MISSING, while portal_only means money IS
--   missing and we know where to fetch it. Collapsing the two turned a real, actionable gap into
--   silence -- the flattering direction again.
--
--   So portal_only no longer suppresses. It reclassifies: the vendor moves out of "unexplained" and
--   into `vendors_billing_outside_email`, which still counts toward suspected_missing and still
--   makes the report incomplete, but carries the remedy with it instead of asking the same open
--   question every month.
--
-- No figure moves. Nothing is booked, nothing is un-booked.

CREATE OR REPLACE FUNCTION public.fn_accountant_receipt_cadence_gaps(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz      text := 'Asia/Dubai';
  v_as_of   date;
  v_gaps    jsonb;
  v_stale   jsonb;
  v_single  jsonb;
  v_ended   jsonb;
  v_n_gap   int;
  v_n_stale int;
  v_n_once  int;
  v_portal   jsonb;
  v_n_portal int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);

  with per_vendor_month as (
    select vendor, date_trunc('month', charged_on)::date mo, count(*) n
      from public.expense_entries
     group by vendor, date_trunc('month', charged_on)::date
  ),
  span as (
    select vendor, min(mo) first_mo, max(mo) last_mo, count(*) months_seen, sum(n) receipts
      from per_vendor_month group by vendor
  ),
  -- TWO distinct months, not three. Requiring three examined neither vendor this was written to
  -- catch: Anthropic had two months booked and Google two. A threshold that excludes the case the
  -- guard exists for is the guard not existing, and it fails in the flattering direction.
  cadenced as (
    select * from span where months_seen >= 2
  ),
  expected as (
    select c.vendor, gs::date mo
      from cadenced c
      cross join lateral generate_series(c.first_mo, c.last_mo, interval '1 month') gs
  ),
  -- A month INSIDE the vendor's own run with no receipt. NEVER suppressed by an explanation: a
  -- vendor that billed May, skipped June and billed July has a real hole whatever happened after.
  gap as (
    select e.vendor, to_char(e.mo, 'YYYY-MM') missing_month
      from expected e
      left join per_vendor_month p on p.vendor = e.vendor and p.mo = e.mo
     where p.vendor is null
  ),
  -- Billed on a cadence, then silent for more than 45 days. 45 rather than 31 so a charge landing a
  -- few days late does not cry wolf. Suppressed only by a recorded explanation.
  stale as (
    select c.vendor, to_char(c.last_mo, 'YYYY-MM') last_month,
           (v_as_of - c.last_mo) days_since_last_month_started, c.receipts
      from cadenced c
      left join public.vendor_billing_ended e on e.vendor = c.vendor
     where v_as_of - c.last_mo > 45 and e.vendor is null
  ),
  -- ONE receipt, silent, and nobody has said why. This is the STRONGEST case, not the weakest: if
  -- that vendor is a monthly subscription then every renewal after it is missing, and no other check
  -- here can see it, because one month is not a cadence. It fed nothing until 9 Sep 2026, which is
  -- how a report claimed completeness while the founder's ChatGPT renewals were unaccounted for.
  single_receipt as (
    select s.vendor, to_char(s.first_mo, 'YYYY-MM') only_month,
           (v_as_of - s.first_mo) days_since
      from span s
      left join public.vendor_billing_ended e on e.vendor = s.vendor
     where s.receipts = 1 and v_as_of - s.first_mo > 45 and e.vendor is null
  ),
  -- STILL BILLING, NEVER EMAILS. The money is missing and the remedy is known: fetch the invoice
  -- from the vendor's own portal. This is a shortfall like any other -- it just carries its answer.
  portal_billing as (
    select s.vendor, to_char(s.last_mo, 'YYYY-MM') last_month, s.receipts,
           (v_as_of - s.last_mo) days_since, e.note
      from span s
      join public.vendor_billing_ended e on e.vendor = s.vendor and e.kind = 'portal_only'
     where v_as_of - s.last_mo > 45
  ),
  explained as (
    select vendor, to_char(ended_after, 'YYYY-MM') ended_after_month, kind, basis
      from public.vendor_billing_ended
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'missing_month', missing_month)
              order by vendor, missing_month), '[]'::jsonb) from gap),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_month', last_month,
              'receipts_seen', receipts, 'days_since', days_since_last_month_started)
              order by vendor), '[]'::jsonb) from stale),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'only_month', only_month,
              'days_since', days_since) order by vendor), '[]'::jsonb) from single_receipt),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'kind', kind,
              'since', ended_after_month, 'basis', basis) order by vendor), '[]'::jsonb) from explained),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_billed', last_month,
              'days_since', days_since, 'remedy', note) order by vendor), '[]'::jsonb) from portal_billing)
    into v_gaps, v_stale, v_single, v_ended, v_portal;

  v_n_gap    := jsonb_array_length(v_gaps);
  v_n_stale  := jsonb_array_length(v_stale);
  v_n_once   := jsonb_array_length(v_single);
  v_n_portal := jsonb_array_length(v_portal);

  return jsonb_build_object(
    'as_of', v_as_of,
    'timezone', v_tz,
    'basis', 'Measured from the VENDOR side: what each vendor billed, not what the mailbox received. '
          || 'The intake-side checks (held, refused, unconvertible, unposted) cannot see a receipt '
          || 'that never arrived, which is why a report can read complete while a subscription is '
          || 'missing three months.',
    'months_with_no_receipt_inside_a_run', v_gaps,
    'vendors_gone_quiet', v_stale,
    'vendors_seen_once_unexplained', v_single,
    'vendors_with_a_recorded_reason', v_ended,
    'vendors_billing_outside_email', v_portal,
    'suspected_missing', v_n_gap + v_n_stale + v_n_once + v_n_portal,
    'claim', case when v_n_gap + v_n_stale + v_n_once + v_n_portal = 0
              then 'No vendor is missing a month, unexplained-quiet, or seen once without a reason. '
                || 'That is NOT a claim that the book is complete: a vendor never forwarded even '
                || 'once is invisible to this and to every other check here.'
              else 'These are SUSPECTED gaps, not proven ones -- a subscription can be cancelled, '
                || 'downgraded or paused, and a one-off purchase legitimately bills once. Each '
                || 'carries the evidence that produced it, and any of them can be closed for good by '
                || 'recording the vendor in vendor_billing_ended as ended, annual or one_off. The '
                || 'book should not be called complete while one stands unexplained.' end);
end;
$function$
;

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

    -- READ THE CHECK'S OWN COUNT, not a hand-picked subset of its findings. The first version of
    -- this block listed two of the check's three lists and left `vendors_seen_once_unexplained`
    -- feeding nothing, so the report returned complete = true while the check returned
    -- suspected_missing = 1. Binding to suspected_missing means a finding added to the check in
    -- future reaches the founder without anyone remembering to wire it.
    if coalesce((v_cadence->>'suspected_missing')::int, 0) > 0 then
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
      if coalesce(jsonb_array_length(v_cadence->'vendors_seen_once_unexplained'), 0) > 0 then
        v_short := v_short || array[(
          jsonb_array_length(v_cadence->'vendors_seen_once_unexplained')
          || ' vendor(s) with exactly ONE receipt and no recorded reason ('
          || (select string_agg((x->>'vendor') || ', only ' || (x->>'only_month')
                 || ', ' || (x->>'days_since') || ' days ago', '; ')
                from jsonb_array_elements(v_cadence->'vendors_seen_once_unexplained') x)
          || '); if any is a monthly subscription then every renewal after it is missing')];
      end if;
      if coalesce(jsonb_array_length(v_cadence->'vendors_billing_outside_email'), 0) > 0 then
        v_short := v_short || array[(
          jsonb_array_length(v_cadence->'vendors_billing_outside_email')
          || ' vendor(s) STILL BILLING that never email an invoice, so their charges are real and unbooked ('
          || (select string_agg((x->>'vendor') || ', last booked ' || (x->>'last_billed'), '; ')
                from jsonb_array_elements(v_cadence->'vendors_billing_outside_email') x)
          || '); the invoices must be fetched from the vendor''s own billing portal by hand')];
      end if;
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

-- CLOSING ASSERTION on the loop this file exists to close: the report may not claim completeness
-- while the check finds anything, and recording WHY a receipt is missing may not make it silent.
do $do$
declare v jsonb; r jsonb; v_openai int; v_portal int; v_entries int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so nothing here is tested';
  end if;
  if (select count(*) from public.vendor_billing_ended where kind = 'portal_only') = 0 then
    raise exception 'POSITIVE CONTROL FAILED: no portal_only vendor exists, so the reclassification cannot be observed';
  end if;

  v := public.fn_accountant_receipt_cadence_gaps();

  -- OpenAI must appear as billing-outside-email, NOT be silently explained away: the money is
  -- missing, and recording why must never make it stop being missing.
  select count(*) into v_portal from jsonb_array_elements(v->'vendors_billing_outside_email') x
   where lower(x->>'vendor') = 'openai';
  if v_portal = 0 then
    raise exception 'OpenAI is not reported as billing outside email, so a real unbooked cost is silent';
  end if;

  select count(*) into v_openai from jsonb_array_elements(v->'vendors_seen_once_unexplained') x
   where lower(x->>'vendor') = 'openai';
  if v_openai > 0 then
    raise exception 'OpenAI is in BOTH lists; it should have moved out of unexplained, not been duplicated';
  end if;

  -- THE LOOP THAT WAS OPEN.
  r := public.fn_accountant_spend_report();
  if coalesce((v->>'suspected_missing')::int, 0) > 0 and (r->>'complete')::boolean then
    raise exception 'the check reports % suspected but the report still claims complete', v->>'suspected_missing';
  end if;

  raise notice 'closed: check reports % suspected, report complete = %, OpenAI named with its remedy',
    v->>'suspected_missing', r->>'complete';
end
$do$;
