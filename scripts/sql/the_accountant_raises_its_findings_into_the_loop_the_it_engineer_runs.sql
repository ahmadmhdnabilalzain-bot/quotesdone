-- THE ACCOUNTANT RAISES ITS FINDINGS INTO THE LOOP THE IT ENGINEER RUNS, AND ITS NOTICES ARE WRITTEN
-- BY THE SALES ENGINEER AND CARRIED BY CUSTOMER SUPPORT.
--
-- Assigned: accountant (the finding ledger entries and the notices it asks for). The words a supplier
-- reads are the sales_engineer's (fn_sales_engineer_writes_money_notice); the send is customer_support's.
-- fn_seat_handoff_act is the loop core the it_engineer's file owns; this file carries its live body with
-- ONE added branch, signed for the it_engineer in the commit.
--
-- The founder, 14 Sep 2026: "yea add them all" (the accountant's eight duties), "always make sure things
-- are in loop. nothing literally should ever be a one way communication", and "just ignore the corporate
-- tax matter for companies" (duty 5 is not built: no table, no warning, no question).
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * The IT engineer's loop (the_it_engineer_closes_every_loop_it_opens.sql) already turns an open,
--     actionable public.it_engineer_finding into an it.finding handoff to the seat named in
--     evidence.owner_seat, gives it a four-hour reply window (seat_handoff_window), lets only the
--     it_engineer close it after the finding itself is closed, escalates to the CEO past the window,
--     and has the CEO send the founder ONE deduped it_new_bug email through customer_support. A ZZ DEMO
--     finding never reaches him. The finding table carries raised_by and a free evidence object.
--   * The accountant has no finding ledger of its own and none is built: a second ledger with a second
--     escalation path is exactly the duplication the brief forbids. The accountant writes into
--     it_engineer_finding with raised_by 'accountant.<duty>' and issue keys 'acct:<duty>:<item>', and
--     the IT loop carries every one of them round. The accountant's own duty check is the
--     re-verification: an item that stops failing is closed by the same settle call that raised it,
--     and the IT loop then closes the handoff.
--   * fn_it_duty_settle does the same for the IT engineer but stamps 'it_engineer.<duty>' and
--     'IT engineer duty' on every row, which would file the accountant's findings under the wrong seat.
--     fn_accountant_duty_settle below is that routine with the accountant's name on it; both call the
--     one upsert and the one close.
--   * The sales engineer has no words for a reminder, a renewal notice or dunning. Adding handoff TYPES
--     would mean redefining fn_seat_handoff_types, whose list three files share and whose TypeScript
--     mirror (payment_handoffs.ts) a check compares against a fixed file list. Instead the accountant
--     sends the EXISTING conversations ('nonresponse.charge_raised', 'subscription.due') with a
--     detail.notice naming which notice it is, and fn_seat_handoff_act routes a sales_engineer handoff
--     that carries a notice to fn_sales_engineer_writes_money_notice. Every conversation, producer and
--     handler the payments check knows about is unchanged.
--
-- WHAT THIS DOES NOT DO. It does not write any duty's detector; each duty is its own file and calls
-- fn_accountant_duty_settle. It seeds no reminder or final-demand wording: those are configuration rows
-- the collections file owns, driven by docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_raises_its_findings_into_the_loop_the_it_engineer_runs.sql --apply --ddl

-- ── 0. HIS WORDS, IN THE REGISTER ─────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, evidence, note)
select '2026-09-14T00:00:00Z', x.i, x.s, x.st, x.ev, x.n
  from (values
    ('yea add them all', 'the accountant''s eight duties', 'open', null,
     'The eight duties the coordinator listed on 14 Sep 2026: bank reconciliation, non-response charge collection, supplier subscription billing, the VAT threshold watch, the corporate tax calendar, expenses and receipts, Stripe disputes, the monthly close. Duty 5 was withdrawn by the founder the same day.'),
    ('yea add them', 'three more accountant duties', 'open', null,
     'Duties 9-11, 14 Sep 2026: the refund reserve (money a refund could still take back is held, not earned), the daily charge audit of every reveal against what Stripe took, and the automatic booking of Stripe fees, the VAT on them and the Mashreq charge (bank entries as drafts while the founder''s bank-booking hold stands).'),
    ('just ignore the corporate tax matter for companies', 'no corporate tax calendar', 'done',
     'Nothing was built for corporate tax: no table, no warning, no founder question. scripts/sql/the_accountant_raises_its_findings_into_the_loop_the_it_engineer_runs.sql names the omission in its header.',
     'Withdraws duty 5 of the eight accountant duties.'),
    ('you need to check as per UAE law the deadline for that and accordingly set it. once the deadline is over, the accountant need to issue a proper legal document that i can take to dubai police or court and complain officially. all as per UAE law exactly, i am not gonna hire any lawyer so make sure the form and the wordings is done correctly',
     'supplier charge recovery under UAE law', 'open', null,
     'Duty 2: the reminder and final-demand timeline and wording are configuration rows citing docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md; when the final deadline passes the filing pack goes to the founder and the item stays open until he records the outcome.')
  ) x(i, s, st, ev, n)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. SETTLING A DUTY'S FINDINGS ────────────────────────────────────────────────────────────────
-- p_items: [{item, title, owner_seat, subject, blast, affected, demo, evidence}] — everything failing NOW.
-- Every open acct:<duty>:* finding not in the list is closed in the same call: that close IS the
-- accountant's re-verification, and fn_it_loop_reverify closes the handoff once it sees it.
create or replace function public.fn_accountant_duty_settle(p_duty text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_accountant_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_accountant_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    if coalesce(x->>'owner_seat', '') not in ('accountant', 'sales_engineer', 'customer_support', 'ceo') then
      raise exception 'fn_accountant_duty_settle: item % names owner seat %, which is not a seat the loop can hand to', x->>'item', x->>'owner_seat';
    end if;
    v_key := 'acct:' || p_duty || ':' || (x->>'item');
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'Accountant duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', coalesce(x->>'subject', 'accountant'),
        'raised_by_seat', 'accountant', 'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'accountant.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'acct:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the accountant''s ' || p_duty || ' duty re-checked and no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0), 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_accountant_duty_settle(text, jsonb) from public, anon, authenticated;

-- A duty that raises is itself a finding (the IT loop's fn_it_loop_stage pattern), closed again the
-- first run the duty succeeds. Owner ceo, blast 'monitor': a blind detector is high from the first tick.
create or replace function public.fn_accountant_duty_stage(p_step text, p_error text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_step), '') = '' then raise exception 'fn_accountant_duty_stage: a stage name is required'; end if;
  if p_error is null then
    if exists (select 1 from public.it_engineer_finding where issue_key = 'acct:stage:' || p_step and closed_at is null) then
      perform public.fn_it_engineer_finding_close('acct:stage:' || p_step, 'the accountant''s ' || p_step || ' duty ran cleanly');
    end if;
    return;
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', 'error', now(), now(), jsonb_build_object('job', 'duties', 'stage', p_step), left(p_error, 600));
  perform public.fn_it_engineer_finding_upsert('acct:stage:' || p_step,
    'The accountant''s ' || p_step || ' duty is failing', 'public.fn_accountant_duties', 'monitor', 1,
    jsonb_build_object('stage', p_step, 'error', left(p_error, 600), 'owner_seat', 'ceo', 'subject', 'accountant', 'duty', 'stage'),
    '{}'::text[], array['why the duty raises: ' || left(p_error, 300)], 'accountant.stage');
end $fn$;
revoke execute on function public.fn_accountant_duty_stage(text, text) from public, anon, authenticated;

-- ── 2. A TEMPLATE IS CONFIGURATION, NOT CODE ─────────────────────────────────────────────────────
-- {{name}} is replaced by p_vars->>'name'. A placeholder with no value is left visible rather than
-- blanked, and the caller refuses to send a text that still carries one.
create or replace function public.fn_render_template(p_text text, p_vars jsonb)
returns text language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare k text; v text; r text := p_text;
begin
  if r is null then return null; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p_vars, '{}'::jsonb)) loop
    r := replace(r, '{{' || k || '}}', coalesce(v, ''));
  end loop;
  return r;
end $fn$;
revoke execute on function public.fn_render_template(text, jsonb) from public, anon, authenticated;

-- ── 3. THE SALES ENGINEER'S WORDS FOR THE ACCOUNTANT'S NOTICES ───────────────────────────────────
-- Called only from fn_seat_handoff_act, for a sales_engineer handoff whose detail carries 'notice'.
-- The supplier's language is leads.locale, applied by fn_sales_engineer_writes and customer_support.
create or replace function public.fn_sales_engineer_writes_money_notice(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; v_notice text; v_sup record; v_tpl jsonb; v_vars jsonb;
  v_sub_en text; v_body_en text; v_sub_ar text; v_body_ar text; v_req bigint; v_msg text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.agent <> 'sales_engineer' or not (a.detail ? 'notice') then
    raise exception 'fn_sales_engineer_writes_money_notice: % is not a sales engineer notice handoff', p_id;
  end if;
  d := a.detail; v_notice := d->>'notice';
  select l.id, l.company_name, coalesce(l.claimed_by, l.email) email into v_sup
    from public.leads l where l.id = (d->>'supplier_id')::bigint;
  if coalesce(v_sup.email, '') not like '%@%' then
    return jsonb_build_object('supplier_reachable', false, 'notice', v_notice);
  end if;
  v_vars := d || jsonb_build_object('company', coalesce(v_sup.company_name, ''),
                                   'reveal_ref', left(coalesce(d->>'transaction_id', ''), 8));

  if v_notice in ('charge_reminder', 'final_demand') then
    -- THE WORDING IS THE LEGAL DOCUMENT'S, NOT THIS FILE'S (founder, 14 Sep 2026: "make sure the form
    -- and the wordings is done correctly"). No template row, no send: the handoff fails and says why.
    select value into v_tpl from public.decision_policy
     where key = case v_notice when 'charge_reminder' then 'supplier_charge_reminder_template'
                               else 'supplier_charge_final_demand_template' end;
    if v_tpl is null or coalesce(v_tpl->>'body_en', '') = '' then
      raise exception 'no % template in decision_policy: the wording comes from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md and has not been configured', v_notice;
    end if;
    v_sub_en := public.fn_render_template(v_tpl->>'subject_en', v_vars);
    v_body_en := public.fn_render_template(v_tpl->>'body_en', v_vars);
    v_sub_ar := public.fn_render_template(v_tpl->>'subject_ar', v_vars);
    v_body_ar := public.fn_render_template(v_tpl->>'body_ar', v_vars);
    v_msg := 'nonresponse_' || v_notice;
  elsif v_notice = 'subscription_renewal' then
    v_sub_en := 'Your QuotesDone supplier subscription renews on ' || (d->>'renews_on');
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual QuotesDone supplier subscription is paid until '
      || (d->>'paid_until') || '. The renewal of ' || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee')
      || ' falls due on ' || (d->>'renews_on') || E'.\n\nYou can renew from the Billing section of your supplier portal: https://quotesdone.com/suppliers. Stripe issues the invoice for the payment.\n\nYou keep paying no commission on the jobs you win.';
    v_sub_ar := 'يتجدد اشتراكك كمورّد في QuotesDone في ' || (d->>'renews_on');
    v_body_ar := 'اشتراكك السنوي مدفوع حتى ' || (d->>'paid_until') || '، ويستحق التجديد بقيمة ' || (d->>'fee')
      || ' درهم في ' || (d->>'renews_on') || '. يمكنك التجديد من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_renewal_reminder';
  elsif v_notice = 'subscription_dunning' then
    v_sub_en := 'Reminder ' || (d->>'dunning_no') || ': your QuotesDone subscription is unpaid';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual supplier subscription of '
      || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || ' fell due on ' || (d->>'due_on') || ' and is still unpaid ('
      || (d->>'days_overdue') || E' days).\n\nPlease settle it from the Billing section of your supplier portal: https://quotesdone.com/suppliers. '
      || E'Until it is settled your profile does not receive new customer requests.\n\nIf you have already paid, reply to this email and we will check it against the payment record.';
    v_sub_ar := 'تذكير ' || (d->>'dunning_no') || ': اشتراكك في QuotesDone غير مدفوع';
    v_body_ar := 'استحق اشتراكك السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم في ' || (d->>'due_on') || ' ولم يُسدَّد بعد ('
      || (d->>'days_overdue') || ' يومًا). يُرجى السداد من قسم الفواتير في بوابة المورّد، وحتى السداد لا يتلقى ملفك طلبات جديدة.';
    v_msg := 'subscription_dunning';
  elsif v_notice = 'subscription_payment_failed' then
    v_sub_en := 'Your QuotesDone subscription payment did not go through';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour payment for the annual supplier subscription did not complete, and nothing was charged. '
      || E'You can try again at any time from the Billing section of your supplier portal: https://quotesdone.com/suppliers. If the card was declined, your bank can tell you why, and a different card also works.';
    v_sub_ar := 'لم تكتمل عملية دفع اشتراكك في QuotesDone';
    v_body_ar := 'لم تكتمل عملية دفع الاشتراك السنوي ولم يُخصم أي مبلغ. يمكنك المحاولة مجددًا من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_payment_failed';
  else
    raise exception 'fn_sales_engineer_writes_money_notice: no words for notice %', v_notice;
  end if;

  if v_body_en ~ '\{\{[a-z_]+\}\}' or coalesce(v_body_ar, '') ~ '\{\{[a-z_]+\}\}' then
    raise exception 'notice % for handoff % still carries an unfilled placeholder; nothing was sent', v_notice, p_id;
  end if;
  v_req := public.fn_sales_engineer_writes(v_msg, 'supplier', v_sup.email, v_sup.id, null,
    (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, v_sub_en, v_body_en, v_sub_ar, v_body_ar,
    '{}', v_msg || ':' || (d->>'subject_id'), null,
    jsonb_build_object('transaction_id', d->>'transaction_id', 'due_id', d->>'due_id', 'notice', v_notice));
  return jsonb_build_object('notice', v_notice, 'delivery_request', v_req);
end $fn$;
revoke execute on function public.fn_sales_engineer_writes_money_notice(bigint) from public, anon, authenticated;

-- ── 4. THE LOOP CORE, WITH THE NOTICE BRANCH ─────────────────────────────────────────────────────
-- Live body of fn_seat_handoff_act as defined by the_it_engineer_closes_every_loop_it_opens.sql (read
-- back from production 14 Sep 2026), with ONE branch added before the per-seat dispatch. Whichever file
-- is applied last must carry the delivery.result, it.finding and notice branches.
create or replace function public.fn_seat_handoff_act(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v jsonb; v_originator_closes boolean;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' for update;
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.status = 'done' then return a.evidence; end if;

  if a.detail->>'type' = 'delivery.result' then
    -- The delivery loop (customer_support's build): the originator checks what became of its send.
    v := case when a.agent = 'sales_engineer' and a.detail->>'result' in ('proof_of_response', 'no_response_confirmation')
              then public.fn_sales_engineer_acts_on_handoff(p_id) else '{}'::jsonb end
         || public.fn_originator_checks_delivery(p_id);
  elsif a.detail->>'type' = 'it.finding' then
    v := public.fn_seat_answers_it_finding(p_id);
  elsif a.agent = 'sales_engineer' and a.detail ? 'notice' then
    -- The accountant's reminders, renewals and dunning (this file, section 3).
    v := public.fn_sales_engineer_writes_money_notice(p_id);
  else
    v := case a.agent
           when 'sales_engineer'   then public.fn_sales_engineer_acts_on_handoff(p_id)
           when 'accountant'       then public.fn_accountant_acts_on_handoff(p_id)
           when 'customer_support' then public.fn_customer_support_acts_on_handoff(p_id)
           else null end;
  end if;
  if v is null then raise exception 'seat % has no handler for %', a.agent, a.detail->>'type'; end if;

  select w.originator_closes into v_originator_closes from public.seat_handoff_window w
   where w.type = a.detail->>'type' and w.from_seat = a.detail->>'from';
  if v ? 'waiting' or coalesce(v_originator_closes, false) then
    update public.agent_actions
       set detail = detail || jsonb_build_object('awaiting', coalesce(v->>'waiting', a.detail->>'from' || ' re-verification'),
                                                 'replied_at', now()),
           evidence = v
     where id = p_id;
    perform public.fn_seat_handoff_event(p_id, 'waiting');
    return v;
  end if;
  perform public.fn_seat_handoff_complete(p_id, v);
  return v;
end $fn$;

-- ── 5. PROOF: a finding raised, re-checked away, and a notice with no template refused ────────────
-- This file defines routines, so the probe cleans up after itself and ends in a notice.
do $probe$
declare v jsonb; v_open int; v_closed int; v_left int;
begin
  v := public.fn_accountant_duty_settle('zz_demo_probe', jsonb_build_array(jsonb_build_object(
    'item', 'one', 'title', 'ZZ DEMO accountant probe', 'owner_seat', 'accountant', 'blast', 'internal', 'affected', 0, 'demo', true)));
  select count(*) into v_open from public.it_engineer_finding where issue_key = 'acct:zz_demo_probe:one' and closed_at is null;
  v := public.fn_accountant_duty_settle('zz_demo_probe', '[]'::jsonb);
  select count(*) into v_closed from public.it_engineer_finding where issue_key = 'acct:zz_demo_probe:one' and closed_at is not null;
  delete from public.it_engineer_finding where issue_key = 'acct:zz_demo_probe:one';
  select count(*) into v_left from public.it_engineer_finding where issue_key like 'acct:zz_demo_probe:%';
  if v_open <> 1 or v_closed <> 1 or v_left <> 0 then
    raise exception 'accountant settle probe failed: opened %, closed %, left %', v_open, v_closed, v_left;
  end if;
  if public.fn_render_template('AED {{x}} by {{y}}', '{"x":"10"}') <> 'AED 10 by {{y}}' then
    raise exception 'fn_render_template does not leave an unfilled placeholder visible';
  end if;
  raise notice 'accountant findings raise and close through the IT loop''s ledger; probe rows removed.';
end
$probe$;
