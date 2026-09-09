-- A REPLACEMENT REPORT MUST NOT ARRIVE WEARING THE SAME NAME AS THE ONE IT REPLACES.
--
-- The founder holds a spend report emailed at 05:04 today: AED 4,400.51, subject and attachment both
-- undated beyond the day, and completeness claimed. Every part of that is now wrong -- the total was
-- short AED 2,153 of receipts sitting in mailboxes nobody read, and the completeness claim was
-- measured from the intake side, where a receipt that never arrived leaves no trace.
--
-- The corrected report has to go to the same person on the same day. fn_accountant_spend_report_
-- deliver builds the attachment name from the as-of date alone:
--
--     v_file := 'QuotesDone_Spend_Since_Day_One_' || <as_of> || '.pdf'
--
-- so the replacement would land in his inbox as a second file with the IDENTICAL name, on the same
-- date, carrying a different number. Two files called the same thing, one right and one wrong, is a
-- worse state than the wrong one alone: nothing on either document says which supersedes, and the
-- one he opens is decided by whichever his mail client happens to show.
--
-- So a report is numbered when a previous one for the same as-of date has already been put on his
-- mail lane. The first stays as it was -- renaming a document already delivered would rewrite
-- history -- and each later one says revision N in its filename and its subject.
--
-- The "already sent" guard below is untouched and still keys on the OBJECT PATH, which is correct
-- and is why a corrected report can be sent at all: pdf_native names every render uniquely, so a new
-- render is a new report, while re-delivering the SAME document twice is still refused as a
-- duplicate. That is the distinction that matters -- a second copy of one document is noise, a
-- corrected document is the whole point.
--
-- Everything else in this definition is byte-identical to what was live; only the filename, the
-- subject and the revision lookup were added.

CREATE OR REPLACE FUNCTION public.fn_accountant_spend_report_deliver(p_bucket text, p_path text, p_url text DEFAULT NULL::text, p_bytes bigint DEFAULT NULL::bigint, p_as_of text DEFAULT NULL::text, p_subject text DEFAULT NULL::text, p_body text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_owner text;
  v_file  text;
  v_notif bigint;
  v_prior bigint;
  v_body  text;
  v_report jsonb;
  v_kept_err text;
  v_rev int;
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

  -- How many reports for THIS as-of date have already been put on his mail lane? The first keeps
  -- its plain name because it was delivered under it; every later one is numbered, so two files on
  -- the same date can never be confused for one another.
  select count(*) into v_rev from public.notifications n
   where n.kind = 'accountant_spend_report'
     and n.attachments->0->>'filename' like 'QuotesDone_Spend_Since_Day_One_'
         || regexp_replace(coalesce(nullif(p_as_of,''), to_char((now() at time zone 'Asia/Dubai')::date,'YYYY-MM-DD')), '[^A-Za-z0-9_-]', '_', 'g') || '%';

  v_file := 'QuotesDone_Spend_Since_Day_One_'
         || regexp_replace(coalesce(nullif(p_as_of, ''), to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM-DD')), '[^A-Za-z0-9_-]', '_', 'g')
         || case when v_rev > 0 then '_revision_' || (v_rev + 1) else '' end
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
            -- The subject carries the revision too. A founder scanning an inbox reads subjects, not
            -- attachment names, and "which of these two is the current number" must be answerable
            -- without opening either.
            case when v_rev > 0
              then 'REVISION ' || (v_rev + 1) || ' (supersedes the earlier report of the same date) — '
                || coalesce(p_subject, 'QuotesDone - everything spent since day one')
              else coalesce(p_subject, 'QuotesDone - everything spent since day one') end, v_body,
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
$function$
;
