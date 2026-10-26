-- THE ACCOUNTANT STOPS KEEPING ITS OWN COPY OF THE REPORTING RULES.
--
-- fn_accountant_weekly_report_deliver open-coded an INSERT into support_ceo_report instead of
-- calling fn_support_report_to_ceo. That was not laziness — it was forced. Until 9 September 2026
-- the shared routine hardcoded the literal 'customer_support' in three places: the reporting-edge
-- lookup that decides WHO the report goes to, the `source_agent` recorded on it, and the
-- `owner_role_id` that keeps it until the CEO accepts. An accountant calling it would have filed
-- its own weekly financial report under Support's name, addressed via Support's reporting edge.
-- So the accountant grew a private copy, and the company acquired two places where the rules for
-- reporting to the CEO lived.
--
-- The shared routine gained `p_source_agent` earlier today
-- (scripts/sql/the_ceo_seat_gets_its_own_credential_and_the_tray_its_staff_file_into.sql), so the
-- reason for the copy is gone. What remains is the cost: two implementations that must be kept in
-- step by memory, which is the shape every drift defect in this estate has started as.
--
-- WHAT THE SHARED ROUTINE DOES BETTER THAN THE COPY DID:
--
--   THE MANAGER IS READ FROM THE SENDER'S EDGE. The copy looked up the parent of 'accountant' with
--   the child hardcoded. The shared routine reads the edge of whoever is sending, so if the
--   accountant is ever re-parented this follows automatically instead of silently continuing to ask
--   about a relationship that changed.
--
--   A REPORT MUST SAY WHAT IT WANTS. The shared routine refuses an empty requested_outcome. The
--   copy could have written one and nobody would have noticed until the CEO opened a report that
--   asked for nothing.
--
--   IDEMPOTENCY IS THE SAME RULE, STATED ONCE. The copy caught unique_violation and re-selected the
--   existing row by idempotency key. The shared routine checks first and returns that row's id with
--   duplicate=true. Same outcome, one implementation — and it no longer depends on a constraint
--   name that a future migration could rename.
--
-- THE ONE BEHAVIOURAL CHANGE, AND IT IS AN IMPROVEMENT. The shared routine returns jsonb rather
-- than a bare id, and it REFUSES with a reason rather than raising. So a CEO copy that does not go
-- now lands in accountant_weekly_report.last_delivery_error as a sentence — "no active reporting
-- parent for accountant" — instead of leaving ceo_submitted_at null with nothing said. Everything
-- else is preserved exactly: the idempotency key, the evidence payload, the requested_outcome text,
-- the seven-day review, the v_errs accumulation, and ceo_report_id / ceo_submitted_at being set
-- from the returned id whether the report was new or already there.
--
-- Everything outside the LANE 2 block is byte-identical to what was live; only that block, and the
-- v_parent declaration it was the sole user of, changed.

CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row     public.accountant_weekly_report%rowtype;
  v_owner   text;
  v_rpt     jsonb;
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
  -- ONE ROUTINE OWNS THIS, NOT TWO. This block used to open-code its own INSERT into
  -- support_ceo_report, because fn_support_report_to_ceo hardcoded 'customer_support' as the sender
  -- in three places and the accountant could not use it without filing under Support's name. That
  -- was fixed on 9 Sep 2026 with p_source_agent, so the private copy is now only a second place for
  -- the rules to drift.
  --
  -- WHAT MOVED BACK: the manager lookup (the shared routine reads the SENDER's reporting edge and
  -- refuses rather than picking someone), the requirement that a report states what it wants, and
  -- idempotency by business event. Its duplicate path returns the existing row's id with
  -- duplicate=true, which is exactly what the unique_violation handler here did by hand -- and it no
  -- longer depends on a constraint name a future migration could rename.
  --
  -- IT RETURNS jsonb, NOT AN id, and it REFUSES rather than raising. So a CEO copy that does not go
  -- now lands in last_delivery_error as a sentence instead of leaving ceo_submitted_at silently null.
  if v_row.ceo_submitted_at is null then
    begin
      v_rpt := public.fn_support_report_to_ceo(
        p_idempotency_key => 'accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision,
        p_severity        => 'routine',
        p_subject         => v_row.subject,
        p_evidence        => jsonb_build_object(
                               'report_key', v_row.report_key, 'revision', v_row.revision,
                               'week_start', v_row.week_start, 'week_end', v_row.week_end,
                               'pdf', coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path,
                               'pdf_filename', v_file,
                               'pdf_bytes', v_row.pdf_bytes,
                               'basis_counts', v_row.figures->'basis_counts',
                               'figures', v_row.figures->'this_week'->'lines'),
        p_attempted       => '[]'::jsonb,
        p_requested       => 'Note the week''s financial position. NOTHING IS REQUESTED: this is the informational weekly report the founder asked for on 9 Sep 2026, delivered to the CEO because the accountant reports to the CEO. It carries no decision, no approval and no deadline. Refund and Meta-ads approvals reach the CEO through their own lanes, never through this one.',
        p_review_in       => interval '7 days',
        p_source_agent    => 'accountant');

      if coalesce((v_rpt->>'ok')::boolean, false) then
        -- Covers the fresh insert AND the duplicate: a revision already reported IS the delivery,
        -- and the shared routine hands back that report's id either way.
        v_ceo_id := (v_rpt->>'report_id')::bigint;
      else
        v_errs := v_errs || ('CEO submission refused: '||coalesce(v_rpt->>'reason','(no reason given)'));
      end if;
    exception when others then
      v_errs := v_errs || ('CEO submission raised: '||sqlerrm);
    end;
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


-- ══ PROVE IT, ON A THROWAWAY ROW THAT THE PROBE REMOVES ITSELF ══════════════════════════════════
--
-- NOT an aborted transaction: this file carries a routine definition, and rolling back to undo the
-- probe would roll the definition back with it. That mistake was made earlier today on the refund
-- chain, so the probe cleans up explicitly instead.
--
-- founder_submitted_at is pre-set so LANE 1 is skipped. The founder must not receive a test email
-- from a probe, and this estate has already paged him once today from exactly that.
--
-- The two real reports (138, 140) are never touched: the probe asserts their ids and count before
-- and after, so a sweep that took them would fail here rather than be discovered later.
do $do$
declare
  v_id bigint; v_key text; v_res jsonb; v_res2 jsonb; v_rep public.support_ceo_report;
  v_real_before int; v_real_after int; v_ceo_id bigint; v_row public.accountant_weekly_report;
begin
  select count(*) into v_real_before from public.support_ceo_report where id in (138, 140);
  if v_real_before <> 2 then
    raise exception 'POSITIVE CONTROL FAILED: expected the 2 real reports 138 and 140, found %', v_real_before;
  end if;

  v_key := 'quotesdone:PROBE-' || substr(md5(random()::text), 1, 8);

  insert into public.accountant_weekly_report
    (iso_year, iso_week, week_start, week_end, report_key, subject,
     pdf_bucket, pdf_path, pdf_bytes, figures, founder_submitted_at, status)
  values
    (2026, 99, date '2026-08-31', date '2026-09-06', v_key,
     'PROBE - not a real report', 'agent-docs', 'probe/not-a-real-file.pdf', 1234,
     jsonb_build_object('basis_counts', jsonb_build_object('measured', 0),
                        'this_week', jsonb_build_object('lines', '[]'::jsonb)),
     now(), 'generated')
  returning id into v_id;

  -- FIRST DELIVERY: the CEO copy must be created through the shared routine, as the accountant.
  v_res := public.fn_accountant_weekly_report_deliver(v_id);
  select * into v_row from public.accountant_weekly_report where id = v_id;
  v_ceo_id := v_row.ceo_report_id;

  if v_ceo_id is null then
    raise exception 'no CEO report was created. deliver returned: %  |  last error: %',
      v_res::text, coalesce(v_row.last_delivery_error, '(none)');
  end if;

  select * into v_rep from public.support_ceo_report where id = v_ceo_id;
  if v_rep.source_agent <> 'accountant' then
    raise exception 'the report was filed as "%" — the whole point of this change is that it says accountant', v_rep.source_agent;
  end if;
  if v_rep.owner_role_id <> 'accountant' then
    raise exception 'ownership was set to "%" rather than accountant', v_rep.owner_role_id;
  end if;
  if v_rep.idempotency_key <> ('accountant_weekly_report:'||v_key||':r1') then
    raise exception 'the idempotency key changed shape: %', v_rep.idempotency_key;
  end if;
  if v_row.ceo_submitted_at is null then
    raise exception 'ceo_report_id was set but ceo_submitted_at was not';
  end if;

  -- SECOND DELIVERY: the duplicate path must return the SAME id, not raise and not create a second.
  update public.accountant_weekly_report set ceo_submitted_at = null where id = v_id;
  v_res2 := public.fn_accountant_weekly_report_deliver(v_id);
  select * into v_row from public.accountant_weekly_report where id = v_id;
  if v_row.ceo_report_id <> v_ceo_id then
    raise exception 'a second delivery created report % instead of returning the existing %', v_row.ceo_report_id, v_ceo_id;
  end if;
  if (select count(*) from public.support_ceo_report
       where idempotency_key = 'accountant_weekly_report:'||v_key||':r1') <> 1 then
    raise exception 'the duplicate path created a second row for one revision';
  end if;

  -- CLEAN UP, then assert the real reports survived untouched.
  delete from public.support_ceo_report where id = v_ceo_id;
  delete from public.accountant_weekly_report where id = v_id;

  select count(*) into v_real_after from public.support_ceo_report where id in (138, 140);
  if v_real_after <> 2 then
    raise exception 'the probe disturbed the real reports: % of 2 remain', v_real_after;
  end if;
  if exists (select 1 from public.accountant_weekly_report where id = v_id)
     or exists (select 1 from public.support_ceo_report where id = v_ceo_id) then
    raise exception 'the probe left rows behind';
  end if;

  raise notice 'FOLDED IN. The accountant filed CEO report % through fn_support_report_to_ceo with source_agent=accountant, owner=accountant, key=%. A second delivery returned the same id and created no duplicate. Probe rows removed; real reports 138 and 140 untouched.',
    v_ceo_id, 'accountant_weekly_report:'||v_key||':r1';
end
$do$;
