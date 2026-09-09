-- THE WEEKLY REPORT ARRIVES AS A FILE, NOT A LINK.
--
-- The founder, 9 Sep 2026: "create weekly report as pdf and share it with me and the CEO", then
-- "make sure he is capable of generating proper organized PDF also with our format when he shares
-- the weekly report with me and the CEO."
--
-- fn_accountant_weekly_report_deliver was written before the estate could email a document -- until
-- earlier today public.notifications had no column that could carry one and send_outbox built its
-- Resend payload without an attachments field. So the founder's lane put a SIGNED URL in the body
-- and nothing else. That is not the report; it is a way to fetch the report for seven days, from a
-- session, if the object has not moved.
--
-- an_agent_can_attach_a_document_to_the_mail_it_sends.sql added the carriage. This file uses it:
-- the founder's copy now leaves with the PDF ON it. The signed link stays in the body underneath --
-- a phone that will not open a 100 KB attachment still has somewhere to go, and the storage path is
-- how the CEO's copy and the archive refer to the same object.
--
-- WHY THE FILENAME IS BUILT AND NOT STORED. The attachment guard refuses any filename outside
-- [A-Za-z0-9 ._-], and report_key is 'quotesdone:2026-W36' -- the colon would be refused, correctly,
-- because a filename crosses into a MIME header. The name is derived here so the two can never drift:
--   quotesdone:2026-W36  ->  QuotesDone_Weekly_Financial_Report_2026-W36.pdf
-- A revision above 1 is named, because a founder holding two files called the same thing cannot tell
-- which one supersedes the other.
--
-- WHAT IS NOT CHANGED: the CEO lane (support_ceo_report already carries bucket/path in its evidence
-- and the CEO seat reads from storage, not from mail), the idempotency key, the retained-on-failure
-- behaviour, and the rule that a report with no rendered PDF is NOT delivered.

create or replace function public.fn_accountant_weekly_report_deliver(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_row     public.accountant_weekly_report%rowtype;
  v_owner   text;
  v_parent  text;
  v_notif   bigint;
  v_ceo_id  bigint;
  v_errs    text[] := '{}';
  v_link    text;
  v_body    text;
  v_file    text;
  v_attach  jsonb;
begin
  select * into v_row from public.accountant_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  -- THE PDF IS THE DELIVERABLE. He asked for the report AS a PDF; mailing the text alone and
  -- marking the week delivered would close the key on something he did not ask for.
  if v_row.pdf_path is null then
    update public.accountant_weekly_report
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'not delivered: the PDF has not been rendered yet. The report is retained and the next tick retries.',
           updated_at = now()
     where id = p_id returning * into v_row;
    return jsonb_build_object('ok', false, 'report_key', v_row.report_key, 'retained', true,
      'reason', 'pdf not yet rendered', 'delivery_attempts', v_row.delivery_attempts);
  end if;

  -- The attachment the founder actually opens. Built from the row so the name cannot drift from
  -- the week it reports, and stripped to what the attachment guard accepts.
  v_file := 'QuotesDone_Weekly_Financial_Report_'
         || regexp_replace(replace(v_row.report_key, 'quotesdone:', ''), '[^A-Za-z0-9_-]', '_', 'g')
         || case when coalesce(v_row.revision, 1) > 1 then '_revision_'||v_row.revision else '' end
         || '.pdf';
  v_attach := jsonb_build_array(jsonb_build_object(
    'bucket',   coalesce(v_row.pdf_bucket, 'agent-docs'),
    'path',     v_row.pdf_path,
    'filename', v_file));

  -- The link stays, underneath the attachment rather than instead of it.
  v_link := case when v_row.pdf_url is not null
    then E'\n\n'||'The report is attached as '||v_file||'.'||E'\n'
       ||'If your mail client has stripped it, the same document is here: '||v_row.pdf_url||E'\n'
       ||'(That link is signed and expires seven days from generation; the document itself is retained at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.)'
    else E'\n\n'||'The report is attached as '||v_file||'. It is retained at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.' end;
  v_body := coalesce(v_row.body,'') || v_link;

  -- ---- LANE 1: THE FOUNDER -------------------------------------------------------------------
  if v_row.founder_submitted_at is null then
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_errs := v_errs || 'no recipient configured in app_secrets.admin_emails';
    else
      begin
        insert into public.notifications(type, kind, to_email, to_role, channel, subject, body, attachments)
        values ('accountant_weekly_report', 'accountant_weekly_report', v_owner, 'admin', 'email',
                v_row.subject, v_body, v_attach)
        returning id into v_notif;
        if v_notif is null then
          -- The gate returned NULL: a refusal, not an error. Name it, do not swallow it.
          v_errs := v_errs || 'the founder-mail gate did not accept the row (kind accountant_weekly_report)';
        end if;
      exception when others then
        -- a20_notifications_attachment_policy RAISES on a bad reference rather than dropping the
        -- row, so a malformed attachment lands here by name instead of vanishing.
        v_errs := v_errs || ('founder submission raised: '||sqlerrm);
      end;
    end if;
  end if;

  -- ---- LANE 2: THE CEO -----------------------------------------------------------------------
  if v_row.ceo_submitted_at is null then
    select e.parent_role_id into v_parent
      from public.org_reporting_edge e
      join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
     where e.child_role_id = 'accountant';
    if v_parent is null then
      v_errs := v_errs || 'no active reporting parent for accountant; the CEO copy is NOT redirected to anyone else';
    else
      begin
        insert into public.support_ceo_report
          (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
           requested_outcome, owner_role_id, next_review_at)
        values
          ('accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision,
           'accountant', 'routine', v_row.subject,
           jsonb_build_object(
             'report_key', v_row.report_key, 'revision', v_row.revision,
             'week_start', v_row.week_start, 'week_end', v_row.week_end,
             'pdf', coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path,
             'pdf_filename', v_file,
             'pdf_bytes', v_row.pdf_bytes,
             'basis_counts', v_row.figures->'basis_counts',
             'figures', v_row.figures->'this_week'->'lines'),
           '[]'::jsonb,
           'Note the week''s financial position. NOTHING IS REQUESTED: this is the informational weekly report the founder asked for on 9 Sep 2026, delivered to the CEO because the accountant reports to the CEO. It carries no decision, no approval and no deadline. Refund and Meta-ads approvals reach the CEO through their own lanes, never through this one.',
           'accountant',
           now() + interval '7 days')
        returning id into v_ceo_id;
      exception
        when unique_violation then
          -- This revision was already reported. The original IS the delivery.
          select id into v_ceo_id from public.support_ceo_report
           where idempotency_key = 'accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision;
        when others then
          v_errs := v_errs || ('CEO submission raised: '||sqlerrm);
      end;
    end if;
  end if;

  update public.accountant_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         ceo_report_id        = coalesce(v_ceo_id, ceo_report_id),
         ceo_submitted_at     = case when v_ceo_id is not null then now() else ceo_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = nullif(array_to_string(v_errs, ' | '), ''),
         updated_at           = now()
   where id = p_id returning * into v_row;

  update public.accountant_weekly_report
     set status = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null then 'delivered'
           when v_row.founder_submitted_at is not null or  v_row.ceo_submitted_at is not null then 'partial'
           else 'delivery_failed' end,
         delivered_at = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null
           then coalesce(delivered_at, now()) else delivered_at end
   where id = p_id returning * into v_row;

  return jsonb_build_object(
    'ok', v_row.status in ('delivered','partial'),
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status,
    'founder_submitted', v_row.founder_submitted_at is not null,
    'ceo_submitted', v_row.ceo_submitted_at is not null,
    'ceo_report_id', v_row.ceo_report_id,
    'pdf_filename', v_file,
    'delivery_attempts', v_row.delivery_attempts,
    'error', v_row.last_delivery_error);
end;$function$;

comment on function public.fn_accountant_weekly_report_deliver(bigint) is
  'Delivers one weekly financial report to BOTH recipients. The founder gets a notifications row of '
  'the registered kind with THE PDF ATTACHED (notifications.attachments, carried by send_outbox v43) '
  'and the signed link underneath as a fallback -- before 9 Sep 2026 the estate could not email a '
  'file at all, so this lane sent a link and called it delivered. The CEO gets public.support_ceo_'
  'report, the channel that seat already reads, with bucket, path and filename in its evidence. The '
  'two lanes are independent, each already-delivered lane is skipped on a retry, and neither can '
  'raise into the caller. A report whose PDF has not rendered is NOT delivered.';
