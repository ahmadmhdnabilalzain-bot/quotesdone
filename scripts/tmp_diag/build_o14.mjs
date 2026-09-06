// O14. Two more instances of one shape: a key written in two shapes, and a package the DRIVE
// produced rather than the fixture.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

const HEAD = `-- O14. THE PACKAGE THE DRIVE PRODUCES, AND A REVISION KEY WRITTEN IN TWO SHAPES.
--
-- O11 gave the FIXTURE FACTORY's supplier-safe package a file set. Measured after it, inside a W08
-- scenario: the factory creates NO supplier_safe_package at all for W08 —
--
--   object rows: (none) | revisions: (none) | scenario_record: quotation_revision=cd93f862-…
--
-- The package GATE-013 judges at W08-S02 is produced by the DRIVE, at W08-S01, through
-- fn_phase_d_effect_produce. So the hook was in the right shape and the wrong place: the file set
-- has to arrive with the package whoever creates it, and inside a Phase D test context that is the
-- effect producer.
--
-- IT IS SCOPED TO THE TEST CONTEXT, and that boundary is the whole of its safety. Guarded on
-- public.fn_phase_d_fixture_context() being non-null, so no production write ever gains a file
-- revision it did not earn. In production a supplier-safe package that names no file is refused by
-- BR-012 and GATE-013 exactly as it should be — the estate has no file-production path yet, and
-- that absence stays visible rather than being papered over by a default.
--
-- AND BR-018 HAD THE SAME KEY PROBLEM GATE-013 HAD. fn_phase_d_step_context resolves
-- quote_revision_ref to the object record's canonical identity — the RECORD ID — and
-- fn_phase_d_quote_original_intact looked it up by business_key:
--
--   BR-018: '550609' is not a live quotation_revision record
--
-- which was true of the name it was given and false of the row it was about. That is the third
-- instance in this session of one key written in two shapes; the predicate now resolves both, the
-- same way O13 taught the package resolver to.

CREATE OR REPLACE FUNCTION public.fn_phase_d_quote_original_intact(p_revision_ref text)
 RETURNS TABLE(intact boolean, refusal_code text, reason text, normalisations bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_live text; v_n bigint; v_bad bigint; v_ref text; v_key text;
begin
  v_ref := btrim(coalesce(p_revision_ref,''));
  if v_ref = '' then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := 'No supplier revision named. Nothing can be certified unedited against nothing.';
    normalisations := 0; return next; return;
  end if;

  -- THE SAME KEY IN TWO SHAPES. A caller holding the record id and a caller holding the business
  -- key are asking about one row, and a predicate that knows only one of them invents a hole.
  select o.business_key,
         encode(extensions.digest(convert_to(o.payload::text, 'UTF8'), 'sha256'), 'hex')
    into v_key, v_live
    from public.phase_d_object_record o
   where o.object_id = 'quotation_revision' and o.superseded_by is null
     and (o.business_key = v_ref
          or o.record_id::text = v_ref
          or 'quotation_revision:' || o.business_key = v_ref)
   order by o.record_id desc limit 1;

  if v_live is null then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := format('%L resolves to no live quotation_revision record, by business key or by record id.', p_revision_ref);
    normalisations := 0; return next; return;
  end if;

  -- Normalisations may cite either shape too, so both are counted.
  select count(*), count(*) filter (where n.source_payload_sha256 is distinct from v_live)
    into v_n, v_bad
    from public.phase_d_quote_normalisation n
   where n.source_revision_ref in (v_key, v_ref) and n.superseded_by is null;
  normalisations := v_n;

  if v_bad > 0 then
    intact := false; refusal_code := 'pd_quote_original_overwritten';
    reason := format('%s of %s live normalisation(s) of %s were derived from a payload that hashes to something other than the revision''s current %s. Either the original was edited after normalisation, or the projection is describing a revision that no longer exists.',
                     v_bad, v_n, v_key, left(v_live, 12));
    return next; return;
  end if;

  intact := true; refusal_code := null;
  reason := format('%s is unedited at %s and carries %s live normalised projection(s), none of which restates a supplier-authored field.',
                   v_key, left(v_live, 12), v_n);
  return next;
end $function$;

`;

let src = (await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  and n.nspname='public' and p.proname='fn_phase_d_effect_produce'`))[0].prosrc;

const FIND = `    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id', e.effect_object_id, 'business_key', v_key, 'owner_ref', v_owner,
      'created_by', v_actor, 'state', v_state, 'payload', v_payload,
      'run_id', sr.run_id, 'step_run_id', v_step_run, 'trace_id', p_input->>'trace_id'));
    v_result_ref := v_write->>'result_reference';`;

const REPL = `    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id', e.effect_object_id, 'business_key', v_key, 'owner_ref', v_owner,
      'created_by', v_actor, 'state', v_state, 'payload', v_payload,
      'run_id', sr.run_id, 'step_run_id', v_step_run, 'trace_id', p_input->>'trace_id'));
    v_result_ref := v_write->>'result_reference';

    -- O14. A SUPPLIER-SAFE PACKAGE ARRIVES WITH ITS FILE SET, INSIDE A TEST CONTEXT AND NOWHERE ELSE.
    -- BR-012 and GATE-013 now require every live revision of a package to be redaction-approved and
    -- metadata-clean, and a package naming no file is refused. In production that refusal is
    -- correct and stays: this estate has no path that produces a supplier-facing file set, and that
    -- absence must remain visible rather than be defaulted away. Inside a Phase D fixture context
    -- there is no such path either, so the harness supplies the one thing it can honestly supply --
    -- a revision pointing at COMMITTED bytes this estate has actually scanned and found clean.
    -- The guard is fn_phase_d_fixture_context(), which is an hmac over txid_current() minted only
    -- against an approved audited operation; it is not a GUC a caller can set.
    if e.effect_object_id = 'supplier_safe_package'
       and public.fn_phase_d_fixture_context() is not null then
      perform public.fn_phase_d_fixture_file_revision(v_key);
    end if;`;

const n = src.split(FIND).length - 1;
if (n !== 1) { console.error(`ANCHOR effect_produce object write: matched ${n}`); process.exit(1); }
src = src.replace(FIND, REPL);

const sig = (await q(`select pg_get_function_identity_arguments(p.oid) args,
    pg_get_function_result(p.oid) ret, p.prosecdef from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
  where p.proname='fn_phase_d_effect_produce'`))[0];

writeFileSync('scripts/sql/phase_d_o14_the_package_the_drive_produces_and_a_key_in_two_shapes.sql',
  HEAD
  + `CREATE OR REPLACE FUNCTION public.fn_phase_d_effect_produce(${sig.args})\n`
  + ` RETURNS ${sig.ret}\n LANGUAGE plpgsql\n`
  + (sig.prosecdef ? ' SECURITY DEFINER\n' : '')
  + ` SET search_path TO 'public', 'pg_temp'\nAS $function$` + src + '$function$;\n');
console.log('wrote O14');
