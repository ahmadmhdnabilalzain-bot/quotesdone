-- =================================================================================================
-- Phase D — D52. A bound that is visible in the value it shortened.
--
-- build_injected_defect_result.mjs emits one probe per defect category and reads the rows back out
-- of the raised message. Its own header records why: "A single message carrying all 75 rows is
-- truncated by the transport at 2000 characters — the same defect the workflow builder hit — and
-- the guard below caught it again by refusing a partial export rather than writing 11 rows as if
-- they were 75."
--
-- D44 lengthened one PD-PRIV `observed` string, which pushed the PRIVACY category over that limit.
-- The builder printed "PRIVACY produced 4 row(s); 5 are expected" and exited 1. The guard did
-- exactly what it was built for. Without it the deliverable would have shipped four privacy defects
-- and looked complete.
--
-- Raising the per-category limit is not available — 2000 is the transport's. Emitting one probe per
-- defect would be 75 round trips against a management API that rate-limits hard. So each free-text
-- field is bounded, and THE BOUND IS PART OF THE VALUE: a shortened reason ends in
-- ' …[+N chars]' so a reader of PHASE_D_INJECTED_DEFECT_RESULT.csv can see that it was shortened.
--
-- That distinction is the whole file. A silent truncation is the defect this estate keeps finding —
-- a partial scorer run read as a score, a 30-day total read as a run rate, 3,605 better records
-- reported as unchanged. A truncation that says so in the value is a measurement with its boundary
-- stated, which is the standing rule.
--
-- The builder also now refuses outright if a category still exceeds 1800 characters after bounding,
-- rather than letting a row fall off the end again.
-- =================================================================================================

create or replace function public.fn_phase_d_bounded(p_text text, p_max int)
returns text
language sql
immutable
set search_path = public, pg_temp
as $fn$
  select case
           when p_text is null then ''
           when length(p_text) <= greatest(p_max, 1) then p_text
           else left(p_text, greatest(p_max, 1)) || ' …[+'
                || (length(p_text) - greatest(p_max, 1))::text || ' chars]'
         end;
$fn$;

revoke execute on function public.fn_phase_d_bounded(text, int) from public, anon, authenticated;
grant  execute on function public.fn_phase_d_bounded(text, int) to service_role;

comment on function public.fn_phase_d_bounded(text, int) is
  'Shortens a string and says so in the string. Used where a transport limit would otherwise drop a '
  'whole row silently. Never use it where the full value is the thing being asserted.';


-- ---- CONTROL ------------------------------------------------------------------------------------
do $ctl$
declare v text;
begin
  -- a short string is returned untouched, so the marker cannot appear where nothing was cut
  if public.fn_phase_d_bounded('short', 240) <> 'short' then
    raise exception 'D52: a string inside the bound was altered.';
  end if;
  if public.fn_phase_d_bounded(null, 240) <> '' then
    raise exception 'D52: null did not become an empty string.';
  end if;

  -- a long one is cut AND says by how much
  v := public.fn_phase_d_bounded(repeat('x', 300), 240);
  if v not like '%…[+60 chars]' then
    raise exception 'D52: a 300-character string bounded at 240 did not report the 60 it dropped: %', right(v, 30);
  end if;
  if length(v) - length(' …[+60 chars]') <> 240 then
    raise exception 'D52: the kept portion is % characters, not 240.',
      length(v) - length(' …[+60 chars]');
  end if;

  -- ---- CLEARING WHAT THE FIRST VERSION OF THIS CONTROL LEFT BEHIND ----------------------------
  -- The first version called fn_phase_d_injected_defect_report() directly. That routine runs the
  -- injector, the injector writes mock attempt rows, and this file COMMITS -- so 14 zz-idem-* and
  -- zz-conc-* rows landed in public.phase_d_external_attempt at 00:51:03 and stayed. The workflow
  -- and defect builders both refuse on exactly that residue and caught it on the next regeneration.
  --
  -- A control that leaves rows behind is the harness answering its own question in the next run:
  -- PD-OUTBOX-001 and PD-OUTBOX-002 read "FAILED TO REFUSE" only because the attempt counts they
  -- assert on had already been incremented by this file.
  -- Everything the injector wrote in that one instant, by the demo convention this estate already
  -- uses: a mock provider_mode with a zz- idempotency key, and a customer named ZZ DEMO. Scoped by
  -- convention AND by provider_mode so a real attempt row can never match.
  delete from public.phase_d_external_attempt
   where provider_mode = 'mock' and idempotency_key like 'zz-%';

  -- A BUSINESS TABLE. public.customers is one of the five that must stay at zero residue, and the
  -- injector left one row in it -- "ZZ DEMO — idem001", no email, written at the same instant.
  -- fn_phase_d_fixture_residue() is what caught it, and it is the authority for what counts.
  delete from public.customers
   where full_name like 'ZZ DEMO — %'
     and coalesce(email, '') = ''
     and not exists (select 1 from public.inquiries i where i.customer_id = customers.id)
     and not exists (select 1 from public.transactions t where t.customer_id = customers.id);

  -- and the real subject: every PRIVACY row must fit, with all five present. THE INJECTOR RUNS
  -- INSIDE A BLOCK THAT ALWAYS RAISES, so nothing it writes survives this file.
  declare v_len int; v_rows int; v_left int;
  begin
    begin
      perform set_config('app.phase_d_test_context', 'on', true);
      select count(*), sum(length(concat_ws('|', r.defect_id, r.category, r.status,
               public.fn_phase_d_bounded(coalesce(r.observed,''), 240),
               public.fn_phase_d_bounded(coalesce(r.blocker,''), 240))) + 1)
        into v_rows, v_len
        from public.fn_phase_d_injected_defect_report() r
       where r.category = 'PRIVACY';
      raise exception 'D52_PROBE % %', v_rows, v_len;
    exception
      when others then
        if SQLERRM not like 'D52_PROBE%' then
          raise exception 'D52: the PRIVACY probe failed: % (%)', SQLERRM, SQLSTATE;
        end if;
        v_rows := split_part(substr(SQLERRM, 11), ' ', 1)::int;
        v_len  := split_part(substr(SQLERRM, 11), ' ', 2)::int;
    end;

    if v_rows <> 5 then
      raise exception 'D52: PRIVACY reports % rows, not the 5 the catalogue holds.', v_rows;
    end if;
    if v_len > 1800 then
      raise exception 'D52: PRIVACY still needs % characters after bounding, over the 1800 the transport carries.', v_len;
    end if;

    -- THE RESIDUE CHECK THIS FILE EXISTS TO HAVE. The probe above must have left nothing.
    select coalesce(sum(surviving_rows),0) into v_left from public.fn_phase_d_fixture_residue();
    if v_left <> 0 then
      raise exception 'D52: % fixture row(s) survive after the probe: %. It is meant to roll back.',
        v_left,
        (select string_agg(format('%s=%s', relation, surviving_rows), ' ')
           from public.fn_phase_d_fixture_residue() where surviving_rows > 0);
    end if;
    if (select count(*) from public.phase_d_external_attempt
         where provider_mode = 'mock' and idempotency_key like 'zz-%') <> 0 then
      raise exception 'D52: mock attempt rows survive after the probe.';
    end if;
    if (select count(*) from public.customers) <> 0
       or (select count(*) from public.inquiries) <> 0
       or (select count(*) from public.quotes) <> 0
       or (select count(*) from public.transactions) <> 0 then
      raise exception 'D52: a business table is not at zero: customers=% inquiries=% quotes=% transactions=%',
        (select count(*) from public.customers), (select count(*) from public.inquiries),
        (select count(*) from public.quotes), (select count(*) from public.transactions);
    end if;

    raise notice 'D52: PRIVACY is % rows in % characters after bounding, and the probe left nothing behind.',
      v_rows, v_len;
  end;
end
$ctl$;
