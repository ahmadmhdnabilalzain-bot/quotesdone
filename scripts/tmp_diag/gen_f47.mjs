import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

let inp = (await sql(
  `select pg_get_functiondef('public.fn_phase_d_fixture_input(bigint,text,text)'::regprocedure) as def`))[0].def;

const OLD = `    -- F45. THE CANONICAL REFERENCE, OR NOTHING. There is no coalesce chain here on purpose: a`;
const NEW = `    -- ---- F47. A KEY THAT NAMES AN OBJECT IS ANSWERED FROM THAT OBJECT'S REFERENCE --------------
    --
    -- Twelve of the 33 context keys the 54 business rules declare are references to a business
    -- object rather than values in their own right. Which object each names is recorded in
    -- public.phase_d_context_key_object, and the identity then comes from that object's canonical
    -- reference -- so the answer is the same one fn_phase_d_ref_resolve would give and the same one
    -- the rule looks up, whichever store the object lives in.
    --
    -- THIS RUNS BEFORE THE STAGE'S OWN contributes_ref, and that is the point. Before F43 the
    -- answer depended on which stage happened to declare it and what that stage set; now it depends
    -- on the OBJECT, which is what the key is about. A stage no longer has to be classified
    -- correctly for a rule to be given the right subject.
    select sc.canonical_ref->>'canonical_identity' into r
      from public.phase_d_context_key_object m
      join public.phase_d_scenario_record sc
        on sc.object_id = m.object_id
       and sc.fixture_run_id = v_run
     where m.context_key = p_key
       and sc.canonical_ref is not null
     order by sc.scenario_record_id
     limit 1;
    if r is not null then
      value := to_jsonb(r);
      provenance := format('the canonical reference of the %s this fixture run created, resolved '
                        || 'through public.phase_d_context_key_object',
                           (select object_id from public.phase_d_context_key_object where context_key = p_key));
      select sc.fixture_id, sc.fixture_version, sc.source_checksum
        into fixture_id, fixture_version, checksum
        from public.phase_d_context_key_object m
        join public.phase_d_scenario_record sc
          on sc.object_id = m.object_id and sc.fixture_run_id = v_run
       where m.context_key = p_key order by sc.scenario_record_id limit 1;
      return next; return;
    end if;

    -- F45. THE CANONICAL REFERENCE, OR NOTHING. There is no coalesce chain here on purpose: a`;

const c = inp.split(OLD).length - 1;
if (c !== 1) { console.error(`anchor matched ${c}`); process.exit(1); }
inp = inp.replace(OLD, NEW);

// `r` is a RECORD in this routine; the select above needs a scalar. Rename to a dedicated text var.
inp = inp.replace(`  r      record;`, `  r      record;\n  v_ckey text;   -- F47: the identity a context key that names an object resolves to`);
inp = inp.replace(`    select sc.canonical_ref->>'canonical_identity' into r`,
                  `    select sc.canonical_ref->>'canonical_identity' into v_ckey`);
inp = inp.replace(`    if r is not null then
      value := to_jsonb(r);`,
                  `    if v_ckey is not null then
      value := to_jsonb(v_ckey);`);

const PRELUDE = `-- ---- THE REGISTRY: which context keys name a business object, and which one ------------------
CREATE TABLE IF NOT EXISTS public.phase_d_context_key_object (
  context_key text PRIMARY KEY,
  object_id   text NOT NULL,
  why         text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.phase_d_context_key_object IS
  'The context keys that are REFERENCES to a business object rather than values in their own right, '
  'and which of the 56 frozen objects each names. fn_phase_d_fixture_input answers such a key from '
  'that object''s canonical reference, so a rule is handed the same identity it looks up, whichever '
  'store the object lives in. F47.';

REVOKE ALL ON public.phase_d_context_key_object FROM PUBLIC;
REVOKE ALL ON public.phase_d_context_key_object FROM anon, authenticated;
GRANT SELECT ON public.phase_d_context_key_object TO service_role;

INSERT INTO public.phase_d_context_key_object (context_key, object_id, why) VALUES
 ('acceptance_ref','customer_terms_acceptance',
  'BR-026 refuses a certificate before an acceptance and resolves this against the terms-acceptance record'),
 ('approved_revision_ref','quotation_revision',
  'BR-035 compares the approved revision with the published one; both are IMMUTABLE_REVISION records'),
 ('publishing_revision_ref','quotation_revision',
  'BR-035, the other half of the same comparison'),
 ('quote_revision_ref','quotation_revision',
  'BR-018 asks whether the supplier quote is still supplier-authored, against the revision record'),
 ('artifact_ref','ux_specification',
  'BR-036 requires the reviewer to have reviewed the artifact itself; the artifact is the revision record'),
 ('caller_customer_id','customer_account',
  'BR-019 decides visibility from who is asking, which is a customer account'),
 ('comparison_id','quotation_comparison',
  'BR-019 resolves the comparison whose visibility it is judging'),
 ('inquiry_id','inquiry',
  'BR-013 refuses a quote against an inquiry that is not quote-ready, reading public.inquiries'),
 ('provider_event_id','provider_event',
  'BR-032 refuses a replayed provider event, reading the recorded event'),
 ('safe_package_ref','supplier_safe_package',
  'BR-012 requires an approved supplier-safe package record'),
 ('supplier_id','supplier_account',
  'BR-015 requires an approved, verified supplier, reading public.leads'),
 ('transaction_id','payment_transaction',
  'BR-020 refuses a reveal before payment, reading public.transactions')
ON CONFLICT (context_key) DO UPDATE
  SET object_id = excluded.object_id, why = excluded.why, recorded_at = now();

-- A key naming an object that is not one of the 56 would resolve nothing and say so only at
-- runtime. It is checkable here, once.
DO $guard$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(m.context_key || ' -> ' || m.object_id, ', ')
    INTO v_bad
    FROM public.phase_d_context_key_object m
   WHERE NOT EXISTS (SELECT 1 FROM public.phase_d_object_reference_strategy s
                      WHERE s.object_id = m.object_id);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'phase_d_context_key_object names objects that are not in the frozen 56: %', v_bad;
  END IF;
END $guard$;
`;

const HEADER = `-- F47 - a context key that names an object is answered from that object's reference
--
-- F43 recorded which identity each of the 56 objects is known by; F44 and F45 made the write
-- services return it and the factory store it. This closes the last place where the answer still
-- depended on something other than the object: WHICH object a context key is about.
--
-- Twelve of the 33 context keys the 54 business rules declare are references to a business object
-- rather than values in their own right -- safe_package_ref, acceptance_ref, the two revision refs,
-- inquiry_id, supplier_id, transaction_id, comparison_id, caller_customer_id, quote_revision_ref,
-- provider_event_id and artifact_ref. Until now each was answered by whichever fixture stage
-- happened to declare it as its contributes_ref, and by whatever that stage had set -- which is why
-- reclassifying two stages in F42 fixed two rules and left four.
--
-- The mapping is recorded as data, with the reason on each row, in the same way
-- public.phase_d_object_write_map records which relation an object is written to. It is checked at
-- apply time against the 56-object registry, so a key can never name an object that does not exist.
--
-- The lookup runs BEFORE the stage's own contributes_ref, deliberately: the answer now depends on
-- the OBJECT the key is about rather than on a stage being classified correctly.
--
-- The rest of fn_phase_d_fixture_input is byte-identical. One anchor, required to match once.

`;

writeFileSync('scripts/sql/phase_d_f47_a_key_that_names_an_object_is_answered_from_that_objects_reference.sql',
  HEADER + PRELUDE + '\n' + inp + ';\n');
console.log('written');
