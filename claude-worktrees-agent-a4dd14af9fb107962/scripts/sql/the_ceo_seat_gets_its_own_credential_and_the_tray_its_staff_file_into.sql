-- THE CEO SEAT GETS ITS OWN CREDENTIAL, AND THE TRAY ITS STAFF FILE INTO.
--
-- Two defects, both measured on 9 September 2026, both on the CEO seat.
--
-- ONE. THE SEAT HAD NO CREDENTIAL OF ITS OWN. ceo_agent's SEAT_BY_CREDENTIAL held exactly one
-- entry -- 'fn.founder_channel' -> 'founder' -- and no fn.ceo_agent row existed in
-- internal_credential. Every other seat has one: fn.accountant, fn.sales_engineer,
-- fn.it_engineer. The consequence was not that the CEO could not log in. It was that the ONLY
-- entity able to reach action=decide was the founder, and the row that action writes hardcoded
-- decided_by 'ceo'. So the founder's approvals were being recorded as the CEO's. That inverts his
-- own ruling of 8 September ("all approvals are from CEO. nothing goes to me") by pointing it
-- backwards: instead of the CEO deciding, the founder decided and the register said the CEO had.
-- A decision register that names the wrong decider is worse than none, because it is believed.
--
-- The credential minted here is the seat's own, scoped to exactly one function -- ceo_agent, its
-- own runtime. After the edge deploy that accompanies this file, 'fn.ceo_agent' -> 'ceo' is the
-- only way to reach decide, decided_by is the authenticated seat rather than a string literal, and
-- the founder issuing a decision is refused by name rather than silently relabelled.
--
-- THE FOUNDER IS DELIBERATELY *NOT* ADDED TO ceo_identity. That table is "the identities permitted
-- to decide as the CEO seat" and it is what the refund guards check. Adding him there so that
-- decided_by could honestly read 'founder' would hand the founder back the approval authority he
-- gave away on 8 September -- the honest record would have bought a dishonest permission. The
-- register stays single-identity, and the runtime refuses him instead of impersonating him.
--
-- TWO. THE CEO'S INBOX DID NOT READ THE TRAY ITS STAFF FILE INTO. ceo_agent action=inbox read
-- ceo_command, ceo_task and refunds. Subordinate seats escalate through fn_ceo_request_decision ->
-- fn_support_report_to_ceo -> support_ceo_report, and the accountant's weekly financial report is
-- delivered into that same table by fn_accountant_weekly_report_deliver. Two rows sat there
-- status='sent', accepted_at=null. fn_support_open_reports and fn_ceo_accept_support_report both
-- existed with NO caller anywhere in the estate. Finished capability, no entry point. That half is
-- an edge-function change and is not in this file; what is in this file is the third defect, which
-- is the reason the tray was mis-addressed in the first place.
--
-- THREE (found while in there). fn_support_report_to_ceo LIED ABOUT WHO WAS REPORTING. It
-- hardcoded 'customer_support' in three places: the reporting-edge lookup that decides whether the
-- report may be sent at all, the inserted source_agent, and owner_role_id. So the ACCOUNTANT's
-- escalations would have been filed under Support's name and gated on Support's edge. Measured
-- before this change, calling it with the accountant's intent produced
-- source_agent='customer_support', owner_role_id='customer_support'. The proof that this was not
-- theoretical is that fn_accountant_weekly_report_deliver does not call this function at all -- it
-- open-codes its own INSERT into support_ceo_report, because the shared routine could not say
-- 'accountant'. A shared routine that cannot name its caller grows a private copy per caller, and
-- then the guards live in only one of them.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_seat_gets_its_own_credential_and_the_tray_its_staff_file_into.sql --apply --ddl

begin;

-- ── 1. THE SEAT'S OWN CREDENTIAL ───────────────────────────────────────────────────────────────
-- Same shape as fn.accountant, fn.sales_engineer and fn.it_engineer: the value is generated inside
-- the database, stored once in app_secrets, and never printed. The scope names only what this
-- credential may call, and that is exactly one function -- the seat's own runtime.
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.ceo_agent') then
    raise notice 'fn.ceo_agent already exists -- left untouched';
    return;
  end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.ceo_agent',
          'The CEO seat acting on its own behalf -- deciding, accepting its staff''s reports, '
          'closing its own tasks. Distinct from fn.founder_channel, which is the founder speaking '
          'TO the seat and may only command.',
          public.fn_internal_credential_hash(v_secret),
          array['ceo_agent'], false, true);
  insert into public.app_secrets (key, value)
  values ('cred_fn_ceo_agent', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

-- ── 2. THE REPORT NAMES ITS SENDER ─────────────────────────────────────────────────────────────
-- DROP then CREATE rather than CREATE OR REPLACE: a new trailing parameter makes a new signature,
-- so replacing would leave the nine-argument version standing beside it and every existing
-- six-argument call would become ambiguous. The default keeps fn_ceo_request_decision, which
-- passes six positional arguments, working unchanged.
drop function if exists public.fn_support_report_to_ceo(text, text, text, jsonb, jsonb, text, text, text, interval);

create function public.fn_support_report_to_ceo(
  p_idempotency_key text,
  p_severity        text,
  p_subject         text,
  p_evidence        jsonb,
  p_attempted       jsonb,
  p_requested       text,
  p_case_ref        text default null,
  p_task_ref        text default null,
  p_review_in       interval default '1 day'::interval,
  p_source_agent    text default 'customer_support')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_parent text;
  v_id     bigint;
  v_agent  text := lower(btrim(coalesce(p_source_agent, '')));
  v_existing public.support_ceo_report%rowtype;
begin
  -- WHO IS REPORTING IS AN ARGUMENT NOW, NOT A LITERAL. It defaults to customer_support so every
  -- existing caller behaves exactly as it did, and it is used in all three of the places the
  -- literal used to sit: the edge lookup, source_agent, and owner_role_id. Getting only two of the
  -- three would be worse than none -- a report filed under the accountant's name but gated on
  -- support's edge is a report that can be sent when support is reorganised and refused when the
  -- accountant is.
  if v_agent = '' then
    return jsonb_build_object('ok', false, 'reason',
      'source_agent is required. A report with no sender cannot be routed, because the reporting '
      || 'edge that decides where it goes is the SENDER''s edge, not a constant.');
  end if;

  -- THE MANAGER IS READ, NOT ASSUMED. If the edge is gone or the parent is not active, this
  -- refuses rather than picking someone.
  select e.parent_role_id into v_parent
    from public.org_reporting_edge e
    join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
   where e.child_role_id = v_agent;

  if v_parent is null then
    return jsonb_build_object('ok', false, 'reason',
      format('No active reporting parent for %s. The report is NOT sent and NOT silently '
             || 'redirected: inventing a recipient is how work goes to nobody.', v_agent));
  end if;

  if coalesce(btrim(p_requested), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'requested_outcome is required. A report that does not say what it wants is a notification, '
      || 'and the CEO cannot act on it.');
  end if;

  -- IDEMPOTENT BY THE BUSINESS EVENT. A webhook that fires twice, a retry after a timeout and a
  -- restart mid-flight must all produce ONE report. Returning the existing row is the correct
  -- answer, not an error: the caller's intent was satisfied the first time.
  select * into v_existing from public.support_ceo_report where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'report_id', v_existing.id,
      'status', v_existing.status,
      'note', 'This matter was already reported. Returning the original rather than sending a second.');
  end if;

  insert into public.support_ceo_report
    (idempotency_key, source_agent, case_ref, task_ref, severity, subject,
     verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at)
  values
    (p_idempotency_key, v_agent, p_case_ref, p_task_ref, p_severity, p_subject,
     p_evidence, coalesce(p_attempted, '[]'::jsonb), p_requested,
     v_agent,                       -- the sender keeps it until the CEO accepts
     now() + coalesce(p_review_in, interval '1 day'))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'report_id', v_id, 'reported_to', v_parent,
    'owner', v_agent,
    'note', format('Sent. Ownership stays with %s until the CEO accepts it with a receipt.', v_agent));
end $function$;

revoke execute on function public.fn_support_report_to_ceo(text, text, text, jsonb, jsonb, text, text, text, interval, text) from public;
grant  execute on function public.fn_support_report_to_ceo(text, text, text, jsonb, jsonb, text, text, text, interval, text) to service_role;

comment on function public.fn_support_report_to_ceo(text, text, text, jsonb, jsonb, text, text, text, interval, text) is
  'A subordinate seat reports a matter up to its own reporting parent. p_source_agent names the '
  'sender and is used for the edge lookup, source_agent and owner_role_id alike; it defaults to '
  'customer_support so the six-argument callers that predate 9 Sep 2026 are unchanged. Before that '
  'date the sender was hardcoded, so an accountant escalation would have been filed under support''s '
  'name and gated on support''s edge.';

-- ── 3. THE CLOSING ASSERTION AND A SELF-CLEANING PROBE ─────────────────────────────────────────
-- The probe writes real rows through the real routine and deletes them again. It does NOT abort
-- the transaction to undo itself, because that would roll back the DDL above with it.
do $check$
declare
  v_cred int; v_secret_len int; v_auth jsonb; v_scope jsonb;
  v_ok jsonb; v_bad jsonb; v_row public.support_ceo_report%rowtype;
  v_secret text; v_open int;
begin
  -- 3a. THE CREDENTIAL EXISTS, IS ACTIVE, AND IS SCOPED TO THE SEAT'S RUNTIME AND NOTHING ELSE.
  select count(*) into v_cred from public.internal_credential
   where context = 'fn.ceo_agent' and active and scope = array['ceo_agent'];
  if v_cred <> 1 then
    raise exception 'THE CEO SEAT STILL HAS NO CREDENTIAL OF ITS OWN: % active fn.ceo_agent row(s) scoped to {ceo_agent}, expected 1.', v_cred;
  end if;

  select length(value) into v_secret_len from public.app_secrets where key = 'cred_fn_ceo_agent';
  if coalesce(v_secret_len, 0) <> 64 then
    raise exception 'cred_fn_ceo_agent is not a 32-byte hex secret: length=%', coalesce(v_secret_len, 0);
  end if;

  -- 3b. IT AUTHENTICATES TO ITS OWN RUNTIME, AND IS REFUSED EVERYWHERE ELSE. The second half is
  -- the one that matters: a credential that opens every door is the thing this whole scheme
  -- replaced.
  select value into v_secret from public.app_secrets where key = 'cred_fn_ceo_agent';
  v_auth  := public.fn_internal_auth(v_secret, 'ceo_agent');
  v_scope := public.fn_internal_auth(v_secret, 'accountant');
  if coalesce((v_auth->>'ok')::boolean, false) is not true or v_auth->>'context' <> 'fn.ceo_agent' then
    raise exception 'THE SEAT CANNOT AUTHENTICATE TO ITS OWN RUNTIME: %', v_auth;
  end if;
  if coalesce((v_scope->>'ok')::boolean, false) is not false or v_scope->>'error' <> 'out_of_scope' then
    raise exception 'NEGATIVE CONTROL FAILED: the CEO credential was accepted for accountant. %', v_scope;
  end if;

  -- 3c. THE REPORT NAMES ITS SENDER. Filed as the accountant, it must come out as the accountant.
  v_ok := public.fn_support_report_to_ceo(
    'probe:the_report_names_its_sender:accountant', 'routine',
    'PROBE - the accountant reports, and the row says so',
    jsonb_build_object('probe', true), '[]'::jsonb, 'delete this row', null, null,
    interval '1 day', 'accountant');
  if coalesce((v_ok->>'ok')::boolean, false) is not true then
    raise exception 'THE ACCOUNTANT COULD NOT REPORT: %', v_ok;
  end if;
  select * into v_row from public.support_ceo_report where id = (v_ok->>'report_id')::bigint;
  if v_row.source_agent <> 'accountant' or v_row.owner_role_id <> 'accountant' then
    raise exception 'THE REPORT STILL LIES ABOUT ITS SENDER: source_agent=% owner_role_id=%, expected accountant/accountant.',
      v_row.source_agent, v_row.owner_role_id;
  end if;
  delete from public.support_ceo_report where id = v_row.id;

  -- 3d. NEGATIVE CONTROL: a sender with no active reporting edge is REFUSED, and no row is
  -- written. The old code could not fail this way because it never looked the sender up.
  v_bad := public.fn_support_report_to_ceo(
    'probe:no_edge_no_report', 'routine', 'PROBE - a seat that reports to nobody',
    jsonb_build_object('probe', true), '[]'::jsonb, 'delete this row', null, null,
    interval '1 day', 'no_such_seat');
  if coalesce((v_bad->>'ok')::boolean, true) is not false then
    raise exception 'NEGATIVE CONTROL FAILED: a seat with no reporting edge was allowed to report. %', v_bad;
  end if;
  if exists (select 1 from public.support_ceo_report where idempotency_key = 'probe:no_edge_no_report') then
    raise exception 'NEGATIVE CONTROL FAILED: the refused report wrote a row anyway.';
  end if;

  -- 3e. THE DEFAULT IS UNCHANGED, so no existing six-argument caller moved.
  if (select pg_get_function_arg_default(p.oid, 10) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'fn_support_report_to_ceo') is distinct from '''customer_support''::text' then
    raise exception 'THE DEFAULT SENDER MOVED: existing six-argument callers would change behaviour.';
  end if;

  -- 3f. THE TRAY THE INBOX IS ABOUT TO LEARN TO READ IS NOT EMPTY, and it is exactly the rows the
  -- probe did not create.
  select count(*) into v_open from public.fn_support_open_reports();
  raise notice 'fn_support_open_reports() holds % open report(s) the CEO inbox does not yet read.', v_open;

  raise notice 'CEO SEAT: credential minted and scoped, report routine names its sender, negative controls held.';
end
$check$;

commit;
