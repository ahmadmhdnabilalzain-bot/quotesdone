-- A LICENCE OUR READER FAILED ON IS READ AGAIN, AND ITS SUPPLIER IS NEVER ASKED FOR IT.
-- Seat: customer_support (supplier registration; the gate and the decider are the sales_engineer's routines, the close is the
-- ceo seat's). 10 Nov 2026, item 6 of the supplier-journey audit's report (#1901), founder ruling 1608 (free audit and fixes
-- before the final paid test round; priority 1: supplier registration working 100%).
--
-- MEASURED BEFORE THIS FILE (code read on origin/main 8cc16e24b; production read-only 10 Nov 20:30 UTC):
--   * supplier_api process_docs (actions/documents.ts) answered `license_error: 'extract_failed'` to the browser when OUR
--     model read failed (license_extract 5xx, timeout, out of credit, unparseable) and stored nothing about it. supplier_portal
--     save_documents swallowed the same failure. The row then read exactly like a licence the supplier had made unreadable.
--   * fn_sales_engineer_verifies_supplier held it licence_unreadable / _expiry_unread / _number_unread / _authority_unread,
--     and fn_sales_engineer_decides_held_registrations asked the supplier three times (day 0, 3, 7) for "a clearer copy of the
--     whole page" and closed the registration at day 14 ("We asked three times for a trade licence we could accept").
--   * The OpenRouter account was out of credit on 10 Nov (memory checkpoint-10-nov), so every scanned licence was on that
--     path. Production today: 26 leads hold a licence, 0 are held for a licence reason, document_expiry_ai = 'on'.
--
-- WHAT THIS CHANGES:
--   * leads.licence_read_state ('read' | 'ours_failed' | 'file_unreadable', _shared/licence_read_state.ts decides it),
--     licence_read_at, licence_read_failed_since and licence_read_tries. Both licence readers write the state with the fields,
--     in the one update, so z20's re-verification sees both. a05_leads_licence_read_clock keeps the clock: a new licence path
--     resets the tries, the first 'ours_failed' starts licence_read_failed_since, any other state clears it.
--   * fn_sales_engineer_verifies_supplier: a blank field on a licence our reader failed on holds as 'licence_being_read'
--     (pending, needs_review), ahead of the four unread reasons. The live body read on 10 Nov (md5 4c2c25a8...), these lines added.
--   * fn_sales_engineer_decides_held_registrations: 'licence_being_read' is never asked and never closed; three days after
--     our first failure it is put to the ceo seat once per licence, the way a held registration with a reply already is.
--     The live body read on 10 Nov (md5 cb489960...), these lines added.
--   * fn_supplier_licence_reread_claim: the due licences for supplier_api docs_reread (the heartbeat's supplier_doc_reread
--     step, the existing re-read duty), 10 min x 2^tries apart, at most 8 tries (about 42 h of re-reads); it counts the try
--     as it hands one out. A demo row is never handed out in real mode (no model spend on our own fixtures).
-- WHAT IT DOES NOT CHANGE: what counts as read (supplier_doc_trades, document_expiry), the four hold reasons for a licence
-- our reader DID read (they still ask for a clearer copy), resend_inbound and wa_inbound (a licence that arrives by e-mail or
-- WhatsApp writes no state, so it keeps today's behaviour; said in the report), and any row: nothing is backfilled, a null
-- state behaves as before.
-- Deploy supplier_api and supplier_portal AFTER this is applied (they write the new columns).
-- Prevented by: supabase/functions/_shared/licence_read_state.test.ts (whose failure it is),
-- scripts/checks/a_licence_our_reader_failed_on_never_asks_the_supplier.test.mjs (the gate, the decider, the sweep and both
-- readers), and the probe of the same name (rolled back on production).

alter table public.leads add column if not exists licence_read_state text;
alter table public.leads add column if not exists licence_read_at timestamptz;
alter table public.leads add column if not exists licence_read_failed_since timestamptz;
alter table public.leads add column if not exists licence_read_tries integer not null default 0;
alter table public.leads drop constraint if exists leads_licence_read_state_known;
alter table public.leads add constraint leads_licence_read_state_known
  check (licence_read_state is null or licence_read_state in ('read', 'ours_failed', 'file_unreadable'));
create index if not exists leads_licence_ours_failed_idx on public.leads (licence_read_at) where licence_read_state = 'ours_failed';

create or replace function public.fn_leads_licence_read_clock()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- a new licence starts its own count; a re-read of the same path keeps it
  if tg_op = 'INSERT' or new.license_doc_path is distinct from old.license_doc_path then
    new.licence_read_tries := 0;
  end if;
  if new.licence_read_state = 'ours_failed' then
    if tg_op = 'INSERT' or old.licence_read_state is distinct from 'ours_failed'
       or new.license_doc_path is distinct from old.license_doc_path or new.licence_read_failed_since is null then
      new.licence_read_failed_since := now();
    end if;
  else
    new.licence_read_failed_since := null;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_leads_licence_read_clock() from public, anon, authenticated;
drop trigger if exists a05_leads_licence_read_clock on public.leads;
create trigger a05_leads_licence_read_clock before insert or update of licence_read_state, license_doc_path on public.leads
  for each row execute function public.fn_leads_licence_read_clock();

create or replace function public.fn_supplier_licence_reread_claim(p_limit integer default 3)
returns table(lead_id bigint, claimed_by text, license_doc_path text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
begin
  return query
  with due as (
    select l.id from public.leads l
     where l.licence_read_state = 'ours_failed'
       and l.license_doc_path is not null
       and coalesce(btrim(l.claimed_by), '') <> ''
       and not coalesce(l.banned, false)
       and l.licence_read_tries < 8
       and coalesce(l.licence_read_at, '-infinity'::timestamptz) <= now() - make_interval(mins => 10 * (2 ^ l.licence_read_tries)::int)
       -- our own fixtures are read again only by a fixture run: a demo licence never spends a real model call
       and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by) or coalesce(l.company_name, '') ~* '^\s*zz\s*demo') = v_fx
     order by l.licence_read_at nulls first, l.id
     limit greatest(1, least(coalesce(p_limit, 3), 20))
     for update of l skip locked
  )
  update public.leads l set licence_read_tries = l.licence_read_tries + 1, licence_read_at = now()
    from due where l.id = due.id
  returning l.id, l.claimed_by, l.license_doc_path;
end $fn$;
revoke execute on function public.fn_supplier_licence_reread_claim(integer) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int; v_doc_reading boolean; v_authority_unread boolean; v_authority_foreign boolean; v_authority_unknown boolean; v_services_open boolean; v_ours_failed boolean;
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
  -- FOUNDER RULING 1176 (7 Oct 2026): "auto fill the name from the attachment instead of rejection". A licence name
  -- that was READ (code, or the model under its confidence rule - licence_legal_name is only ever written so) and
  -- differs from the registered name becomes the company name: the old name is kept in agent_actions, the supplier
  -- is told in English, and the gate goes on as for a matching name. Not a hold, not a review.
  -- The one exception is a licence naming a company ANOTHER claimed supplier already registered: copying that name
  -- would break leads_claimed_company_name_uidx and hand one company's identity to another, so it stays the
  -- licence_name_mismatch hold of #1275 for a person to look at.
  if v_name_mismatch then
    v_name_taken := exists (select 1 from public.leads o where o.id <> l.id and o.claimed
                              and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name));
    if not v_name_taken then
      v_old_name := l.company_name;
      update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;
      l.company_name := btrim(l.licence_legal_name);
      v_name_mismatch := false;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_name_from_licence', 'auto_done', 'low',
              'Company name updated from the trade licence — ' || left(l.company_name, 120),
              'No action required. The registered name did not match the name the trade licence prints; the licence name now is the company name (founder ruling 1176). The previous name is in detail.previous_name.',
              jsonb_build_object('supplier_id', l.id, 'previous_name', v_old_name, 'new_name', l.company_name,
                                 'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path, 'source', p_source),
              'leads', l.id::text);
      if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
        perform public.fn_sales_engineer_writes('company_name_from_licence', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
          'Your company name was updated to match your trade licence',
          'Your registered company name was "' || coalesce(v_old_name, '') || '". Your trade licence prints "' || l.company_name
            || '", so your company name on QuotesDone is now "' || l.company_name || '". This is the name customers, quotes and documents show. '
            || 'If this is not right, reply to this email or upload the correct trade licence.',
          null, null, '{}'::text[], 'company_name_from_licence:' || l.id || ':' || md5(l.company_name));
      end if;
    end if;
  end if;
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  -- 2 Nov 2026 (ledger 1442, Supplier Agreement v16 clause 13): only a readable UAE authority approves automatically.
  v_authority_unread := l.license_doc_path is not null and coalesce(btrim(l.license_authority), '') = '';
  v_authority_foreign := l.license_doc_path is not null and public.fn_licence_authority_class(l.license_authority) = 'foreign';
  v_authority_unknown := l.license_doc_path is not null and public.fn_licence_authority_class(l.license_authority) = 'unknown';
  -- 10 Nov 2026 (customer_support, item 6 of #1901's report): a field is blank because OUR reader failed on the licence
  -- (leads.licence_read_state, _shared/licence_read_state.ts), not because the file is unreadable. It is held, never approved,
  -- and never put to the supplier as "upload a clearer copy": supplier_api docs_reread reads it again.
  v_ours_failed := l.license_doc_path is not null and coalesce(l.licence_read_state, '') = 'ours_failed'
                   and (v_name_unread or v_expiry_unread or v_number_unread or v_authority_unread);
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  -- 13 Oct 2026 (review of #1404): a profile or catalogue still being read ('reading', marked before its parse) holds
  -- approval: the gate never approves past a document whose read has not finished (or was killed mid-parse).
  v_doc_reading := exists (select 1 from public.supplier_capabilities c, jsonb_array_elements(coalesce(c.source_docs -> 'docs', '[]'::jsonb)) e
                            where c.supplier_id = l.id and e ->> 'status' = 'reading');
  -- 2 Nov 2026 (founder ledger 1469, a_supplier_is_verified_only_after_it_confirms_its_services): the supplier has confirmed what the company does, for the CURRENT version of the record.
  -- Seeders (their own source) are given a capability row by their harness and are not asked.
  v_services_open := p_source not in ('demo_factory', 'hvac_dress_rehearsal', 'document_intake_accuracy')
                     and not exists (select 1 from public.supplier_capabilities c
                                      where c.supplier_id = l.id and c.confirmed_at is not null
                                        and coalesce(c.confirmed_version, 0) >= coalesce((select max(k.version) from public.supplier_capability_confirmation k where k.supplier_id = l.id), 0));
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread
     and not v_authority_unread and not v_authority_foreign and not v_authority_unknown then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    -- An approved supplier is never asked to confirm services after the fact (ledger 1469): nobody is demoted.
    v_decision := 'approved';
  -- 7 Oct 2026 (review of #1275): an APPROVED supplier whose licence names another company is held for
  -- review, whatever asked - a licence change or a save. The approved branch above used to keep him approved
  -- and log "the licence name matches", which was false. A supplier whose name matches is untouched by a save.
  elsif coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_ours_failed then v_decision := 'pending'; v_reason := 'licence_being_read';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
  elsif v_expiry_unread then v_decision := 'pending'; v_reason := 'licence_expiry_unread';
  elsif v_number_unread then v_decision := 'pending'; v_reason := 'licence_number_unread';
  elsif v_authority_unread then v_decision := 'pending'; v_reason := 'licence_authority_unread';
  elsif v_authority_foreign then v_decision := 'pending'; v_reason := 'licence_authority_not_uae';
  elsif v_authority_unknown then v_decision := 'pending'; v_reason := 'licence_authority_unconfirmed';
  elsif v_doc_reading then v_decision := 'pending'; v_reason := 'documents_being_read';
  elsif v_services_open then v_decision := 'pending'; v_reason := 'services_unconfirmed';
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
  if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed', 'documents_being_read', 'licence_being_read') or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches, the licence is not known to be expired and the supplier has confirmed its services.'
            when 'pending' then case when v_reason = 'licence_being_read'
              then 'Held: our document reader failed on the trade licence (the model did not answer, is switched off, or the file could not be fetched to send it); the file itself was never judged unreadable. The supplier is told it is on our side and is not asked for a copy. supplier_api docs_reread reads it again (after 10 minutes, doubling, at most 8 tries); after 3 days fn_sales_engineer_decides_held_registrations puts it to the ceo seat. If you can read it by hand meanwhile, record the fields and approve.'
              when v_reason = 'documents_being_read'
              then 'Held: a company profile or catalogue of this supplier is still being read. The gate is run again when the read finishes; a read still unfinished after 30 minutes is marked unreadable and handed to you (document_read_stuck).'
              when v_reason = 'services_unconfirmed'
              then 'Held: the six mandatory items are complete, but the supplier has not yet confirmed what its company does. The portal shows the summary and keywords prepared from its company profile; the gate is run again the moment it presses confirm (source services_confirmed).'
              when v_reason in ('licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed')
              then 'Held: the issuing authority on the trade licence ' || case v_reason when 'licence_authority_unread' then 'could not be read' when 'licence_authority_unconfirmed' then 'is on no list we hold, which does not make it foreign' else 'names a foreign country or registry' end || '. fn_sales_engineer_decides_held_registrations asks the supplier and closes the registration through the ceo seat after 14 days.'
              when v_reason = 'licence_name_mismatch'
              then 'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.'
              when v_reason in ('licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' else 'licence number' end || ' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.'
              when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                             'licence_expiry_unread', v_expiry_unread, 'licence_number_unread', v_number_unread,
                             'services_unconfirmed', v_services_open, 'licence_read_state', l.licence_read_state,
                             'licence_authority_unread', v_authority_unread, 'licence_authority_foreign', v_authority_foreign, 'license_authority', l.license_authority,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$;


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_decides_held_registrations(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v jsonb; v_to text; v_first timestamptz; v_asks int; v_days numeric; v_key text; v_what text; v_replied boolean; v_ever_approved boolean; v_why text; v_asked int := 0; v_closed int := 0; v_out jsonb; v_waiting int := 0; v_to_ceo int := 0;
begin
  for r in select l.id, l.company_name, l.claimed_by, l.email, l.license_doc_path, l.licence_gate_reason reason, l.approved_at, l.phone, l.licence_read_failed_since from public.leads l
            where l.approval_status = 'pending' and not coalesce(l.banned, false)
              and l.licence_gate_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed', 'licence_name_mismatch', 'licence_being_read')
            order by l.id limit 200 loop
    -- A file may have arrived by a path that missed the trigger. A re-run that changes nothing writes no log.
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'mandatory_item_changed');
    if v ->> 'approval_status' is distinct from 'pending' or v ->> 'reason' is distinct from r.reason then continue; end if;
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_key := r.reason || ':' || coalesce(r.license_doc_path, '');
    -- OUR READER FAILED, NOT THE FILE (10 Nov 2026, customer_support; _shared/licence_read_state.ts). The supplier is never
    -- asked for a clearer copy and the registration is never closed for it: supplier_api docs_reread reads the licence again.
    -- One that is still unread three days after our first failure is put to the ceo seat, once per licence.
    if r.reason = 'licence_being_read' then
      if coalesce(r.licence_read_failed_since, p_at) <= p_at - interval '3 days'
         and not exists (select 1 from public.agent_actions a where a.kind = 'held_registration_for_ceo' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key) then
        perform public.fn_ceo_task_open('Decide a held supplier registration: ' || left(coalesce(r.company_name, '#' || r.id), 120),
          'Supplier ' || r.id || ' is held because our document reader has failed on its trade licence since ' || to_char(r.licence_read_failed_since at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai. The supplier was not asked for anything. Read the licence by hand, record the fields, then approve.');
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('sales_engineer', 'held_registration_for_ceo', 'auto_done', 'low', 'Held registration put to the ceo seat — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
                'No action required here. The ceo task decides it.', jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'why', 'our document reader could not read the licence for 3 days'), 'leads', r.id::text);
        v_to_ceo := v_to_ceo + 1;
      else
        v_waiting := v_waiting + 1;
      end if;
      continue;
    end if;
    select min(a.created_at), count(*) into v_first, v_asks from public.agent_actions a
     where a.kind = 'held_registration_asked' and a.target_table = 'leads' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key;
    v_days := coalesce(extract(epoch from p_at - v_first) / 86400, 0);
    -- A reply stops the close: a supplier who answered is never closed unheard. Mail by lead, WhatsApp by number.
    v_replied := v_asks > 0 and (exists (select 1 from public.inbound_messages m where m.lead_id = r.id and m.created_at > v_first)
      or exists (select 1 from public.wa_messages w where w.created_at > v_first and nullif(regexp_replace(coalesce(r.phone, ''), '[^0-9]', '', 'g'), '') = regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g')));
    v_ever_approved := r.approved_at is not null;
    if v_asks > 0 and (v_replied or (v_days >= 14 and (v_ever_approved or r.reason = 'licence_authority_unconfirmed'))) then
      v_why := case when v_replied then 'the supplier replied' when v_ever_approved then 'the supplier was approved before' else 'the authority is on no list we hold' end;
      if not exists (select 1 from public.agent_actions a where a.kind = 'held_registration_for_ceo' and a.target_id = r.id::text and a.detail ->> 'clock' = v_key) then
        perform public.fn_ceo_task_open('Decide a held supplier registration: ' || left(coalesce(r.company_name, '#' || r.id), 120),
          'Supplier ' || r.id || ' is held for ' || r.reason || ' and is not closed automatically because ' || v_why || '. Read the licence and any reply, then approve or ask again.');
        insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
        values ('sales_engineer', 'held_registration_for_ceo', 'auto_done', 'low', 'Held registration put to the ceo seat — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
                'No action required here. The ceo task decides it.', jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'why', v_why), 'leads', r.id::text);
      end if;
    elsif v_asks > 0 and v_days >= 14 then
      update public.leads set approval_status = 'rejected', verified = false, approval_decided_by = 'ceo',
             rejection_reason = 'registration incomplete after 14 days: ' || r.reason where id = r.id;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('ceo', 'held_registration_decision', 'auto_done', 'low', 'Held registration closed after 14 days — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
              'No action required. The supplier was asked three times and sent nothing new. Uploading a licence and saving reopens the registration.',
              jsonb_build_object('supplier_id', r.id, 'decision', 'closed', 'reason', r.reason, 'first_asked_at', v_first, 'asks', v_asks), 'leads', r.id::text);
      if v_to is not null then
        perform public.fn_sales_engineer_writes('registration_closed', 'supplier', v_to, r.id, null, null, null, 'Your QuotesDone supplier registration has closed',
          'We asked three times for a trade licence we could accept and have not received one, so your registration is now closed. Upload your current UAE trade licence in the Documents tab of https://quotesdone.com/portal and save your profile, and it opens again.',
          null, null, '{}'::text[], 'registration_closed:' || r.id || ':' || md5(v_key));
      end if;
      v_closed := v_closed + 1;
    elsif v_asks = 0 or (v_asks = 1 and v_days >= 3) or (v_asks = 2 and v_days >= 7) then
      v_what := case r.reason
        when 'licence_authority_not_uae' then 'The trade licence you uploaded was not issued by a UAE authority, and QuotesDone registers companies licensed in the UAE. Please upload your current UAE trade licence.'
        when 'licence_authority_unconfirmed' then 'We could not confirm the authority that issued your trade licence. Please reply to this e-mail naming the UAE authority or free zone that issued it, or upload a clearer copy of the whole page.'
        when 'licence_authority_unread' then 'We could not read the issuing authority on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_expiry_unread' then 'We could not read the expiry date on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_number_unread' then 'We could not read the licence number on your trade licence. Please upload a clearer copy of the whole page.'
        when 'licence_name_mismatch' then 'The company name on your trade licence is already registered with us by another account. Please upload the licence of your own company, or reply to this e-mail if this is your company.'
        else 'We could not read the company name on your trade licence. Please upload a clearer copy of the whole page.' end;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'held_registration_asked', 'auto_done', 'low', 'Asked for what a held registration is missing — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
              'No action required. Asked again at day 3 and day 7; the ceo seat closes it at day 14.',
              jsonb_build_object('supplier_id', r.id, 'clock', v_key, 'reason', r.reason, 'ask', v_asks + 1, 'told', v_to is not null), 'leads', r.id::text);
      if v_to is not null then
        perform public.fn_sales_engineer_writes('registration_held', 'supplier', v_to, r.id, null, null, null, 'Your QuotesDone registration: one thing is needed',
          v_what || ' Upload it in the Documents tab of https://quotesdone.com/portal; we read it as soon as it arrives. If you have a question, reply to this e-mail. If we hear nothing 14 days after our first request, the registration may close, and you can reopen it at any time.',
          null, null, '{}'::text[], 'registration_held:' || r.id || ':' || md5(v_key) || ':' || (v_asks + 1));
      end if;
      v_asked := v_asked + 1;
    end if;
  end loop;
  v_out := jsonb_build_object('asked', v_asked, 'closed', v_closed, 'being_read', v_waiting, 'being_read_to_ceo', v_to_ceo);
  perform public.fn_it_duty_ran('held_registrations', v_out);
  return v_out;
end $function$;

