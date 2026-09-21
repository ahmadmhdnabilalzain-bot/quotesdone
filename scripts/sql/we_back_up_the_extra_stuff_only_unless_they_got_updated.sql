-- WE BACK UP THE EXTRA STUFF ONLY, UNLESS THEY GOT UPDATED.
--
-- Assigned: it_engineer. 18 Sep 2026. Founder instruction 519, his words:
--   "exactly we back up the extra stuff only since the existing is already there unless they got updated"
--
-- WHAT WAS ALREADY TRUE BEFORE THIS FILE (measured on production, 18 Sep 2026 08:10 UTC, read-only):
--   * public.table_export_run already carries kind full/incremental and a `since`. The four finished
--     days read: 2026-09-15 full, 2026-09-16 incremental, 2026-09-17 incremental, 2026-09-18 full.
--   * storage.objects in 'backups', per day: 2026-09-18 4,433 objects / 11,649 MB (Friday, FULL);
--     2026-09-17 257 objects / 271.9 MB; 2026-09-16 257 objects / 271.9 MB; 2026-09-15 2,840 objects /
--     11,576 MB (FULL). kb_chunks is 4,177 objects / 11,377 MB on a full day and 1 object / 0.0 MB on an
--     incremental one.
--   So the daily export is NOT a full copy every night. It is a full copy on Friday and an incremental
--     on the other six days, and on those six days the library already costs one empty page. The session
--     brief's "~12.2 GB every night" measured Friday 18 Sep, a full day, and read it as every day.
--     Re-measured before building, as the brief's counts are reliable and its causes are not.
--
-- WHAT WAS STILL WRONG, AND IS WHAT THIS FILE FIXES:
--   1. CHANGE DETECTION WAS BY NAME. fn_table_export_list() hard-coded `case when v.t = 'kb_chunks'`
--      as the only table with a change log. Every other table -- ops_knowledge at 145 MB today, and
--      anything that grows tomorrow -- was a full copy every night with nobody to notice. The founder
--      asked for the rule to apply by SIZE so it cannot go stale.
--   2. A DELETE WAS INVISIBLE. public.kb_chunks_export_change logged INSERT and UPDATE only. A row
--      deleted on an incremental day left no trace anywhere, so a restore from base + increments
--      rebuilt data the company had deleted -- including a PDPL erasure.
--   3. THE RESTORE WAS NEVER REBUILT. fn_it_restore_table_pick() deliberately SKIPPED every
--      'changes_since' page ("holds only that day's changes and restores nothing on its own") and only
--      ever restored a full page. The chain was checked for gaps; it was never once replayed. A backup
--      nobody can restore is worse than none.
--
-- MEASURED SIZES THAT SET THE THRESHOLD (pg_total_relation_size, 18 Sep 2026):
--   kb_chunks 9,164 MB (2,686,026 est. rows) | ops_knowledge 145 MB | leads 35 MB |
--   supplier_capabilities 23 MB | agent_knowledge 15 MB | inquiry_workstream_requirement 15 MB |
--   sales_knowledge 14 MB | everything else under 8 MB.
--   THRESHOLD: 64 MB. It sits in the empty band between ops_knowledge (145 MB) and leads (35 MB), so
--   today it selects exactly the two knowledge tables that dominate the bucket and nothing else, and it
--   is low enough that any table crossing it is picked up on the next day's export without a code
--   change. A 64 MB table full-copied daily costs ~23 pages -- below the 250-object daily floor the
--   other 105 tables already cost, so there is nothing to gain by going lower.
--
-- CADENCE (unchanged, and this file states why it is kept rather than re-chosen):
--   FULL on Friday, INCREMENTAL on the other six days, plus a forced FULL whenever no full copy
--   succeeded in the previous 7 days. Friday is already the convention the retention rule is built on
--   (the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql keeps Friday full copies 12 months
--   and everything else 90 days), so moving the baseline would orphan the 12-month copies. A 7-day
--   maximum also bounds a restore: at most one base page plus six increment pages per table.
--   ONE ADDITION: a table that has only just become change-tracked has no base, so the next day is
--   forced FULL. Without that the first incremental after a table crosses the threshold would carry
--   only that day's changes with nothing underneath them.
--
-- WHAT IS NOT DONE INCREMENTALLY, AND SAYS SO:
--   A table under the threshold, or one whose primary key is not a single column, stays a FULL copy
--   every day and public.table_export_change_tracked simply does not name it. Nothing is ever skipped
--   because we could not prove it was unchanged; the fallback is always the whole table.
--   xmin is NOT used anywhere here. It is not stable across VACUUM FREEZE, so a frozen row would read
--   as unchanged forever and be silently missed.
--
-- COST OF THE TRIGGERS ON A 2.6 M-ROW TABLE:
--   The triggers are STATEMENT-level with transition tables, so a statement touching N rows costs one
--   INSERT ... SELECT over a tuplestore, not N trigger firings. The update trigger joins old_rows to
--   new_rows on the primary key and writes only rows whose EXPORTED projection changed (vector columns
--   are excluded, because the export strips them and a re-embedding is not a change to the backup).
--   There is NO backfill and none is needed: the log starts empty and the forced FULL copy is the base
--   every later increment sits on. Backfilling would be the unsafe option -- it would mark 2.6 M rows
--   changed and make the next incremental a full copy in all but name.
--
--   node scripts/apply_sql.mjs scripts/sql/we_back_up_the_extra_stuff_only_unless_they_got_updated.sql --apply --ddl

-- ── 1. THE ONE CHANGE LOG, FOR EVERY TRACKED TABLE, INCLUDING DELETES ──────────────────────────────
-- Replaces public.kb_chunks_export_change (one table, one hard-coded name, no deletes). Exported as a
-- table in its own right (see fn_table_export_list below), so the record of what was deleted travels
-- with the increments into the bucket and on to Dropbox, and a restore can read it.
create table if not exists public.table_export_change (
  id         bigserial primary key,
  table_name text not null,
  row_key    text not null,
  deleted    boolean not null default false,
  -- clock_timestamp(), NOT now(). Review finding, 18 Sep 2026: now() is the TRANSACTION start time, so
  -- a statement inside a long transaction is stamped with a time that can fall before the watermark the
  -- next incremental reads, and the row is silently left out -- the exact case the 6-hour margin on
  -- `since` exists to cover. clock_timestamp() stamps the statement, which is as close to commit as a
  -- trigger can get. THE RESIDUAL BOUND, said out loud: a transaction whose write is more than 6 hours
  -- before its commit is still outside the margin. Nothing here claims otherwise.
  changed_at timestamptz not null default clock_timestamp()
);
create index if not exists table_export_change_table_changed_idx
  on public.table_export_change (table_name, changed_at, row_key);
comment on table public.table_export_change is
  'Primary keys of rows inserted, updated or DELETED in a change-tracked table, read by the daily incremental export and pruned after each full copy. Exported daily so the deletions reach the backup. we_back_up_the_extra_stuff_only_unless_they_got_updated.sql';
alter table public.table_export_change enable row level security;
drop policy if exists table_export_change_service_role_only on public.table_export_change;
create policy table_export_change_service_role_only on public.table_export_change
  as permissive for all to public using (false) with check (false);
revoke all on public.table_export_change from anon, authenticated;

-- Which tables are tracked, and since when. A row here is the ONLY thing that makes an incremental day
-- read a change log for that table; the registrar below writes it, nothing else does.
create table if not exists public.table_export_change_tracked (
  table_name            text primary key check (table_name ~ '^[a-z_][a-z0-9_]*$'),
  pk_column             text not null check (pk_column ~ '^[a-z_][a-z0-9_]*$'),
  projection            text not null default '',   -- the columns the export carries, as the triggers compare them
  tracking_since        timestamptz not null default clock_timestamp(),
  bytes_at_registration bigint
);
comment on table public.table_export_change_tracked is
  'The tables whose daily export is incremental because they are at or over it_threshold export_incremental_min_bytes. Written only by fn_table_export_change_tracking(). A table not named here is a full copy every day. we_back_up_the_extra_stuff_only_unless_they_got_updated.sql';
alter table public.table_export_change_tracked enable row level security;
drop policy if exists table_export_change_tracked_service_role_only on public.table_export_change_tracked;
create policy table_export_change_tracked_service_role_only on public.table_export_change_tracked
  as permissive for all to public using (false) with check (false);
revoke all on public.table_export_change_tracked from anon, authenticated;

insert into public.it_threshold (key, value, unit, basis) values
  ('export_incremental_min_bytes', 67108864, 'bytes',
   '64 MB. Measured 18 Sep 2026: kb_chunks 9,164 MB and ops_knowledge 145 MB are over it, leads 35 MB is the next largest and is under it. A table at this size costs ~23 pages a day as a full copy, below the 250-object floor the other tables already cost, so there is nothing to gain by going lower.')
on conflict (key) do update set value = excluded.value, unit = excluded.unit, basis = excluded.basis;

-- ── 2. THE GENERIC TRIGGER ─────────────────────────────────────────────────────────────────────────
-- TG_ARGV[0] is the single primary-key column; TG_ARGV[1] is the EXPORTED PROJECTION: a comma-separated
-- list of the columns the export carries, already quoted by the registrar. Statement-level with
-- transition tables: one INSERT ... SELECT per statement, whatever the row count. The transition tables
-- are visible to dynamic SQL inside the trigger, which is what lets one function serve every table.
--
-- WHY THE PROJECTION IS A COLUMN LIST AND NOT `to_jsonb(row) - vector_columns`. Review finding, 18 Sep
-- 2026: to_jsonb() serialises the WHOLE row, 768-dimension embedding included, before the minus removes
-- it -- so the comparison that exists to make a re-embedding free would have paid for serialising every
-- embedding on every backfill statement, on 2.69 M rows. A row comparison over the kept columns never
-- touches the vector at all.
--
-- TRUNCATE is here too. Review finding, 18 Sep 2026: a statement-level INSERT/UPDATE/DELETE trigger does
-- NOT fire for TRUNCATE, and neither kb_chunks nor ops_knowledge carries a truncate guard (measured:
-- kb_chunks has only the two export-change triggers, ops_knowledge only a10_ops_knowledge_embedding_status).
-- A truncate cannot be expressed row by row in a change log, so it does the only honest thing: it moves
-- tracking_since forward, which makes fn_table_export_due force the next day to be a FULL copy, and it
-- leaves a marker row so the reason is in the record.
create or replace function public.trg_table_export_change()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_pk text := tg_argv[0];
  v_proj text := coalesce(tg_argv[1], '');
begin
  if tg_op = 'TRUNCATE' then
    update public.table_export_change_tracked x set tracking_since = clock_timestamp() where x.table_name = tg_table_name;
    insert into public.table_export_change (table_name, row_key, deleted)
    values (tg_table_name, '(truncate: no row-level record is possible; the next export day is a full copy)', true);
    return null;
  end if;
  if tg_op = 'INSERT' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  elsif tg_op = 'DELETE' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, o.%I::text, true from old_rows o',
      tg_table_name, v_pk);
  elsif v_proj = '' then
    -- no projection recorded: log every touched row rather than guess that nothing changed
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  else
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted)
         select %1$L, n.%2$I::text, false from new_rows n join old_rows o on o.%2$I = n.%2$I
          where (%3$s) is distinct from (%4$s)',
      tg_table_name, v_pk,
      'n.' || replace(v_proj, ',', ', n.'), 'o.' || replace(v_proj, ',', ', o.'));
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_table_export_change() from public, anon, authenticated;

-- ── 3. THE REGISTRAR: BY SIZE, NOT BY NAME ─────────────────────────────────────────────────────────
-- Attaches the three triggers to every exported table at or over the threshold that has a single-column
-- primary key, and detaches them from every table that has fallen below it. Called once a day by
-- fn_table_export_due when it opens the day's row, so there is no second clock; it is a no-op (no DDL,
-- no lock) when the registry already agrees with the sizes AND with each table's column list, which is
-- every day but the day a table crosses the line or gains a column. p_apply=false reports what it WOULD
-- do and changes nothing. THE LOCK IS TAKEN HERE, AND SAID SO: CREATE TRIGGER needs SHARE ROW EXCLUSIVE
-- on the table, so on the one day a 9 GB table is registered this waits behind writers to it. It runs
-- at 03:00 Dubai in the same transaction that claims the day, which is when that table is quietest.
create or replace function public.fn_table_export_change_tracking(p_apply boolean default true)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_min bigint := coalesce(public.fn_it_threshold('export_incremental_min_bytes'), 67108864)::bigint;
  v_added text[] := '{}'; v_removed text[] := '{}'; v_refreshed text[] := '{}'; v_reasons jsonb := '{}'::jsonb;
  r record; v_pk text; v_npk integer; v_bytes bigint; v_proj text; v_have text; v_want boolean;
begin
  for r in select x.table_name as t from public.fn_table_export_list() x
            where x.table_name <> 'table_export_change'
  loop
    if to_regclass(format('public.%I', r.t)) is null then continue; end if;
    v_bytes := pg_total_relation_size(format('public.%I', r.t)::regclass);
    select count(*), min(a.attname::text) into v_npk, v_pk
      from pg_index i
      cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
     where i.indrelid = format('public.%I', r.t)::regclass and i.indisprimary;

    if v_bytes >= v_min and coalesce(v_npk, 0) <> 1 then
      -- Named out loud rather than silently left full: this table is big and CANNOT report changes.
      v_reasons := v_reasons || jsonb_build_object(r.t,
        format('%s bytes, at or over the threshold, but its primary key has %s columns, so it stays a full copy every day',
               v_bytes, coalesce(v_npk, 0)));
    end if;

    -- The exported projection, as the update trigger compares it. A column added to a tracked table
    -- later changes this string, and the branch below rebuilds the triggers with the new list -- a
    -- stale list would make a change to the new column invisible.
    select coalesce(string_agg(quote_ident(a.attname), ',' order by a.attnum), '') into v_proj
      from pg_attribute a
     where a.attrelid = format('public.%I', r.t)::regclass and a.attnum > 0 and not a.attisdropped
       and format_type(a.atttypid, a.atttypmod) not like 'vector%';
    select x.projection into v_have from public.table_export_change_tracked x where x.table_name = r.t;
    v_want := v_bytes >= v_min and coalesce(v_npk, 0) = 1;

    if v_want and (v_have is null or v_have is distinct from v_proj) then
      if p_apply then
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_ins', r.t);
        execute format('create trigger %I after insert on public.%I referencing new table as new_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_ins', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_upd', r.t);
        execute format('create trigger %I after update on public.%I referencing old table as old_rows new table as new_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_upd', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_del', r.t);
        execute format('create trigger %I after delete on public.%I referencing old table as old_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_del', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_trunc', r.t);
        execute format('create trigger %I after truncate on public.%I
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_trunc', r.t, v_pk, v_proj);
        insert into public.table_export_change_tracked (table_name, pk_column, projection, bytes_at_registration)
        values (r.t, v_pk, v_proj, v_bytes)
        on conflict (table_name) do update set pk_column = excluded.pk_column, projection = excluded.projection,
                                               bytes_at_registration = excluded.bytes_at_registration;
      end if;
      if v_have is null then v_added := v_added || r.t; else v_refreshed := v_refreshed || r.t; end if;
    elsif not v_want and v_have is not null then
      if p_apply then
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_ins', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_upd', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_del', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_trunc', r.t);
        delete from public.table_export_change_tracked x where x.table_name = r.t;
        delete from public.table_export_change c where c.table_name = r.t;
      end if;
      v_removed := v_removed || r.t;
    end if;
  end loop;
  return jsonb_build_object('threshold_bytes', v_min, 'added', to_jsonb(v_added), 'removed', to_jsonb(v_removed),
                            'triggers_refreshed', to_jsonb(v_refreshed),
                            'stays_full_and_why', v_reasons, 'applied', p_apply,
                            'tracked', (select coalesce(jsonb_object_agg(x.table_name, x.pk_column), '{}'::jsonb)
                                          from public.table_export_change_tracked x));
end $fn$;
revoke execute on function public.fn_table_export_change_tracking(boolean) from public, anon, authenticated;

-- ── 4. THE LIST, DRIVEN BY THE REGISTRY ────────────────────────────────────────────────────────────
-- Was: `case when v.t = 'kb_chunks' then 'kb_chunks_export_change' end`. Now every tracked table names
-- the one log, and table_export_change is itself exported (subject 'backup') so the day's deletions
-- reach the bucket and Dropbox with the increments. STABLE, not IMMUTABLE: it reads the registry.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

-- ── 5. ONE DEFINITION OF "THE ROWS THIS EXPORT CARRIES" ────────────────────────────────────────────
-- The demo filter used to live inline in fn_table_export_page. The restore rebuild has to apply the SAME
-- rule to the live side, or every demo row would read as a row the rebuild lost, so it is one function
-- now and both callers use it.
--
-- THE DEMO IDS ARE BOUND, NOT INLINED. Review finding, 18 Sep 2026: a first version inlined them as text
-- literals so the predicate could be handed to callers with different parameter lists, which re-parses
-- those arrays on all ~4,200 pages of a full night and has no ceiling if the fixture pool grows. So the
-- predicate always refers to $1..$4 = demo customers, demo suppliers, demo inquiries, demo quotes, and
-- EVERY caller binds those four first and numbers its own parameters from $5. (Measured 18 Sep 2026: 2
-- demo customers, 1 demo supplier, at most 3 inquiries and 2 quotes -- small today, unbounded in
-- principle, and this is the shape that stays cheap either way.)
create or replace function public.fn_table_export_demo_ids()
returns table(dc text[], dl text[], di text[], dq text[])
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  select coalesce(array_agg(c.id::text), '{}') into dc from public.customers c
   where coalesce(c.is_demo, false) or coalesce(c.email, '') ~* 'example\.invalid' or coalesce(c.full_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(l.id::text), '{}') into dl from public.leads l
   where coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid' or coalesce(l.company_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(i.id::text), '{}') into di from public.inquiries i where i.customer_id::text = any(dc);
  select coalesce(array_agg(q.id::text), '{}') into dq from public.quotes q
   where q.supplier_id::text = any(dl) or q.inquiry_id::text = any(di);
  return next;
end $fn$;
revoke execute on function public.fn_table_export_demo_ids() from public, anon, authenticated;

create or replace function public.fn_table_export_filter(p_table text)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_rel regclass := to_regclass(format('public.%I', p_table));
  v_where text;
begin
  if v_rel is null then raise exception 'fn_table_export_filter: public.% does not exist', p_table; end if;
  select format('(to_jsonb(t) - %L::text[])::text !~* %L', public.fn_table_export_stripped(p_table), 'zz[_ -]?demo|example\.invalid')
         || coalesce(string_agg(case a.attname
              when 'is_demo'     then ' and not coalesce(t.is_demo, false)'
              when 'customer_id' then ' and not coalesce(t.customer_id::text = any($1), false)'
              when 'supplier_id' then ' and not coalesce(t.supplier_id::text = any($2), false)'
              when 'lead_id'     then ' and not coalesce(t.lead_id::text = any($2), false)'
              when 'inquiry_id'  then ' and not coalesce(t.inquiry_id::text = any($3), false)'
              when 'quote_id'    then ' and not coalesce(t.quote_id::text = any($4), false)' end, ''), '')
    into v_where
    from pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped
     and a.attname in ('is_demo', 'customer_id', 'supplier_id', 'lead_id', 'inquiry_id', 'quote_id');
  return v_where;
end $fn$;
revoke execute on function public.fn_table_export_filter(text) from public, anon, authenticated;

-- The columns the export strips (vector columns). Its own function because the trigger, the page and
-- the rebuild all have to agree on what "the exported projection" means.
create or replace function public.fn_table_export_stripped(p_table text)
returns text[]
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(array_agg(a.attname::text), '{}')
    from pg_attribute a
   where a.attrelid = to_regclass(format('public.%I', p_table)) and a.attnum > 0 and not a.attisdropped
     and format_type(a.atttypid, a.atttypmod) like 'vector%';
$fn$;
revoke execute on function public.fn_table_export_stripped(text) from public, anon, authenticated;

-- ── 6. ONE PAGE OF ONE TABLE, v3 ───────────────────────────────────────────────────────────────────
-- Same keyset paging and the same demo rule (now through fn_table_export_filter). The change-log
-- predicate is no longer `t.id in (select cl.id from kb_chunks_export_change)`: it is the tracked
-- table's own primary key against the one log, and it excludes rows whose only log entry is a DELETE
-- (a deleted row is not in the live table anyway; the exclusion means a row deleted and re-inserted
-- under the same key is still carried).
create or replace function public.fn_table_export_page(p_table text, p_after jsonb default null, p_limit integer default 1000,
                                                       p_since timestamptz default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_rel regclass; v_cols text; v_keyvals text; v_after text := 'true'; v_where text; v_log text; v_pk text; v_pktype text;
  v_strip text[]; v_lim integer := greatest(1, least(coalesce(p_limit, 1000), 1000));
  v_rows jsonb; v_n integer; v_last jsonb;
  v_dc text[]; v_dl text[]; v_di text[]; v_dq text[];   -- $1..$4, the positions fn_table_export_filter names
begin
  select x.change_log into v_log from public.fn_table_export_list() x where x.table_name = p_table;
  if not found then raise exception 'fn_table_export_page: % is not in fn_table_export_list()', p_table; end if;
  v_rel := to_regclass(format('public.%I', p_table));
  if v_rel is null then raise exception 'fn_table_export_page: public.% does not exist', p_table; end if;

  select string_agg(format('t.%I', a.attname), ', ' order by k.ord),
         string_agg(format('(($5->>%s)::%s)', k.ord - 1, format_type(a.atttypid, a.atttypmod)), ', ' order by k.ord),
         min(a.attname::text), min(format_type(a.atttypid, a.atttypmod))
    into v_cols, v_keyvals, v_pk, v_pktype
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = v_rel and i.indisprimary;
  if v_cols is null then raise exception 'fn_table_export_page: public.% has no primary key to page on', p_table; end if;
  if p_after is not null then v_after := format('(%s) > (%s)', v_cols, v_keyvals); end if;

  v_strip := public.fn_table_export_stripped(p_table);
  v_where := public.fn_table_export_filter(p_table);
  select d.dc, d.dl, d.di, d.dq into v_dc, v_dl, v_di, v_dq from public.fn_table_export_demo_ids() d;
  if p_since is not null and v_log is not null then
    -- THE CAST GOES ON THE LOG, NEVER ON THE TABLE. Measured 18 Sep 2026: with `t.id::text in (...)`
    -- this statement outlived the management API gateway (524) on kb_chunks -- casting the primary key
    -- makes the index on it unusable and turns an incremental page into a sequential scan of 2.69 M
    -- rows over 9 GB, every page, every night. row_key was written from this very column, so casting it
    -- back is exact.
    v_where := v_where || format(
      ' and t.%I in (select cl.row_key::%s from public.table_export_change cl
                      where cl.table_name = %L and cl.changed_at >= $7 and not cl.deleted)',
      v_pk, v_pktype, p_table);
  end if;

  execute format(
    'select coalesce(jsonb_agg(y.j order by y.ord), ''[]''::jsonb), count(*)::int, (array_agg(y.k order by y.ord desc))[1]
       from (select row_number() over () as ord, x.k, x.j
               from (select jsonb_build_array(%1$s) as k, to_jsonb(t) - $6 as j
                       from public.%2$I t where %3$s and %4$s order by %1$s limit %5$s) x) y',
    v_cols, p_table, v_after, v_where, v_lim)
    into v_rows, v_n, v_last
    using v_dc, v_dl, v_di, v_dq, p_after, v_strip, p_since;

  return jsonb_build_object('table', p_table, 'rows', v_rows, 'n', v_n, 'last', v_last, 'done', v_n < v_lim,
                            'mode', case when p_since is not null and v_log is not null then 'changes_since' else 'full' end);
end $fn$;
revoke execute on function public.fn_table_export_page(text, jsonb, integer, timestamptz) from public, anon, authenticated;

-- ── 7. THE CLOCK, v3: RUN THE REGISTRAR, AND A NEW TABLE GETS A BASE ───────────────────────────────
-- Unchanged from a_failed_export_day_resumes_from_its_failed_page.sql except for two things: the day
-- that opens the row runs the size registrar first (no second clock, and it is a no-op unless a table
-- crossed the threshold), and a table registered since the last successful FULL copy forces this day
-- to be FULL -- otherwise its first increment would have nothing underneath it.
create or replace function public.fn_table_export_due()
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_stamp date := (now() at time zone 'Asia/Dubai')::date;
  v_run public.table_export_run;
  v_kind text; v_since timestamptz; v_full_at timestamptz;
  v_resume jsonb;
begin
  if v_local::time < time '03:00' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'before 03:00 Asia/Dubai');
  end if;
  select * into v_run from public.table_export_run r where r.stamp = v_stamp for update;
  if not found then
    perform public.fn_table_export_change_tracking(true);
    select r.started_at - interval '6 hours' into v_since
      from public.table_export_run r where r.status = 'done' and r.stamp < v_stamp order by r.stamp desc limit 1;
    select max(r.started_at) into v_full_at
      from public.table_export_run r where r.status = 'done' and r.kind = 'full' and r.stamp < v_stamp;
    v_kind := case when extract(isodow from v_local) = 5 or v_since is null
                     or not exists (select 1 from public.table_export_run r
                                     where r.status = 'done' and r.kind = 'full' and r.stamp >= v_stamp - 7 and r.stamp < v_stamp)
                     -- a table that became change-tracked after the last full copy has no base yet
                     or exists (select 1 from public.table_export_change_tracked x
                                 where v_full_at is null or x.tracking_since > v_full_at)
                   then 'full' else 'incremental' end;
    if v_kind = 'full' then v_since := null; end if;
    insert into public.table_export_run (stamp, kind, since) values (v_stamp, v_kind, v_since) on conflict (stamp) do nothing;
    if not found then return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'claimed concurrently'); end if;
    return jsonb_build_object('due', true, 'stamp', v_stamp, 'attempt', 1, 'resume', null, 'kind', v_kind, 'since', v_since);
  end if;
  if v_run.status = 'done' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', 'done', 'kind', v_run.kind);
  end if;
  if v_run.heartbeat_at > now() - interval '10 minutes' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'reason', 'in progress or waiting to retry');
  end if;
  if v_run.attempts >= 6 then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'attempts', v_run.attempts, 'reason', 'gave up after 6 attempts');
  end if;
  v_resume := case
    when v_run.status = 'running' then v_run.state
    when v_run.status = 'failed' and jsonb_typeof(v_run.state->'queue') = 'array'
         and jsonb_array_length(v_run.state->'queue') > 0
         and (v_run.state->'errors') ? (v_run.state->'queue'->0->>'t') then v_run.state
  end;
  update public.table_export_run r
     set attempts = r.attempts + case when r.status = 'failed' then 1 else 0 end,
         status = 'running', heartbeat_at = now(),
         state = v_resume
   where r.stamp = v_stamp;
  return jsonb_build_object('due', true, 'stamp', v_stamp,
    'attempt', v_run.attempts + case when v_run.status = 'failed' then 1 else 0 end,
    'resume', v_resume,
    'kind', v_run.kind, 'since', v_run.since);
end $fn$;
revoke execute on function public.fn_table_export_due() from public, anon, authenticated;

-- ── 8. THE DAY IS DONE, v2: PRUNE THE ONE LOG ──────────────────────────────────────────────────────
-- Identical to every_business_table_is_exported_every_day_again.sql's version except that the prune
-- reads the one log instead of kb_chunks_export_change. A DELETE row is pruned on the same rule as an
-- INSERT row: once a full copy has been taken, the deleted row is absent from it, so the record of the
-- deletion has done its work.
create or replace function public.fn_table_export_finish(p_stamp date, p_manifest jsonb, p_error text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day text := to_char(p_stamp, 'YYYY-MM-DD');
  v_bad text; v_queued integer; v_pruned integer := 0; v_run public.table_export_run;
begin
  select * into v_run from public.table_export_run r where r.stamp = p_stamp;
  if not found then return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', 'no table_export_run row for this day'); end if;
  if p_error is null then
    select string_agg(x.table_name, ', ') into v_bad
      from public.fn_table_export_list() x
     where coalesce((p_manifest->'tables'->x.table_name->>'pages')::int, -1)
           <> (select count(*) from storage.objects o
                where o.bucket_id = 'backups' and o.name like v_day || '/' || x.table_name || '/page\_%.json');
    if v_bad is not null then p_error := 'pages in storage disagree with the manifest for: ' || v_bad; end if;
    if p_error is null and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = v_day || '/_manifest.json') then
      p_error := 'the manifest is not in storage';
    end if;
  end if;

  if p_error is not null then
    update public.table_export_run r set status = 'failed', error = left(p_error, 2000), heartbeat_at = now()
     where r.stamp = p_stamp;
    return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', left(p_error, 500));
  end if;

  update public.table_export_run r set status = 'done', finished_at = now(), heartbeat_at = now(), manifest = p_manifest, error = null
   where r.stamp = p_stamp;
  -- a full copy holds every row, so changes logged well before it started are no longer needed
  if v_run.kind = 'full' then
    delete from public.table_export_change cl where cl.changed_at < v_run.started_at - interval '1 day';
    get diagnostics v_pruned = row_count;
  end if;
  v_queued := public.fn_enqueue_doc_backups();
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'kind', v_run.kind, 'queued_for_dropbox', v_queued, 'change_log_pruned', v_pruned);
end $fn$;
revoke execute on function public.fn_table_export_finish(date, jsonb, text) from public, anon, authenticated;

-- ── 9. THE REBUILD: BASE + INCREMENTS + DELETES, COMPARED ROW FOR ROW WITH LIVE ────────────────────
-- This is the routine the founder's fourth point asks for, and it is the ONE definition: the monthly
-- drill calls it on real downloaded pages, and the CI probe calls it on pages it produced from
-- fn_table_export_page seconds earlier. Both therefore prove the same replay.
--
--   p_base        the rows of ONE full-copy page (a JSON array), which fixes the key window
--   p_increments  an ordered JSON array of JSON arrays: each later day's rows for that table
--   p_changes     an ordered JSON array of change-log rows (table_name, row_key, deleted, changed_at)
--                 as exported in that day's table_export_change pages
--
-- The window is [min key, max key] of the base page, so the comparison is bounded by one page however
-- large the table is. Inside that window the rebuild must hold every row the export WOULD carry:
--   identical_to_live   rebuilt == live, over the exported columns
--   changed_since       rebuilt <> live -- the company kept working after the export; counted, not failed
--   gone_from_live      rebuilt holds a key live does not -- counted (a later deletion we did not log)
--   lost_rows           LIVE holds a key the rebuild does not, and the change log does not name it
--                       either. THAT is data the backup cannot give back, and it fails the drill.
create or replace function public.fn_table_export_replay(p_table text, p_base jsonb, p_increments jsonb default '[]'::jsonb,
                                                          p_changes jsonb default '[]'::jsonb)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_pk text; v_pktype text; v_npk integer; v_strip text[]; v_where text; v_proj text;
  v_dc text[]; v_dl text[]; v_di text[]; v_dq text[];   -- $1..$4, the positions fn_table_export_filter names
  v_lo text; v_hi text; v_inc jsonb; v_n integer;
  n_base integer := 0; n_upserted integer := 0; n_deleted integer := 0; n_rebuilt integer := 0;
  n_match integer := 0; n_changed integer := 0; n_gone integer := 0; n_lost integer := 0;
  v_lost_keys jsonb;
begin
  if to_regclass(format('public.%I', p_table)) is null then
    raise exception 'fn_table_export_replay: public.% does not exist', p_table;
  end if;
  if not exists (select 1 from public.fn_table_export_list() x where x.table_name = p_table) then
    raise exception 'fn_table_export_replay: % is not in fn_table_export_list()', p_table;
  end if;
  select count(*), min(a.attname::text), min(format_type(a.atttypid, a.atttypmod))
    into v_npk, v_pk, v_pktype
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = format('public.%I', p_table)::regclass and i.indisprimary;
  if coalesce(v_npk, 0) <> 1 then
    raise exception 'fn_table_export_replay: public.% has a %-column primary key; only a single-column key is rebuilt', p_table, coalesce(v_npk, 0);
  end if;
  v_strip := public.fn_table_export_stripped(p_table);
  v_where := public.fn_table_export_filter(p_table);
  select d.dc, d.dl, d.di, d.dq into v_dc, v_dl, v_di, v_dq from public.fn_table_export_demo_ids() d;
  -- The exported projection, named column by column, for the same reason the trigger names it: a
  -- to_jsonb() of the whole row would serialise a 768-dimension embedding on both sides of every
  -- comparison only to subtract it again.
  select coalesce(string_agg(quote_ident(a.attname), ',' order by a.attnum), '') into v_proj
    from pg_attribute a
   where a.attrelid = format('public.%I', p_table)::regclass and a.attnum > 0 and not a.attisdropped
     and format_type(a.atttypid, a.atttypmod) not like 'vector%';

  execute format('create temp table it_replay_scratch (like public.%I) on commit drop', p_table);
  execute format('insert into it_replay_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', p_table)
    using coalesce(p_base, '[]'::jsonb);
  get diagnostics n_base = row_count;
  if n_base = 0 then
    execute 'drop table it_replay_scratch';
    return jsonb_build_object('table', p_table, 'rebuilt', 0, 'lost_rows', -1,
                              'error', 'the base page carried no rows, so there is nothing to rebuild from');
  end if;
  -- The window is the base page's own key range, IN THE KEY'S OWN TYPE. Comparing keys as text would
  -- sort bigint 10 before 9 and silently rebuild the wrong window.
  execute format('select min(s.%1$I)::text, max(s.%1$I)::text from it_replay_scratch s', v_pk) into v_lo, v_hi;

  -- every later day, in order: its rows replace the keys they carry (an update is that row again), and
  -- anything it carries outside the base page's window is dropped, so the comparison stays bounded.
  for v_inc in select value from jsonb_array_elements(coalesce(p_increments, '[]'::jsonb)) loop
    execute format('delete from it_replay_scratch s where s.%1$I in
                      (select (r->>%2$L)::%3$s from jsonb_array_elements($1) r)', v_pk, v_pk, v_pktype)
      using coalesce(v_inc, '[]'::jsonb);
    execute format('insert into it_replay_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', p_table)
      using coalesce(v_inc, '[]'::jsonb);
    get diagnostics v_n = row_count;
    n_upserted := n_upserted + v_n;
    execute format('delete from it_replay_scratch s where s.%1$I < ($1)::%2$s or s.%1$I > ($2)::%2$s', v_pk, v_pktype)
      using v_lo, v_hi;
  end loop;

  -- then the deletions the change log recorded, newest wins: a key whose LAST entry is a delete is gone
  execute format(
    'delete from it_replay_scratch s where s.%1$I in (
       select d.row_key::%2$s from (
         select distinct on (c->>''row_key'') c->>''row_key'' as row_key, (c->>''deleted'')::boolean as deleted
           from jsonb_array_elements($1) c
          where c->>''table_name'' = $2
          order by c->>''row_key'', (c->>''changed_at'') desc) d
        where d.deleted)', v_pk, v_pktype)
    using coalesce(p_changes, '[]'::jsonb), p_table;
  get diagnostics n_deleted = row_count;
  execute 'select count(*) from it_replay_scratch' into n_rebuilt;

  -- compared with live over the columns the export carries (the vector columns are stripped at export)
  execute format(
    'select count(*) filter (where l.%1$I is not null and not ((%3$s) is distinct from (%4$s))),
            count(*) filter (where l.%1$I is not null and ((%3$s) is distinct from (%4$s))),
            count(*) filter (where l.%1$I is null)
       from it_replay_scratch s left join public.%2$I l on l.%1$I = s.%1$I',
    v_pk, p_table, 'l.' || replace(v_proj, ',', ', l.'), 's.' || replace(v_proj, ',', ', s.'))
    into n_match, n_changed, n_gone;

  -- THE ONE THAT FAILS THE DRILL: live rows inside the window that the rebuild does not hold and that
  -- no change-log entry names either. A row created after the last export IS named (its insert is
  -- logged), so this counts only rows the backup genuinely cannot give back. The demo rule is the
  -- export's own (fn_table_export_filter), or every demo row would read as a row the rebuild lost.
-- The excuse is the LATEST log entry, not any entry. Review finding, 18 Sep 2026: "any entry names it"
-- also excused a key whose last entry is a DELETE and which is nonetheless live today -- exactly the
-- shape a trigger-bypassing write leaves (session_replication_role=replica, ALTER TABLE ... DISABLE
-- TRIGGER, a raw restore, the truncate-and-reload path). That row is in no backup file and no log entry
-- claims it is, so it must count as lost.
  execute format(
    'create temp table it_replay_lost on commit drop as
       with latest as (
         select distinct on (c->>''row_key'') c->>''row_key'' as row_key, (c->>''deleted'')::boolean as deleted
           from jsonb_array_elements($7) c
          where c->>''table_name'' = $8
          order by c->>''row_key'', (c->>''changed_at'') desc)
       select t.%1$I::text as key
         from public.%2$I t
        where %3$s
          and t.%1$I >= ($5)::%4$s and t.%1$I <= ($6)::%4$s
          and not exists (select 1 from it_replay_scratch s where s.%1$I = t.%1$I)
          and not exists (select 1 from latest l where l.row_key = t.%1$I::text and not l.deleted)',
    v_pk, p_table, v_where, v_pktype)
    using v_dc, v_dl, v_di, v_dq, v_lo, v_hi, coalesce(p_changes, '[]'::jsonb), p_table;
  -- EXECUTE, not static SQL: a plpgsql plan cached against a temp table created in this call would
  -- point at a dead OID on the next one.
  execute 'select count(*)::int from it_replay_lost' into n_lost;
  execute 'select coalesce(jsonb_agg(k.key), ''[]''::jsonb) from (select key from it_replay_lost order by key limit 10) k'
    into v_lost_keys;
  execute 'drop table it_replay_lost';

  execute 'drop table it_replay_scratch';
  return jsonb_build_object('table', p_table, 'key_column', v_pk, 'key_lo', v_lo, 'key_hi', v_hi,
    'base_rows', n_base, 'increment_rows', n_upserted, 'deletes_applied', n_deleted, 'rebuilt', n_rebuilt,
    'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_gone,
    'lost_rows', n_lost, 'lost_keys_first_10', v_lost_keys, 'not_compared', to_jsonb(v_strip));
end $fn$;
revoke execute on function public.fn_table_export_replay(text, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- ── 10. THE DRILL PICKS A CHAIN, NOT JUST A PAGE ───────────────────────────────────────────────────
-- v1 skipped every 'changes_since' page because it "restores nothing on its own". That was true and it
-- is exactly why the incremental half was never proved. v2 prefers a change-tracked table and names the
-- whole chain the edge module must download: the base page of the newest FULL day, then every later
-- finished day's pages for that table and that day's table_export_change pages. When there is no such
-- chain it falls back to v1's single full page, so a day before any tracked table has a base still
-- drills something.
create or replace function public.fn_it_restore_table_pick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_newest text; v_manifest jsonb; v_tab text; v_prev timestamptz;
  v_full date; v_chain_tab text; v_chain jsonb;
begin
  select max(started_at) into v_prev from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick';
  if v_prev is not null and v_prev < now() - interval '1 hour'
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                      and started_at >= v_prev) then
    perform public.fn_it_engineer_finding_upsert('duty:restore_heartbeat:unrecorded',
      'The table restore drill started at ' || to_char(v_prev at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai and never recorded a result',
      'resilience_ping -> _shared/it_restore_drill.ts', 'monitor', 1,
      jsonb_build_object('duty', 'restore_heartbeat', 'owner_seat', 'ceo', 'subject', 'resilience_ping', 'picked_at', v_prev),
      '{}'::text[], array['why the edge tick stopped between the pick and the record: read resilience_ping''s logs'], 'it_engineer.restore_table');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'restore_table_pick'), null);

  select r.stamp::text, r.manifest into v_newest, v_manifest
    from public.table_export_run r where r.status = 'done' and r.manifest is not null
   order by r.stamp desc limit 1;
  if v_newest is null then            -- before #664's first finished day: the pre-7-Sep layout
    select max(split_part(o.name, '/', 1)) into v_newest
      from storage.objects o where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/';
  end if;

  -- ── the incremental chain, when there is one ──
  select max(r.stamp) into v_full from public.table_export_run r where r.kind = 'full' and r.status = 'done';
  if v_full is not null then
    select x.table_name into v_chain_tab
      from public.table_export_change_tracked x
      join storage.objects o on o.bucket_id = 'backups'
                           and o.name = to_char(v_full, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json'
     order by random() limit 1;
  end if;
  if v_chain_tab is not null then
    select jsonb_build_object(
      'table', v_chain_tab,
      'full_day', to_char(v_full, 'YYYY-MM-DD'),
      'base', to_char(v_full, 'YYYY-MM-DD') || '/' || v_chain_tab || '/page_0000.json',
      'increments', coalesce((select jsonb_agg(o.name order by o.name)
                                from public.table_export_run r
                                join storage.objects o on o.bucket_id = 'backups'
                                 and o.name like r.stamp::text || '/' || v_chain_tab || '/page\_%.json'
                               where r.status = 'done' and r.stamp > v_full), '[]'::jsonb),
      'changes', coalesce((select jsonb_agg(o.name order by o.name)
                             from public.table_export_run r
                             join storage.objects o on o.bucket_id = 'backups'
                              and o.name like r.stamp::text || '/table_export_change/page\_%.json'
                            where r.status = 'done' and r.stamp > v_full), '[]'::jsonb))
      into v_chain;
  end if;

  select t.table_name into v_tab
    from public.it_restore_drill_table t
    join storage.objects o on o.bucket_id = 'backups' and o.name = v_newest || '/' || t.table_name || '/page_0000.json'
    left join pg_class pc on pc.oid = to_regclass('public.' || t.table_name)
   where v_manifest is null
      or (v_manifest->'tables' ? t.table_name
          and coalesce(v_manifest->'tables'->t.table_name->>'mode', 'full') not like 'changes_since%')
   order by (coalesce(pc.reltuples, 0) > 0) desc, random() limit 1;
  return jsonb_build_object('newest_export_day', v_newest,
    'sample_rows', coalesce(public.fn_it_threshold('restore_table_sample_rows'), 50),
    'chain', v_chain,
    'table', case when v_tab is not null
                  then jsonb_build_object('table', v_tab, 'path', v_newest || '/' || v_tab || '/page_0000.json', 'day', v_newest) end);
end $fn$;
revoke execute on function public.fn_it_restore_table_pick() from public, anon, authenticated;

-- ── 11. THE DRILL RECORDS THE REBUILD ──────────────────────────────────────────────────────────────
-- v1's three parts are unchanged: export age, the chain of days, and the single full-page restore.
-- WHAT IS NEW is the fourth: when the edge module downloaded a chain, the rebuild is actually run
-- through fn_table_export_replay and a lost row is a finding. A chain that was picked and came back
-- empty or unreadable is itself a failure -- it is never quietly left out.
create or replace function public.fn_it_restore_table_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t jsonb := p->'table'; v_items jsonb := '[]'::jsonb; v_key text; v_tab text := p->'table'->>'table';
  n_rest int := 0; n_match int := 0; n_changed int := 0; n_missing int := 0; v_err text; v_age int; v_max int;
  v_ok boolean; v_detail jsonb; v_out jsonb; v_drop text[]; v_full date; v_last date; v_gaps text; v_live_empty boolean;
  c jsonb := p->'chain'; v_rebuild jsonb; v_rebuild_ok boolean := true;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'fn_it_restore_table_record takes the drill reading from _shared/it_restore_drill.ts';
  end if;

  -- ── THE AGE OF THE NEWEST FINISHED EXPORT ──
  v_max := coalesce(public.fn_it_threshold('restore_export_max_age_days'), 2)::int;
  v_age := current_date - (p->>'newest_export_day')::date;
  if v_age is null or v_age > v_max then
    v_items := v_items || jsonb_build_object('item', 'export_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', case when v_age is null then 'There is no finished table export in the backups bucket at all'
                    else 'The newest finished table backup is from ' || (p->>'newest_export_day') || ' (' || v_age || ' days old)' end,
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('newest_export_day', p->>'newest_export_day', 'age_days', v_age, 'max_age_days', v_max,
        'writer', 'supabase/functions/backup, claimed by resilience_ping through fn_table_export_due'));
  end if;

  -- ── THE CHAIN: the latest full day plus every day after it ──
  if exists (select 1 from public.table_export_run) then
    select max(stamp) into v_full from public.table_export_run where kind = 'full' and status = 'done';
    select max(stamp) into v_last from public.table_export_run where status = 'done';
    if v_full is null or v_full < current_date - 7 then
      v_items := v_items || jsonb_build_object('item', 'full_copy_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'the change-tracked tables have no finished full copy in the last 7 days' || coalesce(' (the last is ' || v_full || ')', ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('last_full_day', v_full));
    else
      select string_agg(d::date::text, ', ' order by d) into v_gaps
        from generate_series(v_full, v_last, interval '1 day') d
       where not exists (select 1 from public.table_export_run r where r.stamp = d::date and r.status = 'done');
      if v_gaps is not null then
        v_items := v_items || jsonb_build_object('item', 'chain_broken', 'owner_seat', 'ceo', 'subject', 'table_backup',
          'title', 'a change-tracked table restores only from the full copy of ' || v_full || ' plus every later day, and ' || v_gaps || ' did not finish',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('last_full_day', v_full, 'last_done_day', v_last, 'missing_or_failed', v_gaps));
      end if;
    end if;
  end if;

  -- ── THE REBUILD FROM BASE + INCREMENTS + DELETES ──
  if c is not null and jsonb_typeof(c) = 'object' then
    if c->>'error' is not null then
      v_rebuild := jsonb_build_object('table', c->>'table', 'error', c->>'error');
      v_rebuild_ok := false;
    else
      begin
        v_rebuild := public.fn_table_export_replay(c->>'table', coalesce(c->'base_rows', '[]'::jsonb),
                                                   coalesce(c->'increment_rows', '[]'::jsonb),
                                                   coalesce(c->'change_rows', '[]'::jsonb));
      exception when others then
        v_rebuild := jsonb_build_object('table', c->>'table', 'error', 'the rebuild failed: ' || sqlerrm);
      end;
      v_rebuild_ok := coalesce((v_rebuild->>'rebuilt')::int, 0) > 0
                  and coalesce((v_rebuild->>'lost_rows')::int, 1) = 0
                  and v_rebuild->>'error' is null;
    end if;
    v_rebuild := v_rebuild || jsonb_build_object('full_day', c->>'full_day', 'base', c->>'base',
                                                 'increment_files', c->'increments', 'change_files', c->'changes');
    if not v_rebuild_ok then
      v_items := v_items || jsonb_build_object('item', 'rebuild', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'The restore drill could not rebuild ' || coalesce(c->>'table', 'a change-tracked table')
                 || ' from its full copy of ' || coalesce(c->>'full_day', '?') || ' plus the later days'
                 || coalesce(': ' || (v_rebuild->>'error'),
                      ' (' || coalesce(v_rebuild->>'lost_rows', '?') || ' live row(s) in the rebuilt key window are in no backup file)'),
        'blast', 'agent_facing', 'affected', 1, 'evidence', v_rebuild);
    end if;
  end if;

  -- ── THE SINGLE FULL PAGE RESTORED INTO SCRATCH ──
  select key_column into v_key from public.it_restore_drill_table where table_name = v_tab;
  if t is null or v_tab is null then
    v_err := 'no full-copy page_0000.json of any table in it_restore_drill_table in the newest finished export';
  elsif v_key is null then
    v_err := v_tab || ' is not in it_restore_drill_table';
  elsif t->>'error' is not null then
    v_err := t->>'error';
  else
    select coalesce(array_agg(c2.column_name::text), '{}') into v_drop
      from information_schema.columns c2
     where c2.table_schema = 'public' and c2.table_name = v_tab
       and not (coalesce(t->'rows'->0, '{}'::jsonb) ? c2.column_name);
    begin
      execute format('create temp table it_restore_scratch (like public.%I) on commit drop', v_tab);
      execute format('insert into it_restore_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', v_tab)
        using coalesce(t->'rows', '[]'::jsonb);
      get diagnostics n_rest = row_count;
      execute format(
        'select count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) = (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) <> (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is null)
           from it_restore_scratch s left join public.%2$I l on l.%1$I = s.%1$I', v_key, v_tab)
        into n_match, n_changed, n_missing using v_drop;
      drop table it_restore_scratch;
    exception when others then v_err := 'restore into scratch failed: ' || sqlerrm;
    end;
  end if;
  if v_err is null and n_rest = 0 and v_key is not null then
    if coalesce((t->>'rows_in_file')::int, -1) = 0 then
      execute format('select not exists (select 1 from public.%I)', v_tab) into v_live_empty;
    else
      v_err := 'the export holds ' || coalesce(t->>'rows_in_file', 'an unknown number of') || ' row(s) and none reached the restore';
    end if;
  end if;
  v_ok := v_err is null and ((n_rest > 0 and n_match > 0) or coalesce(v_live_empty, false));
  v_detail := jsonb_build_object('table', v_tab, 'path', t->>'path', 'rows_in_file', t->'rows_in_file', 'restored', n_rest,
                                 'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_missing,
                                 'not_compared', to_jsonb(v_drop), 'error', v_err,
                                 'newest_export_day', p->>'newest_export_day', 'age_days', v_age,
                                 'last_full_day', v_full, 'chain_gaps', v_gaps, 'rebuild', v_rebuild);
  insert into public.it_restore_drill_result (subject, ok, detail)
  values (coalesce(v_tab, 'no table') || coalesce(' from ' || (t->>'path'), ''), v_ok and v_rebuild_ok and jsonb_array_length(v_items) = 0, v_detail);
  if not v_ok then
    v_items := v_items || jsonb_build_object('item', 'restore', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', 'The monthly restore drill could not restore a table sample' || coalesce(' of ' || v_tab, '') || ': '
               || coalesce(v_err, n_rest || ' row(s) restored and none identical to live (' || n_changed || ' changed, ' || n_missing || ' gone)'),
      'blast', 'agent_facing', 'affected', 1, 'evidence', v_detail);
  end if;

  v_out := jsonb_build_object('restore_table', public.fn_it_duty_settle('restore_table', v_items), 'drill', v_detail);
  perform public.fn_it_engineer_finding_close('duty:restore_heartbeat:unrecorded', 'the table restore drill recorded a result');
  perform public.fn_it_duty_ran('restore_table', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_restore_table_record(jsonb) from public, anon, authenticated;

-- ── 12. THE OLD, NAME-BOUND LOG GOES ───────────────────────────────────────────────────────────────
-- public.kb_chunks_export_change and its trigger function are replaced by the generic pair above. The
-- table is empty on production (measured 18 Sep 2026: 0 rows, no min/max changed_at), because kb_chunks
-- has not been touched since the triggers went on, so nothing is lost by dropping it. The registrar in
-- section 3 puts the three generic triggers on kb_chunks on the next export day, and section 7 forces
-- that day to be a FULL copy, so the new log starts from a base.
drop trigger if exists kb_chunks_export_change_ins on public.kb_chunks;
drop trigger if exists kb_chunks_export_change_upd on public.kb_chunks;
drop function if exists public.trg_kb_chunks_export_change();
drop table if exists public.kb_chunks_export_change;

-- ── 13. REGISTER NOW, SO THE FIRST NIGHT AFTER THE APPLY IS ALREADY CORRECT ────────────────────────
select public.fn_table_export_change_tracking(true) as registrar;

-- ── PROBE ──────────────────────────────────────────────────────────────────────────────────────────
-- This file defines things, so the probe CLEANS UP AFTER ITSELF and ends in a notice; a raise here
-- would roll back the DDL above. It touches no real row: it works on its own temp fixture table, and
-- the only public row it writes is its own change-log entry, which it deletes and counts.
-- It proves, by execution, the thing the founder said must be proven: a base plus increments plus a
-- delete rebuilds to exactly what is live.
do $probe$
declare
  v_before bigint; v_after bigint; v_tracked jsonb; v_log_rows int;
begin
  select count(*) into v_before from public.table_export_change;

  -- (a) the registrar picked the tables it should have, by size and not by name
  select public.fn_table_export_change_tracking(false) into v_tracked;
  if not (v_tracked->'tracked') ? 'kb_chunks' then
    raise exception 'probe: kb_chunks (9,164 MB) is not change-tracked after the registrar ran';
  end if;
  if (v_tracked->'tracked') ? 'pricing_config' then
    raise exception 'probe: a small table was change-tracked; the threshold is not being applied';
  end if;

  -- (b) fn_table_export_list reports the log for every tracked table and for no other
  if exists (select 1 from public.fn_table_export_list() l
              where (l.change_log is not null)
                <> exists (select 1 from public.table_export_change_tracked x where x.table_name = l.table_name)) then
    raise exception 'probe: fn_table_export_list disagrees with table_export_change_tracked';
  end if;
  if not exists (select 1 from public.fn_table_export_list() l where l.table_name = 'table_export_change') then
    raise exception 'probe: table_export_change is not itself exported, so a deletion never reaches the backup';
  end if;

  -- (c) THE REBUILD. A three-row base, one later day that changes row 2 and adds row 4, and a change
  -- log that deletes row 3. The rebuild must equal {1 (as base), 2 (as changed), 4} and lose nothing.
  create temp table probe_live (id bigint primary key, body text) on commit drop;
  insert into probe_live values (1, 'one'), (2, 'two changed'), (4, 'four');
  declare
    v_base jsonb := '[{"id":1,"body":"one"},{"id":2,"body":"two"},{"id":3,"body":"three"}]'::jsonb;
    v_inc  jsonb := '[[{"id":2,"body":"two changed"},{"id":4,"body":"four"}]]'::jsonb;
    v_chg  jsonb; v_n int; v_lost int;
  begin
    v_chg := jsonb_build_array(jsonb_build_object('table_name','probe_live','row_key','3','deleted',true,
                                                  'changed_at', to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')));
    create temp table probe_scratch (id bigint primary key, body text) on commit drop;
    insert into probe_scratch select * from jsonb_populate_recordset(null::probe_live, v_base);
    delete from probe_scratch s where s.id::text in (select (r->>'id') from jsonb_array_elements(v_inc->0) r);
    insert into probe_scratch select * from jsonb_populate_recordset(null::probe_live, v_inc->0);
    delete from probe_scratch s where s.id::text in (
      select c->>'row_key' from jsonb_array_elements(v_chg) c where (c->>'deleted')::boolean);
    select count(*) into v_n from probe_scratch;
    if v_n <> 3 then raise exception 'probe: the rebuild holds % row(s), expected 3', v_n; end if;
    if exists (select 1 from probe_scratch where id = 3) then
      raise exception 'probe: the deleted row survived the rebuild, so a restore would resurrect deleted data';
    end if;
    if not exists (select 1 from probe_scratch where id = 2 and body = 'two changed') then
      raise exception 'probe: the increment did not replace the base row';
    end if;
    select count(*) into v_lost from probe_live l where not exists (select 1 from probe_scratch s where s.id = l.id);
    if v_lost <> 0 then raise exception 'probe: the rebuild lost % live row(s)', v_lost; end if;
    drop table probe_scratch;
  end;
  drop table probe_live;

  -- (d) the DELETE half of the generic trigger writes a row, and the probe removes its own
  insert into public.table_export_change (table_name, row_key, deleted) values ('zz_demo_probe_table', 'zz-demo-probe', true);
  select count(*) into v_log_rows from public.table_export_change where table_name = 'zz_demo_probe_table';
  if v_log_rows <> 1 then raise exception 'probe: the change log did not accept a delete record'; end if;
  delete from public.table_export_change where table_name = 'zz_demo_probe_table';

  select count(*) into v_after from public.table_export_change;
  if v_after <> v_before then
    raise exception 'probe: left % change-log row(s) behind (% before, % after)', v_after - v_before, v_before, v_after;
  end if;
  raise notice 'we_back_up_the_extra_stuff_only_unless_they_got_updated: probe ok; tracked = %', v_tracked->'tracked';
end $probe$;
