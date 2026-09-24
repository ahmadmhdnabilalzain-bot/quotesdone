-- AN APPROVED SUPPLIER IS TOLD, AND THE LICENCE NAME MUST MATCH THE REGISTERED NAME (24 Sep 2026).
-- Seat: sales_engineer (decides and composes); customer_support delivers (its own door).
--
-- FOUNDER (ledger 993/994, 24 Sep 2026): the sales engineer's review checks the documents — licence
-- validity, that the licence name matches the registered company name, and expiry; the supplier's
-- categories come from the documents; and on approval the supplier is told on email AND WhatsApp that he
-- is verified, to open the portal, to confirm the categories we set from his documents, and to add more.
--
-- MEASURED 24 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * pricing_config.auto_approve_suppliers = true. fn_sales_engineer_verifies_supplier approves when
--     fn_supplier_mandatory_six is empty and the licence is not known to be expired. It sends nothing.
--   * trg_emit_supplier_approved -> fn_emit('supplier.approved') and no consumer of that event exists; no
--     approval notice of any kind was in notifications for 60 days. THERE WAS NO "YOU ARE APPROVED" NOTICE.
--   * THE NAME WAS NEVER CHECKED. supplier_api process_docs read the licence's legal name only through
--     license_extract (a model), behind app_secrets.document_expiry_ai, which is UNSET (so off): the name
--     was never read. And when it was read, it OVERWROTE leads.company_name (name_corrected_from kept the
--     old one), so a comparison after it would always have matched. 0 rows carry name_corrected_from.
--   * Categories from documents EXIST (_shared/supplier_doc_trades.ts, deterministic): each uploaded
--     document proposes trades into supplier_capabilities.proposed_trades; the supplier's confirm writes
--     supplier_capabilities.trades + confirmed_at. Nothing to build there; the notice lists them.
--   * https://quotesdone.com/portal answers HTTP 200 (curl, 24 Sep); send_whatsapp's PORTAL_URL is the same.
--   * WhatsApp: fn_wa_fanout (AFTER INSERT on notifications) twins every supplier email to the CONFIRMED
--     number fn_whatsapp_destination returns ('other' + whatsapp_verified_at -> whatsapp_phone; 'same' ->
--     the verified mobile; 'none' -> a twin a03 marks skipped; unanswered -> no twin). send_whatsapp maps
--     the new type 'supplier_approved' to the supplier_account_notice template (same PR). That template's
--     ledger row (messaging_template) reads 'received' (with Meta, not approved) as last checked 18 Sep, so
--     until Meta approves it the WhatsApp copy waits and expires after wa_stale_hours; the email carries
--     the whole message by itself.
--
-- WHAT THIS CHANGES
--   1. leads.licence_legal_name — the name the licence prints, written by process_docs (code reader first,
--      the model only when the flag is on). process_docs no longer overwrites company_name with it.
--   2. fn_company_name_norm / fn_supplier_licence_name_mismatch — deterministic: lowercase, '&' = 'and',
--      dots dropped, punctuation to spaces, legal-form words (LLC, FZE, Est, Co, ش.ذ.م.م …) removed.
--      A licence with no readable name is not a mismatch (nothing was read; nothing is guessed).
--   3. fn_sales_engineer_verifies_supplier: a mismatch is action_required, reason licence_name_mismatch
--      (the portal prints it under "why", serverCopy.ts). Order: missing items, then name, then expiry.
--      An already-approved supplier stays approved, as for expiry. z20 re-verifies on licence_legal_name.
--   4. trg_sales_engineer_tells_the_supplier_he_is_approved: on the transition to approved, once per
--      supplier (dedupe key supplier_approved:<id>), the sales engineer hands customer_support one English
--      email to the portal account address (claimed_by); fn_wa_fanout makes the WhatsApp twin. Refused by
--      the existing guard fn_seat_clock_refusal (fixture subject -> fixture address only, real subject never
--      to a fixture address, suppression, dead domain). A failure to queue never blocks the approval.
--
-- NOT CHANGED: fn_emit_supplier_approved, the mandatory six, matching, the template text.
--
--   node scripts/apply_sql.mjs scripts/sql/an_approved_supplier_is_told_and_the_licence_name_must_match.sql --apply --ddl
--   then run scripts/sql/an_approved_supplier_is_told_and_the_licence_name_must_match_probe.sql (PROBE OK)

set local lock_timeout = '5s';

-- ── 1. the name the licence prints ───────────────────────────────────────────────────────────────
alter table public.leads add column if not exists licence_legal_name text;
comment on column public.leads.licence_legal_name is
  'The company name printed on the uploaded trade licence (supplier_api process_docs: code reader, then license_extract when document_expiry_ai is on). Compared with company_name by fn_supplier_licence_name_mismatch; never copied over it.';

-- ── 2. the comparison ────────────────────────────────────────────────────────────────────────────
-- ponytail: a fixed legal-form word list, Latin and Arabic; a licence spelling a name in the other
-- script ("Al Meydan" vs «الميدان») reads as a mismatch and the supplier is asked to fix it. Add a
-- transliteration step if real registrations show that case.
create or replace function public.fn_company_name_norm(p text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(string_agg(w, '' order by i), '')
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[.''’`]', '', 'g'),
                                '[^[:alnum:]]+', ' ', 'g')), ' ') with ordinality t(w, i)
   where w <> '' and w not in ('llc', 'fze', 'fzco', 'fzllc', 'fz', 'dmcc', 'est', 'establishment', 'co', 'company',
                               'ltd', 'limited', 'plc', 'inc', 'and', 'the', 'sole', 'proprietorship', 'br', 'branch',
                               'شذمم', 'ذمم', 'مؤسسة', 'شركة', 'ذات', 'مسؤولية', 'مسئولية', 'محدودة', 'فرع', 'و')
$fn$;
revoke execute on function public.fn_company_name_norm(text) from public, anon, authenticated;

create or replace function public.fn_supplier_licence_name_mismatch(p public.leads)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_company_name_norm(p.licence_legal_name) <> ''
     and public.fn_company_name_norm(p.licence_legal_name) <> public.fn_company_name_norm(p.company_name)
$fn$;
revoke execute on function public.fn_supplier_licence_name_mismatch(public.leads) from public, anon, authenticated;

-- ── 3. the review reads it ───────────────────────────────────────────────────────────────────────
-- Body as live (the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql's), plus
-- v_name_mismatch. Nothing else moved.
create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text default 'save_profile')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
begin
  select * into l from public.leads where id = p_lead_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;
  -- A registration closed for being incomplete (fn_sales_engineer_supplier_documents_tick) is re-opened
  -- by the supplier saving again: the closing notice tells them they may. Any other rejection stands.
  if coalesce(l.banned, false)
     or (coalesce(l.approval_status, '') = 'rejected'
         and not (p_source = 'save_profile' and coalesce(l.rejection_reason, '') like 'registration incomplete after %')) then
    return jsonb_build_object('ok', true, 'decision', 'unchanged', 'approval_status', l.approval_status);
  end if;

  v_missing := public.fn_supplier_mandatory_six(l);
  -- "Not known to be expired": license_extract leaves the expiry null when the licence prints none, and
  -- blocking on that would refuse suppliers whose licence genuinely has no date (29 Jul 2026 note).
  v_expired := l.license_expiry is not null and l.license_expiry < current_date;
  -- 24 Sep 2026: the licence must be this company's. Unread name = not a mismatch (nothing guessed).
  v_name_mismatch := public.fn_supplier_licence_name_mismatch(l);
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := 'approved';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif coalesce(v_auto, false) then v_decision := 'approved';
  else v_decision := 'pending';
  end if;

  update public.leads
     set approval_status = v_decision,
         verified = (v_decision = 'approved'),
         approved_at = case when v_decision = 'approved' then coalesce(approved_at, now()) else approved_at end,
         approval_decided_by = 'sales_engineer',
         licence_gate_reason = v_reason
   where id = p_lead_id
     and (approval_status is distinct from v_decision or verified is distinct from (v_decision = 'approved')
          or licence_gate_reason is distinct from v_reason);
  get diagnostics v_changed = row_count;

  -- Every decision is recorded; a re-run by the trigger that changed nothing is not a decision.
  if v_changed > 0 or p_source <> 'mandatory_item_changed' then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', 'auto_done',
          case when v_decision = 'action_required' then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.'
            when 'pending' then 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.'
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_legal_name', l.licence_legal_name,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$;

-- A licence read that lands a (different) name re-runs the review, like any mandatory item.
drop trigger if exists z20_leads_mandatory_item_landed_reverifies on public.leads;
create trigger z20_leads_mandatory_item_landed_reverifies
  after update of company_name, phone, phone_e164, owner_phone_verified, owner_email_verified, license_doc_path,
                  license_expiry, company_profile_doc_path, signed_terms_path, licence_legal_name
  on public.leads for each row
  when (new.approval_status = any (array['action_required', 'pending']) and pg_trigger_depth() < 1)
  execute function public.fn_leads_mandatory_item_landed_reverifies();

-- ── 4. the approval notice ───────────────────────────────────────────────────────────────────────
-- The categories are the confirmed trades when the supplier has confirmed, otherwise what his documents
-- proposed (minus any he excluded). The subject is also WhatsApp {{1}} (send_whatsapp: <= 90 chars).
-- Never the word "AI", no licence number (founder rules, 23 Sep).
create or replace function public.fn_supplier_approved_notice_compose(p public.leads)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), ''); v_cats text; v_n int; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/portal';
  select string_agg('• ' || coalesce(t.label, c), E'\n' order by coalesce(t.label, c)), count(*) into v_cats, v_n
    from public.supplier_capabilities sc
    cross join lateral unnest(case when sc.confirmed_at is not null and cardinality(sc.trades) > 0 then sc.trades
                                   else array(select x from unnest(coalesce(sc.proposed_trades, '{}')) x
                                               where x <> all (coalesce(sc.excluded_trades, '{}'))) end) c
    left join public.taxonomy_trade t on t.code = c
   where sc.supplier_id = p.id;

  v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
    || 'Your company is now verified on QuotesDone. Our sales engineer has reviewed your registration documents, and your supplier account is approved.'
    || E'\n\n'
    || case when coalesce(v_n, 0) > 0
         then 'From your documents we have set these categories for your company:' || E'\n' || v_cats
         else 'We could not read any categories from your documents, so none are set yet. Until you add them, no inquiry can reach you.' end
    || E'\n\nWhat to do now (about two minutes):'
    || E'\n1. Open your supplier portal: ' || v_link
    || E'\n2. In the Services tab, check that the categories are correct, and press "Remove this trade" for any your company does not work in.'
    || E'\n3. Add any categories and services we missed, then press "Confirm my services".'
    || E'\n\nInquiries are matched to the categories and services you confirm, so the sooner you confirm them, the sooner the right inquiries reach you.'
    || E'\n\nNeed help? Reply to this e-mail or message us on WhatsApp.'
    || E'\n\nKind regards,\nQuotesDone Customer Support';
  return jsonb_build_object('lang', 'en', 'subject', 'You are verified on QuotesDone: please confirm your categories',
                            'body', v_body, 'link', v_link, 'categories', coalesce(v_n, 0));
end
$fn$;
revoke execute on function public.fn_supplier_approved_notice_compose(public.leads) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_tells_the_supplier_he_is_approved()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_to text := lower(btrim(coalesce(new.claimed_by, ''))); v_why text; m jsonb;
begin
  if tg_op = 'UPDATE' and coalesce(old.approval_status, '') = 'approved' then return null; end if;   -- the transition only
  v_why := public.fn_seat_clock_refusal(public.fn_seat_clock_lead_is_fixture(new), v_to, 'supplier_approved');
  if v_why is null then
    m := public.fn_supplier_approved_notice_compose(new);
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_approved', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', v_to, 'to_role', 'supplier', 'lead_id', new.id, 'lang', m->>'lang',
      'subject', m->>'subject', 'body', m->>'body',
      'dedupe_key', 'supplier_approved:' || new.id)));
  end if;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_approved_notice', case when v_why is null then 'auto_done' else 'skipped' end, 'low',
          left('Approval notice ' || case when v_why is null then 'queued' else 'not sent (' || v_why || ')' end
               || ' — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'to_email', nullif(v_to, ''), 'not_sent', v_why, 'categories', m->'categories'),
          'leads', new.id::text);
  return null;
exception when others then
  -- The approval stands whatever happens here; the failure is on the record for the sales engineer.
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_approved_notice', 'failed', 'medium',
          left('Approval notice failed — ' || coalesce(new.company_name, 'supplier #' || new.id), 200),
          jsonb_build_object('supplier_id', new.id, 'error', left(sqlerrm, 500)), 'leads', new.id::text);
  return null;
end
$fn$;
revoke execute on function public.fn_sales_engineer_tells_the_supplier_he_is_approved() from public, anon, authenticated;

drop trigger if exists trg_sales_engineer_tells_the_supplier_he_is_approved on public.leads;
create trigger trg_sales_engineer_tells_the_supplier_he_is_approved
  after insert or update of approval_status on public.leads
  for each row
  when (new.approval_status = 'approved')
  execute function public.fn_sales_engineer_tells_the_supplier_he_is_approved();
