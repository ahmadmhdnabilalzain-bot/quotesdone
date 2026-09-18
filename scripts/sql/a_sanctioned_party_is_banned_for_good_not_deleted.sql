-- A SANCTIONED PARTY IS BANNED FOR GOOD, AND THE RECORD IS NEVER DELETED (18 Sep 2026, it_engineer
-- for the plumbing, ceo for the decision).
--
-- FOUNDER RULING, instruction 516, 18 Sep 2026. His first words were "if any of them is in the
-- sanctions delete that record totally". When it was put to him that deleting destroys the proof we
-- screened, and frees the name to sign up again the same afternoon, he chose: "better banned i
-- believe". So the rule this file implements is:
--
--   * a sanctioned party is PERMANENTLY banned -- never matched, never invited, never messaged,
--     never shown to a customer or another supplier, never able to sign in or act;
--   * the record is RETAINED AND SEALED, readable by the CEO seat as the audit trail of who was
--     matched, against which list and entry, when, and who decided;
--   * the NAME and the TRADE LICENCE NUMBER are blocked from re-registering;
--   * NOTHING hard-deletes a sanctions record.
--
-- WHAT WAS ALREADY TRUE, MEASURED 18 Sep 2026 against htdblwldjkcgjvmqkbeh before writing a line.
-- fn_supplier_screening_decide('confirmed') sets leads.banned, matching_blocked and withdraws the
-- approval. That flip reaches ONE surface honestly -- fn_is_matchable, and therefore
-- fn_match_capability, the only path that builds an RFQ shortlist. Everywhere else it is a column
-- nobody reads. This is the estate's "a status column is not a delivery record" lesson in its
-- access-control form. Counted: 120 live routines read public.leads; 22 of them name `banned` or
-- fn_is_matchable; 98 do not.
--
-- The four gaps that let a confirmed sanctions hit stay reachable, each measured:
--
--   1. INVITATIONS. enqueue_supplier_invites counts its pool with
--      `and coalesce(l.banned,false) = false` (full_schema.sql:12414-12417) and then selects the
--      actual recipients in the `cand` CTE (12496-12501) WITHOUT that clause. The instrument
--      excluded the banned; the actor invited them. Fixed below in the CTE.
--   2. MESSAGING. fn_supplier_notice, fn_notify_supplier, fn_wa_fanout,
--      fn_supplier_notice_whatsapp_twin_under_v11 and the customer_api loser-notice all queue into
--      public.notifications, and not one of them reads `banned`. Rather than patch five producers
--      and miss the sixth, the refusal goes on the table every one of them writes to:
--      a02_notifications_never_reach_a_sanctioned_party.
--   3. RE-REGISTRATION. public.leads has a unique index on lower(email) and on lower(claimed_by)
--      and NOTHING on company_name or trade_license_no. A sanctioned party signs up again with a
--      fresh mailbox and is a clean lead. Fixed by a01_leads_sanctioned_identity_cannot_re_register,
--      which sits on the table rather than in supplier_api, because there are three lead-creating
--      paths (supplier_api create_company, supplier_api claim, inbound_email) and a fourth will be
--      written one day.
--   4. THE RECORD IS DELETABLE. supplier_screening_hit.lead_id carries ON DELETE CASCADE
--      (full_schema.sql:8538), so `delete from leads where id = <the sanctioned party>` silently
--      takes the proof with it; and fn_supplier_sanctions_screen's own retention sweep
--      (52149) deletes every screening_entry outside the newest good run per source, evidence
--      rows included. Both are closed below: the lead cannot be deleted, and the retention sweep
--      keeps any entry a hit points at.
--
-- WHAT THIS FILE DOES NOT CHANGE, deliberately. fn_os_search, fn_suppliers_board, fn_ws_suppliers
-- and fn_table_export_page list a banned supplier, and they should: they are the CEO seat's own
-- screens, they already render `banned` as a field, and the founder asked for the record to stay
-- READABLE. "Never shown" is about customers and other suppliers, not about the owner of the
-- audit trail.
--
-- WHY A SEPARATE REGISTER AND NOT JUST `banned`. leads.banned is also set by fn_ban_overdue_dues
-- and fn_fraud_resolve, and those bans are reversible and ordinary -- a supplier banned for unpaid
-- dues must still be able to sign in and PAY them. A sanctions ban is a different animal: permanent,
-- total, and it must survive the row. public.sanctions_ban is what the surfaces ask, so a dues ban
-- is not silently promoted to a sanctions ban, and so the identity outlives the lead it was on.
--
-- APPLY ORDER: this file, then its probe (scripts/sql/probe_a_sanctioned_party_is_unreachable.sql),
-- then the MANIFEST line, then scripts/checks/a_sanctioned_party_is_unreachable.test.mjs.

-- ---------------------------------------------------------------------------------------------
-- 1. THE SEALED REGISTER
-- ---------------------------------------------------------------------------------------------
create table if not exists public.sanctions_ban (
  id               bigserial primary key,
  lead_id          bigint not null references public.leads(id),
  hit_id           bigint,
  entry_source     text,
  entry_reference  text,
  entry_name       text,
  name_key         text,                    -- fn_screening_normalise(company_name)
  licence_key      text,                    -- fn_sanctions_identity_key(trade_license_no)
  account_email    text,                    -- lower(claimed_by) at the moment of the ban
  contact_email    text,                    -- lower(email) at the moment of the ban
  decided_by       text not null,
  decided_at       timestamptz not null default now(),
  note             text
);
-- The lead_id FK deliberately has NO `on delete cascade`: it is the second lock on the door that
-- a00_leads_sanctioned_row_is_never_deleted holds shut. If that trigger were ever dropped, the
-- FK still refuses the delete.
create unique index if not exists sanctions_ban_lead_uidx    on public.sanctions_ban (lead_id);
create index        if not exists sanctions_ban_name_idx     on public.sanctions_ban (name_key)      where name_key is not null;
create index        if not exists sanctions_ban_licence_idx  on public.sanctions_ban (licence_key)   where licence_key is not null;
create index        if not exists sanctions_ban_account_idx  on public.sanctions_ban (account_email) where account_email is not null;
-- contact_email is indexed too, and not for symmetry: a02_notifications_never_reach_a_sanctioned_party
-- matches on it for EVERY insert into public.notifications, which is the busiest write in the estate.
create index        if not exists sanctions_ban_contact_idx  on public.sanctions_ban (contact_email) where contact_email is not null;

alter table public.sanctions_ban enable row level security;
drop policy if exists sanctions_ban_service_role_only on public.sanctions_ban;
create policy sanctions_ban_service_role_only on public.sanctions_ban
  as permissive for all to public using (false) with check (false);
revoke all on public.sanctions_ban from anon, authenticated;
revoke all on sequence public.sanctions_ban_id_seq from anon, authenticated;

comment on table public.sanctions_ban is
  'The permanent record of a CONFIRMED sanctions screening hit (founder instruction 516, 18 Sep 2026: '
  '"better banned i believe"). Written only by fn_supplier_screening_decide. Append-only: '
  'a00_sanctions_ban_is_append_only refuses UPDATE, DELETE and TRUNCATE. Read by the CEO seat as the '
  'audit trail, and by every surface that must refuse a sanctioned party.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE TWO KEYS EVERY SURFACE ASKS WITH
-- ---------------------------------------------------------------------------------------------
-- A licence number is written by hand and by OCR: "1633275", "1633275 ", "CN-1633275", "cn1633275"
-- are one licence. Names go through fn_screening_normalise, which already strips LLC/FZE/Trading
-- and the rest, because that is the function the screening itself matched with -- a blocklist that
-- normalises differently from the matcher is a blocklist with a gap shaped like the difference.
create or replace function public.fn_sanctions_identity_key(p text)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^[:alnum:]]+', '', 'g')), '');
$fn$;
revoke execute on function public.fn_sanctions_identity_key(text) from public, anon, authenticated;

-- SECURITY DEFINER is load-bearing, not habit. public.sanctions_ban is RLS-on with a deny-all
-- policy, so the same question asked as `authenticated` returns zero rows -- a guard that answers
-- "not sanctioned" for everyone it cannot see is the estate's "guarded by a condition that cannot
-- occur" in reverse, and it would pass every test run as service_role.
create or replace function public.fn_is_sanctioned_lead(p_lead bigint)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.sanctions_ban b where b.lead_id = p_lead);
$fn$;
revoke execute on function public.fn_is_sanctioned_lead(bigint) from public, anon, authenticated;

-- The identity question, asked of a name / licence / e-mail rather than of a row. Returns the
-- lead_id of the sanctioned party it recognises, or null. p_self excludes the banned row itself so
-- an ordinary UPDATE of the sanctioned lead (the CEO annotating it) is not refused by its own ban.
create or replace function public.fn_sanctioned_identity(
  p_name text, p_licence text, p_account_email text DEFAULT NULL, p_self bigint DEFAULT NULL)
returns bigint language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select b.lead_id from public.sanctions_ban b
   where (p_self is null or b.lead_id <> p_self)
     and ( (b.name_key       is not null and b.name_key       = public.fn_screening_normalise(p_name))
        or (b.licence_key    is not null and b.licence_key    = public.fn_sanctions_identity_key(p_licence))
        or (b.account_email  is not null and b.account_email  = lower(btrim(coalesce(p_account_email, ''))))
        or (b.contact_email  is not null and b.contact_email  = lower(btrim(coalesce(p_account_email, '')))) )
   order by b.lead_id limit 1;
$fn$;
revoke execute on function public.fn_sanctioned_identity(text,text,text,bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. THE REGISTER IS APPEND-ONLY
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_sanctions_ban_is_append_only()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  raise exception 'SANCTIONS_RECORD_IS_SEALED: public.sanctions_ban is append-only (founder instruction 516, 18 Sep 2026). % refused.', tg_op
    using errcode = '42501';
end $fn$;
revoke execute on function public.fn_sanctions_ban_is_append_only() from public, anon, authenticated;

drop trigger if exists a00_sanctions_ban_is_append_only     on public.sanctions_ban;
drop trigger if exists a00_sanctions_ban_no_truncate        on public.sanctions_ban;
create trigger a00_sanctions_ban_is_append_only
  before update or delete on public.sanctions_ban
  for each row execute function public.fn_sanctions_ban_is_append_only();
create trigger a00_sanctions_ban_no_truncate
  before truncate on public.sanctions_ban
  for each statement execute function public.fn_sanctions_ban_is_append_only();

-- ---------------------------------------------------------------------------------------------
-- 4. THE SCREENING EVIDENCE IS NEVER HARD-DELETED
-- ---------------------------------------------------------------------------------------------
-- supplier_screening_hit and screening_run: no delete, ever. screening_entry: the weekly sweep in
-- fn_supplier_sanctions_screen legitimately discards last week's copy of a 2,176,957-byte list,
-- but an entry that a HIT points at is evidence, not a stale copy, so that one stays.
create or replace function public.fn_screening_record_is_never_deleted()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_table_name = 'screening_entry' and tg_op = 'DELETE' then
    if exists (select 1 from public.supplier_screening_hit h
                where h.entry_id = old.id
                   or (h.entry_source = old.source and h.entry_reference = old.reference)) then
      raise exception 'SANCTIONS_RECORD_IS_SEALED: screening_entry #% is cited by a supplier_screening_hit and cannot be deleted.', old.id
        using errcode = '42501';
    end if;
    return old;
  end if;
  raise exception 'SANCTIONS_RECORD_IS_SEALED: % on public.% is refused (founder instruction 516, 18 Sep 2026: never hard-delete a sanctions record).', tg_op, tg_table_name
    using errcode = '42501';
end $fn$;
revoke execute on function public.fn_screening_record_is_never_deleted() from public, anon, authenticated;

drop trigger if exists a00_hit_is_never_deleted       on public.supplier_screening_hit;
drop trigger if exists a00_hit_is_never_truncated     on public.supplier_screening_hit;
drop trigger if exists a00_run_is_never_deleted       on public.screening_run;
drop trigger if exists a00_entry_cited_is_kept        on public.screening_entry;
create trigger a00_hit_is_never_deleted before delete on public.supplier_screening_hit
  for each row execute function public.fn_screening_record_is_never_deleted();
-- A TRUNCATE trigger is statement-level by definition; a row-level one is a syntax error, and a
-- whole-table wipe of the screening hits is the exact shape the estate's TRUNCATE guard exists for.
create trigger a00_hit_is_never_truncated before truncate on public.supplier_screening_hit
  for each statement execute function public.fn_screening_record_is_never_deleted();
create trigger a00_run_is_never_deleted before delete on public.screening_run
  for each row execute function public.fn_screening_record_is_never_deleted();
create trigger a00_entry_cited_is_kept before delete on public.screening_entry
  for each row execute function public.fn_screening_record_is_never_deleted();

-- ---------------------------------------------------------------------------------------------
-- 5. THE SANCTIONED LEAD ROW IS NEVER DELETED, AND NEVER QUIETLY UN-BANNED
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_leads_sanctioned_row_is_permanent()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_op = 'DELETE' then
    if public.fn_is_sanctioned_lead(old.id) then
      raise exception 'SANCTIONS_RECORD_IS_SEALED: lead #% carries a confirmed sanctions ban; deleting it would cascade away its supplier_screening_hit rows. The record is retained (founder instruction 516).', old.id
        using errcode = '42501';
    end if;
    return old;
  end if;
  -- UPDATE: the ban is permanent. Everything else about the row stays editable, so the CEO can
  -- annotate it and the screen can keep writing to it.
  if public.fn_is_sanctioned_lead(new.id)
     and (coalesce(new.banned, false) = false or coalesce(new.matching_blocked, false) = false) then
    raise exception 'SANCTIONS_BAN_IS_PERMANENT: lead #% is banned on a confirmed sanctions hit and cannot be un-banned or re-admitted to matching.', new.id
      using errcode = '42501';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_leads_sanctioned_row_is_permanent() from public, anon, authenticated;

-- TWO TRIGGERS, AT OPPOSITE ENDS OF THE NAME ORDER, AND THE REASON IS THE WHOLE POINT (database
-- review, 18 Sep 2026). Postgres fires BEFORE row triggers in NAME order.
--   * The DELETE half must run FIRST (a00): nothing else on this table should get to act on a row
--     that is not allowed to go.
--   * The UPDATE half must run LAST (zzz, after the existing zzz_collaboration_hold_guard, which
--     'zzz_c' < 'zzz_l' puts ahead of it): its job is to have the final word on NEW.banned and
--     NEW.matching_blocked. At a00 it would inspect NEW before any later BEFORE trigger could
--     change those columns, and a guard that reads the value somebody else is about to overwrite
--     is the estate's "before triggers do not read what a later one writes" defect. No live trigger
--     touches them today; this is so the next one added alphabetically cannot un-ban silently.
drop trigger if exists a00_leads_sanctioned_row_is_permanent on public.leads;
drop trigger if exists a00_leads_sanctioned_row_is_never_deleted on public.leads;
drop trigger if exists zzz_leads_sanctioned_ban_is_permanent on public.leads;
create trigger a00_leads_sanctioned_row_is_never_deleted
  before delete on public.leads
  for each row execute function public.fn_leads_sanctioned_row_is_permanent();
create trigger zzz_leads_sanctioned_ban_is_permanent
  before update on public.leads
  for each row execute function public.fn_leads_sanctioned_row_is_permanent();

-- ---------------------------------------------------------------------------------------------
-- 6. THE NAME AND THE LICENCE CANNOT RE-REGISTER
-- ---------------------------------------------------------------------------------------------
-- BEFORE INSERT OR UPDATE, on the table, because the licence number does not arrive with the
-- sign-up: supplier_api create_company writes only a company name, and trade_license_no is written
-- later by the document extraction (supplier_api/index.ts:492, supplier_portal/index.ts:479). A
-- guard that only looked at INSERT would admit every sanctioned party that uploads its licence on
-- the second visit.
create or replace function public.fn_leads_sanctioned_identity_cannot_re_register()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_banned bigint;
begin
  v_banned := public.fn_sanctioned_identity(new.company_name, new.trade_license_no,
                coalesce(nullif(btrim(new.claimed_by), ''), nullif(btrim(new.email), '')), new.id);
  if v_banned is not null then
    raise exception 'SANCTIONED_PARTY_BLOCKED: this company name, trade licence number or account e-mail belongs to lead #%, which carries a confirmed sanctions ban. It cannot be registered again (founder instruction 516, 18 Sep 2026).', v_banned
      using errcode = '23514';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_leads_sanctioned_identity_cannot_re_register() from public, anon, authenticated;

drop trigger if exists a01_leads_sanctioned_identity_cannot_re_register on public.leads;
create trigger a01_leads_sanctioned_identity_cannot_re_register
  before insert or update of company_name, trade_license_no, claimed_by, email on public.leads
  for each row execute function public.fn_leads_sanctioned_identity_cannot_re_register();

-- ---------------------------------------------------------------------------------------------
-- 7. NOTHING IS EVER SENT TO A SANCTIONED PARTY
-- ---------------------------------------------------------------------------------------------
-- public.notifications is the one table every outbound path writes to -- the invitation enqueuer,
-- fn_supplier_notice, fn_notify_supplier, the WhatsApp twin triggers, the loser notice, the
-- customer-message alert. Named a02 so it runs before the existing a03..a20 policies: a message to
-- a sanctioned party must not first be translated, signed and attachment-checked.
create or replace function public.fn_notifications_never_reach_a_sanctioned_party()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v bigint;
begin
  if new.lead_id is not null and public.fn_is_sanctioned_lead(new.lead_id) then
    v := new.lead_id;
  elsif coalesce(btrim(new.to_email), '') <> '' then
    select b.lead_id into v from public.sanctions_ban b
      where b.account_email = lower(btrim(new.to_email)) or b.contact_email = lower(btrim(new.to_email))
      limit 1;
  end if;
  if v is not null then
    raise exception 'SANCTIONED_PARTY_BLOCKED: nothing is sent to lead #%, which carries a confirmed sanctions ban (notification type %).', v, coalesce(new.type, '(none)')
      using errcode = '42501';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_never_reach_a_sanctioned_party() from public, anon, authenticated;

drop trigger if exists a02_notifications_never_reach_a_sanctioned_party on public.notifications;
create trigger a02_notifications_never_reach_a_sanctioned_party
  before insert on public.notifications
  for each row execute function public.fn_notifications_never_reach_a_sanctioned_party();

-- ---------------------------------------------------------------------------------------------
-- 8. THE DECISION WRITES THE REGISTER AND KILLS THE CLAIM LINK
-- ---------------------------------------------------------------------------------------------
-- CREATE OR REPLACE, so the ACL (postgres, service_role) is preserved -- see the apply-discipline
-- skill: only a DROP+CREATE would re-open this to PUBLIC.
--
-- Everything above the sanctions_ban insert is the body applied by PR #739, unchanged. Three things
-- are added: the register row (which is what every surface reads), the claim-token revocation (the
-- portal claim link /{lang}/portal?t=<claim_token> was never rotated on a ban, so an invitation
-- e-mail sent last month stayed a working front door), and the `claimed` flag going false so no
-- account continues to own the row.
create or replace function public.fn_supplier_screening_decide(p_hit_id bigint, p_decision text, p_actor text DEFAULT 'ceo'::text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; l record; v_open int; v_closed int := 0; t bigint; v jsonb;
begin
  if p_decision not in ('confirmed', 'false_positive') then
    raise exception 'fn_supplier_screening_decide: decision must be confirmed or false_positive, not %', p_decision;
  end if;
  select * into h from public.supplier_screening_hit where id = p_hit_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such hit ' || p_hit_id); end if;
  if h.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'hit ' || p_hit_id || ' is already ' || h.status); end if;

  update public.supplier_screening_hit set status = p_decision, decided_by = p_actor, decided_at = now() where id = p_hit_id;

  if p_decision = 'confirmed' then
    select * into l from public.leads where id = h.lead_id;
    -- THE REGISTER FIRST. Every refusal below and in the surfaces asks public.sanctions_ban, so it
    -- has to exist before the leads UPDATE fires a00_leads_sanctioned_row_is_permanent.
    insert into public.sanctions_ban
      (lead_id, hit_id, entry_source, entry_reference, entry_name, name_key, licence_key,
       account_email, contact_email, decided_by, note)
    values (h.lead_id, p_hit_id, h.entry_source, h.entry_reference, h.entry_name,
            public.fn_screening_normalise(l.company_name),
            public.fn_sanctions_identity_key(l.trade_license_no),
            nullif(lower(btrim(coalesce(l.claimed_by, ''))), ''),
            nullif(lower(btrim(coalesce(l.email, ''))), ''),
            p_actor,
            'Confirmed sanctions hit on ' || h.entry_source || ' ' || h.entry_reference
            || ' (' || h.entry_name || ') matched ' || h.field || ' "' || coalesce(h.supplier_value, '') || '".')
    on conflict (lead_id) do nothing;
    -- do nothing, not do update: one register row per party, written by the FIRST confirmed hit.
    -- A second confirmed hit on the same party changes nothing here on purpose — the register says
    -- WHO is banned, and public.supplier_screening_hit, which is append-only from today, holds every
    -- entry that was ever matched. The audit trail is the join, not this row alone.

    -- the same columns fn_ban_overdue_dues writes: banned + reason, matching blocked, and the approval withdrawn
    update public.leads
       set banned = true,
           banned_reason = 'Sanctions screening hit confirmed by ' || p_actor || ' on ' || to_char(now(), 'DD Mon YYYY') || ': '
                           || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') matched ' || h.field || ' "' || coalesce(h.supplier_value, '') || '".',
           matching_blocked = true,
           matching_block_reason = 'Banned: sanctions screening hit confirmed (' || h.entry_source || ')',
           approval_status = case when approval_status = 'approved' then 'rejected' else approval_status end,
           rejection_reason = coalesce(rejection_reason, 'sanctions screening hit confirmed'),
           -- THE FRONT DOORS. claim_token is NOT NULL with a default, so the link is ROTATED
           -- rather than cleared: /{lang}/portal?t=<the token in the invitation e-mail> stops
           -- resolving, and the new value has never been sent to anybody. claimed goes false so no
           -- account continues to own the row.
           claim_token = gen_random_uuid(),
           claimed = false
     where id = h.lead_id;
    -- every other open hit on the same supplier is decided by the same fact
    update public.supplier_screening_hit set status = 'confirmed', decided_by = p_actor, decided_at = now()
     where lead_id = h.lead_id and status = 'open';

    -- THE SESSION THEY ALREADY HOLD (security review, 18 Sep 2026). login_otp refuses to MINT a
    -- session for a sanctioned party, and supplier_api / supplier_portal / kyc / supplier_pay /
    -- supplier_catalog_ingest re-ask on every request, so a token issued five minutes before the
    -- ban buys nothing. This closes the last of it at the identity provider itself: GoTrue refuses
    -- both sign-in and refresh for a user whose banned_until is in the future. Measured 18 Sep
    -- 2026: this function is owned by postgres, and has_table_privilege('postgres','auth.users',
    -- 'update') is true, so this line cannot fail for want of rights -- if it ever did, the whole
    -- decision would roll back rather than half-land, which is the correct failure.
    update auth.users u
       set banned_until = 'infinity'::timestamptz
     where lower(u.email) in (nullif(lower(btrim(coalesce(l.claimed_by, ''))), ''),
                              nullif(lower(btrim(coalesce(l.email, ''))), ''));
  end if;

  select count(*) into v_open from public.supplier_screening_hit where lead_id = h.lead_id and status = 'open';
  if v_open = 0 then
    foreach t in array array_remove(array[h.task_id, h.bd_task_id], null) loop
      v := public.fn_org_task_close_as_fact(t, p_actor,
             case when p_decision = 'confirmed'
                  then 'Sanctions screening hit CONFIRMED by ' || p_actor || ': ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || '). The supplier (lead #' || h.lead_id || ') is PERMANENTLY banned and recorded in public.sanctions_ban: not matched, not invited, not messaged, not shown, unable to sign in, and the name and trade licence cannot register again. The record is retained and sealed.'
                  else 'Sanctions screening hit reviewed by ' || p_actor || ' and recorded as a FALSE POSITIVE: ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') is not lead #' || h.lead_id || '. No status change; outreach and onboarding may continue.' end,
             jsonb_build_object('hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id, 'owner', p_actor));
      if coalesce((v ->> 'ok')::boolean, false) then v_closed := v_closed + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id,
                            'open_hits_left', v_open, 'tasks_closed', v_closed,
                            'sanctions_ban', p_decision = 'confirmed');
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 9. THE INVITATION ENQUEUER STOPS COUNTING ONE POOL AND WRITING TO ANOTHER
-- ---------------------------------------------------------------------------------------------
-- `and coalesce(l.banned,false) = false` added to the `cand` CTE, the clause the pool count two
-- hundred lines above has always had. Nothing else in enqueue_supplier_invites is changed.
create or replace function public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
returns integer language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text;
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select count(*) into v_pool from leads l
   where l.email is not null and l.email <> '' and l.invite_status is null
     and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
     and coalesce(l.banned,false) = false;
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' never-invited lead(s) with an email, cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  select coalesce(nullif(btrim(value),''), 'https://quotesdone.com') into v_site
    from app_secrets where key='public_site_url';
  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing. Both CTEs are referenced exactly once, from
  -- inside the correlated subquery in `prio`. Without this keyword Postgres inlines them there and
  -- re-runs the whole leads x lead_subcategory aggregate once per candidate - 19,632 times, twice
  -- over, ~220 s against a 120 s timeout. Neither depends on the outer row, so computing them once
  -- is semantically identical and 54x faster. Do not remove.
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      -- 18 SEP 2026: the pool count 120 lines above has always excluded banned leads and this CTE
      -- never did, so the number reported as "the pool" and the set actually written to were not
      -- the same set. A banned supplier with invite_status null was invited.
      and coalesce(l.banned,false) = false
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select id, email, company_name, claim_token from (
      select id, email, company_name, claim_token, pdomain, unverified_rank, role_rank,
        case when pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by pdomain order by unverified_rank, role_rank, id) as rk,
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, role_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    order by is_none, rk, unverified_rank, role_rank, pdomain
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(
             replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')),
             '{{link}}', v_site || '/en/portal?t=' || claim_token::text), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap || ').', now(), now());
  return v_count;
end;
$fn$;

-- ---------------------------------------------------------------------------------------------
-- 10. THE RETENTION SWEEP KEEPS THE EVIDENCE
-- ---------------------------------------------------------------------------------------------
-- fn_supplier_sanctions_screen deletes every screening_entry outside the newest good run per
-- source, and a00_entry_cited_is_kept now refuses the delete of an entry a hit cites -- which
-- would make that sweep raise and take the whole weekly screening run with it. The sweep skips
-- those rows instead.
--
-- RESTATED IN FULL, NOT PATCHED IN PLACE (18 Sep 2026, after the apply).
--
-- This section first narrowed the sweep with a `do $do$` block that read
-- pg_get_functiondef(), regexp_replace()d one clause into it and re-executed the result. It worked
-- -- production carries the narrowing -- and it was the WRONG SHAPE, which canonical_routine_manifest
-- said out loud the moment it was applied:
--
--   fn_supplier_sanctions_screen DRIFTED - 1 canonical body not deployed, 1 deployed body not in
--   the canonical file [scripts/sql/the_sanctions_screen_stops_opening_tasks_on_seats_that_do_not_exist.sql]
--
-- The scanner was right and the check must not be softened. A routine's canonical file is the file
-- that CONTAINS its body, and a dynamic rewrite contains a diff instead: the older file stayed the
-- canonical owner while no longer matching production, so the repository stopped showing what
-- production runs. "One canonical file per routine, and it is what is deployed" is exactly the rule
-- a rewrite block cannot satisfy, however correct its output.
--
-- So the body below is the LIVE definition, read back out of htdblwldjkcgjvmqkbeh with
-- pg_get_functiondef() after the apply and pasted verbatim. This file is last in MANIFEST.txt, so it
-- becomes the canonical owner and the drift closes. Everything here is PR #746's and #739's work
-- unchanged except the one clause this change is about, marked SANCTIONS_EVIDENCE_KEPT below: an
-- entry that a supplier_screening_hit cites is evidence, not a stale copy of the list, so the weekly
-- retention sweep leaves it alone. a00_entry_cited_is_kept remains the backstop for every other
-- caller -- the clause here is so the sweep SKIPS those rows rather than colliding with the trigger
-- and taking the whole screening run down with it.
--
-- The rewrite block also reported nothing: it ended in `raise notice`, which the management API
-- discards. A restated body needs no verdict -- apply_sql.mjs reads the definition back and compares
-- it to the file, which is a stronger statement than any notice.
CREATE OR REPLACE FUNCTION public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_hold bigint; v_title text; v_hold_title text; v_hits text;
begin
  select string_agg(distinct source || ' (' || entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ')', '; ')
    into v_sources from public.screening_run where id = any(p_run_ids);

  create temp table tmp_screen_sup on commit drop as
    select l.id, f.field, f.val, public.fn_screening_normalise(f.val) as norm, public.fn_screening_tokens(f.val) as toks
      from public.leads l
      cross join lateral (values ('legal_name', l.company_name), ('licence_name', l.name_corrected_from),
                                 ('owner', l.signatory_name), ('contact', l.contact_name),
                                 ('email_domain', split_part(coalesce(l.email_domain, split_part(coalesce(l.email, ''), '@', 2)), '.', 1))) f(field, val)
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and case when v_reh then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end
       and nullif(btrim(coalesce(f.val, '')), '') is not null;
  select count(distinct id) into v_suppliers from tmp_screen_sup;
  select count(*) into v_entries from public.screening_entry where run_id = any(p_run_ids);

  for h in
    select s.id as lead_id, s.field, s.val, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from tmp_screen_sup s
      join public.screening_entry e
        on e.run_id = any(p_run_ids)
       and ((s.field <> 'email_domain' and s.norm = e.name_norm and length(s.norm) >= 6)
         or (s.field <> 'email_domain' and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2
             and (s.toks <@ e.tokens or e.tokens <@ s.toks))
         or (s.field = 'email_domain' and length(s.norm) >= 6 and replace(e.name_norm, ' ', '') = s.norm))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, h.field, h.val, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- THE TEAM UPDATE, ON SEATS THAT EXIST (18 Sep 2026). One DECISION task on the ceo, because a confirmed
  -- hit removes a supplier and every approval in this company is the CEO's; one HOLD on the sales_engineer,
  -- because supplier verification and supplier-facing outreach are that seat's work. Never the founder.
  for r in
    select x.lead_id, l.company_name, count(*) as n,
           string_agg(format('%s %L matched %L [%s %s] %s, score %s', x.field, x.supplier_value, x.entry_name, x.entry_source, x.entry_reference, x.match_kind, x.score), E'\n' order by x.score desc, x.id) as ev,
           string_agg(x.id::text, ', ' order by x.id) as ids
      from public.supplier_screening_hit x join public.leads l on l.id = x.lead_id
     where x.status = 'open' and x.task_id is null and x.run_id = any(p_run_ids)
     group by x.lead_id, l.company_name
  loop
    v_title := 'Sanctions screening hit: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id;
    select id into v_task from public.org_tasks where title = v_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_task is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_title,
              'The weekly sanctions screening (' || coalesce(v_sources, 'fixture run') || ') matched a REGISTERED supplier. EVIDENCE:' || E'\n' || r.ev
              || E'\n\n' || 'No automatic removal has happened. Compare the supplier''s trade licence, owner and address against the listing and decide, per hit: '
              || 'select public.fn_supplier_screening_decide(<hit_id>, ''confirmed'' | ''false_positive'', ''ceo''). '
              || 'A confirmed hit moves the supplier through the existing status path (leads.banned + banned_reason, matching_blocked, approval_status rejected) and closes this task and the sales engineer''s hold; a false positive closes the hit. '
              || 'Hit id(s): ' || r.ids || '.',
              'assigned', 'supervised', false, 'compliance_check', 'ceo')
      returning id into v_task;
    end if;
    v_hold_title := 'Hold outreach and onboarding: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id || ' (sanctions screening)';
    select id into v_hold from public.org_tasks where title = v_hold_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_hold is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_hold_title,
              'The CEO is reviewing a sanctions-screening match on this supplier (task #' || v_task || '). Send no invitation, follow-up or onboarding step to lead #' || r.lead_id
              || ' until the CEO decides; this task closes with that decision.',
              'assigned', 'autonomous', false, 'coordinate', 'sales_engineer')
      returning id into v_hold;
    end if;
    update public.supplier_screening_hit set task_id = v_task, bd_task_id = v_hold
     where lead_id = r.lead_id and status = 'open' and task_id is null;
    v_leads_hit := v_leads_hit + 1;
  end loop;

  -- retention: the latest fetch per source is the list; older entries go (their run rows stay as the record)
  if not v_reh then
    delete from public.screening_entry e
     where e.run_id not in (select max(id) from public.screening_run where status = 'ok' group by source)
       -- SANCTIONS_EVIDENCE_KEPT (18 Sep 2026): an entry a hit cites is evidence, not a stale copy of
       -- the list. Kept here, and a00_entry_cited_is_kept refuses it for every other caller.
       and not exists (select 1 from public.supplier_screening_hit h
                        where h.entry_id = e.id or (h.entry_source = e.source and h.entry_reference = e.reference));
  end if;

  select count(*) into v_open from public.supplier_screening_hit where status = 'open';
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_sanctions_screen', 'ok',
          jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open,
                             'runs', to_jsonb(p_run_ids), 'rehearsal', v_reh),
          'Sanctions screening: ' || v_suppliers || ' registered supplier(s) screened against ' || v_entries || ' list entries (' || coalesce(v_sources, 'no run') || '): '
          || v_new || ' new hit(s) on ' || v_leads_hit || ' supplier(s); ' || v_open || ' open. A hit opens ONE decision task on the ceo and ONE hold on the sales_engineer; nobody is removed automatically.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open, 'sources', v_sources);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 11. WHAT IS DELIBERATELY NOT CHANGED HERE
-- ---------------------------------------------------------------------------------------------
-- fn_supplier_registration_state.may_quote reads the SUBSCRIPTION only, so it answers true for a
-- banned supplier. It is left alone: supplier_api's submit_quote gate refuses on
-- `approval_status !== 'approved'` first, and section 8 sets approval_status to 'rejected'
-- (from 'approved') or leaves it at whatever non-approved value it already held. Measured, not
-- assumed: a sanctioned lead cannot reach the may_quote branch because the gate above it never
-- passes. Widening may_quote to read the ban is a second gate on the same door, and the surface
-- guard added to supplier_api in the same PR is the one that is actually reached.

-- ---------------------------------------------------------------------------------------------
-- 12. A PHONE NUMBER STOPS NAMING A SANCTIONED PARTY
-- ---------------------------------------------------------------------------------------------
-- The WhatsApp channel authenticates by handset, not by session, so none of the edge-function
-- guards reach it (security review, 18 Sep 2026). fn_whatsapp_owner is the root of that identity:
-- fn_wa_lead_id reads it, fn_conversation_party's phone branch reads it, fn_identify_contact reads
-- it, and fn_supplier_apply_change -- which lets a supplier CHANGE A QUOTED PRICE by text message
-- -- is scoped by fn_wa_lead_id. One clause here closes all four, instead of four clauses that
-- would have to be kept in step.
--
-- Everything else in the body is PR #322's, unchanged, including the "a phone may confirm, never
-- select" rule at the bottom. The sanctioned lead is dropped from `hits` rather than filtered at
-- the end deliberately: dropping it EARLY means a number shared between a sanctioned party and a
-- clean supplier resolves to the clean one, where filtering late would have left one row and
-- silently handed the number to somebody else.
create or replace function public.fn_whatsapp_owner(p_phone text, p_all boolean DEFAULT false)
returns TABLE(party_kind text, customer_id uuid, lead_id bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with t as (select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9) as tail),
  hits as (
    select 'customer'::text as party_kind, c.id as customer_id, null::bigint as lead_id
      from public.customers c, t
     where length(t.tail) = 9
       and ((c.whatsapp_opt = 'other' and c.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (c.whatsapp_opt = 'same' and coalesce(c.phone_verified, false)
             and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail))
    union
    select 'supplier', null, l.id
      from public.leads l, t
     where length(t.tail) = 9
       -- 18 Sep 2026, founder instruction 516: a confirmed sanctions ban means the handset names
       -- nobody. WhatsApp is the one channel with no session to refuse.
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id)
       and ((l.whatsapp_opt = 'other' and l.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (l.whatsapp_opt = 'same' and coalesce(l.owner_phone_verified, false)
             and right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)))
  -- A PHONE MAY CONFIRM, NEVER SELECT: one party or nobody.
  select h.party_kind, h.customer_id, h.lead_id from hits h where p_all or (select count(*) from hits) = 1
$fn$;
