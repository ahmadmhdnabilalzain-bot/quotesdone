-- =================================================================================================
-- Phase D — D44. An endpoint that ignores an id has not refused it.
--
-- THE FINDING. Two injected defects are published as REFUSED_AS_REQUIRED on the strength of a §8
-- probe that observed HTTP 200 and nothing else:
--
--     PD-AUTH-002  probe P2-document-scope         expected 403/404   observed 200
--     PD-PRIV-004  probe P3-supplier-surface-body  expected 403/404   observed 200
--
-- Neither raw runner row says REFUSED. Measured on production 2026-08-20, both rows come out of
-- public.fn_phase_d_run_injected_defects() as NOT_RUN; the whole verdict is the overlay in
-- public.fn_phase_d_injected_defect_report(), which coalesces phase_d_section8_probe_result.verdict
-- over the runner's status. So the published "refused" is entirely a stored probe verdict, and the
-- probe that stored it never saw a refusal.
--
-- WHY IT SCORED GREEN: A LIST WITH NO THIRD ANSWER. Both scorers are two-valued.
--
--     scripts/phase_d/run_section8_security_probes.mjs:248-251
--       const same       = docsA.text === docsCross.text;
--       const mentionsB  = docsCross.text.includes('probe supplier B') || …EMAIL.supB…;
--       record('P2-document-scope', …, same && !mentionsB ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED', …)
--
--     scripts/phase_d/run_section8_security_probes.mjs:268-272
--       const hits = needles.filter((n) => hay.includes(n.toLowerCase()));
--       record('P3-supplier-surface-body', …, hits.length === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED', …)
--
-- There is no branch for "the comparison could not tell the two apart". Absence of a difference is
-- scored as a refusal, which is the same defect as scoring a missing input as a satisfied one.
--
-- WHAT THE ENDPOINTS ACTUALLY DO, READ OUT OF THE CODE, NOT INFERRED FROM THE STATUS.
--
--   PD-AUTH-002 / supplier_portal `documents`. The handler is
--   supabase/functions/supplier_portal/index.ts:314-361. Identity is resolved once, at :41, from the
--   JWT: `.from('leads').select(…).eq('claimed_by', email).maybeSingle()`. The handler then reads
--   :318 `.eq('id', sup.id)` and :356 `admin.rpc('fn_supplier_expiries', { p_supplier_id: sup.id })`.
--   Grepping the whole file for a body-sourced identifier — b.id, b.lead_id, b.leads_id,
--   b.supplier_id — returns nothing at all. The probe at :247 posts
--   `{action:'documents', id, leads_id, supplier_id}` naming supplier B; every one of those three
--   keys is discarded before any query runs. A byte-identical body is therefore the ONLY answer this
--   endpoint can give, whoever is named, and it distinguishes nothing.
--
--   The second half of the scorer is inert for a different reason. `mentionsB` looks for the strings
--   'probe supplier B' and EMAIL.supB; the handler is passed A's own id and can emit neither,
--   regardless of the response shape. (The `expiries` element comes back from a routine declared to
--   return bare jsonb, so a shape argument would not have been safe here — the identity argument is.)
--
--   And both fixtures were empty. Measured on production 2026-08-20 over 20,465 leads:
--   license_doc_path is non-null on 1 row and catalog_doc_paths is non-empty on 0. The probe's own
--   fixture insert (run_section8_security_probes.mjs:170-171) writes company_name, email, claimed,
--   claimed_by, verified, approval_status, source, business_role — no document path column at all.
--   So A and B each returned the same nine all-`missing` slots with path:null and url:null.
--
--   PD-PRIV-004 / P3-supplier-surface-body. supplier_api `inbox`
--   (supabase/functions/supplier_api/index.ts:655-657) also resolves the supplier from `claimed_by`
--   on the JWT and never from the body, then reads inquiry_matches for that id and returns
--   `{ inquiries: [] }` immediately when no ids come back. Measured on production 2026-08-20:
--   public.inquiries 0 rows, public.customers 0 rows, public.inquiry_matches 0 rows. The scan at
--   :268-270 looked for two customer canaries in a body that could not contain a customer, because
--   there are no customers and no matches. A zero cannot tell a masking layer from an idle system.
--   The probe's own observed text already discloses this — "BOUNDED: 0 inquiries exist … NOT that a
--   populated payload is masked" — and the verdict it was stored with contradicts its own caveat.
--   (That BOUNDED clause is a hard-coded constant in the template string at :272, not a measurement;
--   it happens to be true today. Named here so the next reader does not take it as evidence.)
--
-- WHAT THIS FILE DOES, AND WHAT IT DELIBERATELY DOES NOT DO.
--
-- It reclassifies. Remedy (a) — make supplier_portal answer 403 when the body names an id that is
-- not the JWT-resolved sup.id — is NOT taken, and the reason is not effort. The endpoint has no
-- ownership parameter to honour: it derives identity from the token and discards the body, which is
-- the correct pattern and the one the rest of this estate has been moved towards. Adding a refusal
-- for a parameter the API does not accept would invent a contract no caller has, and would give the
-- probe a 403 to score without any change in what a supplier can actually reach. If a body-sourced
-- id is ever honoured on that surface, the refusal arrives with it.
--
-- THIS CORRECTION IS DATA, AND §8 CAN OVERWRITE IT. run_section8_security_probes.mjs upserts these
-- rows. Re-running §8 unchanged will re-derive REFUSED_AS_REQUIRED from the same two-valued scorers
-- and silently revert both rows. The durable fix is a third branch at :250 and :271 that returns
-- NOT_DISCRIMINATED when the comparison had nothing to compare — for P2 when both bodies carry zero
-- documents, for P3 when the estate holds zero inquiries. That is a change to the probe runner and
-- belongs with the §8 work, not in a SQL file; it is named here so it is not lost.
--
-- THE DOMAIN HAS TO BE WIDENED ON BOTH TABLES, NOT ONE. phase_d_section8_probe_result.verdict and
-- phase_d_injected_defect_result.status carry the same three-value CHECK for the same concept.
-- phase_d_injected_defect_result holds 0 rows and nothing writes it today, which is exactly how a
-- rule lands on one table and not its sibling. Both are widened.
--
-- WHY THE CONTROL DOES NOT CALL THE RUNNER. public.fn_phase_d_run_injected_defects() is VOLATILE and
-- is NOT idempotent within a transaction: measured over three sequential calls in one aborted
-- transaction, call 1 reported 0 NOT_REFUSED and call 2 reported 2 (PD-OUTBOX-001 and PD-OUTBOX-002,
-- whose outbox attempt counts accumulate across invocations). This file COMMITS, so calling it here
-- would both write those attempt rows for real and read a figure that only holds on a first
-- invocation. The control instead reproduces the report's own LEFT JOIN against a literal left side,
-- and asserts separately that the report body still contains the join and coalesce it reproduces.
--
-- AND THE CONTROL WAS PROVED TO FIRE BEFORE THIS FILE WAS WRITTEN. Section (3) below was executed
-- read-only against production on 2026-08-20 with the two updates NOT applied. It returned
-- REFUSED_AS_REQUIRED for PD-AUTH-002 and PD-PRIV-004 where it expects NOT_DISCRIMINATED, and the
-- correct value for the other four rows. So this control fails before the change and passes after
-- it, which is the only thing that makes its zero worth reading.
-- =================================================================================================

-- ---- 1. Widen the verdict domain on both tables ------------------------------------------------

alter table public.phase_d_section8_probe_result
  drop constraint if exists phase_d_section8_probe_result_verdict_check;
alter table public.phase_d_section8_probe_result
  add  constraint phase_d_section8_probe_result_verdict_check
  check (verdict in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED'));

alter table public.phase_d_injected_defect_result
  drop constraint if exists phase_d_injected_defect_status_check;
alter table public.phase_d_injected_defect_result
  add  constraint phase_d_injected_defect_status_check
  check (status in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED'));

comment on column public.phase_d_section8_probe_result.verdict is
  'REFUSED_AS_REQUIRED = the probe observed the refusal it was written to provoke. NOT_REFUSED = it '
  'observed the defect succeed. NOT_RUN = the assertion did not execute. NOT_DISCRIMINATED = the '
  'assertion executed and its comparison could not separate a refusal from an ignored parameter or '
  'an empty estate, so it answers nothing about the defect. A two-valued scorer has no way to say '
  'the fourth thing, which is why two rows were published as refusals on an HTTP 200 — see D44.';

-- ---- 2. Reclassify the two rows, and correct the mapping justifications -------------------------
-- The original observation text is kept verbatim and the boundary appended. What was seen over the
-- wire is a fact and is not being rewritten; only the reading of it is.

update public.phase_d_section8_probe_result
   set verdict  = 'NOT_DISCRIMINATED',
       observed = observed ||
         '. NOT DISCRIMINATED (D44, 2026-08-20): supplier_portal accepts no owner id at all — the '
         'documents handler at index.ts:314-361 reads only sup.id, resolved at :41 from claimed_by '
         'on the JWT, and the file contains no reference to b.id, b.lead_id, b.leads_id or '
         'b.supplier_id. An identical body is the only answer the endpoint can give whoever is '
         'named, so IDENTICAL cannot separate a refusal from a discarded parameter. Both fixtures '
         'also held zero documents: over 20,465 leads, license_doc_path is non-null on 1 and '
         'catalog_doc_paths non-empty on 0, and the fixture insert writes no document path column'
 where probe_id = 'P2-document-scope'
   and verdict  = 'REFUSED_AS_REQUIRED'
   and observed not like '%NOT DISCRIMINATED (D44%';

update public.phase_d_section8_probe_result
   set verdict  = 'NOT_DISCRIMINATED',
       observed = observed ||
         '. NOT DISCRIMINATED (D44, 2026-08-20): the scan had nothing to find. public.inquiries 0 '
         'rows, public.customers 0 rows, public.inquiry_matches 0 rows; supplier_api inbox '
         '(index.ts:655-657) resolves the supplier from claimed_by on the JWT and returns '
         '{inquiries: []} as soon as inquiry_matches yields no ids, so the 200 is an empty list and '
         'not a masked payload. The row already carried this caveat and was stored as a refusal '
         'anyway'
 where probe_id = 'P3-supplier-surface-body'
   and verdict  = 'REFUSED_AS_REQUIRED'
   and observed not like '%NOT DISCRIMINATED (D44%';

update public.phase_d_section8_defect_map
   set justification =
         'NOT DISCRIMINATED (D44). The probe compared supplier A''s own documents response with the '
         'response to the same call naming supplier B''s id and found them byte-identical. '
         'supplier_portal takes no owner id from the body, so an identical body is the only possible '
         'answer and answers nothing about the defect; both fixtures also held zero documents.'
 where defect_id = 'PD-AUTH-002';

update public.phase_d_section8_defect_map
   set justification =
         'NOT DISCRIMINATED (D44). A real supplier bearer called supplier_api inbox, supplier_portal '
         'opportunities and /rest/v1/inquiries and the response bodies were scanned for the two known '
         'customer identities; none appeared. With 0 inquiries, 0 customers and 0 inquiry_matches on '
         'the estate there was no identity to find, so the scan proves the surfaces are empty, not '
         'that a populated payload is masked.'
 where defect_id = 'PD-PRIV-004';


-- =================================================================================================
-- CONTROL. Both directions exercised: the two reclassified rows must now read NOT_DISCRIMINATED
-- through the report's own overlay, the nine other mapped defects must still read
-- REFUSED_AS_REQUIRED through the same overlay, an unmapped defect must still fall through to the
-- runner's own status, and the widened CHECK must still refuse a value that is not in the domain.
--
-- The runner is not called. See the header for why.
-- =================================================================================================
do $ctl$
declare
  v_notdisc  int;
  v_refused  int;
  v_total    int;
  v_bad      int;
  v_src      text;
  v_check_fired boolean := false;
  r record;
  v_wrong text := '';
begin
  ------------------------------------------------------------------------------------------------
  -- (1) The stored rows.
  ------------------------------------------------------------------------------------------------
  select count(*) filter (where verdict = 'NOT_DISCRIMINATED'),
         count(*) filter (where verdict = 'REFUSED_AS_REQUIRED'),
         count(*),
         count(*) filter (where verdict not in ('REFUSED_AS_REQUIRED','NOT_DISCRIMINATED'))
    into v_notdisc, v_refused, v_total, v_bad
    from public.phase_d_section8_probe_result;

  if v_notdisc <> 2 then
    raise exception 'D44: expected exactly 2 NOT_DISCRIMINATED probe rows, found %. The update did not take, or it took too widely.', v_notdisc;
  end if;
  if not exists (select 1 from public.phase_d_section8_probe_result
                  where probe_id = 'P2-document-scope' and verdict = 'NOT_DISCRIMINATED')
     or not exists (select 1 from public.phase_d_section8_probe_result
                     where probe_id = 'P3-supplier-surface-body' and verdict = 'NOT_DISCRIMINATED') then
    raise exception 'D44: the two NOT_DISCRIMINATED rows are not the two this file names.';
  end if;
  if v_bad > 0 then
    raise exception 'D44: % probe row(s) hold a verdict that is neither REFUSED_AS_REQUIRED nor NOT_DISCRIMINATED. Nothing in this file should have produced that.', v_bad;
  end if;
  if v_total <> 23 or v_refused <> 21 then
    raise exception 'D44: probe table reads % row(s), % refused — 23 and 21 expected after this change.', v_total, v_refused;
  end if;

  ------------------------------------------------------------------------------------------------
  -- (2) The reproduction is faithful. If fn_phase_d_injected_defect_report() stops coalescing the
  --     probe verdict over the runner status, or stops excluding NOT_RUN on the join, then the
  --     join reproduced below is no longer what the report does and this control is worthless.
  ------------------------------------------------------------------------------------------------
  select p.prosrc into v_src
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'fn_phase_d_injected_defect_report';
  if v_src is null then
    raise exception 'D44: fn_phase_d_injected_defect_report() does not exist.';
  end if;
  if position('coalesce(p.verdict, r.status)' in v_src) = 0
     or position('p.verdict <> ''NOT_RUN''' in v_src) = 0 then
    raise exception 'D44: the report no longer coalesces p.verdict over r.status on a join that excludes NOT_RUN. The control below reproduces a join the report does not perform — re-derive it before trusting this file.';
  end if;

  ------------------------------------------------------------------------------------------------
  -- (3) The overlay, both directions, with the runner replaced by a literal left side so nothing
  --     is written and the figure does not depend on how many times the runner has been called.
  ------------------------------------------------------------------------------------------------
  for r in
    select x.defect_id,
           x.expected,
           coalesce(p.verdict, x.runner_status) as got
      from (values ('PD-AUTH-002','NOT_RUN','NOT_DISCRIMINATED'),
                   ('PD-PRIV-004','NOT_RUN','NOT_DISCRIMINATED'),
                   ('PD-AUTH-003','NOT_RUN','REFUSED_AS_REQUIRED'),
                   ('PD-PRIV-003','NOT_RUN','REFUSED_AS_REQUIRED'),
                   ('PD-FILE-001','NOT_RUN','REFUSED_AS_REQUIRED'),
                   ('PD-CONC-001','NOT_RUN','NOT_RUN'))
             as x(defect_id, runner_status, expected)
      left join public.phase_d_section8_defect_map m
             on m.defect_id = x.defect_id
      left join public.phase_d_section8_probe_result p
             on p.probe_id = m.probe_id and p.verdict <> 'NOT_RUN'
  loop
    if r.got is distinct from r.expected then
      v_wrong := v_wrong || format('%s expected %s got %s; ', r.defect_id, r.expected, coalesce(r.got,'(null)'));
    end if;
  end loop;
  if v_wrong <> '' then
    raise exception 'D44: the overlay does not produce the stated statuses — %', v_wrong;
  end if;

  ------------------------------------------------------------------------------------------------
  -- (4) POSITIVE CONTROL ON THE WIDENED CHECK. A domain widened by one value must still be a
  --     domain. Run inside a subtransaction so the attempted write is discarded whatever happens.
  ------------------------------------------------------------------------------------------------
  begin
    update public.phase_d_section8_probe_result
       set verdict = 'DEFINITELY_NOT_A_VERDICT'
     where probe_id = 'P2-document-scope';
    -- reaching here means the CHECK accepted an invented value
    raise exception 'D44_CHECK_DID_NOT_FIRE';
  exception
    when check_violation then
      v_check_fired := true;
    when others then
      if SQLERRM = 'D44_CHECK_DID_NOT_FIRE' then
        raise exception 'D44 POSITIVE CONTROL FAILED: phase_d_section8_probe_result_verdict_check accepted DEFINITELY_NOT_A_VERDICT. The widened constraint constrains nothing.';
      end if;
      raise;
  end;

  if not v_check_fired then
    raise exception 'D44 POSITIVE CONTROL FAILED: the check-violation branch was never reached.';
  end if;

  -- The subtransaction rolled back; prove it rather than assume it.
  if not exists (select 1 from public.phase_d_section8_probe_result
                  where probe_id = 'P2-document-scope' and verdict = 'NOT_DISCRIMINATED') then
    raise exception 'D44: the positive control left P2-document-scope in a state other than NOT_DISCRIMINATED.';
  end if;

  ------------------------------------------------------------------------------------------------
  -- (5) The mapping justifications no longer claim a refusal.
  ------------------------------------------------------------------------------------------------
  if exists (select 1 from public.phase_d_section8_defect_map
              where defect_id in ('PD-AUTH-002','PD-PRIV-004')
                and justification not like 'NOT DISCRIMINATED (D44).%') then
    raise exception 'D44: a reclassified defect still carries a justification asserting a refusal.';
  end if;

  raise notice 'D44: PD-AUTH-002 and PD-PRIV-004 now read NOT_DISCRIMINATED through the report overlay; 21 of 23 probe rows still read REFUSED_AS_REQUIRED, an unmapped defect still falls through to the runner, and the widened CHECK still refuses a value outside its domain.';
  raise notice 'D44: the published §8 overlay figure moves from 37 REFUSED / 38 NOT_RUN to 35 REFUSED / 2 NOT_DISCRIMINATED / 38 NOT_RUN, over 75 defects. Re-running scripts/phase_d/run_section8_security_probes.mjs unchanged will revert both rows — the third scoring branch at :250 and :271 is the durable fix.';
end $ctl$;
