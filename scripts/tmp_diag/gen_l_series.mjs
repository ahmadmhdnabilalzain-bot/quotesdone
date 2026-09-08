// Generate the L-series migrations from the LIVE bodies on htdblwldjkcgjvmqkbeh.
//   node scripts/tmp_diag/gen_l_series.mjs
import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';

const get = async sig => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) def`))[0].def;
const must = (s, a, name) => { if (!s.includes(a)) { console.error('ANCHOR MISS: ' + name); process.exit(1); } return s; };
const OUT = 'scripts/sql/';

// ================================================================================================
// L01 — a register that could not tell naming an object from describing one
// ================================================================================================
let sc = await get('public.fn_phase_d_step_context(bigint)');
const DOOR = `      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;`;
if (sc.split(DOOR).length - 1 !== 3) { console.error('expected 3 identity doors'); process.exit(1); }
sc = sc.split(DOOR).join(`      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';`);
const SC_L01 = sc;

let fi = await get('public.fn_phase_d_fixture_input(bigint,text,text)');
must(fi, `     where m.context_key = p_key\n       and sc.canonical_ref is not null`, 'fi1');
fi = fi.replace(`     where m.context_key = p_key\n       and sc.canonical_ref is not null`,
                `     where m.context_key = p_key and m.key_role = 'IDENTIFIES'\n       and sc.canonical_ref is not null`)
       .replace(`                           (select object_id from public.phase_d_context_key_object where context_key = p_key));`,
                `                           (select object_id from public.phase_d_context_key_object\n                             where context_key = p_key and key_role = 'IDENTIFIES'));`)
       .replace(`       where m.context_key = p_key order by sc.scenario_record_id limit 1;`,
                `       where m.context_key = p_key and m.key_role = 'IDENTIFIES'\n       order by sc.scenario_record_id limit 1;`);

let fp = await get('public.fn_phase_d_fixture_effect_payload(bigint)');
must(fp, `       where cko.context_key = r.src\n         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''`, 'fp1');
fp = fp.replace(`       where cko.context_key = r.src\n         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''`,
                `       where cko.context_key = r.src and cko.key_role = 'IDENTIFIES'\n         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''`);

const L01 = `-- L01 — a register that could not tell naming an object from describing one
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, with the fixture scenario asked to withhold the
-- object the workflow under test produces on ALL 30 workflows rather than on W12 alone.
--
-- public.phase_d_context_key_object is the estate's answer to "which business object does this
-- context key name". Five call sites read it -- three identity doors in fn_phase_d_step_context
-- (G08 the run's own row, K07 the run's own effect ledger, G08 the scenario record),
-- fn_phase_d_fixture_input's F47 door and fn_phase_d_fixture_effect_payload's H04 door -- and every
-- one of them uses it for the same purpose: to turn a key into a REFERENCE to a record.
--
-- BR-025 needs two keys that are not references. terms_version and terms_hash are FACTS ABOUT an
-- acceptance, and the acceptance they are facts about is the customer's in W04 and the supplier's
-- in W09. The register had no row for either key, so fn_phase_d_rule_applies could not derive
-- BR-025's subject at all, and its primary key (context_key) could not have held both answers if
-- the rows had been written. Adding them without saying what kind of key they are turns the five
-- identity doors into fabricators: measured, the K07 door then answered terms_hash with the
-- business key of the acceptance record the run had just created --
--   "BR-025: terms_hash 2dbc3271-4f4e-84f5-8d56- is not a SHA-256 digest (64 hexadecimal
--    characters), so it was never computed over the displayed terms."
-- -- which is F47's own defect ("a key that names an object is answered from that object's
-- reference") applied to a key that names no object.
--
-- The register now records WHICH KIND each key is. Every existing row is IDENTIFIES and nothing
-- about their behaviour changes; the five doors ask for IDENTIFIES explicitly, so a DESCRIBES key
-- can never be answered with a row id. The partial unique index is the other half: with a
-- composite primary key a second IDENTIFIES row for one key would make every one of those
-- \`select ... into\` doors take whichever row came first, silently, which is the defect this file
-- exists to stop rather than to move.
--
-- ROLLBACK: scripts/sql/down/phase_d_l01_a_register_that_could_not_tell_naming_from_describing_down.sql
-- GENERATED from the live bodies by scripts/tmp_diag/gen_l_series.mjs.

alter table public.phase_d_context_key_object
  add column if not exists key_role text not null default 'IDENTIFIES';

alter table public.phase_d_context_key_object
  drop constraint if exists phase_d_context_key_object_key_role_ck;
alter table public.phase_d_context_key_object
  add constraint phase_d_context_key_object_key_role_ck
  check (key_role in ('IDENTIFIES','DESCRIBES'));

alter table public.phase_d_context_key_object
  drop constraint if exists phase_d_context_key_object_pkey;
alter table public.phase_d_context_key_object
  add constraint phase_d_context_key_object_pkey primary key (context_key, object_id);

-- One key identifies at most one object. Without this the doors below pick a row by chance.
drop index if exists public.phase_d_context_key_object_one_identity_uk;
create unique index phase_d_context_key_object_one_identity_uk
  on public.phase_d_context_key_object (context_key) where key_role = 'IDENTIFIES';

insert into public.phase_d_context_key_object (context_key, object_id, why, key_role) values
  ('terms_version','customer_terms_acceptance',
   'BR-025 judges the displayed version a CUSTOMER terms acceptance names; it is a fact about that record, not a reference to it', 'DESCRIBES'),
  ('terms_version','supplier_terms_acceptance',
   'BR-025 judges the displayed version a SUPPLIER terms acceptance names; W04 and W09 own different acceptances, which is why one row could not hold this', 'DESCRIBES'),
  ('terms_hash','customer_terms_acceptance',
   'BR-025 judges the digest a CUSTOMER terms acceptance names', 'DESCRIBES'),
  ('terms_hash','supplier_terms_acceptance',
   'BR-025 judges the digest a SUPPLIER terms acceptance names', 'DESCRIBES')
on conflict (context_key, object_id) do nothing;

${SC_L01};

${fi};

${fp};
`;
writeFileSync(OUT + 'phase_d_l01_a_register_that_could_not_tell_naming_from_describing.sql', L01);

// ================================================================================================
// L02 — fn_phase_d_rule_applies (already generated by gen_l02.mjs into the candidate file)
// ================================================================================================
const RA = (await import('node:fs')).readFileSync('scripts/tmp_diag/l01_rule_applies.sql', 'utf8');
const L02 = `-- L02 — a rule that judges the creation of its subject must still be asked at the step that creates it
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, with the fixture scenario withholding the object
-- the workflow under test produces on all 30 workflows.
--
-- K06 gave a rule a WHOLE-WORKFLOW exemption wherever the workflow produces the rule's subject.
-- K07, written the same day for gates, had already recorded why that shape is wrong, and had
-- already written the right one:
--
--     before the producing step  -- every gate. The subject does not exist yet and cannot.
--     AT the producing step      -- only where the test is the PRESENCE of the subject.
--     a MEASURED predicate       -- untouched: it exists to judge the creating step.
--
-- BR-025 is the rule that made the difference visible. Scope W04;W09. W09-S06 is the ONLY step in
-- the estate that produces a supplier terms acceptance, and its own frozen completion condition is
-- "Displayed version, recorded version and document hash match". A whole-workflow exemption of W09
-- therefore leaves no step anywhere asking whether a SUPPLIER acceptance names its exact terms.
-- That is a repeal, not an exemption.
--
-- WHICH OF THE TWO A RULE IS, IS DERIVED. A rule requiring a key that IDENTIFIES its subject is
-- asking the step to name a record, and at the step that creates that record there is nothing to
-- name: BR-018 needs quote_revision_ref, BR-032 needs provider_event_id. A rule whose keys only
-- DESCRIBE the subject is judging the content of what is being written and must be asked exactly
-- there: BR-025 needs terms_version and terms_hash. The distinction is
-- public.phase_d_context_key_object.key_role, added by L01 and read by the same three identity
-- doors in fn_phase_d_step_context.
--
-- AND THE SUBJECT IS A SET, NOT THE FIRST MATCH. \`limit 1\` over one register could not represent
-- a key that is a fact about two objects. Both registers are asked and the whole set is kept.
--
-- MEASURED DELTA against the live body, over all 54 rules x 257 steps (13,878 pairs):
--   lost    0
--   gained  14  BR-018 at W14-S04..S09 (6) and BR-032 at W16-S04..S09 (6), plus BR-025 at
--               W09-S06 and W09-S07..S09 becoming askable rather than exempt.
-- Nothing stops being governed. Under the committed basis the estate is unchanged; with the
-- harness withholding every workflow's own output it moves 248 of 257 to 257 of 257.
--
-- REQUIRES: L01 (key_role).
-- ROLLBACK: re-apply the previous body, scripts/sql/phase_d_k06_a_rule_does_not_govern_the_workflow_that_produces_its_subject.sql
-- GENERATED from the live body by scripts/tmp_diag/gen_l_series.mjs.

${RA};
`;
writeFileSync(OUT + 'phase_d_l02_a_rule_that_judges_the_creation_of_its_subject.sql', L02);

// ================================================================================================
// L03 — the acceptance record stated neither the version nor the digest it accepted
// ================================================================================================
const A4 = `        v_val_txt := null;
      end if;

    elsif v_k = 'source_ref' then`;
must(SC_L01, A4, 'A4');
const SC_L03 = SC_L01.replace(A4, `        v_val_txt := null;
      end if;
      -- L03. AND AT THE STEP THAT RECORDS THE ACCEPTANCE THERE IS NOTHING TO FIND YET.
      -- W09-S06 is the only step in the estate whose declared effect object is a terms acceptance.
      -- Asked to withhold the object the workflow under test produces -- which is what a harness
      -- that does not answer its own question must do -- no acceptance record exists at S06, both
      -- keys fell to the catalogue door, and BR-025 refused with "matches 0 row(s) in
      -- public.legal_documents" for fixture PDF-3104/PDF-3105: a version string and a digest over
      -- a fixture terms body that is not a published document and never can be one.
      -- An acceptance step accepts THE CURRENTLY DISPLAYED DOCUMENT. Which document that is, for
      -- which acceptance object, is registered once in public.phase_d_acceptance_document and read
      -- from public.legal_documents here -- the same relation BR-025 judges against, so the rule
      -- keeps its ability to fail: a step that produces no registered acceptance resolves nothing
      -- here and falls through to the catalogue exactly as before.
      if coalesce(btrim(coalesce(v_val #>> '{}','')),'') = '' then
        select case when v_k = 'terms_version' then d.version
                    else encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex') end
          into v_val_txt
          from public.phase_d_step_effect x
          join public.phase_d_acceptance_document a on a.object_id = x.effect_object_id
          join public.legal_documents d on d.slug = a.document_slug
         where x.step_id = sr.step_id
         order by d.version desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'public.legal_documents — the currently published document this step''s own '
                || 'acceptance object accepts, per public.phase_d_acceptance_document';
        end if;
        v_val_txt := null;
      end if;

    elsif v_k = 'source_ref' then`);

let he = await get('public.fn_phase_d_handler_execute(jsonb)');
const AH = `         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end));`;
must(he, AH, 'AH');
he = he.replace(AH, `         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end
         -- L03. THE VERSION AND THE DIGEST THAT WERE ACCEPTED, FOR A STEP THAT RECORDS AN
         -- ACCEPTANCE. W09-S06's own frozen completion condition is "Displayed version, recorded
         -- version and document hash match", and the record it wrote carried none of the three:
         -- the payload was the workflow_record blob and nothing else. It went unseen because the
         -- fixture scenario built the acceptance itself, with the published pair on it, so every
         -- downstream read found the FIXTURE's record rather than the product's. Withhold that
         -- stage and W09-S07, S08 and S09 refuse on BR-025.
         -- The pair is the step's own resolved context -- the same value BR-025 has just judged at
         -- this step -- so the record states what was accepted and BR-025 can judge it again
         -- downstream. A step whose object is not a registered acceptance adds nothing, and a
         -- context that resolved neither key adds nothing.
         || case when exists (select 1 from public.phase_d_acceptance_document a
                               where a.object_id = ec.effect_object_id)
                 then jsonb_strip_nulls(jsonb_build_object(
                        'terms_version', p_input->'context'->>'terms_version',
                        'terms_hash',    p_input->'context'->>'terms_hash'))
                 else '{}'::jsonb end));`);

const L03 = `-- L03 — the acceptance record stated neither the version nor the digest it accepted
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.
--
-- public.phase_b_workflow_step says W09-S06's required output is "Immutable supplier acceptance
-- record" and its completion condition is "Displayed version, recorded version and document hash
-- match". The record the handler wrote carried a workflow_record blob and nothing else: no version,
-- no digest, nothing to match. Nothing reported it, because public.fn_phase_d_fixture_scenario
-- builds a supplier_terms_acceptance of its own with the published pair on it (F08), and every
-- downstream read found THAT record. The product's defect was covered by the harness's fixture --
-- "a harness that seeds the row the step is supposed to create is answering its own question",
-- one layer further in than where that sentence was first written.
--
-- Two halves, and both are reads:
--
--   1. WHAT THE STEP IS ACCEPTING. With the stage withheld there is no acceptance to read the pair
--      from, and both keys fell through to committed catalogue fixtures PDF-3104 and PDF-3105 --
--      'phase-d-fixture-terms-v1' at the digest of a fixture terms body. BR-025 resolves the pair
--      against public.legal_documents and correctly refused: "matches 0 row(s)". Nothing was wrong
--      with the fixtures; what was wrong is that they were the answer at all, for a key that names
--      the document the platform actually displayed. An acceptance step accepts the CURRENTLY
--      PUBLISHED document, and which document belongs to which acceptance object is registered
--      here once, in public.phase_d_acceptance_document, and read by both this resolver and (from
--      L03 onward) nothing else that guesses.
--
--   2. WHAT THE RECORD SAYS. The handler already closes its payload with the review verdict for a
--      REVIEW_VERDICT effect and with decided_by/decided_at for a DECISION_HANDLER. The accepted
--      version and digest join them, for a step whose effect object is a registered acceptance.
--
-- After both: W09-S01..S09 all EXECUTED with the workflow's own output withheld, the acceptance
-- record carries version v5 and the true digest of the published supplier agreement, and BR-025
-- passes at W09-S06 for a reason it can also fail for.
--
-- REQUIRES: L01 (the identity doors), L04 (the owner of an object-store record).
-- ROLLBACK: scripts/sql/down/phase_d_l03_the_acceptance_record_stated_neither_the_version_nor_the_digest_down.sql
-- GENERATED from the live bodies by scripts/tmp_diag/gen_l_series.mjs.

create table if not exists public.phase_d_acceptance_document (
  object_id     text primary key,
  document_slug text not null,
  why           text not null,
  registered_at timestamptz not null default now()
);
revoke all on public.phase_d_acceptance_document from public;
grant select on public.phase_d_acceptance_document to service_role;

insert into public.phase_d_acceptance_document (object_id, document_slug, why) values
  ('customer_terms_acceptance','customer-terms',
   'W04 records a customer''s acceptance of the published customer terms; public.fn_phase_d_fixture_scenario reads the same slug at F08'),
  ('supplier_terms_acceptance','supplier-agreement',
   'W09-S06 records a supplier''s acceptance of the published supplier agreement; public.fn_phase_d_fixture_scenario reads the same slug at F08')
on conflict (object_id) do nothing;

-- A register that names a document nobody publishes is a constant again.
do $l03$
declare v_bad text;
begin
  select string_agg(a.object_id || ' -> ' || a.document_slug, ', ') into v_bad
    from public.phase_d_acceptance_document a
   where not exists (select 1 from public.legal_documents d where d.slug = a.document_slug);
  if v_bad is not null then
    raise exception 'phase_d_acceptance_document names % which public.legal_documents does not publish', v_bad;
  end if;
end $l03$;

${SC_L03};

${he};
`;
writeFileSync(OUT + 'phase_d_l03_the_acceptance_record_stated_neither_the_version_nor_the_digest.sql', L03);

// ================================================================================================
// L04 — an object the estate stores in its own record table had its owner chosen by position
// ================================================================================================
const DS = (await import('node:fs')).readFileSync('scripts/tmp_diag/l01_dispatch_step.sql', 'utf8');
const L04 = `-- L04 — an object the estate stores in its own record table had its owner chosen by position
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.
--
-- J06 fixed "which scenario record is the owner" by reading the owner column's own FOREIGN KEY out
-- of public.phase_d_object_write_map and taking the key the scenario gave the object bound to the
-- referenced relation. That fix reaches only objects that HAVE a write map. Twenty-two of the 56
-- business objects are PHASE_D_OBJECT_VIEW -- views over public.phase_d_object_record -- and have
-- no write map, no owner column and no foreign key, so every one of them fell straight past J06 to
-- the fallback it was written to replace: "the first scenario record of the same ownership scope".
--
-- With the harness withholding the object the workflow under test produces, W09-S06 wrote the
-- supplier terms acceptance owned by ca99c3de-... -- the supplier_safe_package's uuid, and the
-- first SUPPLIER-scoped scenario record, exactly the shape J06's own comment records. The
-- acceptance therefore belonged to no supplier; "the acceptance this run's party owns" (J05) found
-- nothing at W09-S07, S08 and S09; and BR-025 refused all three from the catalogue.
--
-- THE REGISTRY SAYS WHOSE IT IS. public.phase_d_business_object_binding gives the object's
-- governing workflow, and public.phase_b_workflow gives that workflow's primary object. Where the
-- primary object is a DIFFERENT object of the SAME ownership scope, that object is the party:
-- supplier_terms_acceptance is governed by W09 whose primary object is supplier_account, both
-- SUPPLIER. Nothing is chosen by position. An object that is its own governing workflow's primary
-- object (supplier_safe_package, customer_case, and six more), or whose governing workflow names
-- none (the two registered W16/W27 and W09/W10), resolves nothing here and the fallback still
-- runs, so no object loses an owner it had.
--
-- This block is inside the fixture-context branch and cannot fire in production, where an owner
-- this routine chose would be the auto-vivified account defect one table over.
--
-- ROLLBACK: re-apply the previous body, scripts/sql/phase_d_j06_which_scenario_record_is_the_owner.sql
-- GENERATED from the live body by scripts/tmp_diag/gen_l_series.mjs.

${DS};
`;
writeFileSync(OUT + 'phase_d_l04_an_object_stored_in_the_record_table_had_its_owner_chosen_by_position.sql', L04);

console.log('written: L01 %d, L02 %d, L03 %d, L04 %d', L01.length, L02.length, L03.length, L04.length);
