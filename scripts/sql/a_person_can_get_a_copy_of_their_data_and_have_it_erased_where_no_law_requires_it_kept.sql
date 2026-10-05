-- A PERSON CAN GET A COPY OF THEIR DATA, AND HAVE IT ERASED WHERE NO LAW REQUIRES IT KEPT.
--
-- Assigned: it_engineer. 6 Oct 2026. Coordinator brief of 6 Oct (founder): "Restore data-subject
-- export/erasure as a real working path." Founder ledger 1122.
--
-- MEASURED BEFORE WRITING (6 Oct 2026, production, read-only): no routine named %pdpl%, %erase%,
-- %data_export%, %delete_account% or %dsar% exists. fn_pdpl_export and fn_pdpl_erase_plan were dropped
-- on 7 Sep 2026 (scripts/sql/DROPPED.txt 193-194) with the old structure, yet
-- docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md and the privacy policy (s8) still promise access and
-- erasure "through the existing pdpl_request / pdpl_erase functions". A promise with no path behind it.
--
-- WHAT THIS BUILDS:
--   pdpl_requests (existing)      every request and its answer (kind export|delete, status, handled_at).
--   fn_pdpl_export(email)             one JSON document with everything held under that email (and the
--                                     phone numbers on its accounts): account rows, requests, transactions,
--                                     refunds, portal chat, emails both ways, WhatsApp, opt-out record.
--   fn_pdpl_erase(email, apply)       the erasure decision, and with apply = true the erasure:
--     * always: the address goes on email_suppressions (reason 'pdpl_erasure'), so nothing more is sent.
--       That one row is kept on purpose: it is what stops us writing to the person again.
--     * a supplier lead that never registered and has no transaction, due or chat (an outreach-only
--       record): its personal contact fields are removed now (email, phones, WhatsApp, contact and
--       signatory names) and it is closed. The company name, trade and website are business data and stay.
--     * an account with records the law requires us to keep (Cabinet Decision 74/2023 Art. 3: five years
--       from the end of the calendar year of creation): DEFERRED, with the date the duty ends. Its
--       conversations are removed by conversation_retention_daily on that rule
--       (a_conversation_is_kept_five_years_after_the_account_goes_quiet_then_its_text_is_removed.sql).
--   pdpl_export_me() / pdpl_erase_me()  the same, for a signed-in user, keyed on the email in their own
--                                     session token: a real self-service path, no operator needed.
--
-- WHAT THIS DOES NOT DO: no portal button calls pdpl_export_me / pdpl_erase_me yet (the API exists);
-- requests by email to management@quotesdone.com are recorded in pdpl_requests and run by customer_support
-- with fn_pdpl_export / fn_pdpl_erase. It does not delete a registered customer's identity before the retention duty ends.

-- The request record already exists: public.pdpl_requests (id, kind export|delete, email, role, details, status,
-- created_at, handled_at, handled_by), RLS on, 0 rows (measured 6 Oct 2026). It is reused, not duplicated.

-- ── the phone tails on the accounts that carry this email (9 digits, as fn_conversation_party matches) ──
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
revoke execute on function public.fn_pdpl_phone_tails(text) from public, anon, authenticated;

create or replace function public.fn_pdpl_export(p_email text)
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
revoke execute on function public.fn_pdpl_export(text) from public, anon, authenticated;

create or replace function public.fn_pdpl_erase(p_email text, p_apply boolean default false)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_em text := lower(btrim(coalesce(p_email, '')));
  v_now_erased bigint[] := '{}';
  v_deferred jsonb := '[]';
  r record; v_until date;
begin
  if v_em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'error', 'not an email address');
  end if;
  -- leads: outreach-only records are erased now; a lead with any record the law keeps is deferred
  for r in select l.id, l.claimed_by,
                  exists (select 1 from public.transactions t where t.supplier_id = l.id)
               or exists (select 1 from public.supplier_dues d where d.supplier_id = l.id)
               or exists (select 1 from public.messages m where m.supplier_id = l.id)
               or exists (select 1 from public.refunds f where f.supplier_lead_id = l.id) as has_records,
                  public.fn_conversation_party_last_activity('supplier', l.id::text) as last_act
             from public.leads l where lower(l.email) = v_em loop
    if r.claimed_by is null and not r.has_records then
      v_now_erased := v_now_erased || r.id;
    else
      v_until := (greatest(coalesce(r.last_act, now()), date_trunc('year', now()) + interval '1 year') + interval '5 years')::date;
      v_deferred := v_deferred || jsonb_build_object('record', 'supplier ' || r.id, 'kept_until', v_until,
        'reason', 'a registered supplier or one with transactions, dues or messages: kept under Cabinet Decision 74/2023 Art. 3');
    end if;
  end loop;
  for r in select c.id, public.fn_conversation_party_last_activity('customer', c.id::text) as last_act
             from public.customers c where lower(c.email) = v_em loop
    v_until := (greatest(coalesce(r.last_act, now()), date_trunc('year', now()) + interval '1 year') + interval '5 years')::date;
    v_deferred := v_deferred || jsonb_build_object('record', 'customer ' || r.id, 'kept_until', v_until,
      'reason', 'a customer account: kept under Cabinet Decision 74/2023 Art. 3; conversations are removed on that date');
  end loop;

  if p_apply then
    insert into public.email_suppressions (email, reason, source) values (v_em, 'pdpl_erasure', 'pdpl')
    on conflict do nothing;
    update public.leads
       set email = null, email_domain = null, phone = null, phone_e164 = null, whatsapp = null, whatsapp_phone = null,
           contact_name = null, signatory_name = null, accepted_terms_ip = null, permanently_closed = true
     where id = any (v_now_erased);
  end if;
  return jsonb_build_object('ok', true, 'email', v_em, 'applied', p_apply,
    'suppressed', true, 'erased_now', to_jsonb(v_now_erased), 'deferred', v_deferred);
end $fn$;
revoke execute on function public.fn_pdpl_erase(text, boolean) from public, anon, authenticated;

-- ── self-service: the signed-in user's own email, from their own token, never a parameter ──────────
create or replace function public.pdpl_export_me()
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := lower(nullif(auth.jwt() ->> 'email', ''));
        v_out jsonb;
begin
  if v_em is null then return jsonb_build_object('ok', false, 'error', 'sign in first'); end if;
  v_out := public.fn_pdpl_export(v_em);
  insert into public.pdpl_requests (kind, email, role, details, status, handled_at, handled_by)
  values ('export', v_em, 'self_service', 'delivered in the response', 'completed', now(), 'pdpl_export_me');
  return v_out;
end $fn$;
revoke execute on function public.pdpl_export_me() from public, anon;
grant execute on function public.pdpl_export_me() to authenticated;

create or replace function public.pdpl_erase_me()
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_em text := lower(nullif(auth.jwt() ->> 'email', ''));
        v_out jsonb;
begin
  if v_em is null then return jsonb_build_object('ok', false, 'error', 'sign in first'); end if;
  v_out := public.fn_pdpl_erase(v_em, true);
  insert into public.pdpl_requests (kind, email, role, details, status, handled_at, handled_by)
  values ('delete', v_em, 'self_service', v_out::text, 'completed', now(), 'pdpl_erase_me');
  return v_out;
end $fn$;
revoke execute on function public.pdpl_erase_me() from public, anon;
grant execute on function public.pdpl_erase_me() to authenticated;

-- PROBE: read-only. Export and the erase PLAN on a ZZ DEMO address; anon cannot reach any of it.
with demo as (select lower(email) em from public.customers where is_demo and email ~* 'example\.invalid' limit 1),
x as (select public.fn_pdpl_export((select em from demo)) j),
p as (select public.fn_pdpl_erase((select em from demo), false) j)
select case
  when (select em from demo) is null then 'PROBE FAILED: no ZZ DEMO customer to export'
  when jsonb_array_length((select j from x)->'customer_accounts') < 1 then 'PROBE FAILED: the export missed the account'
  when ((select j from p)->>'applied')::boolean then 'PROBE FAILED: a plan applied'
  when jsonb_array_length((select j from p)->'deferred') < 1 then 'PROBE FAILED: a customer account was not deferred'
  when has_function_privilege('anon', 'public.fn_pdpl_export(text)', 'execute')
    or has_function_privilege('anon', 'public.pdpl_export_me()', 'execute')
    or has_function_privilege('authenticated', 'public.fn_pdpl_export(text)', 'execute')
    then 'PROBE FAILED: an exporter is reachable by the wrong role'
  else 'PROBE OK: export carries the account; erase plans a deferral; only the self-service pair is open to signed-in users'
end as verdict;
