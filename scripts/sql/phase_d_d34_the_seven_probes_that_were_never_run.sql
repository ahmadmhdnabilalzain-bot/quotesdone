-- =================================================================================================
-- Phase D — D34. The seven probes that were never run.
--
-- Every Phase D closure so far has recorded the §8 security probes as NOT_RUN, and 20 of the 75
-- injected defects with them, under a blocker that begins "SECTION 8 NOT BUILT". The stated reason
-- was always a variant of "no Phase D path issues an authenticated HTTP request".
--
-- That reason was false. scripts/phase_d/discharge_d0_auth_debt.mjs has minted a real bearer since
-- D0 — management token -> /api-keys?reveal -> auth/admin/generate_link -> /auth/v1/verify — and
-- nothing stopped the same recipe being pointed at the seven probes. The work had simply not been
-- done, and this file is the half of the repair that lives in the database.
--
-- WHAT THIS FILE DOES NOT DO. It does not mark anything satisfied on the strength of posture. A
-- bucket being private is not evidence that supplier A cannot read supplier B's file, and the
-- override below fires ONLY for a defect that a named probe assertion actually executed. The 20
-- rows are NOT all covered: 11 are, 9 are not, and the 9 keep a NOT_RUN status with a blocker that
-- now says what is still missing rather than repeating that section 8 does not exist.
--
-- THE SHAPE OF THE OVERRIDE. fn_phase_d_run_injected_defects() is 500 lines of hand-written probe
-- blocks and is left completely untouched: rewriting it to thread an override through 75 emission
-- sites would put the 26 that already execute at risk to change the 11 that do not. Instead a
-- reporting wrapper LEFT JOINs the recorded verdicts onto it, so there is exactly one place where a
-- status can be overridden and it can be read in full in one screen.
-- =================================================================================================

-- -------------------------------------------------------------------------------------------------
-- 1. Where an HTTP probe records what it observed.
-- -------------------------------------------------------------------------------------------------
create table if not exists public.phase_d_section8_probe_result (
  probe_id    text primary key,
  probe       text not null,
  verdict     text not null check (verdict in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN')),
  observed    text,
  http_status int,
  ran_at      timestamptz not null default now()
);
comment on table public.phase_d_section8_probe_result is
  'One row per §8 security probe ASSERTION, written by scripts/phase_d/run_section8_security_probes.mjs '
  'after it executed the assertion over real HTTP against the deployed project. Never hand-written: a '
  'verdict here is read by fn_phase_d_injected_defect_report() and becomes a defect status, so forging '
  'one would turn a green number into a claim nothing measured.';

revoke all on public.phase_d_section8_probe_result from anon, authenticated;
revoke truncate on public.phase_d_section8_probe_result from service_role, authenticated, anon;

-- -------------------------------------------------------------------------------------------------
-- 2. Which defect each probe assertion actually answers.
--
-- The justification column exists so this mapping can be argued with. A mapping that cannot be
-- checked is the instrument-on-the-wrong-subject defect waiting to happen: it is how "a supplier
-- bearer was refused" quietly becomes "a category overlay cannot dispatch".
-- -------------------------------------------------------------------------------------------------
-- NO FOREIGN KEY to phase_d_section8_probe_result, deliberately. The map is a declaration of which
-- probe ANSWERS which defect and is deployed before any probe has run; a foreign key would make the
-- deployment depend on the probe having already executed, which inverts the order. The wrapper
-- LEFT JOINs, so a mapping whose probe has not run yet simply produces no override — which is the
-- correct reading of "not probed yet".
create table if not exists public.phase_d_section8_defect_map (
  defect_id     text primary key,
  probe_id      text not null,
  justification text not null
);
revoke all on public.phase_d_section8_defect_map from anon, authenticated;
revoke truncate on public.phase_d_section8_defect_map from service_role, authenticated, anon;

-- -------------------------------------------------------------------------------------------------
-- 3. The report. fn_phase_d_run_injected_defects() stays the source for all 75 rows; a recorded
--    probe verdict overrides the status of the mapped row and nothing else.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_injected_defect_report()
returns table(defect_id text, category text, status text, observed text, blocker text)
language sql
set search_path to 'public', 'pg_temp'
as $rep$
  select r.defect_id,
         r.category,
         coalesce(p.verdict, r.status)                                            as status,
         case when p.probe_id is null then r.observed
              else p.observed || ' [§8 probe ' || p.probe_id
                   || coalesce(' · HTTP ' || p.http_status::text, '')
                   || ' · executed ' || to_char(p.ran_at at time zone 'utc','YYYY-MM-DD HH24:MI') || 'Z]'
         end                                                                      as observed,
         -- The nine §8 defects with no probe mapping keep their specific mechanism text, but the
         -- prefix is corrected: "SECTION 8 NOT BUILT" became false on 19 Aug 2026 when the seven
         -- probes ran. Leaving it would be a blocker that lies about why it is a blocker — the
         -- reader would conclude the capability is missing when it exists and simply does not
         -- reach this case. The replace is a no-op on the 29 non-§8 NOT_RUN rows.
         case when p.probe_id is not null then null
              else replace(r.blocker,
                     'SECTION 8 NOT BUILT — ',
                     'SECTION 8 WAS EXECUTED 2026-08-19 AND DOES NOT REACH THIS CASE — ')
         end                                                                      as blocker
    from public.fn_phase_d_run_injected_defects() r
    left join public.phase_d_section8_defect_map m on m.defect_id = r.defect_id
    left join public.phase_d_section8_probe_result p
           on p.probe_id = m.probe_id and p.verdict <> 'NOT_RUN'
$rep$;

revoke all on function public.fn_phase_d_injected_defect_report() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 4. The mapping itself, and the nine that are still NOT covered.
--
-- The session brief asserted that running the probes makes all 20 executable. It does not, and the
-- difference is recorded here rather than smoothed over: a brief carries reliable counts and
-- unreliable diagnoses, and this is the diagnosis half.
-- -------------------------------------------------------------------------------------------------
insert into public.phase_d_section8_defect_map (defect_id, probe_id, justification) values
  ('PD-AUTH-001','P6-table-bypass',            'anon AND a real authenticated customer bearer selected public.customers directly while it held two live rows, against a service_role control proving the rows existed; both read 0.'),
  ('PD-AUTH-002','P2-document-scope',          'supplier A called supplier_portal documents naming supplier B''s lead id; the response was byte-identical to A''s own and carried no trace of B.'),
  ('PD-AUTH-003','P5-non-admin-mutation',      'a real customer bearer attempted an admin mutation on os_api and was refused 403.'),
  ('PD-AUTH-004','P5-no-role-readonly',        'an authenticated identity resolving to no active canonical role was refused 403 by the Command Center.'),
  ('PD-FILE-001','P8-mime-allowlist',          'a ZIP declared application/zip and named .pdf was refused by the bucket MIME allow-list, which storage enforces regardless of the uploading code path.'),
  ('PD-FILE-002','P8-size-limit',              'an upload over the bucket''s declared file_size_limit was refused 413 by storage itself.'),
  ('PD-FILE-003','P8-executable-content',      'an MZ executable declared application/x-msdownload was refused 415 invalid_mime_type.'),
  ('PD-FILE-004','P7-expired-url',             'a signed URL was minted with a 1 second TTL, replayed successfully while valid, and refused after expiry.'),
  ('PD-FILE-005','P7-unowned-insert',          'an authenticated customer bearer inserted directly into storage.objects under a path it does not own and was refused.'),
  ('PD-PRIV-003','P7-wrong-owner-path',        'a customer bearer and an anonymous caller each named a private bucket path belonging to another party on the two minters that accept a caller-supplied path; both were refused.'),
  ('PD-PRIV-004','P3-supplier-surface-body',   'a real supplier bearer called supplier_api inbox, supplier_portal opportunities and /rest/v1/inquiries, and the RESPONSE BODIES were scanned for the two known customer identities; none appeared.')
on conflict (defect_id) do update
  set probe_id = excluded.probe_id, justification = excluded.justification;

-- -------------------------------------------------------------------------------------------------
-- 5. THE NINE THAT REMAIN NOT_RUN, AND WHY. Recorded as a comment rather than as a table because
--    they are the ABSENCE of a mapping, and inventing a row to represent an absence is how a
--    denominator gets fixed instead of a population.
--
--    PD-AUTH-005  category overlay as accountable task owner. A supplier bearer is not a category
--                 overlay; mapping P5 onto it would be the wrong subject. Needs an overlay identity
--                 presented to an authenticated route.
--    PD-DISP-005  category overlay attempts dispatch. Same subject as PD-AUTH-005.
--    PD-QUOTE-001 supplier edits another supplier's quote. public.quotes carries trg_new_quote_sms
--                 on INSERT, so creating the quote this needs would send an SMS. Refused under the
--                 hold. The sibling scoping decision IS proved by P2-cross-write, on a leads row.
--    PD-QUOTE-004 customer sees an unpublished quote. Same reason: no quote may exist.
--    PD-PRIV-001  supplier payload contains a customer email. Needs a RENDERED supplier-facing
--                 payload; §9 records an approved payload and its sha256 but renders no body.
--    PD-PRIV-002  drawing with an unapproved redaction. Needs a drawing revision in that state.
--    PD-PRIV-005  hidden metadata leaks identity. Needs a rendered artifact to inspect.
--    PD-LEGAL-001 certificate issued before terms acceptance. The certificate rendering path is
--                 outside Phase D.
--    PD-LEGAL-004 stale tax/legal static file asserted as current. A content-pipeline fact.
--
--    Three of those nine (PD-QUOTE-001, PD-QUOTE-004 and, on the customer side, the object half of
--    probe 1) are blocked by the ZERO-EXTERNAL-EFFECT HOLD rather than by a missing capability.
--    They are executable the moment the hold lifts, and that is a different sentence from
--    "section 8 does not exist", which is what they used to say.
-- -------------------------------------------------------------------------------------------------

-- -------------------------------------------------------------------------------------------------
-- 6. DEPLOY-TIME CONTROL. The probe runs inside a subtransaction that raises and is caught, so the
--    variables survive and the rows do not. D31 did not do this, committed 14 attempt rows plus a
--    customers row, and corrupted its own next measurement.
-- -------------------------------------------------------------------------------------------------
-- fn_phase_d_run_injected_defects() INJECTS: several of its 26 executed probes write real rows
-- through the canonical service to observe what the machine does with them. Calling it is therefore
-- a WRITE, and D31 learned that the expensive way — it called this function from a control that did
-- not roll back, committed 14 attempt rows and a public.customers row, and corrupted its own next
-- measurement. EVERY call below is inside the subtransaction, the results are carried out in
-- variables (which survive a rollback) and the assertions read only those variables. There is no
-- second call after the rollback, because that call would commit.
do $ctl$
declare
  v_rows int := -1; v_mapped int := -1; v_overridden int := -1; v_orphan text := '(unmeasured)'; v_report int := -1;
  v_msg text;
begin
  begin
    perform set_config('app.phase_d_test_context','on', true);

    select count(*) into v_report from public.fn_phase_d_injected_defect_report();
    select count(*) into v_rows   from public.fn_phase_d_run_injected_defects();
    select count(*) into v_mapped from public.phase_d_section8_defect_map;

    -- Every mapped defect must exist in the catalogue the runner emits. A mapping onto a defect
    -- that does not exist would silently never fire and would read as "not yet probed".
    select coalesce(string_agg(m.defect_id, ', '), '(none)') into v_orphan
      from public.phase_d_section8_defect_map m
     where not exists (select 1 from public.fn_phase_d_run_injected_defects() r
                        where r.defect_id = m.defect_id);

    select count(*) into v_overridden
      from public.fn_phase_d_injected_defect_report()
     where defect_id in (select defect_id from public.phase_d_section8_defect_map);

    raise exception 'D34_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'D34_CTL_ROLLBACK' then
      get stacked diagnostics v_msg = message_text;
      raise exception 'D34 control failed before it could measure: %', left(coalesce(v_msg, SQLERRM), 300);
    end if;
  end;

  if v_rows < 0 or v_report < 0 then
    raise exception 'D34 control: the probe did not complete, so nothing was measured.';
  end if;
  if v_report <> v_rows then
    raise exception 'D34 control: the report returned % row(s) and the runner %. The wrapper must not add or drop a defect.', v_report, v_rows;
  end if;
  if v_rows <> 75 then
    raise exception 'D34 control: the injected defect catalogue emitted % row(s), not 75.', v_rows;
  end if;
  if v_orphan <> '(none)' then
    raise exception 'D34 control: mapping names defect(s) the runner never emits: %', v_orphan;
  end if;
  if v_mapped <> 11 then
    raise exception 'D34 control: % mapping row(s) present, 11 expected. Nine of the twenty section 8 defects are deliberately NOT mapped; changing that number needs the reasons in section 5 changed with it.', v_mapped;
  end if;

  -- AND ASK THE RESIDUE FUNCTION, NOT ONE TABLE. The control above called an injecting routine
  -- twice; if its subtransaction did not actually roll back, this is where it shows. D32 checked
  -- the one relation it had been looking at and inferred the rest was clean, and the kernel board
  -- then found a surviving public.customers row.
  declare v_res int; v_detail text;
  begin
    select count(*), coalesce(string_agg(distinct relation, ', '), '(none)')
      into v_res, v_detail from public.fn_phase_d_fixture_residue();
    if v_res <> 0 then
      raise exception 'D34 control: its own probe left % residue row(s) behind in %. The subtransaction did not roll back.', v_res, v_detail;
    end if;
  end;

  raise notice 'D34: % defects, % mapped to an executed section 8 probe, wrapper preserves the population, 0 residue.', v_rows, v_mapped;
end $ctl$;
