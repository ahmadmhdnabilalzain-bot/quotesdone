-- O04. A SUPPLIER-FACING FILE REVISION WITH NO REDACTION STATE, AND NO SCANNER OVER ITS BYTES.
--
-- PD-PRIV-002 and PD-PRIV-005 are one artefact lifecycle and are built together: a file revision
-- that goes to a supplier must carry a redaction verdict AND a hidden-metadata verdict, both
-- keyed to the exact bytes that are dispatched, or neither means anything.
--
-- WHAT WAS MEASURED BEFORE BUILDING, on the live estate:
--
--   public.drawing_redaction_runs   holds pipeline OUTCOMES written by TypeScript -- 'empty',
--                                   'detect_truncated', 'detect_failed', 'detect_exception',
--                                   'failed', 'partial', 'complete', 'original_stored'. Not one of
--                                   them is an APPROVAL by an accountable reviewer, and
--                                   pages_verified/verify_failed are a vision model's own opinion
--                                   of its own work -- in this estate a vision model has already
--                                   listed eight identifiers verbatim off a solid black rectangle.
--                                   ZERO pg_proc bodies reference the table, so no predicate,
--                                   trigger or board can read it.
--   public.doc_versions.checksum    md5(NEW.extracted::text) -- a hash of extracted JSON, not of
--                                   the stored object. public.documents has no hash column at all.
--                                   So "the dispatched file is the approved revision" could be
--                                   claimed and never asserted.
--   BR-012                          counts an approved supplier_safe_package record and resolves
--                                   the approver string. It never opens the payload, so a package
--                                   with an unredacted drawing and one with a clean drawing get
--                                   the identical ENFORCED_PASS. That identical answer IS the
--                                   defect PD-PRIV-002 names.
--   GATE-013                        tests reviewer independence and never dereferences
--                                   safe_package_ref at all -- the value is used only inside
--                                   format() for the reason string.
--   BR-011                          MEASURED LIVE: the payload
--                                   '/Author (Omar Bin Faisal) /Creator (AL NAHDA CONSULTANTS)'
--                                   returns ok=TRUE, ENFORCED_PASS. Its row arm searches
--                                   public.customers (0 rows) and its shape arm tests only an
--                                   email regex and a UAE mobile. The exact injection PD-PRIV-005
--                                   names -- a customer's NAME in a PDF /Info dictionary -- passes
--                                   the one rule that names it. That is a real hole and O07 closes
--                                   it against the register this file creates.
--   sanitizeUpload (attachment.ts)  strips JPEG APPn/COM and PNG ancillary chunks, returns only
--                                   strippedMetadata: boolean, never the values, and has NO PDF
--                                   branch. All 14 call sites are INBOUND ingestion. Zero
--                                   supplier-facing renders call it.
--
-- WHERE THE BYTES ARE. Postgres in this estate never receives file bytes: the only bytea columns in
-- public are pages._osb and phase_d_fixture_secret.secret. A metadata scan must therefore run where
-- bytes exist and RECORD its verdict here -- which is exactly how the section 8 HTTP probes already
-- work. scripts/phase_d/run_metadata_scan_probe.mjs is that runner; it uses pdf-lib, already a
-- dependency of supabase/functions/doc_render, make_pdf and pdf_native, and adds nothing new.
--
-- FAIL CLOSED IS THE DEFAULT AND IT IS A COLUMN, NOT A CONVENTION. A revision with no scan row, or
-- with a scan row whose outcome is SCAN_FAILED or UNSUPPORTED, is NOT dispatchable. The estate has
-- been caught by "error and empty returning the same value" before; here they are different
-- outcomes and both refuse.

-- ---------------------------------------------------------------------------------------------
-- 1. THE REGISTERED PERSONAL-IDENTIFIER CLASSES. Today the de facto list is three columns of
--    public.customers hard-coded inside one branch of fn_phase_d_rule_check. A list that lives in
--    a predicate cannot be extended without redeploying the predicate, and cannot be audited at all.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_personal_identifier_class (
  identifier_class text PRIMARY KEY,
  description      text NOT NULL,
  detection        text NOT NULL,
  pattern          text,
  supplier_facing_allowed boolean NOT NULL DEFAULT false,
  recorded_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_pic_detection_ck CHECK (detection IN ('REGEX','ROW_MATCH','HUMAN_REVIEW')),
  CONSTRAINT phase_d_pic_pattern_ck CHECK ((detection = 'REGEX') = (COALESCE(pattern,'') <> ''))
);

COMMENT ON TABLE public.phase_d_personal_identifier_class IS
  'O04. What counts as a personal identifier in a supplier-facing artefact. Read by BR-011 in '
  'fn_phase_d_rule_check and by scripts/phase_d/run_metadata_scan_probe.mjs, so the rule and the '
  'scanner cannot disagree about the list.';

ALTER TABLE public.phase_d_personal_identifier_class ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_personal_identifier_class FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_personal_identifier_class TO service_role;

INSERT INTO public.phase_d_personal_identifier_class
  (identifier_class, description, detection, pattern, supplier_facing_allowed)
VALUES
  ('customer_email',      'An email address of any form.', 'REGEX',
   '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}', false),
  ('customer_phone_ae',   'A dialable UAE mobile, with or without separators.', 'REGEX',
   '(971|0)5[0-9]{8}', false),
  ('customer_phone_intl', 'An international dialing prefix followed by 8 or more digits.', 'REGEX',
   '[+][0-9]{1,3}[ -]?[0-9]{8,}', false),
  ('messenger_handle',    'A WhatsApp/Telegram/Skype handle or a wa.me link.', 'REGEX',
   '(wa[.]me/|t[.]me/|skype:|whatsapp[: ]|telegram[: ])', false),
  ('embedded_url',        'Any http or https URL, which can carry identity in its path or query.', 'REGEX',
   'https?://[^\s)>"]+', false),
  ('filesystem_username', 'A Windows or POSIX home-directory path, which names the person who made the file.', 'REGEX',
   '([A-Za-z]:\\Users\\[^\\ ]+|/(home|Users)/[^/ ]+)', false),
  ('customer_full_name',  'The full name of a customer recorded in this estate.', 'ROW_MATCH', NULL, false),
  ('customer_company',    'The company name of a customer recorded in this estate.', 'ROW_MATCH', NULL, false),
  ('site_address',        'A plot, villa or street address identifying the customer site.', 'HUMAN_REVIEW', NULL, false),
  ('person_name_freeform','A personal name that is not yet a row in this estate. Regex cannot decide '
                        ||'a name, so this class is decided by the accountable privacy reviewer and '
                        ||'never scored automatically as absent.', 'HUMAN_REVIEW', NULL, false)
ON CONFLICT (identifier_class) DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- 2. THE FILE REVISION CONTRACT. One row per supplier-facing revision.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_file_revision (
  revision_ref          text PRIMARY KEY,
  package_ref           text NOT NULL,
  source_revision_ref   text,
  file_name             text NOT NULL,
  media_type            text NOT NULL,
  source_sha256         text NOT NULL,
  safe_sha256           text,
  redaction_state       text NOT NULL,
  redaction_method      text,
  elements_removed      jsonb NOT NULL DEFAULT '[]'::jsonb,
  reviewer_role_id      text,
  reviewer_verdict      text,
  reviewed_at           timestamptz,
  authored_by_role_id   text NOT NULL,
  trace_id              bigint,
  superseded_by         text REFERENCES public.phase_d_file_revision(revision_ref),
  supersession_reason   text,
  recorded_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_file_revision_state_ck
    CHECK (redaction_state IN ('NOT_REQUIRED','PENDING','REVIEW_REQUIRED','APPROVED','REJECTED','SUPERSEDED')),
  CONSTRAINT phase_d_file_revision_verdict_ck
    CHECK (reviewer_verdict IS NULL OR reviewer_verdict IN ('approved','rejected','changes_requested')),
  -- An APPROVED revision must name who approved it, when, what they approved (safe_sha256) and how
  -- it was produced. An approval that names none of those is a word, not a verdict.
  CONSTRAINT phase_d_file_revision_approved_is_complete
    CHECK (redaction_state <> 'APPROVED' OR (
      COALESCE(reviewer_role_id,'') <> '' AND reviewer_verdict = 'approved'
      AND reviewed_at IS NOT NULL AND COALESCE(safe_sha256,'') <> ''
      AND COALESCE(redaction_method,'') <> '')),
  CONSTRAINT phase_d_file_revision_not_required_is_complete
    CHECK (redaction_state <> 'NOT_REQUIRED' OR COALESCE(safe_sha256,'') <> ''),
  CONSTRAINT phase_d_file_revision_sha_ck
    CHECK (source_sha256 ~ '^[0-9a-f]{64}$' AND (safe_sha256 IS NULL OR safe_sha256 ~ '^[0-9a-f]{64}$')),
  CONSTRAINT phase_d_file_revision_supersession_ck
    CHECK ((superseded_by IS NULL) = (COALESCE(supersession_reason,'') = '')),
  CONSTRAINT phase_d_file_revision_not_self_superseding
    CHECK (superseded_by IS DISTINCT FROM revision_ref)
);

COMMENT ON TABLE public.phase_d_file_revision IS
  'O04. The redaction and dispatch contract for one supplier-facing file revision. safe_sha256 is '
  'the digest of the bytes that may be dispatched; a dispatch naming a different digest is refused '
  'by fn_phase_d_file_revision_dispatchable, which BR-012 consults.';

ALTER TABLE public.phase_d_file_revision ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_file_revision FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_file_revision TO service_role;

CREATE INDEX IF NOT EXISTS phase_d_file_revision_package_idx
  ON public.phase_d_file_revision (package_ref) WHERE superseded_by IS NULL;

-- THE AUTHOR MAY NOT BE THE REVIEWER. The same rule that holds for a task holds for the artefact,
-- and it resolves both identities rather than comparing two strings.
CREATE OR REPLACE FUNCTION public.fn_phase_d_file_revision_reviewer_independent()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(NEW.reviewer_role_id,'') = '' then return NEW; end if;
  if not public.fn_kernel_reviewer_independent(NEW.authored_by_role_id, NEW.reviewer_role_id) then
    raise exception 'phase_d_file_revision %: reviewer % resolves to the same employee as the author %. A self-review is not a review. (pd_creator_reviewer_collision)',
      NEW.revision_ref, NEW.reviewer_role_id, NEW.authored_by_role_id using errcode = '23514';
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_file_revision_reviewer_independent() FROM PUBLIC;

DROP TRIGGER IF EXISTS a10_phase_d_file_revision_reviewer ON public.phase_d_file_revision;
CREATE TRIGGER a10_phase_d_file_revision_reviewer
  BEFORE INSERT OR UPDATE ON public.phase_d_file_revision
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_d_file_revision_reviewer_independent();

-- ---------------------------------------------------------------------------------------------
-- 3. THE METADATA SCAN. One row per (revision, scanner run). The scan happens where the bytes are;
--    this is where its verdict lands so a predicate can read it.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_metadata_scan (
  scan_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  revision_ref      text NOT NULL REFERENCES public.phase_d_file_revision(revision_ref),
  scanned_sha256    text NOT NULL,
  scanner           text NOT NULL,
  scanner_version   text NOT NULL,
  classes_inspected text[] NOT NULL,
  outcome           text NOT NULL,
  findings          jsonb NOT NULL DEFAULT '[]'::jsonb,
  detail            text,
  scanned_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_metadata_scan_outcome_ck
    CHECK (outcome IN ('CLEAN','IDENTIFIERS_FOUND','SCAN_FAILED','UNSUPPORTED')),
  CONSTRAINT phase_d_metadata_scan_sha_ck CHECK (scanned_sha256 ~ '^[0-9a-f]{64}$'),
  -- A CLEAN verdict with findings in it, or an IDENTIFIERS_FOUND verdict with none, is a scanner
  -- contradicting itself and is refused at write time rather than believed at read time.
  CONSTRAINT phase_d_metadata_scan_findings_agree_with_outcome
    CHECK ((outcome = 'IDENTIFIERS_FOUND') = (jsonb_array_length(findings) > 0)),
  CONSTRAINT phase_d_metadata_scan_classes_named CHECK (cardinality(classes_inspected) > 0)
);

COMMENT ON TABLE public.phase_d_metadata_scan IS
  'O04. The hidden-metadata verdict over the exact bytes named by scanned_sha256. A revision whose '
  'safe_sha256 has no CLEAN scan is not dispatchable; SCAN_FAILED and UNSUPPORTED refuse too, so a '
  'scanner that could not read is never mistaken for a scanner that found nothing.';

ALTER TABLE public.phase_d_metadata_scan ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_metadata_scan FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_metadata_scan TO service_role;

CREATE UNIQUE INDEX IF NOT EXISTS phase_d_metadata_scan_one_per_digest_uk
  ON public.phase_d_metadata_scan (revision_ref, scanned_sha256, scanner, scanner_version);

-- ---------------------------------------------------------------------------------------------
-- 4. THE PREDICATE BOTH GUARDS READ.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_file_revision_dispatchable(
  p_revision_ref text, p_dispatch_sha256 text DEFAULT NULL)
 RETURNS TABLE(dispatchable boolean, refusal_code text, reason text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.phase_d_file_revision%rowtype; s public.phase_d_metadata_scan%rowtype;
begin
  if coalesce(btrim(p_revision_ref),'') = '' then
    dispatchable := false; refusal_code := 'pd_revision_redaction_state_absent';
    reason := 'No file revision named. A file nobody identified cannot be certified safe to send.';
    return next; return;
  end if;
  select * into r from public.phase_d_file_revision where revision_ref = btrim(p_revision_ref);
  if not found then
    dispatchable := false; refusal_code := 'pd_revision_redaction_state_absent';
    reason := format('%L is not a registered supplier-facing file revision.', p_revision_ref);
    return next; return;
  end if;

  if r.superseded_by is not null or r.redaction_state = 'SUPERSEDED' then
    dispatchable := false; refusal_code := 'pd_revision_superseded';
    reason := format('%s was superseded by %s: %s', r.revision_ref,
                     coalesce(r.superseded_by,'(unnamed)'), coalesce(r.supersession_reason,''));
    return next; return;
  end if;

  if r.redaction_state in ('PENDING','REVIEW_REQUIRED') then
    dispatchable := false; refusal_code := 'pd_revision_redaction_unapproved';
    reason := format('%s is %s. A revision whose redaction has not been approved may not reach a supplier.',
                     r.revision_ref, r.redaction_state);
    return next; return;
  end if;
  if r.redaction_state = 'REJECTED' then
    dispatchable := false; refusal_code := 'pd_revision_redaction_rejected';
    reason := format('%s was rejected by %s. It may not reach a supplier and it may not be re-offered unchanged.',
                     r.revision_ref, coalesce(r.reviewer_role_id,'(unnamed)'));
    return next; return;
  end if;

  -- THE DIGEST IS THE POINT. An approval is an approval OF BYTES, so a dispatch naming different
  -- bytes is not covered by it however green the state word looks.
  if p_dispatch_sha256 is not null and lower(btrim(p_dispatch_sha256)) <> coalesce(r.safe_sha256,'') then
    dispatchable := false; refusal_code := 'pd_revision_digest_mismatch';
    reason := format('%s is approved at %s and the dispatch names %s. The approval is of bytes, not of a file name.',
                     r.revision_ref, left(coalesce(r.safe_sha256,'(none)'),12),
                     left(lower(btrim(p_dispatch_sha256)),12));
    return next; return;
  end if;

  -- THE METADATA SCAN, over the SAFE digest and nothing else.
  select * into s from public.phase_d_metadata_scan
   where revision_ref = r.revision_ref and scanned_sha256 = r.safe_sha256
   order by scan_id desc limit 1;
  if not found then
    dispatchable := false; refusal_code := 'pd_metadata_scan_absent';
    reason := format('%s carries no hidden-metadata scan over its approved bytes %s. Fail closed: an unscanned file is not a clean file.',
                     r.revision_ref, left(coalesce(r.safe_sha256,'(none)'),12));
    return next; return;
  end if;
  if s.outcome in ('SCAN_FAILED','UNSUPPORTED') then
    dispatchable := false; refusal_code := 'pd_metadata_scan_failed_closed';
    reason := format('%s: the scanner reported %s (%s). A scan that could not read is not a scan that found nothing.',
                     r.revision_ref, s.outcome, coalesce(s.detail,'no detail'));
    return next; return;
  end if;
  if s.outcome = 'IDENTIFIERS_FOUND' then
    dispatchable := false; refusal_code := 'pd_hidden_metadata_identifier_found';
    reason := format('%s carries %s hidden-metadata identifier(s) of class(es) %s.',
                     r.revision_ref, jsonb_array_length(s.findings),
                     (select string_agg(distinct f->>'identifier_class', ', ')
                        from jsonb_array_elements(s.findings) f));
    return next; return;
  end if;

  dispatchable := true; refusal_code := null;
  reason := format('%s: redaction %s by %s at %s, method %s, safe digest %s, metadata scan CLEAN over %s classes by %s %s.',
                   r.revision_ref, r.redaction_state, coalesce(r.reviewer_role_id,'(not required)'),
                   coalesce(r.reviewed_at::text,'(n/a)'), coalesce(r.redaction_method,'(n/a)'),
                   left(r.safe_sha256,12), cardinality(s.classes_inspected), s.scanner, s.scanner_version);
  return next;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_file_revision_dispatchable(text, text) FROM PUBLIC;

-- Every revision of a package must be dispatchable for the package to be. One bad revision in a set
-- is a leak, so the package answer is the WORST revision answer, never an average or a majority.
CREATE OR REPLACE FUNCTION public.fn_phase_d_package_revisions_dispatchable(p_package_ref text)
 RETURNS TABLE(dispatchable boolean, refusal_code text, reason text, revisions bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_bad record; v_n bigint := 0;
begin
  for r in select fr.revision_ref from public.phase_d_file_revision fr
            where fr.package_ref = btrim(coalesce(p_package_ref,'')) and fr.superseded_by is null
            order by fr.revision_ref loop
    v_n := v_n + 1;
    select * into v_bad from public.fn_phase_d_file_revision_dispatchable(r.revision_ref);
    if not v_bad.dispatchable then
      dispatchable := false; refusal_code := v_bad.refusal_code; reason := v_bad.reason;
      revisions := v_n; return next; return;
    end if;
  end loop;
  revisions := v_n;
  if v_n = 0 then
    -- A PACKAGE THAT NAMES NO FILE IS NOT A CLEAN PACKAGE. Zero here would otherwise be the shape
    -- this estate has been caught by twice: an absent input scoring as satisfied.
    dispatchable := false; refusal_code := 'pd_revision_redaction_state_absent';
    reason := format('package %s names no registered file revision. An empty file set is not an approved one.',
                     p_package_ref);
    return next; return;
  end if;
  dispatchable := true; refusal_code := null;
  reason := format('package %s: all %s live revision(s) are redaction-approved and metadata-clean.',
                   p_package_ref, v_n);
  return next;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_package_revisions_dispatchable(text) FROM PUBLIC;
