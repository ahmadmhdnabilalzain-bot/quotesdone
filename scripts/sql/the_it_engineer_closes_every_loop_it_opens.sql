-- THE IT ENGINEER CLOSES EVERY LOOP IT OPENS. Nothing it finds is a one-way message.
--
-- Assigned: it_engineer (the loop, the re-verification, the daily line); the replies are each owning
-- seat's; the escalation decision is the ceo's; the founder email is sent by customer_support.
--
-- The founder, 14 Sep 2026: "always make sure things are in loop. nothing literally should ever be a
-- one way communication", and "option 1, but for new bugs i just need to be notified on email", and
-- "also we should not rely on the LLM as much as possible in the operation".
--
-- WHAT WAS MEASURED. fn_it_engineer_alert_tick turned every high/critical it_engineer_finding into an
-- email straight to the founder (notifications type it_engineer_handover) and a RESOLVED email when it
-- cleared. No seat was asked to act, nothing waited for a reply, and nobody but the founder ever heard
-- of a fault. On 14 Sep that path emailed him "[HIGH] inquiry_intake is failing 50% of attempts",
-- which was his own OpenRouter hold refusing model calls (fixed in d9_stops_paging_him_about_his_own_
-- rules.sql). A one-way alert has no owner, so a false one cannot be answered either.
--
-- WHAT THIS CHANGES — the loop, every step deterministic, no model call anywhere:
--   1. An actionable finding (fn_it_engineer_severity high or critical) opens ONE 'it.finding' handoff
--      per occurrence to the seat that owns the subject (evidence.owner_seat, else public.function_owner,
--      else the ceo). Reusing fn_seat_handoff: the seats already converse this way.
--   2. The owning seat answers at once through fn_seat_answers_it_finding — its playbook remedy where it
--      has one, or a plain statement that it has none. The answer is a REPLY, never a close.
--   3. Only the originator closes. public.seat_handoff_kind names, per conversation, the reply window
--      and whether only the originator may close; trigger z61 refuses any other close.
--   4. The IT engineer re-verifies itself on every tick: the handoff closes only when the finding it
--      tracked is closed by its own detector or duty check.
--   5. Past the reply window with the finding still open, the IT engineer reports to the CEO
--      (support_ceo_report, it_engineer -> ceo edge). The CEO decides at once: nothing in the company
--      fixed it, so it is a new bug, and the founder gets ONE templated email through customer_support
--      (kind it_new_bug, deduped per issue). A report the CEO has not accepted by next_review_at is
--      itself escalated to the founder.
--   6. Once a Dubai day, after 19:00, a routine daily line goes to the CEO; the CEO acknowledges it;
--      the IT engineer completes it only after the acknowledgement is on the row.
--
-- THE CONVERSATIONS ARE DATA (14 Sep 2026). fn_seat_handoff_types and fn_seat_handoff_act were
-- redefined by four builds the same day (this loop, customer_support's delivery loop, the accountant's
-- notices, the refund loop), and whichever was applied last deleted the others' rows and branches.
-- Every conversation is now a row of public.seat_handoff_kind naming its handler routine; a build adds
-- its conversations with an INSERT in its own file and never redefines a routine.
-- scripts/checks/handoff_kinds_are_data.test.mjs fails if any later file defines them.
--
-- WHAT THIS DOES NOT DO. It holds no remediation playbook of the IT engineer's own: the seats' replies
-- are the remedies it has today. A separate build owns the IT engineer's playbook; when it lands its
-- step belongs at the top of fn_it_loop_open. z60_backup_refile_only_it_engineer_closes (the backup
-- build) stays; z61 accepts its qd.backup_closer setting so the two agree on the backup handoffs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql --apply --ddl

-- ── 1. THE CONVERSATIONS, AS ROWS ───────────────────────────────────────────────────────────────
-- One row per (type, from, to): what it means, the routine the receiving seat answers with
-- (handler(p_id bigint) returns jsonb), how long the receiver has to reply, and whether only the
-- originator may close it. owner_file is the file that inserts the row. It replaces
-- public.seat_handoff_window, whose three rows are the reply_within / originator_closes values below.
create table if not exists public.seat_handoff_kind (
  type              text     not null check (type ~ '^[a-z]+(\.[a-z_]+)+$'),
  from_seat         text     not null,
  to_seat           text     not null,
  meaning           text     not null check (btrim(meaning) <> ''),
  handler           text     not null check (handler ~ '^fn_[a-z0-9_]+$'),
  reply_within      interval check (reply_within > interval '0'),
  originator_closes boolean  not null default false,
  owner_file        text     not null check (owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'),
  primary key (type, from_seat, to_seat)
);
comment on table public.seat_handoff_kind is
  'Every conversation the seats have: meaning, the handler routine the receiving seat answers with, the reply window and who may close it. A build adds conversations by INSERT in its own file; fn_seat_handoff_types and fn_seat_handoff_act only read this table (scripts/checks/handoff_kinds_are_data.test.mjs).';
alter table public.seat_handoff_kind enable row level security;
drop policy if exists seat_handoff_kind_service_role_only on public.seat_handoff_kind;
create policy seat_handoff_kind_service_role_only on public.seat_handoff_kind
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_handoff_kind from anon, authenticated;

-- The 34 conversations live on 14 Sep 2026, each with the handler fn_seat_handoff_act used for it.
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select v.type, v.from_seat, v.to_seat, v.meaning,
       case when v.type = 'it.finding' then 'fn_seat_answers_it_finding'
            when v.type = 'delivery.result' then 'fn_delivery_result_acts'
            else 'fn_' || v.to_seat || '_acts_on_handoff' end,
       case when (v.type, v.from_seat) = ('it.finding', 'it_engineer') then interval '4 hours'
            when (v.type, v.from_seat) = ('delivery.request', 'it_engineer') then interval '1 hour'
            when (v.type, v.from_seat) = ('backup.refile', 'it_engineer') then interval '48 hours' end,
       (v.type, v.from_seat) in (('it.finding', 'it_engineer'), ('backup.refile', 'it_engineer')),
       'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'
  from (values
    ('reveal.paid',              'accountant',       'sales_engineer',   'A reveal charge settled at Stripe: tell the customer the contact is released and the supplier that they were revealed.'),
    ('payment.failed',           'accountant',       'sales_engineer',   'A reveal checkout expired or failed: tell the customer nothing was charged and how to try again.'),
    ('payment.received',         'accountant',       'sales_engineer',   'A supplier paid an outstanding charge or the registration fee: confirm it to them.'),
    ('refund.request_checked',   'accountant',       'sales_engineer',   'The books checked a refund request: acknowledge it to the customer.'),
    ('refund.paid',              'accountant',       'sales_engineer',   'A refund settled: tell the customer what came back and when the bank shows it.'),
    ('refund.declined',          'accountant',       'sales_engineer',   'A refund was declined: tell the customer why.'),
    ('refund.in_progress',       'accountant',       'sales_engineer',   'A refund is approved but not settled after a retry: tell the customer it is in progress.'),
    ('nonresponse.charge_raised','accountant',       'sales_engineer',   'The non-response charge was raised: tell the supplier the figures.'),
    ('charge.corrected',         'accountant',       'sales_engineer',   'A charge already sent was wrong: send a correction to whoever got the original.'),
    ('subscription.due',         'accountant',       'sales_engineer',   'The yearly registration fee fell due: tell the supplier.'),
    ('billing.answer',           'accountant',       'sales_engineer',   'The books answered a billing question: relay it.'),
    ('charge.dispute_answer',    'accountant',       'sales_engineer',   'The books checked a disputed charge: relay the result to the supplier.'),
    ('refund.requested',         'sales_engineer',   'accountant',       'A customer asked for a refund in the portal: check the money behind it.'),
    ('billing.question',         'sales_engineer',   'accountant',       'A customer or supplier asked about a charge, an invoice or a refund: read the books.'),
    ('charge.disputed',          'sales_engineer',   'accountant',       'A supplier disputed a charge: recompute it from the refund record.'),
    ('refund.remediate',         'ceo',              'accountant',       'The CEO refused approval on a money check the accountant owns: fix it and report back.'),
    ('refund.remediate',         'ceo',              'sales_engineer',   'The CEO refused approval on a ladder check the sales engineer owns: fix it and report back.'),
    ('incident.fix',             'ceo',              'accountant',       'Post-payment re-verification found a mismatch: apply the fix the playbook names.'),
    ('delivery.request',         'sales_engineer',   'customer_support', 'Deliver these words to a customer or supplier through the outbox, and watch for the reply when asked.'),
    ('delivery.request',         'ceo',              'customer_support', 'Deliver this summary to the founder on his command channel.'),
    ('delivery.request',         'accountant',       'customer_support', 'Deliver this money exception to the founder on his command channel.'),
    ('delivery.request',         'it_engineer',      'customer_support', 'Deliver this platform notice to the founder.'),
    ('delivery.request',         'customer_support', 'customer_support', 'Support''s own notice (a receipt, a contact-form alert): queued, and checked like any other.'),
    ('delivery.result',          'customer_support', 'sales_engineer',   'What came back: proof the supplier responded, confirmation that nothing did, or what became of the send.'),
    ('delivery.result',          'customer_support', 'accountant',       'What became of the send the accountant asked for: delivered with the provider''s id, or why not.'),
    ('delivery.result',          'customer_support', 'ceo',              'What became of the send the CEO asked for: delivered with the provider''s id, or why not.'),
    ('delivery.result',          'customer_support', 'it_engineer',      'What became of the send the IT engineer asked for: delivered with the provider''s id, or why not.'),
    ('delivery.result',          'customer_support', 'customer_support', 'What became of support''s own notice: delivered with the provider''s id, or why not.'),
    ('backup.refile',            'it_engineer',      'sales_engineer',   'The IT engineer found backed-up documents missing, changed, failed or never queued: file each again. Only the IT engineer closes it, once each new copy is verified.'),
    ('backup.remediate',         'ceo',              'sales_engineer',   'The CEO read the IT engineer''s escalation and sends instructions back: re-file these documents or record why they cannot be. The IT engineer re-checks and closes.'),
    ('it.finding',               'it_engineer',      'sales_engineer',   'The IT engineer found a fault in something the sales engineer owns: apply your remedy or say you have none. The IT engineer re-verifies and closes.'),
    ('it.finding',               'it_engineer',      'accountant',       'The IT engineer found a fault in something the accountant owns: apply your remedy or say you have none. The IT engineer re-verifies and closes.'),
    ('it.finding',               'it_engineer',      'customer_support', 'The IT engineer found a fault in something customer support owns: apply your remedy or say you have none. The IT engineer re-verifies and closes.'),
    ('it.finding',               'it_engineer',      'ceo',              'The IT engineer found a fault in something only the CEO owns: decide the remedy or say there is none. The IT engineer re-verifies and closes.')
  ) v(type, from_seat, to_seat, meaning)
on conflict (type, from_seat, to_seat) do update
  set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
      originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

drop table if exists public.seat_handoff_window;

-- ── 2. THE CONVERSATIONS, AS THE ROUTINE EVERY CALLER ALREADY READS ─────────────────────────────
-- Mirrored in supabase/functions/_shared/payment_handoffs.ts for the payment types only.
create or replace function public.fn_seat_handoff_types()
returns table(type text, from_seat text, to_seat text, meaning text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select k.type, k.from_seat, k.to_seat, k.meaning from public.seat_handoff_kind k
$fn$;


-- ── 3. ONLY THE ORIGINATOR CLOSES ────────────────────────────────────────────────────────────────
-- The closer names itself in qd.handoff_closer inside its own transaction. qd.backup_closer is the
-- backup build's name for the same thing and is honoured so its re-check keeps working unchanged.
create or replace function public.trg_handoff_only_originator_closes()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_closer text;
begin
  if new.kind = 'handoff' and new.status = 'done' and old.status is distinct from 'done'
     and exists (select 1 from public.seat_handoff_kind k
                  where k.type = new.detail->>'type' and k.from_seat = new.detail->>'from' and k.originator_closes) then
    v_closer := coalesce(nullif(current_setting('qd.handoff_closer', true), ''),
                         nullif(current_setting('qd.backup_closer', true), ''));
    if v_closer is distinct from new.detail->>'from' then
      raise exception 'handoff % (%) is closed only by its originator %, after it re-verifies; % tried to close it',
        new.id, new.detail->>'type', new.detail->>'from', coalesce(v_closer, 'an unnamed caller');
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_handoff_only_originator_closes() from public, anon, authenticated;
drop trigger if exists z61_handoff_only_originator_closes on public.agent_actions;
create trigger z61_handoff_only_originator_closes before update of status on public.agent_actions
  for each row execute function public.trg_handoff_only_originator_closes();

-- ── 4. THE RECEIVING SEAT ANSWERS WITH THE HANDLER ITS ROW NAMES ────────────────────────────────
-- The delivery loop's answer, moved verbatim out of the old branch in fn_seat_handoff_act: the
-- originator checks what became of its send (fn_originator_checks_delivery is customer_support's).
create or replace function public.fn_delivery_result_acts(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'delivery.result';
  if not found then raise exception 'fn_delivery_result_acts: % is not a delivery.result handoff', p_id; end if;
  return case when a.agent = 'sales_engineer' and a.detail->>'result' in ('proof_of_response', 'no_response_confirmation')
              then public.fn_sales_engineer_acts_on_handoff(p_id) else '{}'::jsonb end
         || public.fn_originator_checks_delivery(p_id);
end $fn$;
revoke execute on function public.fn_delivery_result_acts(bigint) from public, anon, authenticated;

-- The receiving seat answers with the handler its row names. An answer on a conversation its row
-- marks originator-closed is stored as the reply (detail.replied_at) instead of completing the handoff.
create or replace function public.fn_seat_handoff_act(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; k public.seat_handoff_kind; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' for update;
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.status = 'done' then return a.evidence; end if;

  select * into k from public.seat_handoff_kind
   where type = a.detail->>'type' and from_seat = a.detail->>'from' and to_seat = a.agent;
  if not found then
    raise exception 'no conversation % from % to % in public.seat_handoff_kind', a.detail->>'type', a.detail->>'from', a.agent;
  end if;
  execute format('select public.%I($1)', k.handler) into v using p_id;
  if v is null then raise exception '% answered nothing for handoff %', k.handler, p_id; end if;

  if v ? 'waiting' or k.originator_closes then
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
revoke execute on function public.fn_seat_handoff_act(bigint) from public, anon, authenticated;

-- ── 5. EACH SEAT'S ANSWER TO THE IT ENGINEER ──────────────────────────────────────────────────────
-- Deterministic. A seat with a remedy for the finding's duty applies it and says what it did; a seat
-- with none says so in words the CEO and the founder can read. Either way the reply is on the row and
-- the IT engineer decides, from its own re-check, whether it worked.
create or replace function public.fn_seat_answers_it_finding(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' <> 'it.finding' then
    raise exception 'fn_seat_answers_it_finding: % is not an it.finding handoff', p_id;
  end if;
  d := a.detail;
  -- THE CEO OWNS THE HARNESS, AND CAN CLOSE A REHEARSAL WINDOW A RUN LEFT OPEN. An open window keeps
  -- the failed-run watcher from paging for anything it covers, so closing it is the remedy, not a risk.
  if d->>'duty' = 'demo' and (d->'finding_evidence'->>'rehearsal_window_id') is not null then
    update public.rehearsal_window set ended_at = now()
     where id = (d->'finding_evidence'->>'rehearsal_window_id')::bigint and ended_at is null;
    return jsonb_build_object('waiting', 'it_engineer re-verification', 'seat', a.agent, 'duty', 'demo',
      'remedy', 'closed rehearsal_window ' || (d->'finding_evidence'->>'rehearsal_window_id'),
      'reply', a.agent || ' closed rehearsal window ' || (d->'finding_evidence'->>'rehearsal_window_id')
               || ', which its run had left open.');
  end if;
  return jsonb_build_object(
    'waiting', 'it_engineer re-verification',
    'seat', a.agent,
    'duty', d->>'duty',
    'remedy', null,
    'reply', a.agent || ' acknowledged "' || coalesce(d->>'title', d->>'issue_key') || '". Its playbook has no '
             || 'deterministic remedy for a ' || coalesce(d->>'duty', 'fault') || ' finding on '
             || coalesce(d->>'subject', 'this subject') || ': it needs a code or configuration change.');
end $fn$;
revoke execute on function public.fn_seat_answers_it_finding(bigint) from public, anon, authenticated;

-- ── 6. OPENING A LOOP ────────────────────────────────────────────────────────────────────────────
-- One handoff per OCCURRENCE: the subject id carries the finding's started_at, so a finding that
-- clears and comes back opens a new loop instead of finding the closed one.
create or replace function public.fn_it_loop_open(p_issue_key text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.it_engineer_finding; v_owner text; v_duty text; v_subject text;
begin
  select * into f from public.it_engineer_finding where issue_key = p_issue_key and closed_at is null;
  if not found then raise exception 'fn_it_loop_open: no open finding %', p_issue_key; end if;

  -- A detector finding ('watch:<detector_key>') names its subject on the detector's own row.
  v_subject := coalesce(nullif(f.evidence->>'subject', ''),
                        (select w.subject from public.it_watch_finding w where 'watch:' || w.detector_key = f.issue_key));
  v_owner := coalesce(nullif(f.evidence->>'owner_seat', ''),
                      (select o.owner from public.function_owner o where o.function_slug = v_subject));
  -- 'website' and any retired role are not seats; a finding nobody else owns is the CEO's.
  if not exists (select 1 from public.fn_seat_handoff_types() t
                  where t.type = 'it.finding' and t.from_seat = 'it_engineer' and t.to_seat = v_owner) then
    v_owner := 'ceo';
  end if;
  v_duty := coalesce(nullif(f.evidence->>'duty', ''), 'fault');

  return public.fn_seat_handoff('it_engineer', v_owner, 'it.finding', 'it_engineer_finding',
    f.issue_key || '@' || floor(extract(epoch from f.started_at))::bigint,
    jsonb_build_object(
      'issue_key', f.issue_key, 'occurrence_started_at', f.started_at, 'duty', v_duty,
      'subject', v_subject, 'title', f.title, 'where_it_is', f.where_it_is,
      'severity', public.fn_it_engineer_severity(f.blast, f.affected, f.started_at),
      'finding_evidence', f.evidence,
      'demo', f.title ilike '%ZZ DEMO%' or coalesce((f.evidence->>'demo')::boolean, false)));
end $fn$;
revoke execute on function public.fn_it_loop_open(text) from public, anon, authenticated;

-- ── 7. THE CEO DECIDES AN ESCALATION ─────────────────────────────────────────────────────────────
-- The seat could not fix it within its window and the IT engineer still sees it: nothing in the
-- company fixes this, so it is a new bug. The founder is told once, in plain words, by customer_support.
-- A ZZ DEMO case never reaches him.
create or replace function public.fn_ceo_it_escalation_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; h public.agent_actions; v_demo boolean; v_detail text; v_d bigint; v_acc jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id and source_agent = 'it_engineer' for update;
  if not found or r.status <> 'sent' then
    return jsonb_build_object('ok', false, 'reason', 'no open IT report ' || p_report_id);
  end if;
  select * into h from public.agent_actions where id = (r.verified_evidence->>'handoff_id')::bigint;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'report ' || p_report_id || ' names no handoff');
  end if;
  v_demo := coalesce((h.detail->>'demo')::boolean, false);
  v_detail := 'What is wrong: ' || coalesce(h.detail->>'title', h.detail->>'issue_key') || E'.\n'
    || 'Where: ' || coalesce(h.detail->>'where_it_is', h.detail->>'subject', 'not recorded') || E'.\n'
    || 'Since: ' || to_char((h.detail->>'occurrence_started_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || E' (Dubai).\n'
    || 'What was tried: the ' || h.agent || ' was asked at '
    || to_char(h.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' and '
    || case when h.detail ? 'replied_at' then 'replied: ' || coalesce(h.evidence->>'reply', 'no words recorded')
            else 'did not reply' end || E'\n\n'
    || 'Nothing inside the company fixed it, so it needs a code or configuration change. It stays tracked '
    || 'until the IT engineer confirms it is gone. Reference: ' || (h.detail->>'issue_key') || '.';

  if not v_demo then
    v_d := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
                         'event', 'New problem the IT engineer could not fix: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 120),
                         'detail', v_detail, 'dedupe_key', 'it_new_bug:' || (h.detail->>'issue_key')));
  end if;
  v_acc := public.fn_ceo_accept_support_report(r.id,
    'ceo: new bug, no seat could fix it — ' || case when v_demo then 'ZZ DEMO case, the founder is not emailed'
                                                   else 'founder told through customer_support handoff ' || v_d end);
  return jsonb_build_object('ok', true, 'report_id', r.id, 'handoff_id', h.id, 'demo', v_demo,
                            'founder_delivery_handoff', v_d, 'accepted', v_acc);
end $fn$;
revoke execute on function public.fn_ceo_it_escalation_decide(bigint) from public, anon, authenticated;

-- The CEO reads what the IT engineer sent: a routine report is acknowledged with a receipt naming
-- what was read; a serious or critical one is decided.
create or replace function public.fn_ceo_it_reports_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n_ack int := 0; n_dec int := 0;
begin
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent' order by id loop
    if r.severity = 'routine' then
      perform public.fn_ceo_accept_support_report(r.id,
        'ceo: read the IT line — ' || coalesce(r.verified_evidence->>'open_loops', '0') || ' open loop(s), each with a named owner');
      n_ack := n_ack + 1;
    elsif r.idempotency_key like 'it_loop:%' then
      perform public.fn_ceo_it_escalation_decide(r.id);
      n_dec := n_dec + 1;
    end if;
  end loop;
  return jsonb_build_object('acknowledged', n_ack, 'decided', n_dec);
end $fn$;
revoke execute on function public.fn_ceo_it_reports_sweep() from public, anon, authenticated;

-- ── 8. THE IT ENGINEER RE-VERIFIES, CLOSES, OR ESCALATES ──────────────────────────────────────────
create or replace function public.fn_it_loop_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;
    if v_cleared then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window then
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
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait);
end $fn$;
revoke execute on function public.fn_it_loop_reverify() from public, anon, authenticated;

-- ── 9. A REPORT THE CEO LEAVES UNREAD REACHES THE FOUNDER ─────────────────────────────────────────
-- Sent through customer_support; what became of the send comes back to the IT engineer as a
-- delivery.result, checked by fn_originator_checks_delivery (the delivery loop's own build).
create or replace function public.fn_it_ceo_silence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n_told int := 0;
begin
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent' and next_review_at < now()
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.target_id = 'delivery.request:' || support_ceo_report.id)
            order by id loop
    perform public.fn_seat_handoff('it_engineer', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
        'event', 'The CEO has not answered an IT report: ' || left(r.subject, 120),
        'detail', 'The IT engineer reported this to the CEO at '
                  || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai) and it was due an answer by '
                  || to_char(r.next_review_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || E'. Nobody has answered.\n\n'
                  || 'Report: ' || r.subject || E'\n\nIt stays open until the CEO answers it. Reference: support_ceo_report ' || r.id || '.',
        'dedupe_key', 'it_ceo_silent:' || r.id));
    n_told := n_told + 1;
  end loop;
  return jsonb_build_object('founder_told', n_told);
end $fn$;
revoke execute on function public.fn_it_ceo_silence_watch() from public, anon, authenticated;

-- ── 10. THE DAILY LINE TO THE CEO ────────────────────────────────────────────────────────────────
-- Filed once per Dubai day after 19:00. Repeats of a founder email the dedupe folded away are counted
-- here rather than sent again. The IT engineer completes the line only once the CEO's receipt is on it.
create or replace function public.fn_it_daily_line()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_day   text := to_char(v_local, 'YYYY-MM-DD');
  v_since timestamptz := (date_trunc('day', v_local) at time zone 'Asia/Dubai');
  v_ev jsonb; v_rep jsonb; n_done int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'it_engineer' and idempotency_key like 'it_daily:%' and status = 'accepted';
  get diagnostics n_done = row_count;

  if v_local::time < time '19:00'
     or exists (select 1 from public.support_ceo_report where idempotency_key = 'it_daily:' || v_day) then
    return jsonb_build_object('filed', false, 'completed_after_receipt', n_done);
  end if;

  select jsonb_build_object(
    'day', v_day,
    'open_findings', (select count(*) from public.it_engineer_finding where closed_at is null),
    'open_findings_actionable', (select count(*) from public.it_engineer_finding
                                  where closed_at is null and public.fn_it_engineer_severity(blast, affected, started_at) <> 'warn'),
    'open_loops', (select count(*) from public.agent_actions
                    where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')),
    'open_loops_by_seat', coalesce((select jsonb_object_agg(agent, n) from (
                      select agent, count(*) n from public.agent_actions
                       where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')
                       group by agent) x), '{}'::jsonb),
    'loops_closed_today', (select count(*) from public.agent_actions
                            where kind = 'handoff' and detail->>'from' = 'it_engineer' and status = 'done' and decided_at >= v_since),
    'escalated_today', (select count(*) from public.support_ceo_report
                         where source_agent = 'it_engineer' and idempotency_key like 'it_loop:%' and created_at >= v_since),
    'founder_emails_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'email' and created_at >= v_since),
    'repeats_folded_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'deduped' and created_at >= v_since))
  into v_ev;

  v_rep := public.fn_support_report_to_ceo('it_daily:' || v_day, 'routine',
    'IT engineer daily line ' || v_day || ': ' || (v_ev->>'open_loops') || ' open loop(s), '
      || (v_ev->>'loops_closed_today') || ' closed today, ' || (v_ev->>'founder_emails_today') || ' founder email(s), '
      || (v_ev->>'repeats_folded_today') || ' repeat(s) folded',
    v_ev, '[]'::jsonb,
    'Acknowledge the day''s IT position. Nothing else is requested; anything that needs a decision reaches you as its own report.',
    p_review_in => interval '3 hours', p_source_agent => 'it_engineer');
  if not coalesce((v_rep->>'ok')::boolean, false) then
    raise exception 'fn_it_daily_line: the CEO report was refused: %', v_rep->>'reason';
  end if;
  return jsonb_build_object('filed', true, 'report', v_rep, 'completed_after_receipt', n_done);
end $fn$;
revoke execute on function public.fn_it_daily_line() from public, anon, authenticated;

-- ── 10b. A BROKEN STAGE OF THE LOOP IS ITSELF A FINDING ───────────────────────────────────────────
-- Review of 14 Sep 2026: an error caught inside fn_it_loop_tick lived only in the tick's JSON. It now
-- writes an agent_runs error row and an it_engineer_finding keyed on the stage (blast 'monitor', so it
-- goes round the loop like any other), closed again the first tick that stage succeeds.
create or replace function public.fn_it_loop_stage(p_step text, p_error text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_step), '') = '' then raise exception 'fn_it_loop_stage: a stage name is required'; end if;
  if p_error is null then
    perform public.fn_it_engineer_finding_close('monitor:it_loop:' || p_step, 'the ' || p_step || ' stage of the IT loop ran cleanly');
    return;
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'it_loop', 'stage', p_step), left(p_error, 600));
  perform public.fn_it_engineer_finding_upsert('monitor:it_loop:' || p_step,
    'The ' || p_step || ' stage of the IT engineer''s loop is failing', 'public.fn_it_loop_tick', 'monitor', 1,
    jsonb_build_object('stage', p_step, 'error', left(p_error, 600), 'owner_seat', 'ceo'),
    '{}'::text[], array['why the stage raises: ' || left(p_error, 300)], 'fn_it_loop_tick');
end $fn$;
revoke execute on function public.fn_it_loop_stage(text, text) from public, anon, authenticated;

-- fn_it_loop_reverify, fn_it_daily_line and fn_it_ceo_silence_watch all filter handoffs this way.
create index if not exists agent_actions_kind_type_from_idx
  on public.agent_actions (kind, (detail->>'type'), (detail->>'from'));

-- ── 11. THE TICK ─────────────────────────────────────────────────────────────────────────────────
-- Called by fn_it_engineer_alert_tick every 15 minutes, after it has pulled the detectors. Each step
-- is its own sub-transaction so one failing step is REPORTED in the result and does not stop the rest.
create or replace function public.fn_it_loop_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f record; o jsonb := '{}'::jsonb; n_open int := 0; v_err jsonb := '[]'::jsonb; v_step text;
begin
  for f in select x.issue_key, x.started_at from public.it_engineer_finding x
            where x.closed_at is null and public.fn_it_engineer_severity(x.blast, x.affected, x.started_at) <> 'warn'
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
                                 and a.detail->>'issue_key' = x.issue_key
                                 and (a.detail->>'occurrence_started_at')::timestamptz = x.started_at)
            order by x.started_at loop
    begin
      perform public.fn_it_loop_open(f.issue_key);
      n_open := n_open + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('step', 'open', 'issue_key', f.issue_key, 'error', sqlerrm);
    end;
  end loop;
  o := o || jsonb_build_object('opened', n_open);

  begin o := o || jsonb_build_object('reverify', public.fn_it_loop_reverify());
  exception when others then v_err := v_err || jsonb_build_object('step', 'reverify', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_it_reports_sweep());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_silence', public.fn_it_ceo_silence_watch());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_silence', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('daily', public.fn_it_daily_line());
  exception when others then v_err := v_err || jsonb_build_object('step', 'daily', 'error', sqlerrm); end;

  foreach v_step in array array['open', 'reverify', 'ceo', 'ceo_silence', 'daily'] loop
    perform public.fn_it_loop_stage(v_step,
      (select string_agg(coalesce(e->>'issue_key' || ': ', '') || (e->>'error'), '; ')
         from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_it_loop_tick() from public, anon, authenticated;

-- ── 12. THE FOUNDER'S ONE KIND OF IT EMAIL ───────────────────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, owner_role, reason)
values ('it_new_bug', true, 'it_engineer',
        'Founder, 14 Sep 2026: "for new bugs i just need to be notified on email". Sent by customer_support only after the owning seat and the CEO could not fix it; deduped per issue for 24 hours, repeats folded into the IT daily line.')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, owner_role = excluded.owner_role, reason = excluded.reason;

-- ── 13. THE FOUNDER HANDOVER EMAIL BODY IS RETIRED WITH THE PATH THAT SENT IT ──────────────────────
-- Its only caller was sections C and D of fn_it_engineer_alert_tick, replaced by fn_it_loop_tick.
-- Recorded in scripts/sql/DROPPED.txt.
drop function if exists public.fn_it_engineer_handover_body(text, text);

-- ── 14. PROOF THAT A SEAT CANNOT CLOSE WHAT THE IT ENGINEER OPENED ────────────────────────────────
-- This file defines routines, so the probe cleans up after itself and ends in a notice.
do $probe$
declare v_id bigint; v_refused boolean := false; v_left int;
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO loop probe',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'sales_engineer', 'issue_key', 'zz_demo_probe'),
          'it_engineer_finding', 'it.finding:zz_demo_probe@0')
  returning id into v_id;
  begin
    perform set_config('qd.handoff_closer', 'sales_engineer', true);
    update public.agent_actions set status = 'done' where id = v_id;
  exception when others then v_refused := true; end;
  perform set_config('qd.handoff_closer', 'it_engineer', true);
  update public.agent_actions set status = 'done' where id = v_id;
  perform set_config('qd.handoff_closer', '', true);
  delete from public.agent_actions where id = v_id;
  select count(*) into v_left from public.agent_actions where id = v_id;
  if not v_refused or v_left <> 0 then
    raise exception 'loop probe failed: responder close refused=%, rows left=%', v_refused, v_left;
  end if;
  raise notice 'z61 refused the responder''s close and accepted the originator''s; probe row removed.';
end
$probe$;
