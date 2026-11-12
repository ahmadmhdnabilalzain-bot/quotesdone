-- PROBE (pure, no DDL, aborted transaction) for a_demo_supplier_never_feeds_the_alias_queue.sql.
-- Seat: sales_engineer. 12 Nov 2026.
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_demo_supplier_never_feeds_the_alias_queue.sql scripts/sql/a_demo_supplier_never_feeds_the_alias_queue_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back. It writes only to the alias queue
-- (rolled back) and reads one ZZ DEMO supplier at @example.invalid; it touches no lead and no capability. Lead 19398's
-- two proposals (ids 475, 476) are read, never decided, and must be unchanged whatever their status.
do $probe$
declare f text := ''; v_demo bigint; v jsonb; v_before int; v_real text;
begin
  set local session_replication_role = replica;
  select string_agg(id || ':' || status, ',' order by id) into v_real from public.service_alias_proposal where id in (475, 476);
  select l.id into v_demo from public.leads l where l.is_demo and l.company_name ~* '^\s*zz\s*demo' and l.email like '%@example.invalid' order by l.id limit 1;
  if v_demo is null then raise exception 'CHK<<{"verdict":"PROBE FAILED: no ZZ DEMO lead at @example.invalid"}>>'; end if;

  -- 1. a demo supplier's confirmed words file nothing
  select count(*) into v_before from public.service_alias_proposal;
  v := public.fn_service_alias_propose(v_demo, '[{"phrase":"ZZ probe gold leaf wall panels","key":"wallpaper.wall_panels"}]'::jsonb);
  if v->>'refused' is distinct from 'demo_supplier' or (v->>'proposed')::int <> 0 or not coalesce((v->>'ok')::boolean, false) then
    f := f || 'a demo supplier was not refused: ' || v::text || '; ';
  end if;
  if (select count(*) from public.service_alias_proposal) <> v_before then f := f || 'a demo supplier filed a proposal; '; end if;

  -- 2. the queue still works for a caller that is not a demo supplier (no lead: the routine's null branch)
  v := public.fn_service_alias_propose(null, '[{"phrase":"ZZ probe gold leaf wall panels","key":"wallpaper.wall_panels"}]'::jsonb);
  if (v->>'proposed')::int <> 1 then f := f || 'the queue no longer files a non-demo proposal: ' || v::text || '; '; end if;

  -- 3. the 26 demo rows are rejected, never approved; the real supplier's 2 are as they were
  if exists (select 1 from public.service_alias_proposal
              where id = any(array[431,432,433,434,435,436,437,438,440,441,442,443,444,445,447,448,449,450,452,453,481,483,486,487,511,512]::bigint[])
                and status <> 'rejected') then
    f := f || 'a demo proposal is not rejected; ';
  end if;
  if exists (select 1 from public.service_alias_proposal p where p.status = 'proposed' and p.phrase not like 'ZZ probe %'   -- step 2's own row
              and not exists (select 1 from public.leads l where l.id = any(p.supplier_ids) and not l.is_demo)) then
    f := f || 'a proposal with no real supplier behind it is still open; ';
  end if;
  -- whatever the sales engineer has decided about them (review 382401), this file did not decide them
  if (select count(*) from public.service_alias_proposal where id in (475, 476)) <> 2
     or exists (select 1 from public.service_alias_proposal where id in (475, 476)
                  and reason = 'filed by a ZZ DEMO registration fixture (11 Nov 2026), not a real supplier''s words')
     or (select string_agg(id || ':' || status, ',' order by id) from public.service_alias_proposal where id in (475, 476)) is distinct from v_real then
    f := f || 'the real supplier''s proposals were touched (' || coalesce(v_real, 'none') || '); ';
  end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end,
    'demo_refused', v_demo is not null, 'real_supplier_rows', v_real);
end $probe$;
