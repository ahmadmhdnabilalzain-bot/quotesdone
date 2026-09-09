-- THE ACCOUNTANT REPORTS WHAT THE COMPANY HAS SPENT SINCE DAY ONE.
--
-- The founder, 9 September 2026, verbatim: "once he access the email. let him send me a report of
-- all what we spent since day 1 by trailing the whole inbox and that would be a test. also such
-- tasks dont require LLM i believe and it can be built in code."
--
-- He is right about the second half, and this file honours it: there is NO model call anywhere on
-- this path -- not in the sweep that reads the mailbox (supabase/functions/accountant, action
-- expense_sweep) and not in the report below. Arithmetic over source rows is arithmetic.
--
-- WHAT WAS MEASURED FIRST, 9 Sep 2026, all read from production before a line was written:
--   * Resend's inbound history holds 9 messages. ALL NINE are addressed to
--     expenses@mail.quotesdone.com, and `has_more` is false at the default limit, so nine is the
--     whole history and not a first page.
--   * public.expense_entries 0 rows. public.expenses 0. public.gl_journal 0. ap_bills 0.
--     NOTHING has ever been booked, so this is not a top-up of an existing book -- it is the book.
--   * public.inbound_messages holds 4 of those 9 (15 Aug, 27 Aug, 29 Aug, 3 Sep). The other five
--     never reached the database at all.
--   * The reason: the Resend RECEIVING ROUTE for expenses@mail.quotesdone.com does not exist. Only
--     info@, supplier@ and docs@mail are wired, so resend_inbound was never handed this mail.
--     Resend kept the messages regardless. The history is the only path by which the founder's own
--     spend can reach the ledger, which is why the sweep had to exist.
--
-- WHY THE REPORT IS A ROUTINE AND NOT A QUERY IN A SESSION. He asked for it as a TEST OF THE AGENT.
-- A figure typed into a document by a session is a figure the seat cannot reproduce next month. The
-- seat calls fn_accountant_spend_report, renders what it returns through pdf_native, and mails it
-- with fn_accountant_spend_report_deliver. Nothing on that path is carried by hand.
--
-- THE ONE RULE THIS REPORT IS BUILT AROUND: a total is only worth reading if it says what it does
-- NOT contain. So the document carries, on its face:
--   * every message the sweep HELD because no amount could be read, named individually;
--   * every sender it REFUSED, because a refused receipt is a cost we chose not to book;
--   * every currency it could NOT convert (a currency with no rate is never booked at 1:1);
--   * every booked entry that has NOT reached gl_journal;
--   * the coverage of the last sweep, quoted from agent_runs -- how many messages were LOOKED AT,
--     not just how many were booked. Without that line the total is unbounded, and an unbounded
--     total is a guess with a decimal point on it.
-- If any of those is non-zero the report says the total is INCOMPLETE, in those words, at the top.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE CREDENTIAL. fn.accountant's scope was {accountant} -- itself and nothing else -- so the
--    seat's own call to pdf_native would have been refused with a bare 403 and the report would
--    have had no document. Widened by ONE slug, the same way fn.resilience_ping was on 9 Sep.
--    Nothing else about the credential changes.
-- ---------------------------------------------------------------------------------------------
update public.internal_credential
   set scope = scope || array['pdf_native']
 where context = 'fn.accountant'
   and active
   and not ('pdf_native' = any(scope));

-- ---------------------------------------------------------------------------------------------
-- 2. THE FOUNDER-MAIL KIND. a10_notifications_founder_mail_policy returns NULL for an unregistered
--    kind, which is a REFUSAL, not an error: the row simply never appears and nothing says so. A
--    report the seat believed it had sent and had not is exactly the failure this whole session is
--    about, so the kind is registered before anything tries to use it.
--
--    A NEW kind rather than borrowing 'accountant_weekly_report': the weekly report is a recurring
--    lane with its own idempotency key and its own retry behaviour, and a since-day-one sweep
--    report landing in it would make that key mean two different documents.
-- ---------------------------------------------------------------------------------------------
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('accountant_spend_report', true,
        'The founder asked for this by name on 9 Sep 2026: "let him send me a report of all what we spent since day 1 by trailing the whole inbox and that would be a test". Informational only -- it carries no approval request and opens no queue he must action.',
        'accountant')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email,
      reason = excluded.reason,
      owner_role = excluded.owner_role,
      updated_at = now();

commit;

-- ---------------------------------------------------------------------------------------------
-- 3. THE REPORT. Every figure below is read from public.expense_entries and nothing else, except
--    the coverage line (agent_runs) and the ledger-completeness line (gl_journal).
--
--    CONVERSION IS STATED, NEVER ASSUMED. AED is itself; USD converts at gl_settings.usd_to_aed
--    and the rate is printed; ANY OTHER CURRENCY IS NOT CONVERTED AT ALL and is reported as its own
--    line, because fn_expense_post_to_gl refuses to book it at 1:1 and a report that quietly did so
--    would disagree with the ledger it is describing. Rounding is per ENTRY, to two places, which
--    is what fn_expense_post_to_gl does -- so the report's AED total and gl_journal agree to the
--    fils rather than to within a rounding drift nobody can explain later.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_spend_report(p_as_of date default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $asr$
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
  v_short     text[] := '{}';
  v_subject   text;
  v_body      text;
  v_blocks    jsonb;
  v_money     text;
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

  return jsonb_build_object(
    'as_of', v_as_of,
    'subject', v_subject,
    'body', v_body,
    'blocks', v_blocks,
    'doc_name', 'QuotesDone_Spend_Since_Day_One_' || to_char(v_as_of, 'YYYY-MM-DD'),
    'complete', v_complete,
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
$asr$;

revoke execute on function public.fn_accountant_spend_report(date) from public;
grant execute on function public.fn_accountant_spend_report(date) to service_role;

comment on function public.fn_accountant_spend_report(date) is
  'Everything the company has spent since day one, read from public.expense_entries: total in AED, '
  'per vendor, per month, per currency, plus the four things that would make the total short -- held '
  'receipts named one by one, refused senders, currencies with no rate, and entries that never '
  'reached gl_journal -- and the coverage of the last mailbox sweep quoted from agent_runs. USD '
  'converts per entry at gl_settings.usd_to_aed with the same rounding fn_expense_post_to_gl uses, so '
  'the report and the ledger agree to the fils; any other currency is NOT converted and says so. '
  'Returns the subject, body and pdf_native block list the accountant seat renders. No model, ever.';

-- ---------------------------------------------------------------------------------------------
-- 4. DELIVERY, FROM THE SEAT, WITH THE DOCUMENT ON IT.
--
--    The founder: "i want the agent to do that cause we wanna test him." So the mail is inserted by
--    the seat's own routine into the lane registered above with owner_role 'accountant', and it
--    carries the PDF as a notifications.attachments REFERENCE -- {bucket, path, filename} -- which
--    send_outbox v43 downloads and base64s at send time, failing the row rather than sending a
--    covering note with no document.
--
--    THE FILENAME IS BUILT HERE, NOT PASSED IN. a20_notifications_attachment_policy refuses any
--    filename outside [A-Za-z0-9 ._-] (a filename crosses into a MIME header and a recipient's
--    filesystem), and it RAISES rather than dropping the row, so a malformed one arrives by name.
--    Building it from the as-of date means the document's name and the period it reports can never
--    drift apart.
--
--    IDEMPOTENT ON THE OBJECT. Two calls with the same stored path do not produce two emails: the
--    second finds the first's notification and returns it. A NEW render produces a new path and is
--    a new report, which is correct -- re-reading the mailbox and re-sending is the point.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_spend_report_deliver(
  p_bucket  text,
  p_path    text,
  p_url     text default null,
  p_bytes   bigint default null,
  p_as_of   text default null,
  p_subject text default null,
  p_body    text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $asd$
declare
  v_owner text;
  v_file  text;
  v_notif bigint;
  v_prior bigint;
  v_body  text;
  v_report jsonb;
  v_kept_err text;
begin
  -- THE DOCUMENT IS THE DELIVERABLE. He asked for a report; mailing a covering note and recording
  -- it as delivered would close the loop on something he did not ask for.
  if coalesce(p_path, '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'not delivered: no PDF path was supplied, and the report IS the document. Render it first and pass the path pdf_native returned.');
  end if;
  if coalesce(p_bucket, '') not in ('finance-reports','finance-docs','agent-docs','reports','compliance-docs') then
    return jsonb_build_object('ok', false, 'reason',
      'not delivered: ' || coalesce(p_bucket,'(null)') || ' is not a bucket notifications.attachments accepts. Refused here with a reason rather than at the trigger with a raise.');
  end if;

  v_file := 'QuotesDone_Spend_Since_Day_One_'
         || regexp_replace(coalesce(nullif(p_as_of, ''), to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM-DD')), '[^A-Za-z0-9_-]', '_', 'g')
         || '.pdf';

  -- Already sent for THIS document? The object path is the identity: a new render is a new report.
  select n.id into v_prior
    from public.notifications n
   where n.kind = 'accountant_spend_report'
     and n.attachments @> jsonb_build_array(jsonb_build_object('bucket', p_bucket, 'path', p_path))
   order by n.id limit 1;
  if v_prior is not null then
    return jsonb_build_object('ok', true, 'already_sent', true, 'notification_id', v_prior,
      'attachment', jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file),
      'reason', 'this exact document was already put on the founder''s mail lane; a second row would be a second copy of the same report');
  end if;

  select nullif(btrim(split_part(coalesce(value, ''), ',', 1)), '') into v_owner
    from public.app_secrets where key = 'admin_emails';
  if v_owner is null then
    return jsonb_build_object('ok', false, 'reason', 'not delivered: no recipient is configured in app_secrets.admin_emails');
  end if;

  v_body := coalesce(p_body, '')
    || E'\n\n' || 'The full report is attached as ' || v_file
    || case when coalesce(p_bytes, 0) > 0 then ' (' || round(p_bytes / 1024.0) || ' KB)' else '' end || '.'
    || case when p_url is not null
         then E'\n' || 'If your mail client has stripped it, the same document is here: ' || p_url
              || E'\n' || '(That link is signed and expires seven days from generation; the document itself is retained at ' || p_bucket || '/' || p_path || '.)'
         else E'\n' || 'It is retained at ' || p_bucket || '/' || p_path || '.' end;

  begin
    insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
    values ('accountant_spend_report', 'accountant_spend_report', v_owner, 'admin', 'email',
            coalesce(p_subject, 'QuotesDone - everything spent since day one'), v_body,
            jsonb_build_array(jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file)))
    returning id into v_notif;
  exception when others then
    -- a20_notifications_attachment_policy RAISES on a bad reference rather than dropping the row,
    -- so a malformed attachment lands here by name instead of vanishing.
    return jsonb_build_object('ok', false, 'reason', 'the insert raised: ' || sqlerrm);
  end;

  if v_notif is null then
    -- The a10 gate returned NULL: a REFUSAL, not an error. Name it; never let it read as sent.
    return jsonb_build_object('ok', false, 'reason',
      'the founder-mail gate did not accept the row (kind accountant_spend_report). Nothing was queued and nothing will be sent.');
  end if;

  -- ---- "AND KEEP IT IN HIS RECORD AS WELL" ----------------------------------------------------
  -- The founder asked for the report to be RETAINED, not merely sent. The object in the bucket is
  -- the document; this row is the record OF the document -- what was reported, when, and over which
  -- period -- so a figure he was given in September can be produced again and audited later without
  -- re-reading a mailbox the provider no longer holds. The whole figures payload is stored, not just
  -- the headline, because a total with no breakdown behind it cannot be checked.
  --
  -- Recorded AFTER the notification row exists, so the record can never claim a report was kept
  -- that was never actually queued. A failure to retain is reported alongside the send rather than
  -- swallowed: the mail did go, and he should be told the record did not.
  begin
    v_report := public.fn_accountant_spend_report(nullif(p_as_of,'')::date);
    insert into public.accountant_spend_report
      (as_of, period_start, period_end, entries, total_aed, vat_stated_aed, usd_to_aed,
       complete, shortfalls, figures, coverage, subject, body,
       pdf_bucket, pdf_path, pdf_url, pdf_bytes, notification_id, delivered_at)
    values (
      coalesce(nullif(p_as_of,'')::date, (now() at time zone 'Asia/Dubai')::date),
      nullif(v_report->'figures'->>'first_charge','')::date,
      nullif(v_report->'figures'->>'last_charge','')::date,
      nullif(v_report->'figures'->>'entries','')::int,
      nullif(v_report->'figures'->>'total_aed','')::numeric,
      nullif(v_report->'figures'->>'vat_stated_aed','')::numeric,
      nullif(v_report->'figures'->>'usd_to_aed','')::numeric,
      (v_report->>'complete')::boolean,
      v_report->'shortfalls', coalesce(v_report->'figures','{}'::jsonb), v_report->'coverage',
      coalesce(p_subject, v_report->>'subject'), coalesce(p_body, v_report->>'body'),
      p_bucket, p_path, p_url, p_bytes, v_notif, now())
    on conflict (pdf_bucket, pdf_path) do update
      set notification_id = excluded.notification_id,
          delivered_at    = coalesce(public.accountant_spend_report.delivered_at, excluded.delivered_at);
  exception when others then
    v_kept_err := sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'notification_id', v_notif, 'to', v_owner,
    'retained', v_kept_err is null,
    'retention_error', v_kept_err,
    'attachment', jsonb_build_object('bucket', p_bucket, 'path', p_path, 'filename', v_file),
    'status', 'pending - send_outbox will download the object, base64 it onto the Resend payload and fail the row rather than send a covering note without it');
end
$asd$;

revoke execute on function public.fn_accountant_spend_report_deliver(text, text, text, bigint, text, text, text) from public;
grant execute on function public.fn_accountant_spend_report_deliver(text, text, text, bigint, text, text, text) to service_role;

comment on function public.fn_accountant_spend_report_deliver(text, text, text, bigint, text, text, text) is
  'Puts ONE rendered spend report on the founder''s mail lane FROM THE ACCOUNTANT SEAT, with the PDF '
  'attached by reference ({bucket, path, filename}) rather than as a link. Registered kind '
  'accountant_spend_report, owner_role accountant, so the a10 gate accepts it; the filename is built '
  'from the as-of date so a20''s character rule cannot be violated and the name cannot drift from the '
  'period. Idempotent on the stored object path. A NULL from the gate is a refusal and is returned as '
  'one - it is never reported as sent.';
