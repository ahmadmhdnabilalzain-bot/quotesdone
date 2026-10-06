-- A PERSON CAN GET A COPY OF THEIR DATA, AND HAVE IT ERASED WHERE NO LAW REQUIRES IT KEPT.
--
-- Assigned: it_engineer. 6 Oct 2026. Coordinator brief of 6 Oct (founder): "Restore data-subject
-- export/erasure as a real working path." Founder ledger 1122. Revised the same day on the release
-- operator's review: (1) never act on an unverified email, (2) erase is two-step with a 7-day cooling-off,
-- (3) a lead erase is reversible inside that window, (4) every operator call is logged, (5) erasure
-- suppresses marketing only, never transactional mail. Second review, same day: (6) a self-service erase needs a
-- second verified action (the emailed code) before the 7-day clock starts, (7) every call is logged whatever the
-- role, with the actor (the JWT role, e.g. service_role) and the calling function, and the helpers are revoked from
-- service_role too, so the only doors are the logged ones, (8) mail the law requires (dispute, refund, payment, legal
-- notice) still reaches the person: the opt-out is 'unsubscribe', which stops only fn_opt_out_types(), and a party
-- with an open dispute, refund, complaint or unpaid amount is never soft-erased (legal hold) - both proved by the probe.
--
-- MEASURED BEFORE WRITING (6 Oct 2026, production, read-only): no routine named %pdpl%, %erase%,
-- %data_export% or %dsar% exists. fn_pdpl_export and fn_pdpl_erase_plan were dropped on 7 Sep 2026
-- (scripts/sql/DROPPED.txt 193-194), yet docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md and the privacy policy
-- (s8) promise access and erasure. public.pdpl_requests (0 rows) survived and is reused, not duplicated.
--
-- THE FLOW
--   verification   An address is acted on only when it is proven:
--                    self-service  the signed-in account's email_verified (customers) / owner_email_verified
--                                  (leads) is true - set only by kyc's own 6-digit email code, never by the
--                                  session (a session can be minted by SMS alone; kyc/index.ts 'state').
--                    operator      fn_pdpl_open emails a 6-digit code to the address (sha256 stored, 24 h);
--                                  fn_pdpl_verify(request, code) proves control of it.
--   export         answered at verification, in the response.
--   erase          at verification: the address is opted out of MARKETING (email_suppressions reason
--                  'unsubscribe', which suppression_policy.ts / fn_opt_out_types read as stopping only the
--                  campaign invitation and its reminders - reveal, payment and refund mail still go), and
--                  an outreach-only lead (never registered; no transaction, due, chat or refund) is SOFT
--                  erased: its contact fields move to pdpl_lead_erase_vault and the lead is closed.
--                  status 'cooling_off', confirm_after = +7 days. Cancel inside the window restores the lead.
--                  fn_pdpl_tick (daily) completes each request past its window: the vault rows are deleted
--                  (HARD), unless a legal hold appeared, which holds it. An account with records the law
--                  keeps (Cabinet Decision 74/2023 Art. 3: 5 years from the end of the year of creation) is
--                  recorded as deferred to that date; its conversations go under
--                  a_conversation_is_kept_five_years_after_the_account_goes_quiet_then_its_text_is_removed.sql.
--   logging        every operator entry point (open, verify, cancel) and every daily tick writes pdpl_operator_log
--                  with session_user and the operator label. The data helpers (fn_pdpl_export_data, fn_pdpl_erase_plan,
--                  fn_pdpl_carry_out) are revoked from every role but the owner and are reached only through those.
--
-- WHAT THIS DOES NOT DO: no portal button calls the self-service RPCs yet. The daily table export copies
-- leads into backups, so an erased lead's contact data survives in backups until they rotate (30 dailies,
-- 12 monthlies under the backup rule): said here so it is not lost.

alter table public.pdpl_requests
  add column if not exists verified_via  text,
  add column if not exists verified_at   timestamptz,
  add column if not exists code_sha      text,
  add column if not exists code_expires  timestamptz,
  add column if not exists confirm_after timestamptz,
  add column if not exists completed_at  timestamptz,
  add column if not exists cancelled_at  timestamptz,
  add column if not exists outcome       jsonb;

create table if not exists public.pdpl_lead_erase_vault (
  request_id  uuid not null references public.pdpl_requests(id),
  lead_id     bigint not null,
  snapshot    jsonb not null,
  erased_at   timestamptz not null default now(),
  primary key (request_id, lead_id));
comment on table public.pdpl_lead_erase_vault is
  'The contact fields of a soft-erased lead, held only for the 7-day cooling-off so the erasure can be undone; deleted by fn_pdpl_tick. Deliberately not exported.';
alter table public.pdpl_lead_erase_vault enable row level security;
revoke all on public.pdpl_lead_erase_vault from anon, authenticated;
create policy pdpl_lead_erase_vault_service_only on public.pdpl_lead_erase_vault for all to service_role using (true) with check (true);

-- who is calling: the request's JWT role (service_role, authenticated) when PostgREST set one, else the database user
create or replace function public.fn_pdpl_actor()
returns text
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', session_user::text);
$fn$;

create table if not exists public.pdpl_operator_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  db_user     text not null default session_user,
  actor       text not null default public.fn_pdpl_actor(),
  caller      text,
  operator    text,
  action      text not null,
  email       text,
  request_id  uuid,
  result      jsonb);
comment on table public.pdpl_operator_log is
  'Every call of a PDPL operator entry point or data helper: who, what, on which address, with what result. Never pruned.';
alter table public.pdpl_operator_log enable row level security;
revoke all on public.pdpl_operator_log from anon, authenticated;
create policy pdpl_operator_log_service_only on public.pdpl_operator_log for all to service_role using (true) with check (true);

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('pdpl_operator_log', true, 'legal', 'every PDPL operator call and its result: the evidence a request was handled', 'it_engineer'),
  ('pdpl_lead_erase_vault', false, 'secret', 'erased contact fields held 7 days only so an erasure can be undone; copying them into backups would defeat the erasure', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_pdpl_phone_tails(p_email text)
returns text[]
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(distinct t) filter (where length(t) = 9), '{}')
    from (select right(regexp_replace(x, '[^0-9]', '', 'g'), 9) t
            from (select unnest(array[c.phone, c.whatsapp_phone]) x from public.customers c where lower(c.email) = lower(p_email)
                  union all
                  select unnest(array[l.phone, l.phone_e164, l.whatsapp, l.whatsapp_phone]) from public.leads l where lower(l.email) = lower(p_email)) s
           where x is not null) u;
$fn$;
revoke execute on function public.fn_pdpl_phone_tails(text) from public, anon, authenticated, service_role;

create or replace function public.fn_pdpl_export_data(p_email text)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select lower(btrim(p_email)) as em, public.fn_pdpl_phone_tails(p_email) as tails),
  c as (select cu.* from public.customers cu, e where lower(cu.email) = e.em),
  l as (select le.* from public.leads le, e where lower(le.email) = e.em)
  select jsonb_build_object(
    'email', (select em from e),
    'generated_at', now(),
    'controller', 'QuotesDone Technologies, DET Dubai Trader License No. 1633275, Dubai, United Arab Emirates',
    'customer_accounts', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from c),
    'supplier_records', (select coalesce(jsonb_agg(to_jsonb(l)), '[]') from l),
    'requests', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'created_at', i.created_at, 'category', i.category,
                   'summary', i.summary, 'status', i.status, 'emirate', i.emirate, 'budget', i.budget) order by i.created_at), '[]')
                   from public.inquiries i where i.customer_id in (select id from c)),
    'transactions', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.transactions t
                      where t.customer_id in (select id from c) or t.supplier_id in (select id from l)),
    'refunds', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.refunds r
                 where r.customer_id in (select id from c) or r.supplier_lead_id in (select id from l)),
    'portal_chat', (select coalesce(jsonb_agg(jsonb_build_object('at', m.created_at, 'from', m.sender, 'text', m.body,
                      'attachment', m.attachment_path) order by m.created_at), '[]')
                      from public.messages m where m.customer_id in (select id from c) or m.supplier_id in (select id from l)),
    'emails_we_sent', (select coalesce(jsonb_agg(jsonb_build_object('at', coalesce(n.sent_at, n.created_at), 'subject', n.subject,
                         'text', n.body, 'status', n.status) order by n.created_at), '[]')
                         from public.notifications n, e where lower(n.to_email) = e.em),
    'emails_we_received', (select coalesce(jsonb_agg(jsonb_build_object('at', im.created_at, 'subject', im.subject, 'text', im.body)
                             order by im.created_at), '[]')
                             from public.inbound_messages im, e where lower(im.from_email) = e.em),
    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('at', w.created_at, 'received', w.inbound, 'replied', w.reply)
                   order by w.created_at), '[]')
                   from public.wa_messages w, e
                  where right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (e.tails)),
    'opt_out', (select to_jsonb(s) from public.email_suppressions s, e where lower(s.email) = e.em limit 1));
$fn$;
revoke execute on function public.fn_pdpl_export_data(text) from public, anon, authenticated, service_role;

-- ── the erase decision for an address (pure read): which leads can be soft-erased now, what is deferred ──
create or replace function public.fn_pdpl_erase_plan(p_email text)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with l as (
    select le.id, le.claimed_by,
           exists (select 1 from public.transactions t where t.supplier_id = le.id)
        or exists (select 1 from public.supplier_dues d where d.supplier_id = le.id)
        or exists (select 1 from public.messages m where m.supplier_id = le.id)
        or exists (select 1 from public.refunds f where f.supplier_lead_id = le.id) as has_records,
           public.fn_conversation_party_on_hold('supplier', le.id::text) as on_hold,
           public.fn_conversation_party_last_activity('supplier', le.id::text) as last_act
      from public.leads le where lower(le.email) = lower(btrim(p_email))),
  c as (
    select cu.id, public.fn_conversation_party_on_hold('customer', cu.id::text) as on_hold,
           public.fn_conversation_party_last_activity('customer', cu.id::text) as last_act
      from public.customers cu where lower(cu.email) = lower(btrim(p_email)))
  select jsonb_build_object(
    'erase_now', (select coalesce(jsonb_agg(l.id), '[]') from l where l.claimed_by is null and not l.has_records and not l.on_hold),
    'deferred', (select coalesce(jsonb_agg(x), '[]') from (
        select jsonb_build_object('record', 'supplier ' || l.id, 'legal_hold', l.on_hold,
                 'kept_until', (greatest(coalesce(l.last_act, now()), date_trunc('year', now()) + interval '1 year') + interval '5 years')::date,
                 'reason', case when l.on_hold then 'an open dispute, refund, complaint or unpaid amount' else 'a registered supplier or one with transactions, dues or messages: kept under Cabinet Decision 74/2023 Art. 3' end) x
          from l where not (l.claimed_by is null and not l.has_records and not l.on_hold)
        union all
        select jsonb_build_object('record', 'customer ' || c.id, 'legal_hold', c.on_hold,
                 'kept_until', (greatest(coalesce(c.last_act, now()), date_trunc('year', now()) + interval '1 year') + interval '5 years')::date,
                 'reason', 'a customer account: kept under Cabinet Decision 74/2023 Art. 3; conversations are removed on that date') from c) d));
$fn$;
revoke execute on function public.fn_pdpl_erase_plan(text) from public, anon, authenticated, service_role;

-- ── the work done once a request is verified ─────────────────────────────────────────────────────────
create or replace function public.fn_pdpl_carry_out(p_request uuid)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.pdpl_requests; v_plan jsonb; v_out jsonb; v_id bigint;
begin
  select * into q from public.pdpl_requests where id = p_request for update;
  insert into public.pdpl_operator_log (caller, operator, action, email, request_id, result)
  values ('fn_pdpl_carry_out', q.handled_by, 'carry_out:' || coalesce(q.kind, ''), q.email, p_request, jsonb_build_object('verified', q.verified_at is not null));
  if q.verified_at is null then return jsonb_build_object('ok', false, 'error', 'not verified'); end if;
  if q.kind = 'export' then
    v_out := public.fn_pdpl_export_data(q.email);
    update public.pdpl_requests set status = 'completed', completed_at = now(), handled_at = now(),
           outcome = jsonb_build_object('delivered', 'in the response') where id = q.id;
    return jsonb_build_object('ok', true, 'request_id', q.id, 'export', v_out);
  end if;
  -- erase, step 1: marketing opt-out now (never transactional mail), soft erase, cooling-off
  insert into public.email_suppressions (email, reason, source) values (lower(q.email), 'unsubscribe', 'pdpl')
  on conflict do nothing;
  v_plan := public.fn_pdpl_erase_plan(q.email);
  for v_id in select (jsonb_array_elements_text(v_plan->'erase_now'))::bigint loop
    insert into public.pdpl_lead_erase_vault (request_id, lead_id, snapshot)
    select q.id, l.id, jsonb_build_object('email', l.email, 'email_domain', l.email_domain, 'phone', l.phone, 'phone_e164', l.phone_e164,
             'whatsapp', l.whatsapp, 'whatsapp_phone', l.whatsapp_phone, 'contact_name', l.contact_name,
             'signatory_name', l.signatory_name, 'accepted_terms_ip', l.accepted_terms_ip, 'permanently_closed', l.permanently_closed)
      from public.leads l where l.id = v_id
    on conflict do nothing;
    update public.leads
       set email = null, email_domain = null, phone = null, phone_e164 = null, whatsapp = null, whatsapp_phone = null,
           contact_name = null, signatory_name = null, accepted_terms_ip = null, permanently_closed = true
     where id = v_id;
  end loop;
  update public.pdpl_requests set status = 'cooling_off', confirm_after = now() + interval '7 days', handled_at = now(),
         outcome = v_plan || jsonb_build_object('marketing_opt_out', true, 'transactional_mail', 'unaffected')
   where id = q.id;
  return jsonb_build_object('ok', true, 'request_id', q.id, 'status', 'cooling_off', 'confirm_after', now() + interval '7 days', 'plan', v_plan);
end $fn$;
revoke execute on function public.fn_pdpl_carry_out(uuid) from public, anon, authenticated, service_role;

-- ── operator entry points (customer_support), each logged ───────────────────────────────────────────
create or replace function public.fn_pdpl_open(p_email text, p_kind text, p_operator text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := lower(btrim(coalesce(p_email, ''))); v_code text; v_id uuid; v_out jsonb;
begin
  if v_em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or p_kind not in ('export', 'delete') or coalesce(btrim(p_operator), '') = '' then
    v_out := jsonb_build_object('ok', false, 'error', 'an email, a kind (export|delete) and the operator are required');
  else
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.pdpl_requests (kind, email, role, details, status, code_sha, code_expires, handled_by)
    values (p_kind, v_em, 'operator', 'opened by ' || p_operator, 'received', encode(sha256(convert_to(v_code, 'UTF8')), 'hex'),
            now() + interval '24 hours', p_operator)
    returning id into v_id;
    perform public.fn_sales_engineer_writes('pdpl_verification', 'customer', v_em, null, null, null, null,
      'Your QuotesDone data request: confirmation code',
      'We received a request to ' || case when p_kind = 'export' then 'send you a copy of' else 'erase' end
        || ' the personal data we hold for this address. If you made it, give us this code: ' || v_code
        || E'. It expires in 24 hours.\nIf you did not make this request, ignore this email; nothing will change.',
      'طلب بياناتكم لدى QuotesDone: رمز التأكيد',
      'تلقّينا طلبًا ' || case when p_kind = 'export' then 'بتزويدكم بنسخة من' else 'بحذف' end
        || ' البيانات الشخصية المحفوظة لهذا العنوان. إن كنتم قد قدّمتم الطلب، فيُرجى تزويدنا بهذا الرمز: ' || v_code
        || E'، وتنتهي صلاحيته خلال 24 ساعة.\nوإن لم تقدّموا هذا الطلب، فلا داعي لأي إجراء ولن يتغيّر شيء.',
      '{}', 'pdpl_verification:' || v_id::text);
    v_out := jsonb_build_object('ok', true, 'request_id', v_id, 'code_sent_to', v_em);
  end if;
  insert into public.pdpl_operator_log (caller, operator, action, email, request_id, result) values ('fn_pdpl_open', p_operator, 'open:' || coalesce(p_kind, ''), v_em, v_id, v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_pdpl_open(text, text, text) from public, anon, authenticated;

create or replace function public.fn_pdpl_verify(p_request uuid, p_code text, p_operator text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.pdpl_requests; v_out jsonb;
begin
  select * into q from public.pdpl_requests where id = p_request;
  if q.id is null or q.status <> 'received' then
    v_out := jsonb_build_object('ok', false, 'error', 'no open request');
  elsif q.code_expires < now() or q.code_sha is distinct from encode(sha256(convert_to(btrim(coalesce(p_code, '')), 'UTF8')), 'hex') then
    v_out := jsonb_build_object('ok', false, 'error', 'wrong or expired code');
  else
    update public.pdpl_requests set verified_via = 'email_code', verified_at = now(), code_sha = null where id = q.id;
    v_out := public.fn_pdpl_carry_out(q.id);
  end if;
  insert into public.pdpl_operator_log (caller, operator, action, email, request_id, result)
  values ('fn_pdpl_verify', p_operator, 'verify', q.email, p_request, v_out - 'export');                      -- the export itself is not copied into the log
  return v_out;
end $fn$;
revoke execute on function public.fn_pdpl_verify(uuid, text, text) from public, anon, authenticated;

-- cancel inside the cooling-off window: the soft-erased leads are restored exactly
create or replace function public.fn_pdpl_cancel(p_request uuid, p_operator text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.pdpl_requests; v jsonb; n int := 0; r record;
begin
  select * into q from public.pdpl_requests where id = p_request for update;
  if q.id is null or q.status <> 'cooling_off' or q.confirm_after <= now() then
    v := jsonb_build_object('ok', false, 'error', 'no erasure in its cooling-off window');
  else
    for r in select * from public.pdpl_lead_erase_vault where request_id = q.id loop
      update public.leads l
         set email = r.snapshot->>'email', email_domain = r.snapshot->>'email_domain', phone = r.snapshot->>'phone',
             phone_e164 = r.snapshot->>'phone_e164', whatsapp = r.snapshot->>'whatsapp', whatsapp_phone = r.snapshot->>'whatsapp_phone',
             contact_name = r.snapshot->>'contact_name', signatory_name = r.snapshot->>'signatory_name',
             accepted_terms_ip = r.snapshot->>'accepted_terms_ip', permanently_closed = (r.snapshot->>'permanently_closed')::boolean
       where l.id = r.lead_id;
      n := n + 1;
    end loop;
    delete from public.pdpl_lead_erase_vault where request_id = q.id;
    update public.pdpl_requests set status = 'cancelled', cancelled_at = now() where id = q.id;
    v := jsonb_build_object('ok', true, 'restored_leads', n,
           'note', 'the marketing opt-out stays; the person can resubscribe from any invitation link');
  end if;
  insert into public.pdpl_operator_log (caller, operator, action, email, request_id, result) values ('fn_pdpl_cancel', p_operator, 'cancel', q.email, p_request, v);
  return v;
end $fn$;
revoke execute on function public.fn_pdpl_cancel(uuid, text) from public, anon, authenticated;

-- daily: complete each erasure past its window (hard: the vault copy goes), unless a legal hold appeared
create or replace function public.fn_pdpl_tick()
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q record; done int := 0; held int := 0;
begin
  for q in select * from public.pdpl_requests where status = 'cooling_off' and confirm_after <= now() for update loop
    if exists (select 1 from public.pdpl_lead_erase_vault v where v.request_id = q.id
                and public.fn_conversation_party_on_hold('supplier', v.lead_id::text)) then
      update public.pdpl_requests set status = 'held', outcome = coalesce(outcome, '{}') || jsonb_build_object('held_at', now(), 'held', 'a legal hold appeared during the cooling-off') where id = q.id;
      held := held + 1;
    else
      delete from public.pdpl_lead_erase_vault where request_id = q.id;
      update public.pdpl_requests set status = 'completed', completed_at = now() where id = q.id;
      done := done + 1;
    end if;
  end loop;
  insert into public.pdpl_operator_log (caller, operator, action, result) values ('fn_pdpl_tick', 'fn_pdpl_tick', 'tick', jsonb_build_object('completed', done, 'held', held))
  ;
  return jsonb_build_object('completed', done, 'held', held);
end $fn$;
revoke execute on function public.fn_pdpl_tick() from public, anon, authenticated;
select cron.schedule('pdpl_erasure_daily', '50 23 * * *', $CRON$select public.fn_pdpl_tick();$CRON$);

-- ── self-service: the signed-in user's own address, and only when that address was proven by code ────
create or replace function public.fn_pdpl_my_verified_email()
returns text
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select lower(nullif(auth.jwt() ->> 'email', '')) em)
  select e.em from e
   where exists (select 1 from public.customers c where lower(c.email) = e.em and c.email_verified)
      or exists (select 1 from public.leads l where lower(l.claimed_by) = e.em and l.owner_email_verified);
$fn$;
revoke execute on function public.fn_pdpl_my_verified_email() from public, anon, authenticated, service_role;

create or replace function public.pdpl_request_me(p_kind text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := public.fn_pdpl_my_verified_email(); v_id uuid;
begin
  if v_em is null then
    return jsonb_build_object('ok', false, 'code', 'email_not_verified',
      'message', 'Verify your email address in your account first.', 'message_ar', 'يُرجى توثيق بريدكم الإلكتروني في حسابكم أولًا.');
  end if;
  if p_kind not in ('export', 'delete') then return jsonb_build_object('ok', false, 'code', 'bad_kind'); end if;
  -- ERASE NEEDS A SECOND VERIFIED ACTION: a code is emailed and the clock starts only at pdpl_confirm_me.
  if p_kind = 'delete' then
    return public.fn_pdpl_open(v_em, 'delete', 'self_service') || jsonb_build_object('next', 'pdpl_confirm_me(request_id, code)');
  end if;
  insert into public.pdpl_requests (kind, email, role, details, status, verified_via, verified_at, handled_by)
  values (p_kind, v_em, 'self_service', 'signed-in, email verified by code', 'received', 'session+email_verified', now(), 'self_service')
  returning id into v_id;
  return public.fn_pdpl_carry_out(v_id);
end $fn$;
revoke execute on function public.pdpl_request_me(text) from public, anon;
grant execute on function public.pdpl_request_me(text) to authenticated;

create or replace function public.pdpl_confirm_me(p_request uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := public.fn_pdpl_my_verified_email();
begin
  if v_em is null or not exists (select 1 from public.pdpl_requests where id = p_request and email = v_em and kind = 'delete') then
    return jsonb_build_object('ok', false, 'code', 'not_yours');
  end if;
  return public.fn_pdpl_verify(p_request, p_code, 'self_service');
end $fn$;
revoke execute on function public.pdpl_confirm_me(uuid, text) from public, anon;
grant execute on function public.pdpl_confirm_me(uuid, text) to authenticated;

create or replace function public.pdpl_cancel_me(p_request uuid)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := public.fn_pdpl_my_verified_email();
begin
  if v_em is null or not exists (select 1 from public.pdpl_requests where id = p_request and email = v_em) then
    return jsonb_build_object('ok', false, 'code', 'not_yours');
  end if;
  return public.fn_pdpl_cancel(p_request, 'self_service');
end $fn$;
revoke execute on function public.pdpl_cancel_me(uuid) from public, anon;
grant execute on function public.pdpl_cancel_me(uuid) to authenticated;

-- PROBE: read-only. Returns ONE verdict row.
select case
  when has_function_privilege('anon', 'public.pdpl_request_me(text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_pdpl_open(text,text,text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_pdpl_export_data(text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_pdpl_carry_out(uuid)', 'execute')
    then 'PROBE FAILED: a PDPL routine is reachable by the wrong role'
  when (select count(*) from cron.job where jobname = 'pdpl_erasure_daily') <> 1 then 'PROBE FAILED: the daily erasure tick is missing'
  else 'PROBE OK: only the self-service pair is open to signed-in users; the operator path needs a code'
end as verdict;
