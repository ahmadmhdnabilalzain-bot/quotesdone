-- EVERY FRAUD FLAG AND EVERY SANCTIONS HIT IS REASONED BY ITS SEAT, AND THE PARTY IS FROZEN UNTIL IT IS DECIDED.
-- Seats: ceo (the sanctions decision, the org_task register rows) and accountant (the fraud flags, the request
-- velocity fact). Agent: FLAGS_DECIDED, 16 Nov 2026. Holes 3, 5, 9 and 10 of the real-company hole hunt
-- (scratchpad holes/FAILURES.md, read from origin/main 55489dde7).
--
-- MEASURED BEFORE WRITING (production, light SELECT, 16 Nov 2026, counts only):
--   fraud_flags open: free_email_company 1 (since 29 Sep, 47 days), refund_pattern 1 (since 3 Nov), customer_matches_supplier
--   1 (since 13 Nov); none carries a review. supplier_screening_hit: 0 rows. org_task_kind_handler has no row for
--   compliance_check or coordinate. Duties: accountant.fraud_watch and accountant.risk_screen (6 h), accountant.sanctions_rescreen
--   and accountant.ubo_rescreen (1 day). No new_inquiry notice reached a supplier in the last 30 days (no traffic).
--
-- WHAT WAS TRUE (READ, from the schema mirror):
--   * a weekly or daily sanctions hit opened an org_task for the CEO saying "run fn_supplier_screening_decide by hand"; no
--     routine called it, no handler was registered, fn_is_matchable never read an open hit and the reveal asked only the
--     confirmed register (_shared/sanctioned.ts). Customers were never screened. A confirmed ban told no customer.
--   * customer_matches_supplier was exact phone / e-mail equality, filed no reasoning and bit only at the money screen.
--   * only the three circumvention kinds were reasoned; every other flag waited for a money move or a person.
--   * create_inquiry had no per-account velocity fact, and every request mailed every matched supplier at once.
--
-- WHAT IS TRUE AFTER THIS FILE:
--   1. SANCTIONS. Customers are screened inside fn_supplier_sanctions_screen, so at every point suppliers are (the weekly fetch
--      and the accountant's daily re-screen), against the same UN consolidated and UAE local terrorist list runs, into
--      public.customer_screening_hit (sealed like the supplier record). An OPEN hit freezes the party: a supplier's
--      matching_blocked is set with reason 'compliance_review' (fn_is_matchable already reads it; the supplier portal shows the
--      neutral "set by our team" line, no tipping-off), and the reveal refuses while any hit on either party is open
--      (_shared/sanctioned.ts screeningOpen, reveal_guard.ts). A customer with an open hit is not matched (customer_api).
--      The duty ceo.sanctions_review (hourly) files every party with open hits for the CEO's reasoning
--      (ceo.sanctions_hit) with the screening facts: each hit, the list entry, the party's own record. The model decides
--      confirmed / false_positive / cannot_tell; fn_reason_apply_ceo__sanctions_hit applies it through
--      fn_supplier_screening_decide / fn_customer_screening_decide. The decision is due 24 hours after the first hit
--      (decide_by); past it, with the party still frozen, an it_engineer finding owned by the ceo names what is missing.
--      compliance_check and coordinate are registered in org_task_kind_handler. A confirmed supplier ban (any path: an
--      insert into sanctions_ban) tells every customer holding that supplier's live quote or reveal, honestly and without
--      a reason (fn_sanctions_ban_tells_affected_customers): the supplier is no longer available and its quotation is
--      withdrawn; a customer who paid to reveal it is told to reply so the fee is reviewed.
--   2. FRAUD FLAGS. Every new flag (any writer, any severity) goes to the accountant's reasoning (accountant.fraud_flag) at
--      insert, with full facts (fn_accountant_flag_facts) and a close_by date (high 2 days, medium 5, low 10). The three
--      circumvention kinds keep their own surface. The duty accountant.flag_review (hourly) files the open flags that have
--      no review yet (the backlog of 47 and 13 days included), and reports a flag still open past its close_by to the CEO.
--      genuine -> escalated and cross-reviewed by the CEO; benign -> dismissed; insufficient_evidence -> stays open.
--   3. A SUPPLIER POSING AS A CUSTOMER. The same tick also raises customer_matches_supplier on equal terms IP or an equal
--      company e-mail domain (equality only: the model decides what it means). Its facts carry the IP and domain equality,
--      the supplier's trades, the customer's requests and reveals in those trades and the rival quotes he could see.
--      While it is open or escalated, that customer's quotes in those trades are held ("being checked"):
--      fn_customer_quotes_being_checked, read by customer_api my_inquiries.
--   4. VELOCITY. Every request carries plausibility.velocity (the account's requests in the last hour and day) at insert;
--      at or over decision_policy.request_velocity_flag_per_hour (5) a request_velocity flag is raised on the customer and
--      reasoned like any other. A supplier gets at most one new-job notice per channel per hour: a later one waits for the
--      hour and the ones after it are folded into it (fn_new_job_notices_are_batched_per_hour).
--
-- Nothing here sends a model call itself; the held questions are answered by the existing replay (resilience_ping).
-- Prevented by: scripts/checks/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.test.mjs
-- Probe: scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided_probe.sql
--   node scripts/apply_sql.mjs scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql --apply --ddl --seat ceo

set local lock_timeout = '3s';

-- ── 1. the customer screening record ────────────────────────────────────────────────────────────────────────────────
create table if not exists public.customer_screening_hit (
  id bigint generated always as identity primary key,
  run_id bigint references public.screening_run(id) on delete set null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  field text not null check (field in ('customer_name', 'email_domain')),
  customer_value text,
  entry_id bigint,
  entry_name text,
  entry_source text not null,
  entry_reference text not null default '',
  entry_type text,
  match_kind text not null check (match_kind in ('exact', 'token_overlap')),
  score numeric,
  status text not null default 'open' check (status in ('open', 'confirmed', 'false_positive')),
  decided_by text,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (customer_id, entry_source, entry_reference, field)
);
create index if not exists customer_screening_hit_open_idx on public.customer_screening_hit (customer_id) where status = 'open';
alter table public.customer_screening_hit enable row level security;
drop policy if exists customer_screening_hit_service_role_only on public.customer_screening_hit;
create policy customer_screening_hit_service_role_only on public.customer_screening_hit
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_screening_hit from anon, authenticated;
create index if not exists supplier_screening_hit_open_idx on public.supplier_screening_hit (lead_id) where status = 'open';

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_screening_hit', true, 'company', 'sanctions screening matches on customers, sealed like supplier_screening_hit (16 Nov 2026)', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- the sanctions record is never deleted: the same seal, now also for an entry a customer hit cites
create or replace function public.fn_screening_record_is_never_deleted()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_table_name = 'screening_entry' and tg_op = 'DELETE' then
    if exists (select 1 from public.supplier_screening_hit h
                where h.entry_id = old.id
                   or (h.entry_source = old.source and h.entry_reference = old.reference))
       or exists (select 1 from public.customer_screening_hit h
                   where h.entry_id = old.id
                      or (h.entry_source = old.source and h.entry_reference = old.reference)) then
      raise exception 'SANCTIONS_RECORD_IS_SEALED: screening_entry #% is cited by a screening hit and cannot be deleted.', old.id
        using errcode = '42501';
    end if;
    return old;
  end if;
  raise exception 'SANCTIONS_RECORD_IS_SEALED: % on public.% is refused (founder instruction 516, 18 Sep 2026: never hard-delete a sanctions record).', tg_op, tg_table_name
    using errcode = '42501';
end $fn$;
revoke execute on function public.fn_screening_record_is_never_deleted() from public, anon, authenticated;
drop trigger if exists a00_customer_hit_is_never_deleted on public.customer_screening_hit;
create trigger a00_customer_hit_is_never_deleted before delete on public.customer_screening_hit
  for each row execute function public.fn_screening_record_is_never_deleted();
drop trigger if exists a00_customer_hit_is_never_truncated on public.customer_screening_hit;
create trigger a00_customer_hit_is_never_truncated before truncate on public.customer_screening_hit
  for each statement execute function public.fn_screening_record_is_never_deleted();

-- ── 2. customers are screened against the same runs, by the same matching rule as suppliers ─────────────────────────
-- Fields: the person's full name, and the e-mail domain when it is a company's own (free webmail says nothing about
-- who the party is). Scope: an account that accepted the terms and was not merged away; the demo split is the
-- supplier screen's (a rehearsal tag screens ZZ DEMO only, otherwise demo accounts never).
create or replace function public.fn_customer_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_customers int := 0; v_new int := 0; v_open int := 0; h record;
begin
  drop table if exists tmp_screen_cust;
  create temp table tmp_screen_cust on commit drop as
    select c.id, f.field, f.val, public.fn_screening_normalise(f.val) as norm, public.fn_screening_tokens(f.val) as toks
      from public.customers c
      cross join lateral (values ('customer_name', c.full_name),
                                 ('email_domain', case when public.fn_email_domain_class(c.email) = 'company'
                                                       then split_part(split_part(lower(coalesce(c.email, '')), '@', 2), '.', 1) end)) f(field, val)
     where c.tos_accepted_at is not null and c.merged_into is null
       and case when v_reh then coalesce(c.is_demo, false) else not coalesce(c.is_demo, false) end
       and nullif(btrim(coalesce(f.val, '')), '') is not null;
  select count(distinct id) into v_customers from tmp_screen_cust;

  for h in
    select s.id as customer_id, s.field, s.val, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from tmp_screen_cust s
      join public.screening_entry e
        on e.run_id = any(p_run_ids)
       and ((s.field <> 'email_domain' and s.norm = e.name_norm and length(s.norm) >= 6)
         or (s.field <> 'email_domain' and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2
             and (s.toks <@ e.tokens or e.tokens <@ s.toks))
         or (s.field = 'email_domain' and length(s.norm) >= 6 and replace(e.name_norm, ' ', '') = s.norm))
  loop
    insert into public.customer_screening_hit (run_id, customer_id, field, customer_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.customer_id, h.field, h.val, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (customer_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;
  drop table if exists tmp_screen_cust;
  select count(*) into v_open from public.customer_screening_hit where status = 'open';
  return jsonb_build_object('customers', v_customers, 'hits_new', v_new, 'hits_open', v_open);
end $fn$;
revoke execute on function public.fn_customer_sanctions_screen(bigint[], text) from public, anon, authenticated;

-- ── 2b. the supplier screen, unchanged except that it screens the customers at the end and keeps an entry a customer hit cites ──
create or replace function public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_hold bigint; v_title text; v_hold_title text; v_hits text; v_cust jsonb;
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
       and not exists (select 1 from public.supplier_screening_hit sh
                        where sh.entry_id = e.id or (sh.entry_source = e.source and sh.entry_reference = e.reference))
       -- 16 Nov 2026: an entry a CUSTOMER hit cites is the same kind of evidence.
       and not exists (select 1 from public.customer_screening_hit ch
                        where ch.entry_id = e.id or (ch.entry_source = e.source and ch.entry_reference = e.reference));
  end if;

  -- THE CUSTOMERS, AT THE SAME POINT (16 Nov 2026, FAILURES item 3): every caller of this screen (the weekly fetch, the
  -- accountant's daily re-screen) screens the buyers too, against the same runs. Their hits wait for the same CEO reasoning.
  v_cust := public.fn_customer_sanctions_screen(p_run_ids, p_rehearsal_tag);

  select count(*) into v_open from public.supplier_screening_hit where status = 'open';
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_sanctions_screen', 'ok',
          jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open,
                             'runs', to_jsonb(p_run_ids), 'rehearsal', v_reh, 'customers', v_cust),
          'Sanctions screening: ' || v_suppliers || ' registered supplier(s) screened against ' || v_entries || ' list entries (' || coalesce(v_sources, 'no run') || '): '
          || v_new || ' new hit(s) on ' || v_leads_hit || ' supplier(s); ' || v_open || ' open. A hit opens ONE decision task on the ceo and ONE hold on the sales_engineer; nobody is removed automatically.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open, 'sources', v_sources,
                            'customers', v_cust);
end $function$;
revoke execute on function public.fn_supplier_sanctions_screen(bigint[], text) from public, anon, authenticated;

-- ── 3. an open hit freezes the supplier in matching ─────────────────────────────────────────────────────────────────
-- fn_is_matchable reads matching_blocked; this sets it while any hit on the supplier is open, with a reason the
-- document job neither overwrites nor clears (fn_reconcile_doc_blocks touches only licence_expired / insurance_expired),
-- and lifts it only when the block is this one and no hit is open. A confirmed hit then lands the permanent ban in
-- fn_supplier_screening_decide, in the same transaction.
create or replace function public.fn_screening_hit_freezes_the_supplier()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_open boolean;
begin
  v_open := exists (select 1 from public.supplier_screening_hit h where h.lead_id = new.lead_id and h.status = 'open');
  if v_open then
    update public.leads
       set matching_blocked = true, matching_block_reason = 'compliance_review'
     where id = new.lead_id and not coalesce(banned, false)
       and (not coalesce(matching_blocked, false) or coalesce(matching_block_reason, '') in ('licence_expired', 'insurance_expired', ''));
  else
    update public.leads
       set matching_blocked = false, matching_block_reason = null
     where id = new.lead_id and matching_block_reason = 'compliance_review';
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_screening_hit_freezes_the_supplier() from public, anon, authenticated;
drop trigger if exists z10_screening_hit_freezes_the_supplier on public.supplier_screening_hit;
create trigger z10_screening_hit_freezes_the_supplier after insert or update of status on public.supplier_screening_hit
  for each row execute function public.fn_screening_hit_freezes_the_supplier();

-- ── 4. the customer decision, the twin of fn_supplier_screening_decide ──────────────────────────────────────────────
-- A confirmed hit bans the customer (customers.banned refuses a new request at insert: trg_block_banned_inquiry) and
-- refuses sign-in and refresh at the identity provider; every other open hit on him is decided by the same fact.
create or replace function public.fn_customer_screening_decide(p_hit_id bigint, p_decision text, p_actor text default 'ceo')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.customer_screening_hit; c public.customers; v_open int;
begin
  if p_decision not in ('confirmed', 'false_positive') then
    raise exception 'fn_customer_screening_decide: decision must be confirmed or false_positive, not %', p_decision;
  end if;
  select * into h from public.customer_screening_hit where id = p_hit_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such hit ' || p_hit_id); end if;
  if h.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'hit ' || p_hit_id || ' is already ' || h.status); end if;
  update public.customer_screening_hit set status = p_decision, decided_by = p_actor, decided_at = now() where id = p_hit_id;
  if p_decision = 'confirmed' then
    select * into c from public.customers where id = h.customer_id;
    update public.customers
       set banned = true,
           banned_reason = 'Sanctions screening hit confirmed by ' || p_actor || ' on ' || to_char(now(), 'DD Mon YYYY') || ': '
                           || h.entry_source || ' ' || h.entry_reference || ' (' || coalesce(h.entry_name, '') || ') matched ' || h.field || '.'
     where id = h.customer_id;
    update public.customer_screening_hit set status = 'confirmed', decided_by = p_actor, decided_at = now()
     where customer_id = h.customer_id and status = 'open';
    update auth.users u set banned_until = 'infinity'::timestamptz
     where lower(u.email) = nullif(lower(btrim(coalesce(c.email, ''))), '');
  end if;
  select count(*) into v_open from public.customer_screening_hit where customer_id = h.customer_id and status = 'open';
  return jsonb_build_object('ok', true, 'hit_id', p_hit_id, 'decision', p_decision, 'customer_id', h.customer_id, 'open_hits_left', v_open);
end $fn$;
revoke execute on function public.fn_customer_screening_decide(bigint, text, text) from public, anon, authenticated;

-- ── 5. the CEO decides every open hit with the screening facts, within a day ────────────────────────────────────────
-- The facts the model reads: each hit (which of the party's fields matched which list entry, exact or by shared name
-- tokens, the score), the list entry as published (source, reference, type, name), and the party's own record. The
-- question names both lists the estate screens (UN consolidated, UAE local terrorist list) and what each answer does.
create or replace function public.fn_ceo_sanctions_party_facts(p_party text, p_lead bigint, p_customer uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; v_hits jsonb; v_first timestamptz;
begin
  if p_party = 'supplier' then
    select coalesce(jsonb_agg(jsonb_build_object('hit_id', h.id, 'field', h.field, 'party_value', h.supplier_value,
             'list_entry', jsonb_build_object('name', h.entry_name, 'source', h.entry_source, 'reference', h.entry_reference, 'type', h.entry_type),
             'match', h.match_kind, 'score', h.score, 'found_at', h.created_at) order by h.id), '[]'::jsonb), min(h.created_at)
      into v_hits, v_first
      from public.supplier_screening_hit h where h.lead_id = p_lead and h.status = 'open';
    select jsonb_build_object('party', 'supplier', 'lead_id', l.id, 'company_name', l.company_name,
             'licence_legal_name', l.licence_legal_name, 'name_on_licence_before_correction', l.name_corrected_from,
             'trade_licence_no', l.trade_license_no, 'emirate', l.emirate, 'owner_or_signatory', l.signatory_name,
             'contact_name', l.contact_name, 'email_domain', coalesce(l.email_domain, split_part(coalesce(l.email, ''), '@', 2)),
             'website', l.domain, 'approval_status', l.approval_status, 'registered', l.lifecycle_stage = 'registered',
             'beneficial_owners', (select coalesce(jsonb_agg(jsonb_build_object('name', o.full_name)), '[]'::jsonb)
                                     from public.supplier_beneficial_owner o where o.lead_id = l.id))
      into v from public.leads l where l.id = p_lead;
  else
    select coalesce(jsonb_agg(jsonb_build_object('hit_id', h.id, 'field', h.field, 'party_value', h.customer_value,
             'list_entry', jsonb_build_object('name', h.entry_name, 'source', h.entry_source, 'reference', h.entry_reference, 'type', h.entry_type),
             'match', h.match_kind, 'score', h.score, 'found_at', h.created_at) order by h.id), '[]'::jsonb), min(h.created_at)
      into v_hits, v_first
      from public.customer_screening_hit h where h.customer_id = p_customer and h.status = 'open';
    select jsonb_build_object('party', 'customer', 'customer_id', c.id, 'full_name', c.full_name,
             'email_domain', split_part(coalesce(c.email, ''), '@', 2), 'email_domain_class', public.fn_email_domain_class(c.email),
             'phone_country_code', substring(regexp_replace(coalesce(c.phone, ''), '[^0-9+]', '', 'g') from '^\+?(\d{1,3})'),
             'date_of_birth_on_record', c.date_of_birth is not null, 'industry', c.industry, 'account_created', c.created_at,
             'requests_posted', (select count(*) from public.inquiries i where i.customer_id = c.id))
      into v from public.customers c where c.id = p_customer;
  end if;
  return jsonb_build_object('record', coalesce(v, '{}'::jsonb), 'open_hits', v_hits, 'first_hit_at', v_first,
    'decide_by', v_first + interval '24 hours',
    'lists', 'UN Security Council consolidated list (un_consolidated) and the UAE local terrorist list (uae_local_terrorist_list), fetched weekly into public.screening_run',
    'while_open', 'the party is frozen: not matched, not revealed, no reveal fee taken');
end $fn$;
revoke execute on function public.fn_ceo_sanctions_party_facts(text, bigint, uuid) from public, anon, authenticated;

create or replace function public.fn_ceo_sanctions_review_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r record; v_facts jsonb; v_id bigint; v_filed int := 0; v_overdue int := 0; v_key text; v_q text; v_items jsonb := '[]'::jsonb;
begin
  for r in
    select 'supplier'::text as party, h.lead_id, null::uuid as customer_id, array_agg(h.id order by h.id) as ids, min(h.created_at) as first_at,
           max(case when l.company_name like 'ZZ DEMO%' or coalesce(l.is_demo, false) then 1 else 0 end) = 1 as demo
      from public.supplier_screening_hit h join public.leads l on l.id = h.lead_id
     where h.status = 'open' group by h.lead_id
    union all
    select 'customer', null, h.customer_id, array_agg(h.id order by h.id), min(h.created_at), bool_or(coalesce(c.is_demo, false))
      from public.customer_screening_hit h join public.customers c on c.id = h.customer_id
     where h.status = 'open' group by h.customer_id
  loop
    v_facts := public.fn_ceo_sanctions_party_facts(r.party, r.lead_id, r.customer_id);
    v_key := 'sanctions_hit:' || r.party || ':' || coalesce(r.lead_id::text, r.customer_id::text) || ':' || array_to_string(r.ids, ',');
    v_q := case when r.demo then 'ZZ DEMO ' else '' end
      || 'The weekly sanctions screening matched a ' || r.party || ' of QuotesDone (a UAE marketplace) to an entry on a sanctions list. '
      || 'Compare the party''s own record with the list entry it matched (name, type of entry, the other fields of the record) and decide, '
      || 'as the company''s compliance decision: is this party the listed party? The party is frozen until you decide, and the decision is due by '
      || to_char((r.first_at + interval '24 hours') at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai time.';
    v_id := public.fn_seat_duty_reason('ceo', 'ceo.sanctions_hit', v_q,
      jsonb_build_array(
        jsonb_build_object('id', 'confirmed', 'meaning', 'the party is the listed party: it is permanently banned and recorded, its quotes and contact are withdrawn and affected customers are told'),
        jsonb_build_object('id', 'false_positive', 'meaning', 'the party is not the listed party (a shared common name, a different entity type, a different company): the freeze lifts'),
        jsonb_build_object('id', 'cannot_tell', 'meaning', 'the facts cannot tell: the party stays frozen and the case is raised for review')),
      v_facts,
      jsonb_strip_nulls(jsonb_build_object('party', r.party, 'lead_id', r.lead_id, 'customer_id', r.customer_id, 'hit_ids', to_jsonb(r.ids))),
      v_key);
    if v_id is not null then v_filed := v_filed + 1; end if;
    if r.first_at < now() - interval '24 hours' then
      v_overdue := v_overdue + 1;
      perform public.fn_it_engineer_finding_upsert('sanctions_decision_overdue:' || r.party || ':' || coalesce(r.lead_id::text, r.customer_id::text),
        left('A sanctions hit on a ' || r.party || ' has waited ' || round(extract(epoch from now() - r.first_at) / 3600) || ' hours for the CEO''s decision (due in 24)', 300),
        'public.fn_ceo_sanctions_review_tick / ceo.sanctions_hit', 'agent_facing', 1,
        jsonb_build_object('party', r.party, 'lead_id', r.lead_id, 'customer_id', r.customer_id, 'hit_ids', to_jsonb(r.ids),
          'first_hit_at', r.first_at, 'held_question_id', v_id, 'owner_seat', 'ceo',
          'verdict_so_far', (select q.result->'decision'->>'choice' from public.reasoning_held_question q where q.id = v_id),
          'state', 'the party stays frozen (not matched, not revealed) until a decision; nothing is unfrozen by age'),
        '{}'::text[], array['why the reasoning has not decided (the model hold, a failed answer, or cannot_tell)'], 'ceo');
    end if;
  end loop;
  -- a decided party closes its overdue finding
  update public.it_engineer_finding f set closed_at = now(), close_note = 'every sanctions hit on the party is decided'
   where f.issue_key like 'sanctions_decision_overdue:%' and f.closed_at is null
     and not exists (select 1 from public.supplier_screening_hit h where split_part(f.issue_key, ':', 2) = 'supplier'
                       and h.lead_id::text = split_part(f.issue_key, ':', 3) and h.status = 'open')
     and not exists (select 1 from public.customer_screening_hit h where split_part(f.issue_key, ':', 2) = 'customer'
                       and h.customer_id::text = split_part(f.issue_key, ':', 3) and h.status = 'open');
  return jsonb_build_object('parties_filed', v_filed, 'overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_ceo_sanctions_review_tick() from public, anon, authenticated;

-- the model's answer, applied: each open hit on the party through its decider, as the CEO
create or replace function public.fn_reason_apply_ceo__sanctions_hit(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare q public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_actor text;
        v_ids bigint[]; v_one bigint; v_out jsonb := '[]'::jsonb; v jsonb;
begin
  select * into q from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('confirmed', 'false_positive', 'cannot_tell') then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  if v_choice = 'cannot_tell' then
    return jsonb_build_object('applied', true, 'verdict', v_choice, 'frozen', true,
      'next', 'fn_ceo_sanctions_review_tick raises the overdue finding at the decide-by time');
  end if;
  v_actor := 'ceo (reasoning held#' || p_id || coalesce(', ' || nullif(p_result->>'model', ''), '') || ')';
  select array_agg((x)::bigint) into v_ids from jsonb_array_elements_text(coalesce(q.subject->'hit_ids', '[]'::jsonb)) x;
  foreach v_one in array coalesce(v_ids, '{}'::bigint[]) loop
    if q.subject->>'party' = 'customer' then
      v := public.fn_customer_screening_decide(v_one, v_choice, v_actor);
    else
      v := public.fn_supplier_screening_decide(v_one, v_choice, v_actor);
    end if;
    v_out := v_out || jsonb_build_object('hit_id', v_one, 'result', v);
  end loop;
  return jsonb_build_object('applied', true, 'verdict', v_choice, 'hits', v_out, 'reasoning', left(p_result->>'answer', 2000));
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__sanctions_hit(bigint, jsonb) from public, anon, authenticated;

-- ── 6. a confirmed supplier ban tells the customers who hold that supplier's quote, honestly ───────────────────────
-- No reason is given (a sanctions decision is not explained to third parties); the facts given are true: the supplier
-- is no longer available on QuotesDone and its quotation is withdrawn. An unrevealed supplier is never named.
insert into public.notification_copy (type, subject_en, body_en, subject_ar, body_ar, note) values
  ('supplier_no_longer_available',
   'A supplier on your request is no longer available',
   'A supplier who sent you a quotation on QuotesDone is no longer available on QuotesDone, and its quotation has been withdrawn. Your other quotations are not affected.',
   'أحد الموردين في طلبك لم يعد متاحًا',
   'لم يعد أحد الموردين الذين أرسلوا إليكم عرض سعر عبر QuotesDone متاحًا على المنصة، وقد سُحب عرضه. عروضكم الأخرى لا تتأثر.',
   'fn_sanctions_ban_tells_affected_customers (16 Nov 2026): no reason is stated, by design')
on conflict (type) do update set subject_en = excluded.subject_en, body_en = excluded.body_en,
  subject_ar = excluded.subject_ar, body_ar = excluded.body_ar, note = excluded.note, updated_at = now();

create or replace function public.fn_sanctions_ban_tells_affected_customers()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_lang text; v_subject text; v_body text; v_n int := 0;
begin
  for r in
    select distinct on (c.id, i.id) c.id as customer_id, c.email, i.id as inquiry_id, i.rfq_no, i.lang, c.locale,
           exists (select 1 from public.transactions t where t.quote_id = q.id) as revealed
      from public.quotes q
      join public.inquiries i on i.id = q.inquiry_id
      join public.customers c on c.id = i.customer_id
     where q.supplier_id = new.lead_id
       and (exists (select 1 from public.transactions t where t.quote_id = q.id)
            or (coalesce(i.status, 'open') not in ('cancelled', 'closed', 'completed') and coalesce(q.status, '') not in ('draft', 'withdrawn')))
       and nullif(btrim(coalesce(c.email, '')), '') is not null
     order by c.id, i.id, revealed desc
  loop
    v_lang := coalesce(nullif(public.fn_inquiry_locale(r.inquiry_id), ''), nullif(r.locale, ''), 'en');
    if v_lang = 'ar' then
      v_subject := 'أحد الموردين في طلبك رقم ' || r.rfq_no || ' لم يعد متاحًا';
      v_body := 'لم يعد ' || case when r.revealed then 'المورّد الذي كشفتم عنه' else 'أحد الموردين الذين أرسلوا إليكم عرض سعر' end
        || ' في طلبكم رقم ' || r.rfq_no || ' متاحًا على QuotesDone، وقد سُحب عرضه. عروضكم الأخرى لا تتأثر.'
        || case when r.revealed then ' يُرجى عدم المضي في التعامل مع هذا المورّد عبر QuotesDone. وإن كنتم قد دفعتم رسوم الكشف عنه، ردّوا على هذه الرسالة وسنراجع الرسوم معكم.' else '' end;
    else
      v_subject := 'A supplier on your request RFQ #' || r.rfq_no || ' is no longer available';
      v_body := case when r.revealed then 'The supplier you revealed' else 'A supplier who sent you a quotation' end
        || ' on your request RFQ #' || r.rfq_no || ' is no longer available on QuotesDone, and its quotation has been withdrawn. Your other quotations are not affected.'
        || case when r.revealed then ' Please do not continue with this supplier through QuotesDone. If you paid to reveal it, reply to this message and we will review that fee with you.' else '' end;
    end if;
    insert into public.notifications (type, to_email, to_role, inquiry_id, subject, body, status, channel, sender, requested_by, lang, dedupe_key)
    values ('supplier_no_longer_available', r.email, 'customer', r.inquiry_id, v_subject, v_body, 'queued', 'email',
            'customer_support', 'ceo', v_lang, 'supplier_no_longer_available:' || new.lead_id || ':' || r.inquiry_id);
    v_n := v_n + 1;
  end loop;
  if v_n > 0 then
    perform public.fn_seat_handoff('ceo', 'customer_support', 'sanctions.customers_told', 'sanctions_ban', new.lead_id::text,
      jsonb_build_object('lead_id', new.lead_id, 'customers_told', v_n,
        'say', 'if a told customer replies about a reveal fee he paid for this supplier, the fee is reviewed with him; never state a reason for the withdrawal'));
  end if;
  return null;
exception when others then
  -- the ban itself must land whatever happens to the notice; the miss is recorded for the CEO
  perform public.fn_it_engineer_finding_upsert('sanctions_customers_not_told:' || new.lead_id,
    'A confirmed sanctions ban could not tell the customers holding the supplier''s quotes', 'public.fn_sanctions_ban_tells_affected_customers',
    'customer_facing', 1, jsonb_build_object('lead_id', new.lead_id, 'error', left(sqlerrm, 500), 'owner_seat', 'ceo'),
    '{}'::text[], array['which customers hold a live quote or reveal of this supplier'], 'ceo');
  return null;
end $fn$;
revoke execute on function public.fn_sanctions_ban_tells_affected_customers() from public, anon, authenticated;
drop trigger if exists z10_sanctions_ban_tells_affected_customers on public.sanctions_ban;
create trigger z10_sanctions_ban_tells_affected_customers after insert on public.sanctions_ban
  for each row execute function public.fn_sanctions_ban_tells_affected_customers();

-- ── 7. the two org_task kinds a hit opens are registered ────────────────────────────────────────────────────────────
insert into public.org_task_kind_handler (action_class, mail_kind, owner_seat, handler, rule, owner_file) values
  ('compliance_check', '*', 'ceo', 'condition',
   'a sanctions-screening decision: the CEO''s reasoning (ceo.sanctions_review, ceo.sanctions_hit) decides each hit with the screening facts within 24 hours, and fn_supplier_screening_decide closes this task with the decision',
   'scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql'),
  ('coordinate', '*', 'sales_engineer', 'condition',
   'the sales engineer''s hold on outreach while a sanctions hit is reviewed: it closes with the CEO''s decision on the same hit (fn_supplier_screening_decide)',
   'scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql')
on conflict (action_class, mail_kind) do update set owner_seat = excluded.owner_seat, handler = excluded.handler,
  rule = excluded.rule, owner_file = excluded.owner_file;


-- ── 8. every fraud flag goes to the accountant's reasoning, with full facts and a close-by date ─────────────────────
-- The facts a flag is judged on. Customer and supplier records are summarised, never copied: equality of the terms IP
-- and of the company domain is stated as a fact (true / false), not as the address. customer_matches_supplier adds what
-- the hole is about: the supplier's trades and what the customer did in them (requests, rival quotes he could read,
-- reveals). Every customer subject carries his request velocity (hole 10).
create or replace function public.fn_accountant_flag_customer_facts(p_customer uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('customer_id', c.id, 'account_created', c.created_at,
           'email_domain', split_part(lower(coalesce(c.email, '')), '@', 2), 'email_domain_class', public.fn_email_domain_class(c.email),
           'terms_accepted', c.tos_accepted_at is not null, 'terms_ip_on_record', nullif(btrim(coalesce(c.tos_ip, '')), '') is not null,
           'industry', c.industry, 'banned', coalesce(c.banned, false), 'disputes_filed', c.disputes_filed,
           'requests_total', (select count(*) from public.inquiries i where i.customer_id = c.id),
           'requests_last_hour', (select count(*) from public.inquiries i where i.customer_id = c.id and i.created_at > now() - interval '1 hour'),
           'requests_last_day', (select count(*) from public.inquiries i where i.customer_id = c.id and i.created_at > now() - interval '1 day'),
           'request_trades_90d', (select coalesce(jsonb_agg(distinct i.category), '[]'::jsonb) from public.inquiries i
                                   where i.customer_id = c.id and i.created_at > now() - interval '90 days' and i.category is not null),
           'quotes_received', (select count(*) from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                                where i.customer_id = c.id and coalesce(q.status, '') not in ('draft', 'withdrawn')),
           'reveals', (select count(*) from public.transactions t where t.customer_id = c.id),
           'refund_requests_90d', (select count(*) from public.transactions t where t.customer_id = c.id and t.refund_requested_at > now() - interval '90 days'))
    from public.customers c where c.id = p_customer
$fn$;
revoke execute on function public.fn_accountant_flag_customer_facts(uuid) from public, anon, authenticated;

create or replace function public.fn_accountant_flag_supplier_facts(p_lead bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'licence_legal_name', l.licence_legal_name,
           'approval_status', l.approval_status, 'verified', coalesce(l.verified, false), 'registered', l.lifecycle_stage = 'registered',
           'email_domain', split_part(lower(coalesce(nullif(btrim(l.claimed_by), ''), l.email, '')), '@', 2),
           'email_domain_class', public.fn_email_domain_class(coalesce(nullif(btrim(l.claimed_by), ''), l.email)),
           'website', l.domain, 'emirate', l.emirate,
           'trades', coalesce((select to_jsonb(sc.trades) from public.supplier_capabilities sc where sc.supplier_id = l.id), '[]'::jsonb),
           'sector', l.sector,
           'quotes_submitted', (select count(*) from public.quotes q where q.supplier_id = l.id))
    from public.leads l where l.id = p_lead
$fn$;
revoke execute on function public.fn_accountant_flag_supplier_facts(bigint) from public, anon, authenticated;

-- the trades a supplier works in, as codes (confirmed capability trades, else its sector resolved)
create or replace function public.fn_supplier_trade_codes(p_lead bigint)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select array(select distinct lower(t) from unnest(
           coalesce((select sc.trades from public.supplier_capabilities sc where sc.supplier_id = p_lead), '{}'::text[])
           || coalesce((select public.fn_norm_trades(l.sector) from public.leads l where l.id = p_lead), '{}'::text[])) t
         where nullif(btrim(t), '') is not null)
$fn$;
revoke execute on function public.fn_supplier_trade_codes(bigint) from public, anon, authenticated;

-- the trades a request is in, as codes
create or replace function public.fn_inquiry_trade_codes(p_category text, p_trades text[])
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select array(select distinct lower(t) from unnest(
           coalesce(public.fn_norm_trades(p_category), '{}'::text[]) || coalesce(p_trades, '{}'::text[])
           || array[nullif(btrim(coalesce(p_category, '')), '')]) t
         where nullif(btrim(t), '') is not null)
$fn$;
revoke execute on function public.fn_inquiry_trade_codes(text, text[]) from public, anon, authenticated;

create or replace function public.fn_accountant_flag_facts(p_kind text, p_subject_type text, p_subject_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.fraud_flags; v jsonb; v_cust uuid; v_leads bigint[]; v_sup jsonb := '[]'::jsonb; l record; v_trades text[];
        c public.customers;
begin
  select * into f from public.fraud_flags where kind = p_kind and subject_type = p_subject_type and subject_id = p_subject_id;
  if not found then return null; end if;
  v := jsonb_build_object('flag', jsonb_build_object('kind', f.kind, 'subject_type', f.subject_type, 'severity', f.severity,
         'status', f.status, 'raised_at', f.created_at, 'age_days', extract(day from now() - f.created_at)::int,
         'close_by', f.detail->>'close_by', 'detail', f.detail - 'review' - 'raised_by' - 'owner_seat'));
  if f.subject_type = 'customer' and f.subject_id ~ '^[0-9a-fA-F-]{36}$' then
    v_cust := f.subject_id::uuid;
  elsif jsonb_typeof(f.detail->'customer_ids') = 'array' then
    v := v || jsonb_build_object('customers', (select coalesce(jsonb_agg(public.fn_accountant_flag_customer_facts(x::uuid)), '[]'::jsonb)
                                                 from jsonb_array_elements_text(f.detail->'customer_ids') x where x ~ '^[0-9a-fA-F-]{36}$'));
  end if;
  if v_cust is not null then v := v || jsonb_build_object('customer', public.fn_accountant_flag_customer_facts(v_cust)); end if;
  if f.subject_type in ('lead', 'supplier') and f.subject_id ~ '^[0-9]+$' then
    v := v || jsonb_build_object('supplier', public.fn_accountant_flag_supplier_facts(f.subject_id::bigint));
  end if;
  if jsonb_typeof(f.detail->'lead_ids') = 'array' then
    select array_agg(x::bigint) into v_leads from jsonb_array_elements_text(f.detail->'lead_ids') x where x ~ '^[0-9]+$';
  end if;

  -- A SUPPLIER POSING AS A CUSTOMER: what he could have read, and what ties the two accounts.
  if f.kind = 'customer_matches_supplier' and v_cust is not null then
    select * into c from public.customers where id = v_cust;
    for l in select ld.* from public.leads ld where ld.id = any(coalesce(v_leads, '{}'::bigint[])) loop
      v_trades := public.fn_supplier_trade_codes(l.id);
      v_sup := v_sup || (public.fn_accountant_flag_supplier_facts(l.id) || jsonb_build_object(
        'same_terms_ip', nullif(btrim(coalesce(c.tos_ip, '')), '') is not null and btrim(c.tos_ip) = btrim(coalesce(l.accepted_terms_ip, '')),
        'same_ip_network_24', nullif(btrim(coalesce(c.tos_ip, '')), '') is not null and nullif(btrim(coalesce(l.accepted_terms_ip, '')), '') is not null
                              and substring(btrim(c.tos_ip) from '^(\d+\.\d+\.\d+)\.') = substring(btrim(l.accepted_terms_ip) from '^(\d+\.\d+\.\d+)\.'),
        'same_company_email_domain', public.fn_email_domain_class(c.email) = 'company' and split_part(lower(c.email), '@', 2) <> 'example.invalid'
                              and split_part(lower(c.email), '@', 2) in (split_part(lower(coalesce(l.email, '')), '@', 2), split_part(lower(coalesce(l.claimed_by, '')), '@', 2), lower(coalesce(l.email_domain, ''))),
        'customer_requests_in_these_trades', (select count(*) from public.inquiries i where i.customer_id = v_cust
                              and (cardinality(v_trades) = 0 or public.fn_inquiry_trade_codes(i.category, i.trades) && v_trades)),
        'rival_quotes_the_customer_could_read', (select count(*) from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                              where i.customer_id = v_cust and q.supplier_id <> l.id and coalesce(q.status, '') not in ('draft', 'withdrawn')
                                and (cardinality(v_trades) = 0 or public.fn_inquiry_trade_codes(i.category, i.trades) && v_trades)),
        'customer_reveals_in_these_trades', (select count(*) from public.transactions t join public.inquiries i on i.id = t.inquiry_id
                              where t.customer_id = v_cust and (cardinality(v_trades) = 0 or public.fn_inquiry_trade_codes(i.category, i.trades) && v_trades)),
        'customer_requests_answered_by_this_supplier', (select count(*) from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                              where i.customer_id = v_cust and q.supplier_id = l.id)));
    end loop;
    v := v || jsonb_build_object('suppliers_it_matches', v_sup,
      'while_open', 'the customer''s quotes in these suppliers'' trades are held as being checked, and a reveal is held by the money screen');
  elsif v_leads is not null then
    v := v || jsonb_build_object('suppliers', (select coalesce(jsonb_agg(public.fn_accountant_flag_supplier_facts(x)), '[]'::jsonb) from unnest(v_leads) x));
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_accountant_flag_facts(text, text, text) from public, anon, authenticated;

-- What each kind asks the model, in words. A kind not listed is asked the generic question (a new kind is still reasoned).
create or replace function public.fn_accountant_flag_question(p_kind text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case p_kind
    when 'customer_matches_supplier' then 'A customer account shares an identifier with a registered supplier (an equal phone, e-mail, terms IP or company domain). Is the supplier, or someone acting for him, posing as a customer to read rival suppliers'' prices?'
    when 'request_velocity' then 'One customer account posted many requests in a short time. Is this account abusing the platform (fishing for prices, flooding suppliers, testing), rather than a real buyer with many jobs?'
    when 'free_email_company' then 'A supplier''s company account signs in with free webmail. Is there a real reason to doubt that the account is the company it claims to be?'
    when 'disposable_email' then 'An account signs in with a disposable e-mail address. Is this account likely not a genuine party?'
    when 'refund_pattern' then 'A customer has asked for several refunds in 90 days. Is this a pattern of abuse of the refund guarantee rather than bad luck with suppliers?'
    when 'dispute_pattern' then 'A party has several disputes or refunds in the window. Is this party acting in bad faith?'
    when 'company_name_mismatch' then 'A supplier''s company name differs from the legal name on its trade licence. Is this account misrepresenting which company it is?'
    when 'email_domain_mismatch' then 'A supplier''s account e-mail domain differs from its website domain. Is this account likely not the company it claims?'
    when 'duplicate_license' then 'Two supplier records carry the same trade licence number. Is one of them an impostor or a duplicate account made to evade a rule?'
    when 'dup_trn' then 'Two supplier records carry the same tax registration number. Is one of them an impostor or a duplicate made to evade a rule?'
    when 'dup_customer_phone' then 'Several customer accounts share one phone number. Is one person running several accounts to evade a rule or to game the platform?'
    when 'dup_customer_email' then 'Several customer accounts share one e-mail address. Is one person running several accounts to evade a rule or to game the platform?'
    else 'The accountant''s screen raised a fraud flag of kind ' || coalesce(p_kind, '?') || '. On the facts, is the concern genuine?'
  end
$fn$;
revoke execute on function public.fn_accountant_flag_question(text) from public, anon, authenticated;

create or replace function public.fn_accountant_flag_review(p_kind text, p_subject_type text, p_subject_id text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.fraud_flags; v_close timestamptz; v_id bigint; v_facts jsonb; v_demo boolean; v_subj jsonb;
begin
  select * into f from public.fraud_flags where kind = p_kind and subject_type = p_subject_type and subject_id = p_subject_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such flag'); end if;
  -- the three circumvention kinds have their own surface, filed by fn_accountant_fraud_watch_tick
  if f.kind in ('hired_without_fee', 'refund_after_supplier_contact', 'silent_after_reveal') then
    return jsonb_build_object('ok', true, 'skipped', 'reasoned on accountant.circumvention');
  end if;
  if f.status not in ('open', 'escalated') then return jsonb_build_object('ok', true, 'skipped', 'flag is ' || f.status); end if;
  v_close := coalesce((f.detail->>'close_by')::timestamptz,
                      coalesce(f.created_at, now()) + case f.severity when 'high' then interval '2 days' when 'medium' then interval '5 days' else interval '10 days' end);
  v_facts := public.fn_accountant_flag_facts(f.kind, f.subject_type, f.subject_id) || jsonb_build_object('close_by', v_close);
  v_subj := jsonb_strip_nulls(jsonb_build_object('kind', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id,
              'customer_id', case when f.subject_type = 'customer' then f.subject_id end,
              'supplier_id', case when f.subject_type in ('lead', 'supplier') then f.subject_id end));
  v_demo := public.fn_reason_subject_is_fixture(v_subj);
  v_id := public.fn_seat_duty_reason('accountant', 'accountant.fraud_flag',
    case when v_demo then 'ZZ DEMO ' else '' end || public.fn_accountant_flag_question(f.kind)
      || ' Decide by ' || to_char(v_close at time zone 'Asia/Dubai', 'DD Mon YYYY') || '.',
    jsonb_build_array(
      jsonb_build_object('id', 'genuine', 'meaning', 'the concern is real on these facts; the flag is escalated and the CEO reviews it'),
      jsonb_build_object('id', 'benign', 'meaning', 'the facts have an ordinary explanation; the flag is dismissed and nothing it held stays held'),
      jsonb_build_object('id', 'insufficient_evidence', 'meaning', 'the facts cannot tell yet; the flag stays open and goes to the CEO at its close-by date')),
    v_facts, v_subj,
    'fraud_flag:' || f.kind || ':' || f.subject_type || ':' || f.subject_id || ':' || f.severity);
  update public.fraud_flags
     set detail = detail || jsonb_build_object('close_by', v_close,
                    'review', jsonb_build_object('filed_at', now(), 'surface', 'accountant.fraud_flag', 'held_question_id', v_id,
                                                 'fixture', v_demo, 'severity', f.severity)),
         updated_at = now()
   where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  return jsonb_build_object('ok', true, 'held_question_id', v_id, 'close_by', v_close, 'fixture', v_demo);
end $fn$;
revoke execute on function public.fn_accountant_flag_review(text, text, text) from public, anon, authenticated;

-- at insert, by any writer: the flag is filed for reasoning in the same transaction. It never blocks the flag.
create or replace function public.fn_fraud_flag_goes_to_the_accountants_reasoning()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_accountant_flag_review(new.kind, new.subject_type, new.subject_id);
  exception when others then
    perform public.fn_it_engineer_finding_upsert('fraud_flag_not_reasoned:' || new.kind,
      'A new fraud flag could not be filed for the accountant''s reasoning', 'public.fn_accountant_flag_review (z10 on fraud_flags)',
      'agent_facing', 1, jsonb_build_object('kind', new.kind, 'subject_type', new.subject_type, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
      '{}'::text[], array['the accountant.flag_review duty re-files it on its next hour'], 'accountant');
  end;
  return null;
end $fn$;
revoke execute on function public.fn_fraud_flag_goes_to_the_accountants_reasoning() from public, anon, authenticated;
drop trigger if exists z10_fraud_flag_goes_to_the_accountants_reasoning on public.fraud_flags;
create trigger z10_fraud_flag_goes_to_the_accountants_reasoning after insert on public.fraud_flags
  for each row execute function public.fn_fraud_flag_goes_to_the_accountants_reasoning();

-- the model's answer, applied to the flag
create or replace function public.fn_reason_apply_accountant__fraud_flag(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; f public.fraud_flags; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('genuine', 'benign', 'insufficient_evidence') then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into f from public.fraud_flags
   where kind = h.subject->>'kind' and subject_type = h.subject->>'subject_type' and subject_id = h.subject->>'subject_id' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the flag no longer exists'); end if;
  if f.status not in ('open', 'escalated') then return jsonb_build_object('applied', true, 'changed', false, 'reason', 'a person already closed the flag'); end if;
  update public.fraud_flags
     set detail = detail || jsonb_build_object('accountant_verdict', v_choice, 'verdict_model', p_result->>'model',
                                               'verdict_reasoning', left(p_result->>'answer', 4000), 'held_question_id', p_id, 'verdict_at', now()),
         status = case v_choice when 'benign' then 'dismissed' when 'genuine' then 'escalated' else f.status end,
         updated_at = now()
   where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  if v_choice = 'genuine' then
    v_rev := public.fn_seat_duty_cross_review('fraud_flag', 'accountant', 'ceo',
      case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end || 'Review a reasoned verdict that a fraud flag is genuine, and decide what the company does.',
      jsonb_build_object('signal', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id,
                         'facts', public.fn_accountant_flag_facts(f.kind, f.subject_type, f.subject_id)),
      jsonb_build_object('verdict', v_choice), p_result, 'fraud_flags', f.kind || ':' || f.subject_type || ':' || f.subject_id);
    update public.fraud_flags set detail = detail || jsonb_build_object('review_by_ceo', v_rev)
     where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  end if;
  return jsonb_build_object('applied', true, 'verdict', v_choice, 'status', case v_choice when 'benign' then 'dismissed' when 'genuine' then 'escalated' else f.status end,
                            'review', v_rev);
end $fn$;
revoke execute on function public.fn_reason_apply_accountant__fraud_flag(bigint, jsonb) from public, anon, authenticated;

-- ── 9. while a customer_matches_supplier flag is open, that customer's quotes in the supplier's trades are held ─────
-- Returns the customer's requests whose quotes are being checked. A supplier whose trades are unknown holds every
-- request of the customer: a guess at his trades would leak exactly what the hold exists to protect.
create or replace function public.fn_customer_quotes_being_checked(p_customer uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_trades text[] := '{}'; v_all boolean := false; v_flags int := 0; l bigint; t text[];
begin
  if p_customer is null then return jsonb_build_object('inquiry_ids', '[]'::jsonb, 'flags', 0); end if;
  for l in select x::bigint
             from public.fraud_flags f, jsonb_array_elements_text(coalesce(f.detail->'lead_ids', '[]'::jsonb)) x
            where f.kind = 'customer_matches_supplier' and f.subject_type = 'customer' and f.subject_id = p_customer::text
              and f.status in ('open', 'escalated') and x ~ '^[0-9]+$' loop
    v_flags := v_flags + 1;
    t := public.fn_supplier_trade_codes(l);
    if cardinality(t) = 0 then v_all := true; else v_trades := v_trades || t; end if;
  end loop;
  if v_flags = 0 then return jsonb_build_object('inquiry_ids', '[]'::jsonb, 'flags', 0); end if;
  return jsonb_build_object('flags', v_flags, 'all', v_all, 'trades', to_jsonb(v_trades),
    'inquiry_ids', (select coalesce(jsonb_agg(i.id), '[]'::jsonb) from public.inquiries i
                     where i.customer_id = p_customer and (v_all or public.fn_inquiry_trade_codes(i.category, i.trades) && v_trades)));
end $fn$;
revoke execute on function public.fn_customer_quotes_being_checked(uuid) from public, anon, authenticated;

-- ── 10. request velocity is a plausibility fact, and a burst is a flag the accountant reasons ───────────────────────
insert into public.decision_policy (key, value, description) values
  ('request_velocity_flag_per_hour', '5'::jsonb,
   'Requests one customer account may post in an hour before a request_velocity fraud flag is raised for the accountant''s reasoning (16 Nov 2026). A flag is a question, never a block.')
on conflict (key) do nothing;

-- BEFORE INSERT, named to fire after enrich_inquiry (which copies the intake's plausibility only when none is set).
create or replace function public.fn_inquiry_request_velocity_fact()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_h int; v_d int;
begin
  if new.customer_id is null then return new; end if;
  select count(*) filter (where i.created_at > now() - interval '1 hour'), count(*) into v_h, v_d
    from public.inquiries i where i.customer_id = new.customer_id and i.created_at > now() - interval '1 day';
  new.plausibility := coalesce(new.plausibility, '{}'::jsonb) || jsonb_build_object('velocity',
    jsonb_build_object('requests_last_hour', v_h + 1, 'requests_last_day', v_d + 1, 'at', now()));
  return new;
end $fn$;
revoke execute on function public.fn_inquiry_request_velocity_fact() from public, anon, authenticated;
drop trigger if exists enrich_inquiry_with_request_velocity on public.inquiries;
create trigger enrich_inquiry_with_request_velocity before insert on public.inquiries
  for each row execute function public.fn_inquiry_request_velocity_fact();

create or replace function public.fn_inquiry_request_velocity_flag()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_lim int := coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'request_velocity_flag_per_hour'), 5);
        v_h int := coalesce((new.plausibility->'velocity'->>'requests_last_hour')::int, 0); v_det jsonb; v_sev text;
begin
  if new.customer_id is null or v_h < v_lim then return null; end if;
  v_sev := case when v_h >= 3 * v_lim then 'high' else 'medium' end;
  v_det := jsonb_build_object('requests_last_hour', v_h, 'requests_last_day', new.plausibility->'velocity'->'requests_last_day',
             'limit_per_hour', v_lim, 'latest_inquiry_id', new.id,
             'inquiry_ids_last_hour', (select coalesce(jsonb_agg(i.id order by i.created_at), '[]'::jsonb) from public.inquiries i
                                        where i.customer_id = new.customer_id and i.created_at > now() - interval '1 hour'),
             'raised_by', 'accountant', 'owner_seat', 'accountant');
  insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
  values ('request_velocity', 'customer', new.customer_id::text, v_sev, v_det, 'open', now(), now())
  on conflict (kind, subject_type, subject_id) do update
     set detail = fraud_flags.detail || excluded.detail,
         severity = case when array_position(array['low', 'medium', 'high'], excluded.severity) > coalesce(array_position(array['low', 'medium', 'high'], fraud_flags.severity), 0)
                         then excluded.severity else fraud_flags.severity end,
         updated_at = now()
   where fraud_flags.status in ('open', 'escalated');
  return null;
exception when others then
  return null;   -- a request is never refused for want of its velocity flag
end $fn$;
revoke execute on function public.fn_inquiry_request_velocity_flag() from public, anon, authenticated;
drop trigger if exists z22_request_velocity_raises_a_flag on public.inquiries;
create trigger z22_request_velocity_raises_a_flag after insert on public.inquiries
  for each row execute function public.fn_inquiry_request_velocity_flag();

-- ── 11. a supplier gets at most one new-job notice per channel per hour ─────────────────────────────────────────────
-- The first job of an hour goes at once. A later one becomes the hour's batch row: it waits (not_before) until an hour
-- after the last notice. Every job after that, until the batch row is sent, is folded into it: e-mail bodies are joined
-- under one subject that counts them; on WhatsApp the later row is not sent (the e-mail digest and the portal carry it).
-- A folded row is kept with status 'merged' and names the row it went into.
create or replace function public.fn_new_job_notices_are_batched_per_hour()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.notifications; v_last timestamptz; v_n int;
begin
  if new.type is distinct from 'new_inquiry' or coalesce(new.to_role, '') <> 'supplier' or new.lead_id is null then return new; end if;
  if coalesce(new.status, 'queued') not in ('queued', 'pending') then return new; end if;
  perform pg_advisory_xact_lock(hashtext('new_job_batch:' || new.lead_id || ':' || coalesce(new.channel, 'email')));
  select * into b from public.notifications n
   where n.type = 'new_inquiry' and n.lead_id = new.lead_id and coalesce(n.channel, 'email') = coalesce(new.channel, 'email')
     -- 'suppressed' (a suppressed or demo address) counts too: such a row is never sent, so folding into it sends nothing either
     and n.status in ('queued', 'pending', 'suppressed') and n.dedupe_key = 'new_job_batch' and n.not_before > now()
   order by n.id desc limit 1 for update;
  if found then
    if coalesce(new.channel, 'email') = 'email' then
      select count(*) + 2 into v_n from public.notifications m where m.status = 'merged' and m.last_error like 'batched into notification #' || b.id || ' %';
      update public.notifications
         set subject = 'New job requests on QuotesDone (' || v_n || ')',
             body = coalesce(body, '') || E'\n\n— — —\n\n' || coalesce(new.body, ''),
             html = null
       where id = b.id;
    end if;
    new.status := 'merged';
    new.last_error := 'batched into notification #' || b.id || ' (one new-job notice per supplier per hour)';
    return new;
  end if;
  select max(n.created_at) into v_last from public.notifications n
   where n.type = 'new_inquiry' and n.lead_id = new.lead_id and coalesce(n.channel, 'email') = coalesce(new.channel, 'email')
     and n.status in ('queued', 'pending', 'sending', 'sent', 'suppressed') and n.created_at > now() - interval '1 hour';
  if v_last is not null then
    new.not_before := greatest(coalesce(new.not_before, now()), v_last + interval '1 hour');
    new.dedupe_key := 'new_job_batch';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_new_job_notices_are_batched_per_hour() from public, anon, authenticated;
drop trigger if exists a09_new_job_notices_are_batched_per_hour on public.notifications;
create trigger a09_new_job_notices_are_batched_per_hour before insert on public.notifications
  for each row execute function public.fn_new_job_notices_are_batched_per_hour();

-- ── 12. the accountant's hourly pass: the backlog, the wider supplier-as-customer test, the overdue flags ───────────
create or replace function public.fn_accountant_flag_review_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v_filed int := 0; v_raised int := 0; v_overdue int := 0; v jsonb;
begin
  -- 1. equal terms IP or equal company e-mail domain between a customer and a registered supplier: equality only
  for r in
    select c.id as customer_id, jsonb_agg(distinct l.id) as lead_ids, jsonb_agg(distinct m.what) as on_what
      from public.customers c
      join public.leads l on (coalesce(l.claimed, false) or l.lifecycle_stage = 'registered' or l.approval_status is not null)
                         and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
      cross join lateral (select 'terms_ip' as what
                           where nullif(btrim(coalesce(c.tos_ip, '')), '') is not null and btrim(c.tos_ip) = btrim(coalesce(l.accepted_terms_ip, ''))
                          union all
                          select 'company_email_domain'
                           where public.fn_email_domain_class(c.email) = 'company'
                             -- the reserved test domain every fixture shares says nothing about who anybody is
                             and split_part(lower(c.email), '@', 2) <> 'example.invalid'
                             and split_part(lower(c.email), '@', 2) in (split_part(lower(coalesce(l.email, '')), '@', 2), split_part(lower(coalesce(l.claimed_by, '')), '@', 2))) m
     where (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx and not coalesce(c.banned, false)
     group by c.id
  loop
    insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
    values ('customer_matches_supplier', 'customer', r.customer_id::text, 'high',
            jsonb_build_object('lead_ids', r.lead_ids, 'on', r.on_what, 'raised_by', 'accountant', 'owner_seat', 'accountant'), 'open', now(), now())
    on conflict (kind, subject_type, subject_id) do update
       set detail = fraud_flags.detail || jsonb_build_object(
             'lead_ids', (select jsonb_agg(distinct x) from jsonb_array_elements(coalesce(fraud_flags.detail->'lead_ids', '[]'::jsonb) || (excluded.detail->'lead_ids')) x),
             'on', (select jsonb_agg(distinct x) from jsonb_array_elements(coalesce(fraud_flags.detail->'on', '[]'::jsonb) || (excluded.detail->'on')) x)),
           updated_at = now()
     where fraud_flags.status in ('open', 'escalated')
       and not (coalesce(fraud_flags.detail->'on', '[]'::jsonb) @> (excluded.detail->'on') and coalesce(fraud_flags.detail->'lead_ids', '[]'::jsonb) @> (excluded.detail->'lead_ids'));
    if found then v_raised := v_raised + 1; end if;
  end loop;

  -- 2. the backlog and anything a writer slipped past the trigger: every open flag without a review is filed
  for r in
    select f.kind, f.subject_type, f.subject_id from public.fraud_flags f
     where f.status in ('open', 'escalated') and not (f.detail ? 'review')
       and f.kind not in ('hired_without_fee', 'refund_after_supplier_contact', 'silent_after_reveal')
     order by f.created_at limit 200
  loop
    v := public.fn_accountant_flag_review(r.kind, r.subject_type, r.subject_id);
    if (v->>'held_question_id') is not null then v_filed := v_filed + 1; end if;
  end loop;

  -- 3. a flag still open past its close-by date goes to the CEO, once, with its facts and what the reasoning said
  for r in
    select f.* from public.fraud_flags f
     where f.status = 'open' and (f.detail->>'close_by')::timestamptz < now() and not (f.detail ? 'overdue_reported_at')
       and f.kind not in ('hired_without_fee', 'refund_after_supplier_contact', 'silent_after_reveal')
     order by f.created_at limit 50
  loop
    v := public.fn_support_report_to_ceo(
      p_idempotency_key => 'fraud_flag_overdue:' || r.kind || ':' || r.subject_type || ':' || r.subject_id,
      p_severity => case when r.severity = 'high' then 'serious' else 'elevated' end,
      p_subject => left('A ' || r.severity || ' fraud flag (' || r.kind || ') is still open past its close-by date', 200),
      p_evidence => jsonb_build_object('flag', r.kind || ':' || r.subject_type || ':' || r.subject_id, 'close_by', r.detail->>'close_by',
                                       'accountant_verdict', r.detail->>'accountant_verdict', 'verdict_reasoning', left(r.detail->>'verdict_reasoning', 1500),
                                       'facts', public.fn_accountant_flag_facts(r.kind, r.subject_type, r.subject_id)),
      p_attempted => jsonb_build_array(jsonb_build_object('step', 'filed for the accountant''s reasoning (accountant.fraud_flag)',
                                                          'held_question_id', r.detail->'review'->'held_question_id')),
      p_requested => 'Decide the flag: dismiss it or act on it (fn_fraud_resolve). While it is open it holds what it holds (a reveal for a high flag; a customer''s quotes for customer_matches_supplier).',
      p_review_in => interval '1 day', p_source_agent => 'accountant');
    update public.fraud_flags set detail = detail || jsonb_build_object('overdue_reported_at', now(), 'overdue_report', v)
     where kind = r.kind and subject_type = r.subject_type and subject_id = r.subject_id;
    v_overdue := v_overdue + 1;
  end loop;
  return jsonb_build_object('customer_matches_supplier_raised', v_raised, 'filed', v_filed, 'overdue_reported', v_overdue);
end $fn$;
revoke execute on function public.fn_accountant_flag_review_tick() from public, anon, authenticated;

-- ── 13. the two duties ───────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.sanctions_review', 'ceo', interval '1 hour', 'fn_ceo_sanctions_review_tick',
   'every party with an open sanctions hit is filed for the CEO''s reasoning with the screening facts; past 24 hours it is a finding (the party stays frozen)',
   'scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql'),
  ('accountant.flag_review', 'accountant', interval '1 hour', 'fn_accountant_flag_review_tick',
   'every open fraud flag reasoned with full facts and a close-by date; equal terms IP or company domain raises customer_matches_supplier; an overdue flag goes to the CEO',
   'scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
