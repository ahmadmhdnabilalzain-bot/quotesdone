-- THE PAYMENT EXCEPTION AND THE CEO'S DAY NAME THE KIND THEY SEND THE FOUNDER (it_engineer, 17 Nov 2026; for the accountant and
-- the ceo, whose routines these are).
--
-- MEASURED 17 Nov 2026: the_founder_is_emailed_exceptions_only.test.mjs (rule 2: every routine that calls fn_notify_founder
-- names its kind with p_kind =>, so the check can read the kind and prove it is registered) failed on two routines that pass
-- all six arguments positionally:
--   fn_accountant_escalates_payment_exception   a_paid_reveal_is_reconciled_booked_and_timed_..._it_is_paid.sql   kind finance_alert
--   fn_ceo_daily_summary_to_the_founder          the_ceo_thinks_plans_and_orders_every_week.sql                    kind ceo_daily_summary
-- The positions are right and both kinds are registered (SELECT on founder_mail_policy 17 Nov: allowed_to_email true, owners
-- accountant and ceo), so nothing was mis-sent; the defect is that the rule could not see it. Unseen since 15 Nov because the
-- gate skips npm-test.
--
-- WHAT THIS DOES: re-issues the two routines from their LIVE text (pg_get_functiondef read 17 Nov; md5 of prosrc
-- dc9b6cb5d5a24a4f0819ce00d6108a4f and ce7dc46bd4da55de58dd6be5760b30f2, equal to the repository's files before this one),
-- changing ONLY the fn_notify_founder call to name every argument. CREATE OR REPLACE keeps the closed ACL; the revokes repeat it.
-- NOT CHANGED: what either routine decides, sends or returns; fn_notify_founder; the two owning files (this file follows them
-- in MANIFEST and becomes the canonical definition of these two routines).
-- prevented by: scripts/checks/the_founder_is_emailed_exceptions_only.test.mjs (repository rule 2), and this file's _probe.sql.
-- Pending: scripts/sql/pending/the_payment_exception_and_the_ceo_day_name_the_kind_they_send_the_founder.txt
set local lock_timeout = '3s';
CREATE OR REPLACE FUNCTION public.fn_accountant_escalates_payment_exception(p_tx uuid, p_by text, p_choice text, p_reason text, p_final boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.accountant_reveal_payment_check; t public.transactions; v_p jsonb; v_ceo bigint; v_se bigint; o record; v_n int; v_f jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));   -- lock order: item 6b
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no check for ' || p_tx); end if;
  if c.ceo_handoff_id is not null then return jsonb_build_object('ok', true, 'already', c.ceo_handoff_id); end if;
  select * into t from public.transactions where id = p_tx;
  select * into o from public.fn_payment_check_owed_back(p_tx);
  v_n := greatest(c.exception_count, 1);
  v_p := jsonb_build_object('transaction_id', p_tx, 'quote_id', t.quote_id, 'inquiry_id', t.inquiry_id, 'customer_id', t.customer_id,
    'occurrence', v_n, 'final', p_final, 'findings', c.findings, 'accountant_choice', p_choice,
    'accountant_reason', left(coalesce(p_reason, ''), 2000), 'decided_by', p_by,
    'owed_back_fils', nullif(o.amount_fils, 0), 'owed_back_why', o.why,
    'our_invoice_no', c.our_invoice_no, 'stripe_invoice_number', c.stripe_invoice_number, 'payment_ref', c.payment_ref,
    'expected_fee_fils', c.expected_fee_fils, 'charged_fils', c.charged_fils, 'opened_at', c.opened_at,
    'stripe_snapshot', c.stripe_snapshot);
  if c.is_test_mode then
    perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'ceo', v_p);
    perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'sales_engineer', v_p);
    perform public.fn_demo_shadow_record('escalation', 'payment.exception', 'accountant', 'ceo', v_p);
  else
    v_ceo := public.fn_seat_handoff('accountant', 'ceo', 'payment.exception', 'transactions', p_tx::text || '#' || v_n, v_p);
    v_se  := public.fn_seat_handoff('accountant', 'sales_engineer', 'payment.exception', 'transactions', p_tx::text || '#' || v_n, v_p);
    v_f := public.fn_notify_founder(
      p_event => 'Payment exception on reveal ' || left(p_tx::text, 8) || coalesce(': AED ' || to_char(nullif(o.amount_fils, 0) / 100.0, 'FM999,990.00') || ' ' || o.why, ''),
      p_detail => 'A reveal payment did not reconcile and is with the CEO now (' || coalesce(p_choice, '?') || ', by ' || coalesce(p_by, '?') || ').' || E'\n'
      || 'Findings: ' || coalesce((select string_agg(x->>'fact', '; ') from jsonb_array_elements(c.findings) x), 'none') || E'\n'
      || 'Invoice ' || coalesce(c.our_invoice_no, '?') || ', payment ' || coalesce(c.payment_ref, '?') || '. Nothing is refunded without the CEO''s decision.',
      p_level => 'high', p_kind => 'finance_alert', p_dedupe_key => 'payment_exception:' || p_tx || ':' || v_n, p_owner_agent => 'accountant');
  end if;
  update public.accountant_reveal_payment_check
     set decided_by = p_by, decision = p_choice, decision_reason = left(coalesce(p_reason, ''), 2000),
         escalated_at = now(), final_question = p_final, ceo_handoff_id = coalesce(v_ceo, -1)
   where transaction_id = p_tx;
  return jsonb_build_object('ok', true, 'ceo_handoff_id', v_ceo, 'sales_engineer_handoff_id', v_se, 'founder', v_f, 'choice', p_choice, 'occurrence', v_n);
end $function$;
revoke execute on function public.fn_accountant_escalates_payment_exception(uuid, text, text, text, boolean) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_ceo_daily_summary_to_the_founder(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text := 'ceo_daily_summary:' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'); v_r jsonb;
begin
  if (p_at at time zone 'Asia/Dubai')::time < time '07:00' then return jsonb_build_object('told', false, 'reason', 'before 07:00 Dubai'); end if;
  if exists (select 1 from public.founder_alerts f where f.dedupe_key = v_key) then return jsonb_build_object('told', false, 'reason', 'already told today'); end if;
  v_r := public.fn_notify_founder(p_event => 'The CEO''s day: supplier coverage and decisions',
                                  p_detail => public.fn_ceo_daily_summary_text(p_at - interval '24 hours') || public.fn_ceo_plan_summary_text(p_at - interval '24 hours'),
                                  p_level => 'info', p_kind => 'ceo_daily_summary', p_dedupe_key => v_key, p_owner_agent => 'ceo');
  return jsonb_build_object('told', true, 'result', v_r);
end $function$;
revoke execute on function public.fn_ceo_daily_summary_to_the_founder(timestamptz) from public, anon, authenticated;
