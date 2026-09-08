import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
let d = (await sql(`select pg_get_functiondef('public.fn_phase_d_external_deliver(jsonb)'::regprocedure) def`))[0].def;
const A = `  v_sha := encode(sha256(convert_to(v_payload::text,'UTF8')),'hex');`;
if (!d.includes(A)) { console.error('MISS'); process.exit(1); }
const R = `  -- M05. THE RULE THAT WOULD HAVE REFUSED IT WAS NEVER ASKED.
  --
  -- Measured 24 Aug 2026 while deciding PD-NOTIFY-005: fn_phase_d_external_deliver('W13-S02', ...)
  -- with an approved payload whose body read "contact Ahmad at zz.cust@example.invalid /
  -- 0501234567" returned ok=true, delivered=true, and recorded attempt 25981. BR-011 -- "no customer
  -- identity in a supplier-facing payload" -- refuses that exact string, and refuses it on SHAPE as
  -- well as on a row match, so it works with public.customers at zero. The send path simply never
  -- asked it. That is this estate's "a finished capability with no entry point" one step worse: the
  -- guard exists, it is correct, and nothing calls it.
  --
  -- WHOSE STEPS IT GOVERNS IS NOT DECIDED HERE. fn_phase_d_rule_applies is the estate's own answer
  -- to whether a rule governs a step -- workflow scope, step-level applicability and the producing
  -- step position all live in it -- and this asks that, so a step BR-011 does not govern is
  -- unaffected and the scope moves with the register rather than with this routine.
  select a.applies into v_br011 from public.fn_phase_d_rule_applies('BR-011', v_step) a;
  if coalesce(v_br011, false) then
    select r.ok, r.reason into v_br011_ok, v_br011_why
      from public.fn_phase_d_rule_check('BR-011',
             jsonb_build_object('supplier_payload', v_payload::text)) r;
    if not coalesce(v_br011_ok, false) then
      raise exception 'fn_phase_d_external_deliver: % may not be delivered — %. (br011_identity_before_reveal)',
        v_step, coalesce(v_br011_why, 'BR-011 refused the approved payload')
        using errcode = '23514';
    end if;
  end if;

  v_sha := encode(sha256(convert_to(v_payload::text,'UTF8')),'hex');`;
d = d.replace(A, R).replace('  v_delivered boolean := false;',
  '  v_delivered boolean := false;\n  v_br011     boolean;      -- M05\n  v_br011_ok  boolean;      -- M05\n  v_br011_why text;         -- M05');
writeFileSync('scripts/tmp_diag/m05_external_deliver.sql', d);
console.log('len=' + d.length);
