-- THE WEEKLY SANCTIONS SCREEN CHECKS EVERY MEMBER OF A COMPANY. Seats: customer_support + sales_engineer.
-- Agent: customer_support builder (supplier wave-2 review fixes), 16 Nov 2026. Review supplierw2, items 4 and its noted collision.
--
-- Measured before (SELECT and LOCAL, 16 Nov 2026): fn_supplier_sanctions_screen, the weekly screen and the accountant's daily
-- re-screen, read leads only. A colleague a company added (supplier_member, a_supplier_company_has_members_asks_on_any_channel_and_
-- can_leave.sql) was screened once, when added, and never again, so a name listed after he joined kept acting for the company.
-- And the hit's unique key (lead_id, entry_source, entry_reference, field) held ONE member hit per listing entry per company: a
-- second colleague whose name matched the same entry was not recorded and kept counting.
--
-- Now:
--   1. the key includes the member (supplier_screening_hit.member_id, added by the branch file; null for every non-member hit, and
--      NULLS NOT DISTINCT so those keep exactly the key they had); every existing row is unique under it, as it was under the old one;
--   2. the weekly screen adds each invited, active or screening member to the person rule (exact, or every word of the listing in his
--      name), records the hit naming him, and moves him to 'screening', so he stops acting for the company until a person decides
--      (fn_supplier_member_counts). The company is frozen by fn_screening_hit_freezes_the_supplier exactly as for an owner hit;
--   3. fn_accountant_ubo_rescreen names the widened key; nothing else in it changes.
--
-- Both routines are rebuilt from their PRODUCTION bodies (md5 of pg_get_functiondef, SELECT 16 Nov 2026):
--   fn_supplier_sanctions_screen ba4be23e45cf27efab5b28a10fdec3fd, fn_accountant_ubo_rescreen a47cfdef9dc61f96d6adf3cc057ae026.
-- Re-read both md5s before applying; if either moved, rebuild from the live body.
-- Apply AFTER a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql (supplier_member, member_id). The two are the only
-- writers that name the old key (SELECT 16 Nov: the routines whose body names supplier_screening_hit); fn_supplier_member_screen
-- names no conflict target. Probe: the_weekly_sanctions_screen_checks_every_member_of_a_company_probe.sql (LOCAL only).
set local lock_timeout = '3s';

-- 1. the key includes the member
create unique index if not exists supplier_screening_hit_one_per_entry_and_person_uq
  on public.supplier_screening_hit (lead_id, entry_source, entry_reference, field, member_id) nulls not distinct;
alter table public.supplier_screening_hit drop constraint if exists supplier_screening_hit_lead_id_entry_source_entry_reference_key;

-- 2. the weekly screen
CREATE OR REPLACE FUNCTION public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_hold bigint; v_title text; v_hold_title text; v_hits text; v_cust jsonb;
begin
  select string_agg(distinct source || ' (' || entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ')', '; ')
    into v_sources from public.screening_run where id = any(p_run_ids);

  create temp table tmp_screen_sup on commit drop as
    select l.id, f.field, f.val, null::bigint as member_id, public.fn_screening_normalise(f.val) as norm, public.fn_screening_tokens(f.val) as toks
      from public.leads l
      cross join lateral (values ('legal_name', l.company_name), ('licence_name', l.name_corrected_from),
                                 ('owner', l.signatory_name), ('contact', l.contact_name),
                                 ('email_domain', split_part(coalesce(l.email_domain, split_part(coalesce(l.email, ''), '@', 2)), '.', 1))) f(field, val)
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and case when v_reh then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end
       and nullif(btrim(coalesce(f.val, '')), '') is not null
    -- 16 Nov 2026 (review supplierw2): a company's MEMBERS are screened every week by the owner's rule, not only when added
    -- (fn_supplier_member_screen). A hit is field 'member', the value his name and member_id him, as fn_supplier_member_counts reads it.
    union all
    select m.lead_id, 'member', m.name, m.id, public.fn_screening_normalise(m.name), public.fn_screening_tokens(m.name)
      from public.supplier_member m join public.leads l on l.id = m.lead_id
     where m.status in ('invited', 'active', 'screening')
       and case when v_reh then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and m.email not ilike '%@example.invalid' end
       and nullif(btrim(coalesce(m.name, '')), '') is not null;
  select count(distinct id) into v_suppliers from tmp_screen_sup;
  select count(*) into v_entries from public.screening_entry where run_id = any(p_run_ids);

  for h in
    select s.id as lead_id, s.field, s.val, s.member_id, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from tmp_screen_sup s
      join public.screening_entry e
        on e.run_id = any(p_run_ids)
       and ((s.field <> 'email_domain' and s.norm = e.name_norm and length(s.norm) >= 6)
         -- a company name matches by shared tokens either way (a listed firm inside a longer trade name, or the reverse)
         or (s.field in ('legal_name', 'licence_name') and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2
             and (s.toks <@ e.tokens or e.tokens <@ s.toks))
         -- a PERSON (owner, contact) matches as a customer does: exact, or every word of the listing in his name. An open hit
         -- now freezes matching, and an owner's two common names inside a four-part listing is not a match (the customer
         -- measurement of 16 Nov: 61 of 64 hits on 22 common names were that direction; the same names, the same list, 3 hits
         -- left). SELECT 16 Nov: 2 live owner/contact values on registered suppliers, 0 hits under either rule (4,378 entries).
         or (s.field in ('owner', 'contact', 'member') and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2 and e.tokens <@ s.toks)
         or (s.field = 'email_domain' and length(s.norm) >= 6 and replace(e.name_norm, ' ', '') = s.norm))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, member_id, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, h.field, h.val, h.member_id, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field, member_id) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;
  -- a member with an open hit stops acting for the company until a person decides (fn_supplier_member_counts reads 'screening')
  update public.supplier_member m set status = 'screening', screened_at = now()
   where m.status = 'active'   -- review wave2joint: an invited one stays invited (else, once cleared, he acts without accepting)
     and exists (select 1 from public.supplier_screening_hit sh where sh.member_id = m.id and sh.status = 'open');

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
end $fn$;
revoke execute on function public.fn_supplier_sanctions_screen(bigint[], text) from public, anon, authenticated;
grant execute on function public.fn_supplier_sanctions_screen(bigint[], text) to service_role;

-- 3. the accountant's daily beneficial-owner re-screen, on the widened key
CREATE OR REPLACE FUNCTION public.fn_accountant_ubo_rescreen()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_owners int; v_new int := 0; v_missing int; v_stale int; v_screen jsonb; h record;
begin
  select array_agg(id order by id) into v_runs
    from (select distinct on (source) id from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;

  -- the suppliers in scope are exactly the ones fn_supplier_sanctions_screen screens (same demo split)
  create temp table if not exists tmp_ubo_scope (lead_id bigint primary key) on commit drop;
  truncate tmp_ubo_scope;
  insert into tmp_ubo_scope
  select l.id from public.leads l
   where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
     and l.is_demo = v_fx;   -- the shared marker (founder ruling 1199): fixtures only under qd.duty_fixtures, never otherwise

  select count(*) into v_owners from public.supplier_beneficial_owner o join tmp_ubo_scope s on s.lead_id = o.lead_id;

  for h in
    select o.lead_id, o.full_name, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when x.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when x.norm = e.name_norm then 1.0
                else round(least(cardinality(x.toks), cardinality(e.tokens))::numeric / greatest(cardinality(x.toks), cardinality(e.tokens), 1), 2) end as score
      from public.supplier_beneficial_owner o
      join tmp_ubo_scope s on s.lead_id = o.lead_id
      cross join lateral (select public.fn_screening_normalise(o.full_name) as norm, public.fn_screening_tokens(o.full_name) as toks) x
      join public.screening_entry e
        on e.run_id = any(v_runs)
       and ((x.norm = e.name_norm and length(x.norm) >= 6)
         or (cardinality(x.toks) >= 2 and cardinality(e.tokens) >= 2 and (x.toks <@ e.tokens or e.tokens <@ x.toks)))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, 'beneficial_owner', h.full_name, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field, member_id) do nothing;   -- the widened key (above); an owner is no member
    if found then v_new := v_new + 1; end if;
  end loop;

  -- the existing screen files the CEO decision and the sales_engineer hold for every open hit of these runs
  v_screen := public.fn_accountant_sanctions_rescreen();

  select count(*) filter (where not exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id)),
         count(*) filter (where exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id
                                          and coalesce(o.verified_at, o.declared_at) < now() - interval '365 days'))
    into v_missing, v_stale from tmp_ubo_scope s;

  return jsonb_build_object('owners_screened', v_owners, 'owner_hits_new', v_new,
    'suppliers_without_owner_on_record', v_missing, 'suppliers_with_owner_unverified_a_year', v_stale,
    'screen', v_screen - 'sources' - 'runs' - 'oldest_list');
end $fn$;
revoke execute on function public.fn_accountant_ubo_rescreen() from public, anon, authenticated;
grant execute on function public.fn_accountant_ubo_rescreen() to service_role;
