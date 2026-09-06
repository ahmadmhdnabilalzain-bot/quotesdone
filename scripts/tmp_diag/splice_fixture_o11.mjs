// Splice the file-revision call into fn_phase_d_fixture_scenario's supplier_safe_package stage and
// append the result to O11. Anchored on the complete stage block; asserted to match exactly once.
import { q } from './q.mjs';
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';

let src = (await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  and n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`))[0].prosrc;

const FIND = `    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');`;

const REPL = `    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id';
      -- O11. THE PACKAGE NAMES A FILE, BECAUSE AN EMPTY FILE SET IS NOT AN APPROVED ONE.
      -- Before this line the stage built an inquiry, an approver and a prose 'contents' string and
      -- no files at all. Once BR-012 and GATE-013 gained the file-set leg PD-PRIV-002 needs, that
      -- made every W08, W12 and W13 drive refuse -- 41 of the 1,799 step-contract cases, all
      -- 'positive', all pd_rule_refused or pd_gate_refused. The fixture was incomplete under the
      -- new contract, and the fix is to complete it rather than to soften the rule back to the one
      -- that passed a package with an unredacted drawing.
      --
      -- The revision it registers points at the COMMITTED clean fixture bytes, whose CLEAN metadata
      -- verdict is a real recorded scan of those bytes. A fixture that fabricated its own scan
      -- verdict would be answering the question the scan exists to ask.
      perform public.fn_phase_d_fixture_file_revision(v_key);
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'file_revisions', jsonb_build_array('fxrev:' || v_key),
        'contents','ZZ DEMO — scope and quantities only; no customer identity');`;

const n = src.split(FIND).length - 1;
if (n !== 1) { console.error(`ANCHOR supplier_safe_package: matched ${n}, expected 1`); process.exit(1); }
src = src.replace(FIND, REPL);

const sig = (await q(`select pg_get_function_identity_arguments(p.oid) args,
    pg_get_function_result(p.oid) ret, p.prosecdef, array_to_string(p.proconfig,',') cfg
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
  where p.proname='fn_phase_d_fixture_scenario'`))[0];
console.log('signature:', JSON.stringify(sig));

appendFileSync('scripts/sql/phase_d_o11_a_scan_is_a_fact_about_bytes_and_a_fixture_package_had_no_files.sql',
  `\nCREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(${sig.args})\n`
  + ` RETURNS ${sig.ret}\n LANGUAGE plpgsql\n`
  + (sig.prosecdef ? ' SECURITY DEFINER\n' : '')
  + ` SET search_path TO 'public', 'pg_temp'\nAS $function$` + src + '$function$;\n');
console.log('appended fixture factory to O11');
