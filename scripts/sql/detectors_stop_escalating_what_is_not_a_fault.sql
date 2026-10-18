-- it_engineer, 19 Oct 2026: six detectors escalated to the CEO as "still broken" things that are not faults.
-- Each body below is the live body (supabase/schema/full_schema mirror) copied forward unchanged except the fix.
-- Measured on production 19 Oct 2026 (02:15 Dubai), before -> what the fixed predicate returns:
--   1. fn_accountant_charge_audit_record: unresolved differences raised as findings 1 -> 0 (the one is reveal
--      29ac49f5, a Stripe TEST-mode charge, livemode false). Test-mode audits stay recorded in charge_audit.
--   2. fn_accountant_expense_duty no_document: 12 -> 0 (all 12 are source accountant:openrouter_daily, a
--      measured accrual for which no receipt ever exists).
--   3. fn_backup_coverage not_done_after_48h: 1911 -> 1 (1785 prune_pending + 125 pruned are verified copies
--      that went through retention; a stuck prune is its own backup_prune finding). fn_backup_watch: 12
--      dropbox_backup_escalation reports sat 'accepted', one per day for the same condition; now no new one
--      is raised while an earlier one is still accepted.
--   4. fn_it_loop_reverify: 3 open loops on info findings (affected 0 and title 'info:...'), 6 accepted CEO
--      reports already raised for them; info findings are no longer escalated.
--   5. fn_it_handoff_sla_items: 5 'it.finding:<seat>:open_over_24h' items repeated what the open queue
--      already says; the branch is removed ('unclosed' kept).
--   6. fn_support_reply_watch_tick email: 5 -> 0 waiting (no-reply senders and the founder's calendar+ inbox).
-- CREATE OR REPLACE keeps each routine's ACL; no revoke needed.

CREATE OR REPLACE FUNCTION public.fn_accountant_charge_audit_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x jsonb; n int := 0; v_items jsonb := '[]'::jsonb; r record; v_sys int; v_rep jsonb; v_sign text;
begin
  if jsonb_typeof(p_results) is distinct from 'array' then
    raise exception 'fn_accountant_charge_audit_record(results[]): an array of audit results is required';
  end if;
  for x in select e from jsonb_array_elements(p_results) e loop
    insert into public.charge_audit (transaction_id, audited_at, livemode, basis, quote_amount, rate, expected_total,
                                     expected_processing, actual_total, actual_fee_fils, diff_aed, shortfall_aed, evidence)
    values ((x->>'transaction_id')::uuid, now(), (x->>'livemode')::boolean, x->>'basis', (x->>'quote_amount')::numeric,
            (x->>'rate')::numeric, (x->>'expected_total')::numeric, (x->>'expected_processing')::numeric,
            (x->>'actual_total')::numeric, (x->>'actual_fee_fils')::bigint,
            round((x->>'actual_total')::numeric - (x->>'expected_total')::numeric, 2),
            (x->>'shortfall_aed')::numeric, coalesce(x->'evidence', '{}'::jsonb))
    on conflict (transaction_id) do update
       set audited_at = now(), livemode = excluded.livemode, basis = excluded.basis, quote_amount = excluded.quote_amount,
           rate = excluded.rate, expected_total = excluded.expected_total, expected_processing = excluded.expected_processing,
           actual_total = excluded.actual_total, actual_fee_fils = excluded.actual_fee_fils, diff_aed = excluded.diff_aed,
           shortfall_aed = excluded.shortfall_aed, evidence = excluded.evidence,
           -- a difference that changed is a new difference: its old resolution no longer covers it
           resolved_at = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolved_at end,
           resolution = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolution end;
    n := n + 1;
  end loop;

  -- Every unresolved LIVE-mode difference is a finding, whether or not it was audited on this run.
  -- 19 Oct 2026: a Stripe test-mode charge moved no money; its audit stays recorded in charge_audit, not raised.
  for r in select a.*, coalesce(cu.is_demo, false) demo from public.charge_audit a
             join public.transactions t on t.id = a.transaction_id left join public.customers cu on cu.id = t.customer_id
            where abs(a.diff_aed) >= 0.01 and a.resolved_at is null and a.livemode loop
    v_items := v_items || jsonb_build_object('item', 'charge:' || r.transaction_id,
      'owner_seat', 'accountant', 'subject', 'stripe_checkout',
      'title', case when r.diff_aed > 0
                    then 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || r.diff_aed || ' more than the formula''s AED ' || r.expected_total
                    else 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || abs(r.diff_aed) || ' less than the formula''s AED ' || r.expected_total end,
      'blast', case when r.diff_aed > 0 then 'customer_facing' else 'agent_facing' end, 'affected', 1,
      'demo', r.demo or not r.livemode,
      'evidence', to_jsonb(r) - 'demo' || jsonb_build_object('formula', 'supabase/functions/_shared/reveal_fee.ts revealChargeFor'));
  end loop;

  -- Systematic: the same direction too often inside thirty days is the formula or a rate, not a sale.
  select num_value::int into v_sys from public.gl_settings where key = 'charge_audit_systematic_count';
  foreach v_sign in array array['over', 'under'] loop
    if (select count(*) from public.charge_audit a
         where a.livemode and a.audited_at > now() - interval '30 days'
           and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) >= coalesce(v_sys, 3) then
      v_rep := public.fn_support_report_to_ceo('charge_audit_systematic:' || v_sign || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'),
        'serious',
        'Reveal charges are systematically ' || v_sign || ' the formula: ' || (select count(*) from public.charge_audit a
          where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) || ' sale(s) in 30 days',
        jsonb_build_object('direction', v_sign, 'sales', (select jsonb_agg(jsonb_build_object('transaction_id', a.transaction_id,
            'expected', a.expected_total, 'actual', a.actual_total, 'diff', a.diff_aed, 'basis', a.basis))
          from public.charge_audit a where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01)))),
        '[]'::jsonb,
        'A rate in supabase/functions/_shared/reveal_fee.ts or a Stripe price has moved: every sale is affected, not one. Decide the correction; the accountant refunds any overcharge on your approval and keeps auditing daily.',
        p_review_in => interval '1 day', p_source_agent => 'accountant');
    end if;
  end loop;

  return jsonb_build_object('audited', n, 'findings', public.fn_accountant_duty_settle('charge_audit', v_items));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_accountant_expense_duty(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_grace int := (select num_value::int from public.gl_settings where key = 'renewal_receipt_grace_days');
  v_items jsonb := '[]'::jsonb; v_list jsonb; v_n int; v_gaps jsonb; n_next int; v_vouched jsonb; v_demo boolean;
begin
  if v_grace is null then raise exception 'fn_accountant_expense_duty: gl_settings.renewal_receipt_grace_days is missing'; end if;

  -- (a) next_due from the latest receipt, for every recurring cost on a known cadence.
  update public.expenses e
     set next_due = (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date
    from (select lower(vendor) v, max(charged_on) last_charged from public.expense_entries group by 1) r
   where e.active and e.cadence in ('monthly', 'annual') and r.v = lower(e.vendor)
     and e.next_due is distinct from (coalesce(r.last_charged, e.expense_date)
                     + case e.cadence when 'annual' then interval '1 year' else interval '1 month' end)::date;
  get diagnostics n_next = row_count;

  -- (b) Booked with no document behind it. 14 Sep 2026: an expense the founder vouched for (doc_kind
  -- 'founder_statement', allowed only on source founder_reported with his words in doc_note — expense 122,
  -- the DET licence: "its ok no need for it. just note down the number of 1200 AED") is documented by his
  -- word and is listed, not asked for. ZZ DEMO expenses are their own finding, so a rehearsal never judges,
  -- or is judged by, a real row (scripts/sql/an_expense_the_founder_vouches_for_is_documented_by_his_word.sql).
  select coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'amount', amount, 'currency', currency,
                                               'statement', doc_note) order by id), '[]'::jsonb)
    into v_vouched from public.expense_entries where coalesce(btrim(doc_path), '') = '' and doc_kind = 'founder_statement';
  foreach v_demo in array array[false, true] loop
    select count(*), coalesce(jsonb_agg(jsonb_build_object('entry', id, 'vendor', vendor, 'charged_on', charged_on,
                                                           'amount', amount, 'currency', currency) order by id), '[]'::jsonb)
      into v_n, v_list from public.expense_entries
     where coalesce(btrim(doc_path), '') = '' and doc_kind is distinct from 'founder_statement'
       -- 19 Oct 2026: the daily OpenRouter accrual is measured from usage; no receipt ever exists for it.
       and coalesce(source, '') <> 'accountant:openrouter_daily'
       and ((coalesce(vendor, '') || ' ' || coalesce(note, '')) ~* 'zz[ _-]?demo') = v_demo;
    if v_n > 0 then
      v_items := v_items || jsonb_build_object('item', case when v_demo then 'no_document:zz_demo' else 'no_document' end,
        'owner_seat', 'accountant', 'subject', 'expense_entries', 'demo', v_demo,
        'title', v_n || case when v_demo then ' ZZ DEMO' else '' end || ' booked expense(s) have no receipt or invoice behind them',
        'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('entries', v_list,
          'documented_by_founder_statement', v_vouched,
          'remedy', 'forward each receipt to expenses@mail.quotesdone.com; the sweep attaches it by vendor, amount and date'));
    end if;
  end loop;

  -- (c) A vendor the founder named that has never been billed through the mailbox.
  select count(*), coalesce(jsonb_agg(v order by v), '[]'::jsonb) into v_n, v_list
    from public.decision_policy d, jsonb_array_elements_text(d.value) v
   where d.key = 'accountant_expected_subscription_vendors'
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(v))
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(v));
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'never_billed', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', 'No receipt has ever reached the accountant for ' || v_n || ' of the company''s own subscriptions: '
               || (select string_agg(x, ', ') from jsonb_array_elements_text(v_list) x),
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('vendors', v_list,
        'remedy', 'forward one receipt per vendor to expenses@mail.quotesdone.com, or record the vendor in vendor_billing_ended if it bills elsewhere'));
  end if;

  -- (d) A renewal that should have been charged and has no receipt.
  select count(*), coalesce(jsonb_agg(jsonb_build_object('vendor', e.vendor, 'renewed_on', e.next_due, 'amount', e.amount,
                                                         'currency', e.currency, 'cadence', e.cadence) order by e.vendor), '[]'::jsonb)
    into v_n, v_list
    from public.expenses e
   where e.active and e.next_due is not null and e.next_due + v_grace < v_as_of
     and not exists (select 1 from public.expense_entries x where lower(x.vendor) = lower(e.vendor) and x.charged_on >= e.next_due - 3)
     and not exists (select 1 from public.vendor_billing_ended b where lower(b.vendor) = lower(e.vendor));
  if v_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'renewal_receipt', 'owner_seat', 'accountant', 'subject', 'expenses',
      'title', v_n || ' subscription renewal(s) fell due more than ' || v_grace || ' days ago with no receipt',
      'blast', 'internal', 'affected', v_n, 'evidence', jsonb_build_object('renewals', v_list,
        'remedy', 'forward the renewal receipt, or mark the subscription inactive in expenses if it was cancelled'));
  end if;

  -- (e) The vendor-side gaps fn_accountant_receipt_cadence_gaps already measures, now owned.
  v_gaps := public.fn_accountant_receipt_cadence_gaps(v_as_of);
  if coalesce((v_gaps->>'suspected_missing')::int, 0) > 0 then
    v_items := v_items || jsonb_build_object('item', 'cadence_gaps', 'owner_seat', 'accountant', 'subject', 'expense_entries',
      'title', (v_gaps->>'suspected_missing') || ' suspected missing receipt(s): a vendor skipped a month, went quiet, or billed once without a recorded reason',
      'blast', 'internal', 'affected', (v_gaps->>'suspected_missing')::int, 'evidence', v_gaps);
  end if;

  return jsonb_build_object('as_of', v_as_of, 'next_due_updated', n_next,
    'documented_by_founder_statement', v_vouched,
    'findings', public.fn_accountant_duty_settle('expenses', v_items));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_backup_coverage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_not_done int; v_ids jsonb; v_abandoned int; v_unqueued int; v_unq_err text; v_last_ok timestamptz;
  v_conv jsonb; v_conv_fn text := 'public.fn_conversation_retention' || '_breaches(interval)';
  v_refile int; v_fail text[] := '{}';
begin
  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]'::jsonb) into v_not_done, v_ids
    from (select d.id, row_number() over (order by d.id) rn from public.doc_backups d
           where d.status <> 'done' and d.entity <> 'zz_demo'
             -- 19 Oct 2026: retention moves only a verified copy into these; a stuck prune is a backup_prune finding.
             and d.status not in ('prune_pending', 'pruning', 'pruned')
             and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%')
             and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours') x;
  select count(*) into v_abandoned from public.doc_backups where status = 'abandoned' and coalesce(error, '') like 'abandoned:%';
  if v_not_done > 0 then v_fail := array_append(v_fail, 'not_done_after_48h'); end if;

  begin
    v_unqueued := public.fn_enqueue_doc_backups();
    raise exception using errcode = 'QDRBK', message = 'roll back the coverage measurement';
  exception
    when sqlstate 'QDRBK' then null;
    when read_only_sql_transaction then v_unq_err := 'not measurable in a read-only transaction';
    when others then v_unq_err := left(sqlerrm, 200);
  end;
  select max(started_at) into v_last_ok from public.agent_runs where agent = 'dropbox_backup' and status = 'ok';
  if (v_unqueued > 0 and coalesce(v_last_ok, '-infinity') < now() - interval '48 hours')
     or (v_unq_err is not null and v_unq_err <> 'not measurable in a read-only transaction') then
    v_fail := array_append(v_fail, 'sources_without_a_row');
  end if;

  if to_regprocedure(v_conv_fn) is not null then
    begin
      execute 'select ' || replace(v_conv_fn, '(interval)', '($1)') into v_conv using interval '48 hours';
    exception when others then v_conv := jsonb_build_object('error', left(sqlerrm, 200));
    end;
    if coalesce((v_conv->>'total')::int, 0) > 0 or v_conv ? 'error' then v_fail := array_append(v_fail, 'conversation_retention'); end if;
  end if;

  select count(*) into v_refile from public.agent_actions
   where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' in ('backup.refile', 'backup.remediate')
     and (status = 'failed' or (status = 'pending' and created_at < now() - interval '48 hours'));
  if v_refile > 0 then v_fail := array_append(v_fail, 'refile_not_verified_in_48h'); end if;

  return jsonb_build_object(
    'ok', cardinality(v_fail) = 0, 'failing', to_jsonb(v_fail),
    'not_done_after_48h', v_not_done, 'not_done_ids', v_ids, 'abandoned_documented', v_abandoned,
    'sources_without_a_row', v_unqueued, 'sources_error', v_unq_err, 'last_ok_backup', v_last_ok,
    'conversation_retention', coalesce(v_conv, jsonb_build_object('checked', false, 'reason', 'function not installed')),
    'refiles_open_past_48h', v_refile, 'measured_at', now());
end $function$;

CREATE OR REPLACE FUNCTION public.fn_backup_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_last timestamptz; v_status text; v_stale boolean; v_open int; v_subject_rows int;
  v_cov jsonb; v_cov_ok boolean; v_cov_open int := 0; v_date text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  v_hb timestamptz; v_hb_silent boolean;
  -- when this watcher started expecting a daily check (the apply of this file)
  c_hb_since constant timestamptz := '2026-09-14 15:00:00+00';
  c_agents constant text[] := array['dropbox_backup','fn:dropbox_backup'];
begin
  select count(*) into v_subject_rows from agent_runs where agent = any(c_agents);
  if v_subject_rows = 0 then
    return jsonb_build_object(
      'ok', false,
      'reason', 'subject_not_found',
      'watched', c_agents,
      'detail', 'No run of any watched backup agent has ever been recorded, so this watcher cannot '
             || 'tell a stopped backup from a renamed one. It alerts nobody rather than reporting '
             || 'catastrophe from an empty lookup. Check the agent name before the backup.');
  end if;

  select started_at, status into v_last, v_status
    from agent_runs where agent = any(c_agents) order by started_at desc limit 1;

  -- HEARTBEAT: silence of the check is an alarm, never a clean bill.
  select max(started_at) into v_hb from agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'dropbox_daily_check' and status in ('ok','warn');
  v_hb_silent := coalesce(v_hb, c_hb_since) < now() - interval '26 hours';
  if v_hb_silent then
    perform public.fn_support_report_to_ceo(
      'it_backup_heartbeat:' || v_date, 'serious',
      'The IT engineer''s daily Dropbox check has not run for '
        || round(extract(epoch from (now() - coalesce(v_hb, c_hb_since))) / 3600)::text || ' hours',
      jsonb_build_object('last_daily_check', v_hb, 'expected_since', c_hb_since, 'watched', 'agent_runs it_engineer job dropbox_daily_check'),
      '[]'::jsonb,
      'Find out why the daily check is not running (resilience_ping -> fn_it_backup_tick -> dropbox_backup mode reconcile). Until it runs, nothing confirms that the backup is complete.',
      p_review_in => interval '1 day', p_source_agent => 'it_engineer');
  end if;

  v_cov := public.fn_backup_coverage();
  v_cov_ok := coalesce((v_cov->>'ok')::boolean, false);
  if not v_cov_ok then
    select count(*) into v_cov_open from agent_actions
     where kind = 'backup_coverage' and agent = 'it_engineer' and coalesce(status,'') in ('pending','needs_review')
       and created_at > now() - interval '20 hours';
    if v_cov_open = 0 then
      insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
      values('it_engineer','backup_coverage','pending','medium',
        'Dropbox backup coverage failing: ' || (v_cov->>'failing'),
        'Something that should be in Dropbox has not reached it within 48 hours: '
        || (v_cov->>'not_done_after_48h') || ' queued row(s) not done, '
        || coalesce(v_cov->>'sources_without_a_row','unknown') || ' source(s) with no row, '
        || (v_cov->>'refiles_open_past_48h') || ' refile(s) not verified. Rows: ' || (v_cov->>'not_done_ids') || '.',
        'doc_backups', v_cov);
      -- 19 Oct 2026: one condition is one report. While an earlier escalation is still accepted the CEO holds it;
      -- a new day's key is raised only after that one is completed (12 sat accepted, one per day, before this).
      if not exists (select 1 from public.support_ceo_report
                      where idempotency_key like 'dropbox_backup_escalation:%' and status = 'accepted') then
      perform public.fn_support_report_to_ceo(
        'dropbox_backup_escalation:' || v_date, 'serious',
        'Dropbox backup coverage has been failing for over 48 hours (' || (v_cov->>'failing') || ')',
        v_cov,
        coalesce((select jsonb_agg(jsonb_build_object('handoff_id', id, 'status', status, 'type', detail->>'type'))
                    from agent_actions where kind = 'handoff' and detail->>'type' in ('backup.refile','backup.remediate') and status <> 'done'), '[]'::jsonb),
        'Decide whether the missing documents need the founder''s Dropbox checked by hand or the filing corrected. The IT engineer has raised it and handed each missing file to the sales engineer to refile; this is past 48 hours, which is why it reaches you.',
        p_review_in => interval '1 day', p_source_agent => 'it_engineer');
      end if;
    end if;
  end if;

  v_stale := (v_last < now() - interval '26 hours') or (coalesce(v_status,'') = 'error');
  if not v_stale then
    return jsonb_build_object('ok', v_cov_ok and not v_hb_silent, 'last', v_last, 'status', v_status, 'watched', c_agents,
                              'coverage', v_cov, 'coverage_alerted', not v_cov_ok and v_cov_open = 0,
                              'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
  end if;

  select count(*) into v_open from agent_actions
   where kind = 'backup_alert' and coalesce(status,'') in ('pending','needs_review')
     and created_at > now() - interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values('it_engineer','backup_alert','pending','high',
      'Document backup to Dropbox has failed or is overdue',
      'The Dropbox document mirror has not completed successfully in the last 26 hours (last: '
      || coalesce(v_last::text,'never') || ', status: ' || coalesce(v_status,'unknown')
      || '). Check the dropbox_backup function and its logs. This concerns stored DOCUMENTS only — '
      || 'the managed Postgres backups are outside this database and are not covered by this check.',
      'agent_runs', jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    insert into security_events(kind, severity, source, subject, detail)
    values('backup_overdue','high','backup','dropbox document mirror',
      jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    if v_last < now() - interval '48 hours' then
      perform public.fn_notify_founder(
        'Document backup failing after retry: no successful Dropbox mirror for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours',
        'The Dropbox document mirror has now been failing for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours (last run: '
        || v_last::text || ', status: ' || coalesce(v_status,'unknown')
        || '). This covers stored DOCUMENTS — supplier files, quotes, drawings. The managed Postgres '
        || 'backups are a separate system outside this database and this alert says nothing about '
        || 'them either way. Verify the dropbox_backup function.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;
  end if;

  return jsonb_build_object('alerted', true, 'last', v_last, 'status', v_status,
                            'existing_open', v_open, 'watched', c_agents, 'coverage', v_cov,
                            'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_it_loop_reverify()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0; n_playbook int := 0; v_class text; n_reports int := 0;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Review finding, 18 Sep 2026: with no such row v_window is null, `now() > created_at + null` is
  -- null, and EVERY handoff fell quietly into 'waiting' -- the loop would never escalate again and
  -- would say nothing about why. A missing conversation row is a configuration fault, not a default.
  if v_window is null then
    raise exception 'fn_it_loop_reverify: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  -- 22 Sep 2026: a handoff closed anywhere but the close branch below -- fn_it_attach_learning is the
  -- one other door -- left its CEO report 'accepted' for good. The report follows its handoff here.
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer re-verified: handoff ' || a.id || ' is closed ('
           || coalesce(a.evidence->>'verdict', 'learning recorded by ' || coalesce(a.evidence->>'learning_recorded_by', 'an unnamed recorder')) || ').'
    from public.agent_actions a
   where r.status = 'accepted' and r.idempotency_key ~ '^it_loop:[0-9]+$'
     and a.id = substr(r.idempotency_key, 9)::bigint and a.kind = 'handoff' and a.status = 'done';
  get diagnostics n_reports = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;

    if v_cleared then
      -- A new bug that has cleared needs what was learned (trigger z62). Where the playbook already
      -- covers this failure class, the IT engineer records it from there and closes now; where it
      -- does not, the handoff waits for a human, which is what the gate is for.
      v_class := public.fn_it_learning_from_playbook(h.id);
      if v_class is not null then n_playbook := n_playbook + 1; end if;
    end if;

    if v_cleared and exists (select 1 from public.it_incident i where i.handoff_id = h.id
                              and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = ''
                                   or coalesce(btrim(i.regression_check), '') = ''
                                   or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''))) then
      if not (h.detail ? 'awaiting_learning') then
        update public.agent_actions set detail = detail || jsonb_build_object('awaiting_learning', now()) where id = h.id;
        update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where handoff_id = h.id and ended_at is null;
      end if;
      n_wait := n_wait + 1;
    elsif v_cleared then
      update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, now()), updated_at = now() where handoff_id = h.id;
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'learning_from_playbook', v_class,
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    -- 19 Oct 2026: an info finding (affected 0, title 'info:...') is a note, not a fault; it waits, never escalates.
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window
          and not (coalesce(f.affected, 1) = 0 and coalesce(f.title, '') ilike 'info:%') then
      v_rep := public.fn_support_report_to_ceo(
        'it_loop:' || h.id,
        case when h.detail->>'severity' = 'critical' then 'critical' else 'serious' end,
        'Still broken after ' || h.agent || '''s reply window: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 160),
        jsonb_build_object('handoff_id', h.id, 'issue_key', h.detail->>'issue_key', 'seat', h.agent,
                           'reply', h.evidence, 'finding', to_jsonb(f)),
        jsonb_build_array(jsonb_build_object('action', 'handed to ' || h.agent, 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Decide the remedy, or record that this is a new bug for the founder. The IT engineer keeps re-checking and closes the loop only when the finding is gone.',
        p_review_in => interval '2 hours', p_source_agent => 'it_engineer');
      if not coalesce((v_rep->>'ok')::boolean, false) then
        raise exception 'fn_it_loop_reverify: the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
      end if;
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
       where id = h.id;
      perform public.fn_ceo_it_escalation_decide((v_rep->>'report_id')::bigint);
      n_esc := n_esc + 1;
    else
      n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait, 'learned_from_playbook', n_playbook,
                            'reports_completed', n_reports);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_it_handoff_sla_items(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           -- The contract's own clock: a month directive is closed by the CEO at its due_at (month end),
           -- so it is late only after that, never two days after it was sent.
           coalesce((a.detail->>'due_at')::timestamptz, a.created_at) due,
           -- A review step held by the model hold has not been answered; it waits on the hold, which is
           -- the founder's standing OpenRouter limit and is reported by the review_independence duty.
           coalesce(a.evidence#>>'{step,action}', '') = 'held' held,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and not h.held and now() > h.due + h.w + interval '24 hours' then 'unclosed'
        -- 19 Oct 2026: an answered it.finding whose problem is still there is the open queue itself
        -- (fn_it_loop_reverify escalates it); repeating it here as an SLA item was a duplicate.
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'marketing')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                       else ' were answered but never closed by the seat that sent them' end
                    || ' past the ' || g.w || ' window'
                    || '; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$function$;

CREATE OR REPLACE FUNCTION public.fn_support_reply_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_cut timestamptz; v_founder text[]; c text; v_n int; v_oldest timestamptz; v_ids jsonb; v_median numeric;
  v_out jsonb := '{}'::jsonb;
begin
  v_cut := now() - make_interval(secs => (v_sla * 3600)::double precision);
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  foreach c in array array['email', 'whatsapp', 'chat'] loop
    if c = 'email' then
      select count(*), min(m.created_at), coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.inbound_messages m
       where m.created_at > now() - interval '30 days' and m.created_at < v_cut and m.replied_at is null
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
         -- 19 Oct 2026: a no-reply sender cannot be answered, and calendar+ is the founder's own approval inbox.
         and coalesce(m.to_email, '') !~* '^calendar\+' and coalesce(m.from_email, '') !~* 'no-?reply'
         and not public.fn_is_demo_email(m.from_email);
      select percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60) into v_median
        from public.inbound_messages m
       where m.replied_at is not null and m.created_at > now() - interval '7 days'
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant';
    elsif c = 'whatsapp' then
      select count(*), min(w.created_at), coalesce(jsonb_agg(w.id order by w.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.wa_messages w
       where w.created_at > now() - interval '30 days' and w.created_at < v_cut
         and coalesce(btrim(w.inbound), '') <> '' and (w.reply is null or not coalesce(w.sent, false))
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder));
      v_median := null;   -- the WhatsApp reply is written in the same row as the inbound: minutes are not recorded
    else
      select count(*), min(g.created_at), coalesce(jsonb_agg(g.id order by g.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.assistant_logs g
        left join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and g.created_at > now() - interval '30 days' and g.created_at < v_cut
         and coalesce(t.status, 'open') not in ('done', 'cancelled');
      select percentile_cont(0.5) within group (order by extract(epoch from t.updated_at - g.created_at) / 60) into v_median
        from public.assistant_logs g join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and t.status = 'done' and t.updated_at > g.created_at and g.created_at > now() - interval '7 days';
    end if;

    if v_n > 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:' || c,
        v_n || ' ' || c || ' message(s) have waited more than ' || v_sla || ' h for a first reply (oldest '
          || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> ' || c, 'customer_facing', v_n,
        jsonb_build_object('channel', c, 'sla_hours', v_sla, 'waiting', v_n, 'oldest', v_oldest,
                           'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                           'median_first_reply_minutes_7d', round(v_median), 'owner_seat', 'customer_support', 'duty', 'reply_time'),
        '{}'::text[], array['whether the customer was answered on another channel'], 'customer_support');
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:' || c and closed_at is null) then
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        'every ' || c || ' message older than ' || v_sla || ' h has a first reply');
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end
$function$;

-- Verdict (read-only): each fix is in the live body, and the two routines that can be called read-only answer
-- without the false items.
select case when array_length(f.why, 1) is null then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f.why, '; ') end as verdict
  from (select array_remove(array[
    case when (select prosrc from pg_proc where oid = 'public.fn_accountant_charge_audit_record(jsonb)'::regprocedure) !~ 'resolved_at is null and a\.livemode loop'
         then 'charge audit still raises test-mode charges' end,
    case when (select prosrc from pg_proc where oid = 'public.fn_accountant_expense_duty(date)'::regprocedure) !~ 'accountant:openrouter_daily'
         then 'expense duty still counts the OpenRouter accrual' end,
    case when (select prosrc from pg_proc where oid = 'public.fn_backup_coverage()'::regprocedure) !~ 'prune_pending'
           or exists (select 1 from jsonb_array_elements_text(public.fn_backup_coverage()->'not_done_ids') x
                        join public.doc_backups d on d.id = x::bigint where d.status in ('prune_pending', 'pruning', 'pruned'))
         then 'backup coverage still counts retention' end,
    case when (select prosrc from pg_proc where oid = 'public.fn_backup_watch()'::regprocedure) !~ 'dropbox_backup_escalation:%'' and status = ''accepted'''
         then 'backup escalation still raised every day' end,
    case when (select prosrc from pg_proc where oid = 'public.fn_it_loop_reverify()'::regprocedure) !~ 'info:%'
         then 'IT loop still escalates info findings' end,
    case when exists (select 1 from jsonb_array_elements(public.fn_it_handoff_sla_items()) e where e->>'item' like '%:open_over_24h')
         then 'handoff SLA still repeats open findings' end,
    case when (select prosrc from pg_proc where oid = 'public.fn_support_reply_watch_tick()'::regprocedure) !~ 'calendar'
         then 'reply watch still counts no-reply and calendar+ mail' end
  ], null) why) f;
