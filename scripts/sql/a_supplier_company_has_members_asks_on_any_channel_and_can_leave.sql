-- A SUPPLIER COMPANY HAS MEMBERS, ASKS ON ANY CHANNEL, AND CAN LEAVE.
--
-- Assigned: customer_support + sales_engineer seats. Agent: SUPPLIER_W2. 16 Nov 2026. Founder ledgers 1711-1713 ("is this a real
-- company? find those holes and build them"); the supplier hole hunt of 16 Nov (scratchpad holes/SUPPLIER.md items 4, 5, 6, 9,
-- 10, 12). Built on main 27969740b (wave C #2015: the supplier known on every channel, not-for-me, strikes, flags).
--
-- MEASURED BEFORE WRITING (16 Nov 2026, read from code and one light SELECT of routine md5s on production):
--   4. A company is ONE e-mail (leads.claimed_by). supplier_api claim answers 409 "already claimed by another account"
--      (actions/account.ts:36), the invitation screen promises "If a colleague claimed it, ask them to add you"
--      (src/components/portal/supplier/core/Login.tsx:50) and no add-member action exists; a quotation e-mailed from a
--      colleague's address is "unverified" (resend_inbound/quote_by_email.ts verifiedSender); WhatsApp knows one owner
--      number (fn_whatsapp_owner); there is no way to hand the company to another person.
--   5. Only the portal (messages_api clarify_ask) writes rfq_clarification; a question by e-mail or WhatsApp reaches nobody,
--      nobody tries the job's own facts first, and the customer is asked once with no reminder.
--   6. "Close my account" changes nothing: a registered supplier is always 'deferred' (fn_pdpl_erase_plan) and nothing
--      pauses, unmatches or withdraws him.
--   9. "Why did I lose?" is a fixed 5 % band over quote_amount, which mixes VAT bases (supplier_api/loss_feedback.ts); the
--      customer is never asked, and a request that ends revealed or expired gives the losers nothing.
--  10. customer_followup records hired / not hired and never tells the revealed supplier; he has no "the customer is not
--      answering" door.
--  12. "I'll pay for more leads / exclusivity" is answered correctly and forgotten.
--
-- WHO DECIDES WHAT (rulings 1663/1664): what a person WROTE is read by a model (the channel's reader:
-- _shared/supplier_instruction.ts; the sales engineer's first answer and the loss reason: _shared/job_question.ts,
-- supplier_api/loss_feedback.ts). These routines only do what must be exact or safe: who belongs to which company, codes,
-- scoping by supplier id, clocks, counts, and what the law keeps.
--
-- THE PARTS
--   1. supplier_member, fn_supplier_company_of: a company's owner (leads.claimed_by) adds estimators (may quote) and viewers
--      (read only). Every member signs in with his own e-mail code (login_otp), is screened against the same sanctions
--      lists as the owner (fn_supplier_member_screen), and is resolved to the company on every channel: the portal door,
--      an e-mail he sends, a WhatsApp number he confirmed (fn_whatsapp_owner gains a member branch).
--   2. The ownership transfer: the owner names an active member and confirms with a code sent to the owner's address.
--   3. A job question from any channel is one rfq_clarification row; the sales engineer reads it first (columns below),
--      the customer is asked only what the job's facts do not answer, and chased once (fn_job_questions_due).
--   4. fn_supplier_close_account: withdraw or keep live quotations, stop matching, record what the law keeps and until when,
--      and confirm it in writing. Proposed and confirmed on e-mail and WhatsApp; reopened by the owner.
--   5. inquiry_decision_reason + supplier_loss_reason: the customer's optional word at the reveal; the model's reason per
--      losing supplier, written once (fn_supplier_loss_reasons_due lists the pairs, ex-VAT facts only).
--   6. The follow-up's hired / not hired reaches the revealed supplier (trigger z35); "the customer is not answering"
--      nudges the customer once and is kept as evidence (supplier_customer_silence).
--   7. supplier_demand_signal + fn_ceo_supplier_demand_signals: an offer to pay for leads or exclusivity is recorded for
--      the CEO. Nobody is offered paid ranking.
--
-- Prevented by: a_supplier_company_has_members_asks_on_any_channel_and_can_leave_probe.sql (local Postgres 16), the deno
-- tests named in each edge file, and _shared/supplier_company_instruction.test.ts (15 scenarios EN/AR).
-- fn_whatsapp_owner: redefined from the PRODUCTION body (md5 7c230a4015e017cd1d6ab84b91af4098, read 16 Nov 2026, equal to
-- a_phone_tail_never_joins_two_people.sql); only the member branch is added.

set local lock_timeout = '3s';

-- ── 1. members ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_member (
  id                 bigint generated always as identity primary key,
  lead_id            bigint not null references public.leads(id),
  email              text not null,
  name               text not null,
  phone              text,
  role               text not null check (role in ('estimator', 'viewer')),
  status             text not null default 'invited' check (status in ('invited', 'active', 'screening', 'removed', 'became_owner')),
  invited_by         text not null,
  invited_at         timestamptz not null default now(),
  accepted_at        timestamptz,
  email_verified_at  timestamptz,
  phone_code_sha     text,
  phone_code_expires timestamptz,
  phone_code_tries   integer not null default 0,
  phone_confirmed_at timestamptz,
  screened_at        timestamptz,
  screen             jsonb,
  removed_at         timestamptz,
  removed_by         text,
  constraint supplier_member_email_lower_ck check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
-- one company per person at a time (an e-mail is one person's sign-in)
create unique index if not exists supplier_member_one_company_uq on public.supplier_member (email) where status in ('invited', 'active', 'screening');
create index if not exists supplier_member_lead_idx on public.supplier_member (lead_id) where status in ('invited', 'active', 'screening');
alter table public.supplier_member enable row level security;
drop policy if exists supplier_member_service_role_only on public.supplier_member;
create policy supplier_member_service_role_only on public.supplier_member as permissive for all to public using (false) with check (false);
revoke all on public.supplier_member from anon, authenticated;

-- the ownership transfer's codes (section 2 uses them; fn_supplier_team reads the one waiting)
create table if not exists public.supplier_ownership_transfer (
  id           bigint generated always as identity primary key,
  lead_id      bigint not null references public.leads(id),
  from_email   text not null,
  to_email     text not null,
  code_sha     text not null,
  code_expires timestamptz not null,
  tries        integer not null default 0,
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,
  cancelled_at timestamptz
);
create index if not exists supplier_ownership_transfer_lead_idx on public.supplier_ownership_transfer (lead_id, created_at desc);
alter table public.supplier_ownership_transfer enable row level security;
drop policy if exists supplier_ownership_transfer_service_role_only on public.supplier_ownership_transfer;
create policy supplier_ownership_transfer_service_role_only on public.supplier_ownership_transfer as permissive for all to public using (false) with check (false);
revoke all on public.supplier_ownership_transfer from anon, authenticated;

-- A member counts only while his screen is clear: 'active', or 'screening' whose every hit a person decided was not him.
create or replace function public.fn_supplier_member_counts(p_member bigint)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((
    select case
             when m.status = 'active' then true
             when m.status = 'screening' then not exists (
               select 1 from public.supplier_screening_hit h
                where h.lead_id = m.lead_id and h.field = 'member' and h.supplier_value = m.name and h.status <> 'false_positive')
             else false end
      from public.supplier_member m where m.id = p_member), false);
$fn$;
revoke execute on function public.fn_supplier_member_counts(bigint) from public, anon, authenticated;

-- Which company an address acts for, and as what. The owner is the claimed_by address; a member acts for the company's
-- address (company_email), so every existing door that scopes by claimed_by keeps scoping by the company.
create or replace function public.fn_supplier_company_of(p_email text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_e text := lower(btrim(coalesce(p_email, ''))); l record; m record;
begin
  if v_e = '' then return null; end if;
  select id, claimed_by, company_name into l from public.leads where lower(claimed_by) = v_e order by id limit 1;
  if found then
    return jsonb_build_object('role', 'owner', 'lead_id', l.id, 'company_email', l.claimed_by, 'member_email', v_e, 'company_name', l.company_name);
  end if;
  select sm.*, le.claimed_by, le.company_name into m
    from public.supplier_member sm join public.leads le on le.id = sm.lead_id
   where sm.email = v_e and sm.status in ('invited', 'active', 'screening') order by sm.id limit 1;
  if not found or m.claimed_by is null then return null; end if;
  if m.status = 'invited' then
    return jsonb_build_object('invitation', jsonb_build_object('member_id', m.id, 'lead_id', m.lead_id, 'company_name', m.company_name,
      'role', m.role, 'invited_by', m.invited_by, 'invited_at', m.invited_at));
  end if;
  if not public.fn_supplier_member_counts(m.id) then
    return jsonb_build_object('held', jsonb_build_object('member_id', m.id, 'company_name', m.company_name, 'why', 'screening'));
  end if;
  return jsonb_build_object('role', m.role, 'lead_id', m.lead_id, 'company_email', m.claimed_by, 'member_email', v_e,
    'member_name', m.name, 'member_id', m.id, 'company_name', m.company_name,
    'phone_confirmed', m.phone_confirmed_at is not null);
end $fn$;
revoke execute on function public.fn_supplier_company_of(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_company_of(text) to service_role;

-- The member's name against the same lists, by the same rule the weekly screen uses for an owner or contact (exact, or every
-- word of the listing in his name), and his address against sanctions_ban. A hit is an open supplier_screening_hit
-- (field 'member'), which freezes the company exactly as an owner's hit does, and a CEO decision task, as the weekly screen.
create or replace function public.fn_supplier_member_screen(p_member bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare m public.supplier_member; v_new int := 0; v_hits int := 0; h record; v_title text; l record;
begin
  select * into m from public.supplier_member where id = p_member;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  if exists (select 1 from public.sanctions_ban b where lower(b.account_email) = m.email or lower(b.contact_email) = m.email) then
    update public.supplier_member set status = 'removed', removed_at = now(), removed_by = 'sanctions_screen', screened_at = now(),
           screen = jsonb_build_object('banned_address', true) where id = p_member;
    return jsonb_build_object('ok', false, 'code', 'refused');
  end if;
  for h in
    select e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from (select public.fn_screening_normalise(m.name) as norm, public.fn_screening_tokens(m.name) as toks) s
      join public.screening_entry e
        on e.run_id in (select distinct on (r.source) r.id from public.screening_run r order by r.source, r.fetched_at desc)
       and ((s.norm = e.name_norm and length(s.norm) >= 6)
         or (cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2 and e.tokens <@ s.toks))
  loop
    v_hits := v_hits + 1;
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, m.lead_id, 'member', m.name, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;
  update public.supplier_member set screened_at = now(), screen = jsonb_build_object('hits', v_hits, 'new', v_new),
         status = case when v_hits > 0 and status in ('invited', 'active') then 'screening' else status end
   where id = p_member;
  if v_new > 0 then
    select company_name into l from public.leads where id = m.lead_id;
    v_title := 'Sanctions screening hit (team member): ' || coalesce(l.company_name, 'lead #' || m.lead_id) || ' — lead #' || m.lead_id;
    if not exists (select 1 from public.org_tasks where title = v_title and status not in ('done', 'cancelled')) then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_title,
              'A person the company added as a team member matched a sanctions listing when he was added. Compare his name with the '
              || 'listing and decide each hit with public.fn_supplier_screening_decide(<hit_id>, ''confirmed'' | ''false_positive'', ''ceo''). '
              || 'He cannot act for the company until every hit is decided not to be him; the company is frozen like an owner hit.',
              'assigned', 'supervised', false, 'compliance_check', 'ceo');
    end if;
  end if;
  return jsonb_build_object('ok', true, 'hits', v_hits, 'clear', v_hits = 0);
end $fn$;
revoke execute on function public.fn_supplier_member_screen(bigint) from public, anon, authenticated;

-- The team as the owner and his members see it (never another company's).
create or replace function public.fn_supplier_team(p_lead bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'owner', (select jsonb_build_object('email', l.claimed_by, 'company_name', l.company_name) from public.leads l where l.id = p_lead),
    'members', coalesce((select jsonb_agg(jsonb_build_object('email', m.email, 'name', m.name, 'role', m.role,
                          'status', case when m.status = 'screening' and public.fn_supplier_member_counts(m.id) then 'active' else m.status end,
                          'invited_at', m.invited_at, 'accepted_at', m.accepted_at,
                          'phone_tail', right(regexp_replace(coalesce(m.phone, ''), '[^0-9]', '', 'g'), 4),
                          'phone_confirmed', m.phone_confirmed_at is not null) order by m.invited_at)
                         from public.supplier_member m where m.lead_id = p_lead and m.status in ('invited', 'active', 'screening')), '[]'::jsonb),
    'transfer', (select jsonb_build_object('to_email', t.to_email, 'expires', t.code_expires) from public.supplier_ownership_transfer t
                  where t.lead_id = p_lead and t.confirmed_at is null and t.cancelled_at is null and t.code_expires > now()
                  order by t.id desc limit 1));
$fn$;

create or replace function public.fn_supplier_member_invite(p_lead bigint, p_actor text, p_email text, p_role text, p_name text, p_phone text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; v_e text := lower(btrim(coalesce(p_email, ''))); v_name text := btrim(coalesce(p_name, '')); v_id bigint; v_scr jsonb;
begin
  select id, claimed_by, company_name, banned into l from public.leads where id = p_lead;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then
    return jsonb_build_object('ok', false, 'code', 'owner_only', 'error', 'Only the company''s owner can add people.');
  end if;
  if coalesce(l.banned, false) or exists (select 1 from public.sanctions_ban b where b.lead_id = p_lead) then
    return jsonb_build_object('ok', false, 'code', 'company_closed');
  end if;
  if p_role not in ('estimator', 'viewer') then return jsonb_build_object('ok', false, 'code', 'bad_role', 'error', 'Choose estimator or viewer.'); end if;
  if v_e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'code', 'bad_email', 'error', 'Enter the person''s e-mail address.'); end if;
  if length(v_name) < 2 then return jsonb_build_object('ok', false, 'code', 'name_required', 'error', 'Enter the person''s full name as on his ID: every member is screened like the owner.'); end if;
  if v_e = lower(l.claimed_by) then return jsonb_build_object('ok', false, 'code', 'is_owner', 'error', 'That is the owner''s own address.'); end if;
  if exists (select 1 from public.leads x where lower(x.claimed_by) = v_e) then
    return jsonb_build_object('ok', false, 'code', 'owns_a_company', 'error', 'That address already manages a company on QuotesDone. It cannot be added to a second one.');
  end if;
  if exists (select 1 from public.customers c where lower(c.email) = v_e) then
    return jsonb_build_object('ok', false, 'code', 'is_customer', 'error', 'That address is a customer account on QuotesDone. Ask him to use his work address.');
  end if;
  if exists (select 1 from public.supplier_member m where m.email = v_e and m.status in ('invited', 'active', 'screening')) then
    return jsonb_build_object('ok', false, 'code', 'already_member', 'error', 'That person is already a member of a company on QuotesDone.');
  end if;
  if (select count(*) from public.supplier_member m where m.lead_id = p_lead and m.status in ('invited', 'active', 'screening')) >= 10 then
    return jsonb_build_object('ok', false, 'code', 'team_full', 'error', 'A company can have up to 10 members besides the owner.');
  end if;
  insert into public.supplier_member (lead_id, email, name, phone, role, invited_by)
  values (p_lead, v_e, left(v_name, 120), nullif(left(btrim(coalesce(p_phone, '')), 30), ''), p_role, lower(btrim(p_actor)))
  returning id into v_id;
  v_scr := public.fn_supplier_member_screen(v_id);
  if coalesce(v_scr->>'code', '') = 'refused' then
    return jsonb_build_object('ok', false, 'code', 'refused', 'error', 'We cannot add this person automatically. Please write to management@quotesdone.com.');
  end if;
  perform public.fn_sales_engineer_writes('supplier_team_invitation', 'supplier', v_e, p_lead, null, null, null,
    'You have been added to ' || coalesce(l.company_name, 'a company') || ' on QuotesDone',
    'Hello ' || v_name || ',' || E'\n\n' || coalesce(l.company_name, 'Your company') || ' has added you to its QuotesDone account as '
    || case when p_role = 'estimator' then 'an estimator: you can read its job requests and send quotations for it.'
            else 'a viewer: you can read its job requests and quotations.' end
    || E'\n\nTo accept, sign in at https://quotesdone.ae/supplier with this e-mail address (we send you a sign-in code), then press "Accept".'
    || E'\nIf you do not know this company, ignore this e-mail: nothing happens until you accept.',
    null, null, '{}'::text[], 'supplier_team_invitation:' || v_id);
  return jsonb_build_object('ok', true, 'member_id', v_id, 'screening', not coalesce((v_scr->>'clear')::boolean, true));
end $fn$;
revoke execute on function public.fn_supplier_member_invite(bigint, text, text, text, text, text) from public, anon, authenticated;

-- Accepted by the invited person himself: the address is the one his sign-in code proved (supplier_api's door).
create or replace function public.fn_supplier_member_accept(p_email text, p_phone text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_e text := lower(btrim(coalesce(p_email, ''))); m public.supplier_member; v_scr jsonb; l record;
begin
  select * into m from public.supplier_member where email = v_e and status = 'invited' order by id limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'no_invitation'); end if;
  if exists (select 1 from public.leads x where lower(x.claimed_by) = v_e) then
    return jsonb_build_object('ok', false, 'code', 'owns_a_company', 'error', 'This address already manages a company, so it cannot join another.');
  end if;
  update public.supplier_member set status = 'active', accepted_at = now(), email_verified_at = now(),
         phone = coalesce(nullif(left(btrim(coalesce(p_phone, '')), 30), ''), phone)
   where id = m.id;
  v_scr := public.fn_supplier_member_screen(m.id);
  if coalesce(v_scr->>'code', '') = 'refused' then return jsonb_build_object('ok', false, 'code', 'refused'); end if;
  select claimed_by, company_name into l from public.leads where id = m.lead_id;
  perform public.fn_sales_engineer_writes('supplier_team_joined', 'supplier', l.claimed_by, m.lead_id, null, null, null,
    m.name || ' joined your company on QuotesDone',
    m.name || ' (' || v_e || ') accepted your invitation and is now ' || case when m.role = 'estimator' then 'an estimator' else 'a viewer' end
    || ' of ' || coalesce(l.company_name, 'your company') || ' on QuotesDone. You can remove him at any time in your portal (Settings, Team).',
    null, null, '{}'::text[], 'supplier_team_joined:' || m.id);
  return jsonb_build_object('ok', true, 'lead_id', m.lead_id, 'company_name', l.company_name, 'role', m.role,
    'screening', not coalesce((v_scr->>'clear')::boolean, true));
end $fn$;
revoke execute on function public.fn_supplier_member_accept(text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_member_remove(p_lead bigint, p_actor text, p_email text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_e text := lower(btrim(coalesce(p_email, ''))); v_n int;
begin
  if not exists (select 1 from public.leads l where l.id = p_lead and lower(l.claimed_by) = lower(btrim(coalesce(p_actor, '')))) then
    -- a member may leave on his own
    if v_e <> lower(btrim(coalesce(p_actor, ''))) then return jsonb_build_object('ok', false, 'code', 'owner_only'); end if;
  end if;
  update public.supplier_member set status = 'removed', removed_at = now(), removed_by = lower(btrim(coalesce(p_actor, ''))),
         phone_code_sha = null
   where lead_id = p_lead and email = v_e and status in ('invited', 'active', 'screening');
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n > 0, 'code', case when v_n > 0 then null else 'not_a_member' end);
end $fn$;
revoke execute on function public.fn_supplier_member_remove(bigint, text, text) from public, anon, authenticated;

-- His WhatsApp number becomes the company's voice only when he sends, FROM that number, the code shown to him signed in.
create or replace function public.fn_supplier_member_phone_code(p_email text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare m public.supplier_member; v_code text;
begin
  select * into m from public.supplier_member where email = lower(btrim(coalesce(p_email, ''))) and status in ('active', 'screening') order by id limit 1;
  if not found or not public.fn_supplier_member_counts(m.id) then return jsonb_build_object('ok', false, 'code', 'not_a_member'); end if;
  if length(regexp_replace(coalesce(m.phone, ''), '[^0-9]', '', 'g')) < 9 then return jsonb_build_object('ok', false, 'code', 'no_phone'); end if;
  -- six digits from gen_random_uuid (a cryptographic source), never random()
  v_code := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000))::text, 6, '0');
  update public.supplier_member set phone_code_sha = encode(sha256(convert_to(v_code, 'UTF8')), 'hex'),
         phone_code_expires = now() + interval '30 minutes', phone_code_tries = 0 where id = m.id;
  return jsonb_build_object('ok', true, 'code_to_send', v_code, 'phone_tail', right(regexp_replace(m.phone, '[^0-9]', '', 'g'), 4), 'expires_in_min', 30);
end $fn$;
revoke execute on function public.fn_supplier_member_phone_code(text) from public, anon, authenticated;

create or replace function public.fn_supplier_member_confirm_phone(p_phone text, p_code text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_tail text := right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9); m record; v_sha text;
begin
  if length(v_tail) < 9 or coalesce(p_code, '') !~ '^[0-9]{6}$' then return jsonb_build_object('ok', false, 'code', 'no_code'); end if;
  v_sha := encode(sha256(convert_to(p_code, 'UTF8')), 'hex');
  select sm.id, sm.name, sm.role, sm.phone_code_sha, sm.phone_code_tries, le.company_name into m
    from public.supplier_member sm join public.leads le on le.id = sm.lead_id
   where sm.status in ('active', 'screening') and sm.phone_code_sha is not null and sm.phone_code_expires > now()
     and right(regexp_replace(coalesce(sm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
     and coalesce(public.fn_phone_prefix(sm.phone) = public.fn_phone_prefix(p_phone), true)
   order by sm.id limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'no_pending_code'); end if;
  if m.phone_code_tries >= 5 then
    update public.supplier_member set phone_code_sha = null where id = m.id;
    return jsonb_build_object('ok', false, 'code', 'too_many_tries');
  end if;
  if m.phone_code_sha <> v_sha then
    update public.supplier_member set phone_code_tries = phone_code_tries + 1 where id = m.id;
    return jsonb_build_object('ok', false, 'code', 'wrong_code');
  end if;
  update public.supplier_member set phone_confirmed_at = now(), phone_code_sha = null, phone_code_expires = null where id = m.id;
  return jsonb_build_object('ok', true, 'name', m.name, 'role', m.role, 'company_name', m.company_name);
end $fn$;
revoke execute on function public.fn_supplier_member_confirm_phone(text, text) from public, anon, authenticated;

-- Who is writing from this number, when it is a member's (the WhatsApp reader asks before a step only an owner may take).
create or replace function public.fn_supplier_member_by_phone(p_phone text)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('lead_id', m.lead_id, 'email', m.email, 'name', m.name, 'role', m.role)
    from public.supplier_member m
   where m.status in ('active', 'screening') and m.phone_confirmed_at is not null and public.fn_supplier_member_counts(m.id)
     and right(regexp_replace(coalesce(m.phone, ''), '[^0-9]', '', 'g'), 9) = right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9)
     and length(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9)) = 9
     and coalesce(public.fn_phone_prefix(m.phone) = public.fn_phone_prefix(p_phone), true)
   order by m.id limit 1;
$fn$;
revoke execute on function public.fn_supplier_member_by_phone(text) from public, anon, authenticated;

-- fn_whatsapp_owner: the production body (md5 7c230a40..., 16 Nov 2026) plus ONE branch: a member's confirmed number names
-- his company. A phone still confirms, never selects: one party or nobody.
create or replace function public.fn_whatsapp_owner(p_phone text, p_all boolean DEFAULT false)
returns table(party_kind text, customer_id uuid, lead_id bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with t as (select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9) as tail, public.fn_phone_prefix(p_phone) as prefix),
  hits as (
    select 'customer'::text as party_kind, c.id as customer_id, null::bigint as lead_id
      from public.customers c, t
     where length(t.tail) = 9
       and ((c.whatsapp_opt = 'other' and c.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(c.whatsapp_phone) = t.prefix, true))
         or (c.whatsapp_opt = 'same' and coalesce(c.phone_verified, false)
             and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(c.phone) = t.prefix, true)))
    union
    select 'supplier', null, l.id
      from public.leads l, t
     where length(t.tail) = 9
       -- 18 Sep 2026, founder instruction 516: a confirmed sanctions ban means the handset names
       -- nobody. WhatsApp is the one channel with no session to refuse.
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id)
       and ((l.whatsapp_opt = 'other' and l.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(l.whatsapp_phone) = t.prefix, true))
         or (l.whatsapp_opt = 'same' and coalesce(l.owner_phone_verified, false)
             and right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(l.phone) = t.prefix, true)))
    union
    -- 16 Nov 2026 (SUPPLIER hole 4): a company member's number, confirmed by the code he sent from it, names his company
    select 'supplier', null, m.lead_id
      from public.supplier_member m, t
     where length(t.tail) = 9
       and m.status in ('active', 'screening') and m.phone_confirmed_at is not null
       and public.fn_supplier_member_counts(m.id)
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = m.lead_id)
       and right(regexp_replace(coalesce(m.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
       and coalesce(public.fn_phone_prefix(m.phone) = t.prefix, true))
  -- A PHONE MAY CONFIRM, NEVER SELECT: one party or nobody. The country prefix must agree as well as the last nine digits
  -- (a_phone_tail_never_joins_two_people.sql); a number written in a local form names no country and agrees with any.
  select h.party_kind, h.customer_id, h.lead_id from hits h where p_all or (select count(*) from hits) = 1
$fn$;
revoke execute on function public.fn_whatsapp_owner(text, boolean) from public, anon, authenticated;
grant execute on function public.fn_whatsapp_owner(text, boolean) to service_role;

-- ── 2. the ownership transfer ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_transfer_start(p_lead bigint, p_actor text, p_to text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; v_to text := lower(btrim(coalesce(p_to, ''))); m record; v_code text; v_id bigint;
begin
  select id, claimed_by, company_name into l from public.leads where id = p_lead;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then return jsonb_build_object('ok', false, 'code', 'owner_only'); end if;
  select * into m from public.supplier_member where lead_id = p_lead and email = v_to and status in ('active', 'screening') order by id limit 1;
  if not found or not public.fn_supplier_member_counts(m.id) then
    return jsonb_build_object('ok', false, 'code', 'not_an_active_member', 'error', 'Ownership can be handed only to a member who has accepted his invitation.');
  end if;
  update public.supplier_ownership_transfer set cancelled_at = now() where lead_id = p_lead and confirmed_at is null and cancelled_at is null;
  v_code := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000))::text, 6, '0');
  insert into public.supplier_ownership_transfer (lead_id, from_email, to_email, code_sha, code_expires)
  values (p_lead, lower(l.claimed_by), v_to, encode(sha256(convert_to(v_code, 'UTF8')), 'hex'), now() + interval '30 minutes')
  returning id into v_id;
  -- the code goes to the OWNER's own address: whoever holds the session must also hold his mailbox
  perform public.fn_sales_engineer_writes('supplier_ownership_code', 'supplier', l.claimed_by, p_lead, null, null, null,
    'Your code to hand ' || coalesce(l.company_name, 'your company') || ' to ' || m.name,
    'Someone signed in as the owner of ' || coalesce(l.company_name, 'your company') || ' on QuotesDone asked to make ' || m.name || ' (' || v_to
    || ') the owner. Your code is ' || v_code || ' (valid 30 minutes).' || E'\n\nIf this was not you, do nothing: nothing changes without this code. '
    || 'You stay a member (estimator) after the hand-over, and the new owner can remove you.',
    null, null, '{}'::text[], 'supplier_ownership_code:' || v_id);
  return jsonb_build_object('ok', true, 'transfer_id', v_id, 'to', v_to, 'expires_in_min', 30);
end $fn$;
revoke execute on function public.fn_supplier_transfer_start(bigint, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_transfer_confirm(p_lead bigint, p_actor text, p_code text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; t public.supplier_ownership_transfer; m record; v_from text;
begin
  select id, claimed_by, company_name into l from public.leads where id = p_lead for update;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then return jsonb_build_object('ok', false, 'code', 'owner_only'); end if;
  select * into t from public.supplier_ownership_transfer where lead_id = p_lead and confirmed_at is null and cancelled_at is null
   order by id desc limit 1 for update;
  if not found or t.code_expires <= now() then return jsonb_build_object('ok', false, 'code', 'no_pending_transfer'); end if;
  if t.tries >= 5 then
    update public.supplier_ownership_transfer set cancelled_at = now() where id = t.id;
    return jsonb_build_object('ok', false, 'code', 'too_many_tries');
  end if;
  if coalesce(p_code, '') !~ '^[0-9]{6}$' or encode(sha256(convert_to(p_code, 'UTF8')), 'hex') <> t.code_sha then
    update public.supplier_ownership_transfer set tries = tries + 1 where id = t.id;
    return jsonb_build_object('ok', false, 'code', 'wrong_code');
  end if;
  select * into m from public.supplier_member where lead_id = p_lead and email = t.to_email and status in ('active', 'screening') order by id limit 1 for update;
  if not found or not public.fn_supplier_member_counts(m.id) then return jsonb_build_object('ok', false, 'code', 'not_an_active_member'); end if;
  v_from := lower(l.claimed_by);
  update public.supplier_member set status = 'became_owner', removed_at = now(), removed_by = 'ownership_transfer' where id = m.id;
  update public.leads set claimed_by = t.to_email, owner_email_verified = true, portal_updated_at = now() where id = p_lead;
  insert into public.supplier_member (lead_id, email, name, role, status, invited_by, accepted_at, email_verified_at, screened_at, screen)
  values (p_lead, v_from, coalesce(nullif(btrim((select contact_name from public.leads where id = p_lead)), ''), 'Former owner'),
          'estimator', 'active', 'ownership_transfer', now(), now(), now(), jsonb_build_object('former_owner', true));
  update public.supplier_ownership_transfer set confirmed_at = now() where id = t.id;
  perform public.fn_sales_engineer_writes('supplier_ownership_changed', 'supplier', t.to_email, p_lead, null, null, null,
    'You are now the owner of ' || coalesce(l.company_name, 'your company') || ' on QuotesDone',
    v_from || ' handed ' || coalesce(l.company_name, 'the company') || ' to you on QuotesDone. You now sign the company''s quotations, '
    || 'manage its team and its account. ' || v_from || ' stays a member (estimator) until you remove him (Settings, Team).',
    null, null, array[v_from]::text[], 'supplier_ownership_changed:' || t.id);
  return jsonb_build_object('ok', true, 'owner', t.to_email, 'former_owner', v_from);
end $fn$;
revoke execute on function public.fn_supplier_transfer_confirm(bigint, text, text) from public, anon, authenticated;

-- ── 3. a job question from any channel ────────────────────────────────────────────────────────────────────────────────
alter table public.rfq_clarification
  add column if not exists answered_by        text,
  add column if not exists se_read_at         timestamptz,
  add column if not exists se_verdict         text,
  add column if not exists customer_asked_at  timestamptz,
  add column if not exists customer_chased_at timestamptz,
  add column if not exists asked_by_email     text;
alter table public.rfq_clarification drop constraint if exists rfq_clarification_source_check;
alter table public.rfq_clarification add constraint rfq_clarification_source_check
  check (source = any (array['portal', 'rfq_flag', 'rfq_note', 'missing_specs', 'email', 'whatsapp']));
alter table public.rfq_clarification drop constraint if exists rfq_clarification_answered_by_ck;
alter table public.rfq_clarification add constraint rfq_clarification_answered_by_ck
  check (answered_by is null or answered_by in ('customer', 'sales_engineer'));
create index if not exists rfq_clarification_open_question_idx on public.rfq_clarification (asked_at)
  where kind = 'question' and answered_at is null;

-- What the sales engineer owes on job questions this beat: a first reading, or the one reminder to the customer.
create or replace function public.fn_job_questions_due(p_limit integer default 10)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(x order by x.asked_at), '[]'::jsonb) from (
    select q.id, q.inquiry_id, q.supplier_id, q.question, q.source, q.asked_at,
           case when q.se_read_at is null then 'first_read' else 'chase' end as step
      from public.rfq_clarification q join public.inquiries i on i.id = q.inquiry_id
     where q.kind = 'question' and q.answered_at is null
       and coalesce(i.status, '') not in ('cancelled', 'closed', 'completed', 'expired', 'lost')
       and (q.se_read_at is null
            or (q.customer_asked_at is not null and q.customer_chased_at is null
                and q.customer_asked_at < now() - make_interval(hours => public.fn_seat_clock_policy('job_question_chase_hours', 24)::int)))
     order by q.asked_at
     limit greatest(1, least(coalesce(p_limit, 10), 50))) x;
$fn$;
revoke execute on function public.fn_job_questions_due(integer) from public, anon, authenticated;
grant execute on function public.fn_job_questions_due(integer) to service_role;

-- ── 4. close and reopen the account ───────────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_account_closure (
  id             bigint generated always as identity primary key,
  lead_id        bigint not null references public.leads(id),
  requested_by   text not null,
  channel        text not null check (channel in ('portal', 'email', 'whatsapp')),
  quotes         text not null check (quotes in ('withdraw', 'keep')),
  reason         text,
  state          text not null default 'proposed' check (state in ('proposed', 'closed', 'reopened', 'cancelled')),
  prior          jsonb,
  outcome        jsonb,
  pdpl_request   uuid,
  proposed_at    timestamptz not null default now(),
  closed_at      timestamptz,
  reopened_at    timestamptz,
  cancelled_at   timestamptz
);
create index if not exists supplier_account_closure_lead_idx on public.supplier_account_closure (lead_id, proposed_at desc);
alter table public.supplier_account_closure enable row level security;
drop policy if exists supplier_account_closure_service_role_only on public.supplier_account_closure;
create policy supplier_account_closure_service_role_only on public.supplier_account_closure as permissive for all to public using (false) with check (false);
revoke all on public.supplier_account_closure from anon, authenticated;

-- What the law keeps for this company and until when, in the words the letter uses (fn_pdpl_erase_plan's own rule).
create or replace function public.fn_supplier_what_the_law_keeps(p_lead bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  with f as (
    select (select count(*) from public.quotes q where q.supplier_id = p_lead) as quotes,
           (select count(*) from public.transactions t where t.supplier_id = p_lead and t.revealed_at is not null) as reveals,
           (select count(*) from public.supplier_dues d where d.supplier_id = p_lead) as dues,
           public.fn_conversation_party_on_hold('supplier', p_lead::text) as on_hold,
           public.fn_conversation_party_last_activity('supplier', p_lead::text) as last_act)
  select jsonb_build_object(
    'kept_until', (greatest(coalesce(f.last_act, now()), date_trunc('year', now()) + interval '1 year') + interval '5 years')::date,
    'legal_hold', coalesce(f.on_hold, false),
    'quotes', f.quotes, 'reveals', f.reveals, 'dues', f.dues,
    'kept', jsonb_build_array(
      'your company record, trade licence and the agreement you accepted (supplier checks: the relationship plus 5 years)',
      'your quotations, the requests they answered and any reveal, invoice or payment (tax records: 5 years from the end of the year they were made)',
      'the messages exchanged with us and with customers (5 years after the account goes quiet, then their text is removed)'),
    'law', 'UAE Personal Data Protection Law (Federal Decree-Law 45/2021) for your rights over your data; Cabinet Decision 74/2023, Art. 3 for the 5-year records rule')
  from f;
$fn$;
revoke execute on function public.fn_supplier_what_the_law_keeps(bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_close_propose(p_lead bigint, p_actor text, p_channel text, p_quotes text, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; v_id bigint; v_live jsonb;
begin
  select id, claimed_by, permanently_closed into l from public.leads where id = p_lead;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then
    return jsonb_build_object('ok', false, 'code', 'owner_only', 'error', 'Only the company''s owner can close its account.');
  end if;
  if exists (select 1 from public.supplier_account_closure c where c.lead_id = p_lead and c.state = 'closed') then
    return jsonb_build_object('ok', false, 'code', 'already_closed');
  end if;
  update public.supplier_account_closure set state = 'cancelled', cancelled_at = now() where lead_id = p_lead and state = 'proposed';
  insert into public.supplier_account_closure (lead_id, requested_by, channel, quotes, reason)
  values (p_lead, lower(btrim(p_actor)), p_channel, case when p_quotes = 'keep' then 'keep' else 'withdraw' end, left(p_reason, 1000))
  returning id into v_id;
  v_live := public.fn_supplier_live_quotes(p_lead);
  return jsonb_build_object('ok', true, 'closure_id', v_id, 'quotes', case when p_quotes = 'keep' then 'keep' else 'withdraw' end,
    'live_quotes', jsonb_array_length(coalesce(v_live, '[]'::jsonb)), 'law', public.fn_supplier_what_the_law_keeps(p_lead));
end $fn$;
revoke execute on function public.fn_supplier_close_propose(bigint, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_close_decide(p_lead bigint, p_actor text, p_decision text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare c public.supplier_account_closure;
begin
  select * into c from public.supplier_account_closure where lead_id = p_lead and state = 'proposed' order by id desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'nothing_waiting'); end if;
  if p_decision = 'cancel' then
    update public.supplier_account_closure set state = 'cancelled', cancelled_at = now() where id = c.id;
    return jsonb_build_object('ok', true, 'cancelled', true);
  end if;
  return public.fn_supplier_close_account(p_lead, p_actor, c.channel, c.quotes, c.reason);
end $fn$;
revoke execute on function public.fn_supplier_close_decide(bigint, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_close_account(p_lead bigint, p_actor text, p_channel text, p_quotes text, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  l record; v_id bigint; v_live jsonb; v_ids uuid[]; v_withdrawn int := 0; v_kept int := 0; v_law jsonb; v_avail record; v_req uuid;
  v_cc text[]; v_body text; v_q text := case when p_quotes = 'keep' then 'keep' else 'withdraw' end; v_rev int;
begin
  select id, claimed_by, company_name, permanently_closed into l from public.leads where id = p_lead for update;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then
    return jsonb_build_object('ok', false, 'code', 'owner_only', 'error', 'Only the company''s owner can close its account.');
  end if;
  if exists (select 1 from public.supplier_account_closure c where c.lead_id = p_lead and c.state = 'closed') then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  select state, busy_until into v_avail from public.supplier_availability where supplier_id = p_lead;
  select id into v_id from public.supplier_account_closure where lead_id = p_lead and state = 'proposed' order by id desc limit 1;
  if v_id is null then
    insert into public.supplier_account_closure (lead_id, requested_by, channel, quotes, reason)
    values (p_lead, lower(btrim(p_actor)), p_channel, v_q, left(p_reason, 1000)) returning id into v_id;
  end if;
  v_live := coalesce(public.fn_supplier_live_quotes(p_lead), '[]'::jsonb);
  select coalesce(array_agg((x->>'quote_id')::uuid), '{}') into v_ids from jsonb_array_elements(v_live) x;
  if v_q = 'withdraw' and cardinality(v_ids) > 0 then
    update public.quotes set status = 'withdrawn' where supplier_id = p_lead and id = any(v_ids) and status in ('draft', 'submitted');
    get diagnostics v_withdrawn = row_count;
  else
    v_kept := cardinality(v_ids);
  end if;
  select count(*) into v_rev from public.transactions t where t.supplier_id = p_lead and t.revealed_at is not null
     and coalesce(t.refund_status, '') not in ('refunded', 'completed');
  -- matching stops: the same switch fn_is_matchable and the claim door read, and availability paused for the portal
  update public.leads set permanently_closed = true, portal_updated_at = now() where id = p_lead;
  perform public.fn_supplier_set_availability(p_lead, 'paused', null, 'account_closed');
  v_law := public.fn_supplier_what_the_law_keeps(p_lead);
  -- the PDPL register: a deletion asked by the owner of a registered company is recorded as deferred, with what is kept and why
  insert into public.pdpl_requests (kind, email, role, details, status, verified_via, verified_at, handled_by, handled_at, outcome)
  values ('delete', lower(l.claimed_by), 'supplier', 'Company account closed by its owner (' || p_channel || ')', 'deferred',
          case p_channel when 'portal' then 'signed_in_owner' when 'email' then 'authenticated_owner_address' else 'confirmed_owner_whatsapp' end,
          now(), 'customer_support', now(), jsonb_build_object('lead_id', p_lead, 'closure_id', v_id) || v_law)
  returning id into v_req;
  update public.supplier_account_closure set state = 'closed', closed_at = now(), quotes = v_q, pdpl_request = v_req,
         prior = jsonb_build_object('permanently_closed', coalesce(l.permanently_closed, false), 'availability', v_avail.state, 'busy_until', v_avail.busy_until),
         outcome = jsonb_build_object('withdrawn', v_withdrawn, 'kept', v_kept, 'revealed_open', v_rev) || v_law
   where id = v_id;
  select coalesce(array_agg(m.email), '{}') into v_cc from public.supplier_member m where m.lead_id = p_lead and m.status in ('active', 'screening');
  v_body := 'We have closed the QuotesDone account of ' || coalesce(l.company_name, 'your company') || ', as you asked'
    || coalesce(' (' || nullif(btrim(p_reason), '') || ')', '') || '.'
    || E'\n\nWhat changed today:'
    || E'\n- No new job requests will be sent to you.'
    || case when v_q = 'withdraw' then E'\n- ' || v_withdrawn || ' quotation' || case when v_withdrawn = 1 then ' was' else 's were' end || ' withdrawn from customers.'
            else E'\n- ' || v_kept || ' quotation' || case when v_kept = 1 then ' stays' else 's stay' end || ' with customers, as you chose: a customer may still reveal you on ' || case when v_kept = 1 then 'it' else 'them' end || ', and you are bound by ' || case when v_kept = 1 then 'it' else 'them' end || ' as quoted.' end
    || case when v_rev > 0 then E'\n- ' || v_rev || ' customer' || case when v_rev = 1 then ' who has' else 's who have' end || ' already paid to see your details keep that right; please still answer them.' else '' end
    || E'\n\nWhat the law requires us to keep, and why:'
    || E'\n- ' || (v_law->'kept'->>0) || E'\n- ' || (v_law->'kept'->>1) || E'\n- ' || (v_law->'kept'->>2)
    || E'\nThese are kept until ' || to_char((v_law->>'kept_until')::date, 'DD Mon YYYY') || ' under ' || (v_law->>'law') || '. '
    || 'Nothing is used for marketing, and we do not share it except where the law requires.'
    || case when coalesce((v_law->>'legal_hold')::boolean, false) then E'\nAn open dispute, refund or unpaid amount on your account keeps those records until it is settled.' else '' end
    || E'\n\nYou can ask for a copy of your data at any time by replying to this e-mail. To come back, sign in to your portal and press "Reopen my account" (Settings).';
  perform public.fn_sales_engineer_writes('supplier_account_closed', 'supplier', l.claimed_by, p_lead, null, null, null,
    'Your QuotesDone account is closed', v_body, null, null, v_cc, 'supplier_account_closed:' || v_id);
  return jsonb_build_object('ok', true, 'closure_id', v_id, 'withdrawn', v_withdrawn, 'kept', v_kept, 'revealed_open', v_rev,
    'pdpl_request', v_req) || v_law;
end $fn$;
revoke execute on function public.fn_supplier_close_account(bigint, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_reopen_account(p_lead bigint, p_actor text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare c public.supplier_account_closure; l record;
begin
  select id, claimed_by, company_name into l from public.leads where id = p_lead for update;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then return jsonb_build_object('ok', false, 'code', 'owner_only'); end if;
  if exists (select 1 from public.sanctions_ban b where b.lead_id = p_lead) then return jsonb_build_object('ok', false, 'code', 'company_closed'); end if;
  select * into c from public.supplier_account_closure where lead_id = p_lead and state = 'closed' order by id desc limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_closed'); end if;
  update public.leads set permanently_closed = coalesce((c.prior->>'permanently_closed')::boolean, false), portal_updated_at = now() where id = p_lead;
  perform public.fn_supplier_set_availability(p_lead, 'available', null, 'account_reopened');
  update public.supplier_account_closure set state = 'reopened', reopened_at = now() where id = c.id;
  if c.pdpl_request is not null then
    update public.pdpl_requests set status = 'cancelled', cancelled_at = now() where id = c.pdpl_request and status = 'deferred';
  end if;
  perform public.fn_sales_engineer_writes('supplier_account_reopened', 'supplier', l.claimed_by, p_lead, null, null, null,
    'Your QuotesDone account is open again', 'Welcome back. ' || coalesce(l.company_name, 'Your company') || ' receives job requests in its trades again. Quotations withdrawn when the account closed stay withdrawn.',
    null, null, '{}'::text[], 'supplier_account_reopened:' || c.id);
  return jsonb_build_object('ok', true);
end $fn$;
revoke execute on function public.fn_supplier_reopen_account(bigint, text) from public, anon, authenticated;

-- ── 5. why a quotation was not chosen ─────────────────────────────────────────────────────────────────────────────────
create table if not exists public.inquiry_decision_reason (
  inquiry_id  uuid primary key references public.inquiries(id),
  customer_id uuid not null,
  quote_id    uuid,
  reason      text not null,
  lang        text not null default 'en' check (lang in ('en', 'ar')),
  answered_at timestamptz not null default now()
);
alter table public.inquiry_decision_reason enable row level security;
drop policy if exists inquiry_decision_reason_service_role_only on public.inquiry_decision_reason;
create policy inquiry_decision_reason_service_role_only on public.inquiry_decision_reason as permissive for all to public using (false) with check (false);
revoke all on public.inquiry_decision_reason from anon, authenticated;

create table if not exists public.supplier_loss_reason (
  inquiry_id  uuid not null references public.inquiries(id),
  supplier_id bigint not null,
  text        text not null,
  basis       jsonb not null default '{}'::jsonb,
  written_at  timestamptz not null default now(),
  primary key (inquiry_id, supplier_id)
);
alter table public.supplier_loss_reason enable row level security;
drop policy if exists supplier_loss_reason_service_role_only on public.supplier_loss_reason;
create policy supplier_loss_reason_service_role_only on public.supplier_loss_reason as permissive for all to public using (false) with check (false);
revoke all on public.supplier_loss_reason from anon, authenticated;

-- The customer's one optional word, at the reveal. Only a customer who revealed a supplier on this request.
create or replace function public.fn_customer_decision_reason_save(p_customer uuid, p_quote uuid, p_reason text, p_lang text default 'en')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare t record; v_r text := btrim(coalesce(p_reason, ''));
begin
  select tx.inquiry_id into t from public.transactions tx where tx.quote_id = p_quote and tx.customer_id = p_customer and tx.revealed_at is not null limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_revealed'); end if;
  if length(v_r) < 2 then return jsonb_build_object('ok', false, 'code', 'empty'); end if;
  insert into public.inquiry_decision_reason (inquiry_id, customer_id, quote_id, reason, lang)
  values (t.inquiry_id, p_customer, p_quote, left(v_r, 1000), case when p_lang = 'ar' then 'ar' else 'en' end)
  on conflict (inquiry_id) do update set reason = excluded.reason, lang = excluded.lang, quote_id = excluded.quote_id, answered_at = now();
  return jsonb_build_object('ok', true);
end $fn$;
revoke execute on function public.fn_customer_decision_reason_save(uuid, uuid, text, text) from public, anon, authenticated;

-- The losing suppliers owed a reason: one row per (request, supplier) who sent a quotation on a request that was decided
-- (hired, or revealed and quiet for a week) or ended. Ex-VAT figures only (price_ex_vat; a missing one is null, never
-- guessed from a VAT-inclusive total). The chosen quotation's figures are for the model's comparison and the output check;
-- the writer never shows them (supplier_api/loss_feedback.ts).
create or replace function public.fn_supplier_loss_reasons_due(p_limit integer default 10)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  with ended as (
    select i.id, i.rfq_no, i.status, i.hired_supplier_id, i.lost_reason, i.category,
           (select t.supplier_id from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null order by t.revealed_at desc limit 1) as revealed_supplier,
           (select max(t.revealed_at) from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null) as last_reveal
      from public.inquiries i
     where i.status in ('completed', 'closed', 'cancelled', 'expired', 'lost', 'revealed')
       and i.created_at > now() - interval '180 days'),
  pairs as (
    select e.*, q.supplier_id,
           (select jsonb_build_object('ex_vat', q2.price_ex_vat, 'lead_time', q2.lead_time, 'exclusions', left(q2.exclusions, 400), 'submittable', q2.submittable)
              from public.quotes q2 where q2.inquiry_id = e.id and q2.supplier_id = q.supplier_id and q2.status not in ('draft', 'withdrawn')
             order by q2.price_ex_vat nulls last limit 1) as mine,
           coalesce(e.hired_supplier_id, e.revealed_supplier) as chosen_supplier
      from ended e
      join (select distinct inquiry_id, supplier_id from public.quotes where status not in ('draft', 'withdrawn')) q on q.inquiry_id = e.id
     where not exists (select 1 from public.supplier_loss_reason r where r.inquiry_id = e.id and r.supplier_id = q.supplier_id)
       and q.supplier_id is distinct from e.hired_supplier_id
       and not exists (select 1 from public.transactions t where t.inquiry_id = e.id and t.supplier_id = q.supplier_id and t.revealed_at is not null)
       and (e.status <> 'revealed' or e.last_reveal < now() - make_interval(days => public.fn_seat_clock_policy('loss_reason_after_reveal_days', 7)::int)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'inquiry_id', p.id, 'supplier_id', p.supplier_id, 'ref', 'RFQ-' || p.rfq_no, 'trade', p.category, 'status', p.status,
           'outcome', case when p.hired_supplier_id is not null then 'hired_other' when p.revealed_supplier is not null then 'revealed_other'
                           when p.lost_reason like 'no_exact_spec%' then 'no_exact_spec' else 'no_award' end,
           'decision_reason', (select d.reason from public.inquiry_decision_reason d where d.inquiry_id = p.id),
           'mine', p.mine,
           'chosen', (select jsonb_build_object('ex_vat', c.price_ex_vat, 'lead_time', c.lead_time, 'exclusions', left(c.exclusions, 400), 'submittable', c.submittable)
                        from public.quotes c where c.inquiry_id = p.id and c.supplier_id = p.chosen_supplier and c.status not in ('draft', 'withdrawn')
                       order by (c.status = 'accepted') desc, c.price_ex_vat nulls last limit 1),
           'chosen_name', (select l.company_name from public.leads l where l.id = p.chosen_supplier))), '[]'::jsonb)
    from (select * from pairs order by id limit greatest(1, least(coalesce(p_limit, 10), 50))) p;
$fn$;
revoke execute on function public.fn_supplier_loss_reasons_due(integer) from public, anon, authenticated;
grant execute on function public.fn_supplier_loss_reasons_due(integer) to service_role;

-- ── 6. after the reveal: the follow-up reaches him, and "the customer is not answering" ───────────────────────────────
create table if not exists public.supplier_customer_silence (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null unique,
  lead_id        bigint not null,
  inquiry_id     uuid,
  customer_id    uuid,
  reported_by    text not null,
  channel        text not null check (channel in ('portal', 'email', 'whatsapp')),
  note           text,
  reported_at    timestamptz not null default now(),
  nudge_handoff  bigint
);
alter table public.supplier_customer_silence enable row level security;
drop policy if exists supplier_customer_silence_service_role_only on public.supplier_customer_silence;
create policy supplier_customer_silence_service_role_only on public.supplier_customer_silence as permissive for all to public using (false) with check (false);
revoke all on public.supplier_customer_silence from anon, authenticated;

create or replace function public.fn_supplier_customer_not_answering(p_lead bigint, p_actor text, p_inquiry uuid, p_channel text, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare t record; c record; l record; v_id bigint; v_h bigint; v_ref text;
begin
  select tx.id, tx.customer_id, tx.quote_id, tx.revealed_at, i.rfq_no, i.category into t
    from public.transactions tx join public.inquiries i on i.id = tx.inquiry_id
   where tx.supplier_id = p_lead and tx.inquiry_id = p_inquiry and tx.revealed_at is not null order by tx.revealed_at desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_revealed', 'error', 'This customer has not revealed you on that request.'); end if;
  if t.revealed_at > now() - interval '1 day' then
    return jsonb_build_object('ok', false, 'code', 'too_soon', 'error', 'The customer revealed you less than a day ago; please give them until ' || to_char((t.revealed_at + interval '1 day') at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai).');
  end if;
  insert into public.supplier_customer_silence (transaction_id, lead_id, inquiry_id, customer_id, reported_by, channel, note)
  values (t.id, p_lead, p_inquiry, t.customer_id, lower(btrim(coalesce(p_actor, ''))), p_channel, left(p_note, 500))
  on conflict (transaction_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'already', true); end if;
  select email, full_name into c from public.customers where id = t.customer_id;
  select company_name into l from public.leads where id = p_lead;
  v_ref := coalesce('RFQ-' || t.rfq_no, 'your request');
  if coalesce(c.email, '') ~ '@' then
    v_h := public.fn_sales_engineer_writes('customer_supplier_trying_to_reach', 'customer', c.email, null, t.customer_id, p_inquiry, t.quote_id,
      coalesce(l.company_name, 'Your supplier') || ' is trying to reach you about ' || v_ref,
      'Hello ' || coalesce(c.full_name, '') || ',' || E'\n\n' || coalesce(l.company_name, 'The supplier you revealed') || ' tells us they have tried to reach you about '
      || v_ref || coalesce(' (' || t.category || ')', '') || ' and have not heard back. Their contact details are on your request in your QuotesDone account.'
      || E'\n\nIf you have already spoken, or no longer need the work, a one-line reply to this e-mail is enough and we will tell them.',
      'المورّد ' || coalesce(l.company_name, '') || ' يحاول التواصل معكم بشأن ' || v_ref,
      'مرحبًا ' || coalesce(c.full_name, '') || '،' || E'\n\n' || 'أبلغنا المورّد ' || coalesce(l.company_name, 'الذي كشفتم بياناته') || ' أنه حاول التواصل معكم بشأن ' || v_ref
      || ' ولم يتلقَّ ردًا. بيانات التواصل معه موجودة في طلبكم على حسابكم في QuotesDone.' || E'\n\n' || 'إن كنتم قد تواصلتم أو لم تعودوا بحاجة إلى العمل، يكفي ردّ بسطر واحد على هذه الرسالة وسنبلغه.',
      '{}'::text[], 'customer_supplier_trying_to_reach:' || t.id);
    update public.supplier_customer_silence set nudge_handoff = v_h where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'nudged', coalesce(c.email, '') ~ '@', 'ref', v_ref);
end $fn$;
revoke execute on function public.fn_supplier_customer_not_answering(bigint, text, uuid, text, text) from public, anon, authenticated;

-- The follow-up's answer (hired / not hired / not yet) reaches the supplier the customer revealed. Never the stars or words.
create or replace function public.trg_customer_followup_tells_the_supplier()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare t record; v_ref text; v_to text;
begin
  if new.answered_at is null or old.answered_at is not null or new.hired is null then return new; end if;
  select tx.supplier_id, tx.inquiry_id, i.rfq_no, i.category, l.claimed_by, l.email into t
    from public.transactions tx join public.inquiries i on i.id = tx.inquiry_id join public.leads l on l.id = tx.supplier_id
   where tx.id = new.transaction_id;
  if not found then return new; end if;
  v_to := coalesce(nullif(btrim(t.claimed_by), ''), t.email);
  if coalesce(v_to, '') !~ '@' then return new; end if;
  v_ref := coalesce('RFQ-' || t.rfq_no, 'the request');
  begin
    perform public.fn_sales_engineer_writes('supplier_followup_outcome', 'supplier', v_to, t.supplier_id, null, t.inquiry_id, null,
      case new.hired when 'yes' then 'The customer on ' || v_ref || ' says they hired you'
                     when 'no' then 'The customer on ' || v_ref || ' did not go ahead with you'
                     else 'The customer on ' || v_ref || ' has not decided yet' end,
      case new.hired
        when 'yes' then 'We asked the customer who revealed you on ' || v_ref || coalesce(' (' || t.category || ')', '') || ' how it went: they say they hired you. Good work.'
        when 'no' then 'We asked the customer who revealed you on ' || v_ref || coalesce(' (' || t.category || ')', '') || ' how it went: they did not go ahead with you this time. '
                       || 'If you think something went wrong between you, reply to this e-mail and tell us.'
        else 'We asked the customer who revealed you on ' || v_ref || coalesce(' (' || t.category || ')', '') || ' how it went: they have not decided yet. '
             || 'If they are not answering you, press "Customer not answering" on the request in your portal and we will remind them once.' end,
      null, null, '{}'::text[], 'supplier_followup_outcome:' || new.id);
  exception when others then
    -- the customer's answer is recorded whatever happens to the relay
    raise warning 'followup relay not filed: %', sqlerrm;
  end;
  return new;
end $fn$;
revoke execute on function public.trg_customer_followup_tells_the_supplier() from public, anon, authenticated;
drop trigger if exists z35_customer_followup_tells_the_supplier on public.customer_followup;
create trigger z35_customer_followup_tells_the_supplier after update of answered_at on public.customer_followup
  for each row execute function public.trg_customer_followup_tells_the_supplier();

-- ── 7. an offer to pay for leads or exclusivity is a demand signal for the CEO ────────────────────────────────────────
create table if not exists public.supplier_demand_signal (
  id         bigint generated always as identity primary key,
  lead_id    bigint not null,
  channel    text not null check (channel in ('portal', 'email', 'whatsapp')),
  asked_for  text not null,
  trade      text,
  size       text,
  words      text,
  created_at timestamptz not null default now()
);
create index if not exists supplier_demand_signal_created_idx on public.supplier_demand_signal (created_at desc);
alter table public.supplier_demand_signal enable row level security;
drop policy if exists supplier_demand_signal_service_role_only on public.supplier_demand_signal;
create policy supplier_demand_signal_service_role_only on public.supplier_demand_signal as permissive for all to public using (false) with check (false);
revoke all on public.supplier_demand_signal from anon, authenticated;

create or replace function public.fn_supplier_demand_signal_record(p_lead bigint, p_channel text, p_asked_for text, p_trade text, p_size text, p_words text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  if not exists (select 1 from public.leads where id = p_lead) or btrim(coalesce(p_asked_for, '')) = '' then return jsonb_build_object('ok', false); end if;
  -- one row per supplier per day and ask: a repeated sentence is the same signal
  select id into v_id from public.supplier_demand_signal where lead_id = p_lead and asked_for = left(btrim(p_asked_for), 200) and created_at > now() - interval '1 day' limit 1;
  if v_id is null then
    insert into public.supplier_demand_signal (lead_id, channel, asked_for, trade, size, words)
    values (p_lead, p_channel, left(btrim(p_asked_for), 200), left(p_trade, 120), left(p_size, 120), left(p_words, 1000)) returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;
revoke execute on function public.fn_supplier_demand_signal_record(bigint, text, text, text, text, text) from public, anon, authenticated;

-- What the CEO reads: how many suppliers offered to pay, for what, in which trades (no paid ranking is offered).
create or replace function public.fn_ceo_supplier_demand_signals(p_days integer default 30)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  with s as (select d.*, l.company_name from public.supplier_demand_signal d left join public.leads l on l.id = d.lead_id
              where d.created_at > now() - make_interval(days => greatest(1, coalesce(p_days, 30))))
  select jsonb_build_object(
    'days', greatest(1, coalesce(p_days, 30)),
    'signals', (select count(*) from s), 'suppliers', (select count(distinct lead_id) from s),
    'by_ask', coalesce((select jsonb_object_agg(asked_for, n) from (select asked_for, count(*) n from s group by 1) a), '{}'::jsonb),
    'by_trade', coalesce((select jsonb_object_agg(coalesce(trade, 'unstated'), n) from (select trade, count(*) n from s group by 1) b), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', created_at, 'supplier', company_name, 'asked_for', asked_for, 'trade', trade, 'size', size, 'words', left(words, 300)) order by created_at desc)
                         from (select * from s order by created_at desc limit 20) r), '[]'::jsonb),
    'policy', 'Nobody can pay to rank higher or to be the only supplier on a request (company brief). These are recorded as demand, not offers we make.');
$fn$;
revoke execute on function public.fn_ceo_supplier_demand_signals(integer) from public, anon, authenticated;
grant execute on function public.fn_ceo_supplier_demand_signals(integer) to service_role;

-- the edge functions call these with the service role
grant execute on function public.fn_supplier_team(bigint) to service_role;
revoke execute on function public.fn_supplier_team(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_member_invite(bigint, text, text, text, text, text) to service_role;
grant execute on function public.fn_supplier_member_accept(text, text) to service_role;
grant execute on function public.fn_supplier_member_remove(bigint, text, text) to service_role;
grant execute on function public.fn_supplier_member_phone_code(text) to service_role;
grant execute on function public.fn_supplier_member_confirm_phone(text, text) to service_role;
grant execute on function public.fn_supplier_member_by_phone(text) to service_role;
grant execute on function public.fn_supplier_transfer_start(bigint, text, text) to service_role;
grant execute on function public.fn_supplier_transfer_confirm(bigint, text, text) to service_role;
grant execute on function public.fn_supplier_close_propose(bigint, text, text, text, text) to service_role;
grant execute on function public.fn_supplier_close_decide(bigint, text, text) to service_role;
grant execute on function public.fn_supplier_close_account(bigint, text, text, text, text) to service_role;
grant execute on function public.fn_supplier_reopen_account(bigint, text) to service_role;
grant execute on function public.fn_supplier_what_the_law_keeps(bigint) to service_role;
grant execute on function public.fn_customer_decision_reason_save(uuid, uuid, text, text) to service_role;
grant execute on function public.fn_supplier_customer_not_answering(bigint, text, uuid, text, text) to service_role;
grant execute on function public.fn_supplier_demand_signal_record(bigint, text, text, text, text, text) to service_role;
