-- A CORRECTED REPORT MUST REACH THE PEOPLE WHO GOT THE ORIGINAL.
--
-- Found 9 Sep 2026, minutes after the accountant delivered his first weekly financial report and
-- the founder replied "the report is empty. all zeros". The report was honest -- the company had
-- never booked an expense or settled a transaction -- and the fix is to book the real spend and
-- re-issue the week as a revision. Which is when this was measured:
--
--   fn_accountant_weekly_report(p_revise => true) bumps revision, rewrites the figures and discards
--   the stale PDF, but leaves founder_submitted_at and ceo_submitted_at exactly as they were.
--
--   fn_accountant_weekly_report_deliver opens both lanes with
--       if v_row.founder_submitted_at is null then ...
--       if v_row.ceo_submitted_at    is null then ...
--
-- So the second the original was delivered, EVERY later correction of that week became
-- undeliverable. It would regenerate, re-render a fresh PDF, return ok, mark itself delivered --
-- and reach nobody. The lie is silent and it is in the direction that flatters the machine: the
-- report row would say 'delivered' while the founder held only the version that was wrong.
--
-- This is the succession trap this estate has already paid for once: a replacement record left
-- unreachable behind the row it replaces. The first correction anybody ever issued would have hit
-- it, which is why it is fixed before the corrected report is sent rather than after.
--
-- WHY CLEARING THE LANES IS SAFE. The CEO's idempotency key is
-- 'accountant_weekly_report:'||report_key||':r'||revision, so revision 2 cannot collide with the
-- row revision 1 wrote -- the two corrections are distinct records and both survive. The founder's
-- lane simply inserts a new notifications row, which is correct: he should receive the corrected
-- report as its own email, not as a silent edit of one already in his inbox.
--
-- delivery_attempts resets to 0 with them, because attempts count tries at delivering THIS
-- revision; carrying the previous revision's failures forward would make a healthy correction look
-- like a struggling one.
--
-- Everything else in this definition is byte-identical to what was live: the file was assembled
-- from pg_get_functiondef and only the update in the p_revise branch was changed.

CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report(p_week_start date DEFAULT NULL::date, p_revise boolean DEFAULT false, p_revision_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz      text := 'Asia/Dubai';
  v_company text := 'quotesdone';
  v_start   date;
  v_end     date;
  v_key     text;
  v_row     public.accountant_weekly_report%rowtype;
  v_now     jsonb;
  v_prev    jsonb;
  v_subject text;
  v_body    text;
  v_blocks  jsonb;
  v_rows    jsonb := '[]'::jsonb;
  v_k       text;
  v_ln      jsonb;
  v_pn      jsonb;
  v_val     text;
  v_mov     text;
  v_unknown int := 0;
  v_truezero int := 0;
  v_measured int := 0;
  -- The line order the report prints in. Insertion order of a jsonb object is not preserved, so it
  -- is stated here rather than discovered.
  v_order text[] := array[
    'reveal_fee_revenue','stripe_settlement_events',
    'expenses_filed_to_ledger','receipts_received_at_the_expenses_inbox','cash_out_this_week',
    'recurring_cost_schedule','refunds_requested','outstanding_bills','cash_position',
    'journal_entries_posted','ai_and_model_cost'];
  v_label jsonb := jsonb_build_object(
    'reveal_fee_revenue','Revenue - reveal fees (Stripe in)',
    'stripe_settlement_events','Stripe settlement events seen',
    'expenses_filed_to_ledger','Expenses filed to the ledger',
    'receipts_received_at_the_expenses_inbox','Receipts received at the expenses inbox',
    'cash_out_this_week','Cash out this week',
    'recurring_cost_schedule','Recurring cost schedule',
    'refunds_requested','Refunds requested',
    'outstanding_bills','Outstanding bills (accounts payable)',
    'cash_position','Cash position',
    'journal_entries_posted','Journal entries posted',
    'ai_and_model_cost','AI and model cost');
begin
  -- Default: the week that CLOSED. Never the week in progress -- a partial week reported as a week
  -- is a figure that will be wrong by Sunday and nobody will go back and correct it.
  v_start := coalesce(p_week_start,
                      (date_trunc('week', (now() at time zone v_tz)::date) - interval '7 days')::date);
  v_start := date_trunc('week', v_start::timestamp)::date;   -- normalise to the Monday
  v_end   := v_start + 6;
  v_key   := v_company||':'||to_char(v_start,'IYYY-"W"IW');

  -- UNFILTERED. Never `and status in (...)`.
  select * into v_row from public.accountant_weekly_report where report_key = v_key;

  if found and not p_revise then
    return jsonb_build_object(
      'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this ISO week',
      'week_start', v_row.week_start, 'week_end', v_row.week_end,
      'pdf_pending', v_row.pdf_path is null,
      'pdf_blocks', case when v_row.pdf_path is null then v_row.pdf_blocks else null end,
      'subject', v_row.subject,
      'delivered', v_row.delivered_at is not null,
      'delivery_attempts', v_row.delivery_attempts);
  end if;

  v_now  := public.fn_accountant_weekly_report_figures(v_start, v_end);
  v_prev := public.fn_accountant_weekly_report_figures(v_start - 7, v_end - 7);

  -- BUILD THE TABLE. One row per line item: what it is, what it says, on what basis, and how it
  -- moved. A line whose basis is 'unknown' prints the word and never a number.
  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    v_pn := v_prev->'lines'->v_k;
    if v_ln is null then continue; end if;

    if (v_ln->>'basis') = 'unknown' then
      v_val := 'UNKNOWN';
      v_unknown := v_unknown + 1;
    elsif v_ln ? 'aed' then
      v_val := 'AED '||to_char((v_ln->>'aed')::numeric, 'FM999,999,990.00')
               || case when v_ln ? 'n' then ' ('||(v_ln->>'n')||')' else '' end;
    else
      v_val := coalesce(v_ln->>'n', '-');
    end if;
    if (v_ln->>'basis') = 'true zero' then v_truezero := v_truezero + 1;
    elsif (v_ln->>'basis') = 'measured' then v_measured := v_measured + 1; end if;

    -- WEEK-OVER-WEEK. A movement is only stated when BOTH weeks carry a comparable number.
    if v_pn is null or (v_pn->>'basis') = 'unknown' or (v_ln->>'basis') = 'unknown' then
      v_mov := 'not comparable';
    elsif v_ln ? 'aed' and v_pn ? 'aed' then
      v_mov := case when (v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric >= 0 then '+' else '' end
               || to_char((v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric, 'FM999,999,990.00');
    elsif v_ln ? 'n' and v_pn ? 'n' then
      v_mov := case when (v_ln->>'n')::int - (v_pn->>'n')::int >= 0 then '+' else '' end
               || ((v_ln->>'n')::int - (v_pn->>'n')::int)::text;
    else
      v_mov := 'not comparable';
    end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_array(
      coalesce(v_label->>v_k, v_k), v_val, upper(coalesce(v_ln->>'basis','?')), v_mov));
  end loop;

  v_subject := 'QuotesDone weekly financial report - '||to_char(v_start,'IYYY-"W"IW')
               ||' ('||to_char(v_start,'DD Mon')||' to '||to_char(v_end,'DD Mon YYYY')||')';

  v_body :=
    'WEEKLY FINANCIAL REPORT'||E'\n'||
    to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||' (Asia/Dubai) - ISO '||to_char(v_start,'IYYY-"W"IW')||E'\n'||
    'Prepared by the accountant seat. Informational: nothing here asks you for a decision.'||E'\n\n'||
    'HOW TO READ THE BASIS COLUMN'||E'\n'||
    '- MEASURED   the figure was computed over source rows that exist.'||E'\n'||
    '- TRUE ZERO  the source table holds no rows at all, so the figure is zero over a zero denominator.'||E'\n'||
    '- UNKNOWN    no record exists from which the figure could be derived. It is NOT zero.'||E'\n\n';

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_body := v_body || upper(coalesce(v_label->>v_k, v_k))||E'\n'||
      '  '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                 when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                 else coalesce(v_ln->>'n','-') end||
      '   ['||upper(v_ln->>'basis')||']'||E'\n'||
      '  '||coalesce(v_ln->>'note','')||E'\n\n';
  end loop;

  v_body := v_body ||
    'RECONCILIATION OF THE TWO CASHFLOW SOURCES'||E'\n'||
    'The founder named two, and only two: Stripe in, the expenses mailbox out. Against the ledger:'||E'\n'||
    '- Stripe in:  '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')||E'\n'||
    '- Mailbox out: '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')||E'\n'||
    '- Ledger:     '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')||E'\n\n'||
    'BASIS SUMMARY: '||v_measured||' measured, '||v_truezero||' true zero, '||v_unknown||' unknown, of '||
      (v_measured + v_truezero + v_unknown)||' line item(s).'||E'\n'||
    case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end;

  -- THE PDF BLOCKS. pdf_native's own block vocabulary; letterhead on, strict glyphs on.
  v_blocks := jsonb_build_array(
    jsonb_build_object('t','h2','text','Weekly financial report'),
    jsonb_build_object('t','p','text', to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||
                                       '  (Asia/Dubai)   ISO '||to_char(v_start,'IYYY-"W"IW')||'   Revision '||
                                       coalesce(v_row.revision + 1, 1)::text),
    jsonb_build_object('t','note','text','Prepared by the accountant seat and reported to the CEO. Informational: nothing in this document asks for a decision or an approval.'),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','h3','text','Position'),
    jsonb_build_object('t','table',
      'head', jsonb_build_array('Line item','This week','Basis','vs prior week'),
      'rows', v_rows,
      'widths', jsonb_build_array(0.42, 0.24, 0.16, 0.18)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','What the basis column means'),
    jsonb_build_object('t','li','text','MEASURED - computed over source rows that exist.'),
    jsonb_build_object('t','li','text','TRUE ZERO - the source table holds no rows at all; the figure is zero over a zero denominator.'),
    jsonb_build_object('t','li','text','UNKNOWN - no record exists from which the figure could be derived. It is not zero, and it is not an omission.'),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Every figure, and the rows it binds to'));

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_blocks := v_blocks || jsonb_build_array(
      jsonb_build_object('t','p','bold',true,'text', coalesce(v_label->>v_k, v_k)||
        ' - '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                    when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                    else coalesce(v_ln->>'n','-') end||'  ['||upper(v_ln->>'basis')||']'),
      jsonb_build_object('t','note','text', coalesce(v_ln->>'note','')));
  end loop;

  v_blocks := v_blocks || jsonb_build_array(
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Reconciliation of the two cashflow sources'),
    jsonb_build_object('t','p','text','The founder named two, and only two: Stripe in, the expenses mailbox out. Reconciled against the general ledger, this week reads as follows.'),
    jsonb_build_object('t','li','text','Stripe in - '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')),
    jsonb_build_object('t','li','text','Mailbox out - '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')),
    jsonb_build_object('t','li','text','Ledger - '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','p','bold',true,'text','Basis summary: '||v_measured||' measured, '||v_truezero||
      ' true zero, '||v_unknown||' unknown, of '||(v_measured+v_truezero+v_unknown)||' line items.'),
    jsonb_build_object('t','note','text', case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end));

  if p_revise and v_row.id is not null then
    update public.accountant_weekly_report
       set revision = revision + 1, revision_note = p_revision_note,
           subject = v_subject, body = v_body,
           figures = jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                                        'basis_counts', jsonb_build_object('measured', v_measured,
                                          'true_zero', v_truezero, 'unknown', v_unknown)),
           pdf_blocks = v_blocks,
           -- A correction regenerates the document. The old PDF is not the new report.
           pdf_path = null, pdf_url = null, pdf_bytes = null, pdf_generated_at = null, pdf_error = null,
           status = 'generated', generated_at = now(), updated_at = now(),
           -- A CORRECTION MUST BE ABLE TO REACH THE PEOPLE WHO GOT THE ORIGINAL. deliver() skips
           -- the founder lane when founder_submitted_at is set and the CEO lane when
           -- ceo_submitted_at is, so bumping the revision without clearing these left every
           -- correction unreachable behind the copy it replaces: regenerated, re-rendered,
           -- reported ok, delivered to nobody. The CEO idempotency key already carries
           -- ':r'||revision, so a re-opened lane cannot collide with the report it supersedes.
           founder_submitted_at = null, ceo_submitted_at = null,
           notification_id = null, ceo_report_id = null,
           delivered_at = null, delivery_attempts = 0, last_delivery_error = null
     where id = v_row.id
    returning * into v_row;
  else
    insert into public.accountant_weekly_report(
      company_key, iso_year, iso_week, week_start, week_end, local_timezone, report_key,
      revision, revision_note, subject, body, figures, pdf_blocks, status)
    values (
      v_company, extract(isoyear from v_start)::int, extract(week from v_start)::int,
      v_start, v_end, v_tz, v_key, 1, p_revision_note, v_subject, v_body,
      jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                         'basis_counts', jsonb_build_object('measured', v_measured,
                           'true_zero', v_truezero, 'unknown', v_unknown)),
      v_blocks, 'generated')
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true,
    'week_start', v_row.week_start, 'week_end', v_row.week_end,
    'subject', v_row.subject,
    'basis', jsonb_build_object('measured', v_measured, 'true_zero', v_truezero, 'unknown', v_unknown),
    'pdf_pending', true, 'pdf_blocks', v_blocks);
end;$function$
;

comment on function public.fn_accountant_weekly_report(date, boolean, text) is
  'Generates the accountant''s weekly financial report for one ISO week, once. Idempotent: the '
  'lookup on the unique report_key is UNFILTERED, so a second call returns the existing row in '
  'whatever state it is in rather than colliding on the key. p_revise bumps revision in place, '
  'discards the stale PDF AND CLEARS BOTH DELIVERY LANES -- without that clear a correction was '
  'undeliverable behind the copy it replaced, reporting ok while reaching nobody (fixed 9 Sep '
  '2026). It does not deliver; delivery waits for fn_accountant_weekly_report_attach_pdf.';

-- CLOSING ASSERTION. Proves a revision genuinely re-opens both lanes. The probe runs inside its own
-- subtransaction and is rolled back by a sentinel exception, so nothing is generated, delivered or
-- emailed -- and a REAL assertion failure still propagates and fails the apply.
-- The positive control comes first: if the original does not deliver, "the correction re-opens the
-- lane" proves nothing at all.
do $do$
declare
  v_gen jsonb; v_id bigint; v_del jsonb; v_rev jsonb; v_f timestamptz; v_c timestamptz; v_n int;
begin
  begin
    v_gen := public.fn_accountant_weekly_report('2026-08-24'::date, false, null);
    v_id  := (v_gen->>'id')::bigint;
    if v_id is null then raise exception 'generate returned no id: %', v_gen::text; end if;

    perform public.fn_accountant_weekly_report_attach_pdf(
      v_id, 'agent-docs', 'accountant/weekly/zz_demo_probe.pdf', null, 1234, null);
    v_del := public.fn_accountant_weekly_report_deliver(v_id);

    select founder_submitted_at into v_f from public.accountant_weekly_report where id = v_id;
    if v_f is null then
      raise exception 'POSITIVE CONTROL FAILED: the original did not deliver to the founder (%), so the revision test below would prove nothing', coalesce(v_del::text,'null');
    end if;

    -- Now revise. Both lanes must re-open, or a correction can never reach anybody.
    v_rev := public.fn_accountant_weekly_report('2026-08-24'::date, true, 'zz demo correction');
    select founder_submitted_at, ceo_submitted_at, delivery_attempts into v_f, v_c, v_n
      from public.accountant_weekly_report where id = v_id;

    if v_f is not null then raise exception 'the founder lane stayed closed on a revision: the correction cannot reach him'; end if;
    if v_c is not null then raise exception 'the CEO lane stayed closed on a revision'; end if;
    if v_n <> 0 then raise exception 'delivery_attempts carried the previous revision forward: %', v_n; end if;
    if (v_rev->>'revision')::int <> 2 then raise exception 'revision did not advance: %', coalesce(v_rev->>'revision','null'); end if;

    raise exception 'ZZ_PROBE_ROLLBACK';
  exception when others then
    if sqlerrm = 'ZZ_PROBE_ROLLBACK' then
      raise notice 'a revision re-opens both delivery lanes (founder null, ceo null, attempts 0); probe rolled back';
    else
      raise;
    end if;
  end;
end
$do$;
