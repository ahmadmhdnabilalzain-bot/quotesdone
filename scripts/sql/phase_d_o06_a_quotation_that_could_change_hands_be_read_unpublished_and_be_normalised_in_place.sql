-- O06. A QUOTATION THAT COULD CHANGE HANDS, BE READ UNPUBLISHED, AND BE NORMALISED IN PLACE.
--
-- Three cases, one artefact, and the three defects are three different sentences about the same
-- row. Measured on the live estate before any of this was written:
--
--   PD-QUOTE-001  public.fn_phase_d_object_write's PHASE_D_OBJECT_VIEW branch resolves the prior
--                 record with `where object_id = ? and business_key = ? and superseded_by is null`
--                 -- NO OWNER PREDICATE. Driven in an aborted transaction: owner_ref '10' wrote
--                 version 2 superseding owner_ref '1' version 1 on the same business key of a
--                 SUPPLIER-scoped object. Its sibling fn_phase_d_object_read already refuses
--                 exactly this (pd_object_caller_ref_mismatch, "A caller does not get to name whose
--                 records these are"), so the writer is the half of a matched pair that was never
--                 built. On the EXISTING_TABLE branch the column map sets supplier_id = owner_ref,
--                 so the same call REWRITES WHOSE QUOTATION IT IS.
--                 public.quotes has RLS enabled and ZERO policies, which reads as a control on
--                 every board that counts relrowsecurity and enforces nothing.
--
--   PD-QUOTE-004  BR-019 and GATE-018 both evaluate `count(*) from quote_comparisons where
--                 id = ? and customer_id = ?` -- OWNERSHIP, never publication -- and no column
--                 matching publish|visib|reveal exists on quote_comparisons or on quotes. A
--                 customer's own unpublished comparison passes both, so injecting "unpublished"
--                 changes nothing a control could separate. customer_api's quote_pdf action
--                 (line ~973) applies no status filter at all, while its list (line ~836) filters
--                 .neq('status','draft') -- a negative filter that publishes any status a future
--                 writer invents.
--
--   PD-QUOTE-005  BR-018 is `quote_revision_ref is non-empty AND platform_edited = 'false'`. It
--                 compares nothing: it reads the caller's own claim about itself, so a
--                 normalisation that genuinely overwrote the supplier's figure and reported
--                 platform_edited=false would pass. And there was nothing to overwrite -- the only
--                 normalisation in the estate is leadTimeDays() in quote_compare/deterministic.ts,
--                 computed in memory and never persisted.
--
-- THREE GUARDS AND ONE TABLE, and every one of them is on a boundary that already exists.
--
-- WHY TRIGGERS AND NOT A REWRITE OF fn_phase_d_object_write. That routine is 28,375 bytes and is
-- the canonical write service for all 56 objects; splicing an owner check into the middle of it
-- risks every other object to fix two. The facts the check needs are visible at the table: on
-- public.phase_d_object_record the prior live record's owner_ref, and on public.quotes the row's
-- OLD.supplier_id. A trigger sees the row's CURRENT owner, which is the one thing a payload cannot
-- lie about -- checking the payload against itself is how the scout found BR-018 already failing.

-- ---------------------------------------------------------------------------------------------
-- 1. PD-QUOTE-001 — A RECORD DOES NOT CHANGE HANDS.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_object_owner_is_stable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_scope text; v_prior text;
begin
  select b.ownership_scope into v_scope
    from public.phase_d_business_object_binding b where b.object_id = NEW.object_id;
  -- COMPANY-scoped objects are owned by the company; only a tenant scope has a foreign owner to be
  -- crossed. Stated rather than left implicit, because widening this to COMPANY would refuse the
  -- estate's own bookkeeping.
  if coalesce(v_scope,'') not in ('CUSTOMER','SUPPLIER') then return NEW; end if;

  select o.owner_ref into v_prior
    from public.phase_d_object_record o
   where o.object_id = NEW.object_id and o.business_key = NEW.business_key
     and o.superseded_by is null and o.record_id is distinct from NEW.record_id
   order by o.record_id desc limit 1;

  if v_prior is not null and v_prior is distinct from NEW.owner_ref then
    raise exception 'phase_d_object_record: %/% is owned by %, and this write names owner %. A %-scoped record does not change hands, and a caller does not get to name whose records these are. (pd_object_cross_owner_write)',
      NEW.object_id, NEW.business_key, v_prior, coalesce(NEW.owner_ref,'(none)'), v_scope
      using errcode = '23514';
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_object_owner_is_stable() FROM PUBLIC;

DROP TRIGGER IF EXISTS a30_phase_d_object_owner_is_stable ON public.phase_d_object_record;
CREATE TRIGGER a30_phase_d_object_owner_is_stable
  BEFORE INSERT OR UPDATE ON public.phase_d_object_record
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_d_object_owner_is_stable();

-- The same sentence on the marketplace table the `quotation` object writes through. Here the fact
-- is even plainer: OLD.supplier_id is who owns it and NEW.supplier_id is who the caller says owns
-- it, and a quotation does not move between suppliers for any reason.
CREATE OR REPLACE FUNCTION public.fn_quote_supplier_is_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.supplier_id is not distinct from OLD.supplier_id then return NEW; end if;
  raise exception 'quotes %: this quotation belongs to supplier % and the write names supplier %. A quotation does not change hands; a correction is a new revision by its own author. (pd_object_cross_owner_write)',
    OLD.id, OLD.supplier_id, coalesce(NEW.supplier_id::text,'(none)') using errcode = '23514';
end $function$;

REVOKE ALL ON FUNCTION public.fn_quote_supplier_is_immutable() FROM PUBLIC;

DROP TRIGGER IF EXISTS a30_quote_supplier_is_immutable ON public.quotes;
CREATE TRIGGER a30_quote_supplier_is_immutable
  BEFORE UPDATE ON public.quotes
  FOR EACH ROW EXECUTE FUNCTION public.fn_quote_supplier_is_immutable();

-- ---------------------------------------------------------------------------------------------
-- 2. PD-QUOTE-004 — PUBLICATION IS A STATE, NOT THE ABSENCE OF THE WORD 'draft'.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.quote_comparisons
  ADD COLUMN IF NOT EXISTS publication_state text NOT NULL DEFAULT 'DRAFT',
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS superseded_by_comparison_id bigint;

-- quote_comparisons.id is BIGINT, not uuid. Corrected here rather than in a follow-up file so the
-- column and the key it points at can never be read as two different types by two different files.
ALTER TABLE public.quote_comparisons
  ALTER COLUMN superseded_by_comparison_id TYPE bigint USING NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.quote_comparisons'::regclass
                    AND conname = 'quote_comparisons_publication_state_ck') THEN
    ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_publication_state_ck
      CHECK (publication_state IN ('DRAFT','SUBMITTED','UNDER_REVIEW','REVISION_REQUIRED',
                                   'APPROVED','PUBLISHED','WITHDRAWN','SUPERSEDED'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.quote_comparisons'::regclass
                    AND conname = 'quote_comparisons_published_is_stamped') THEN
    -- A PUBLISHED row with no published_at is a claim with no moment attached, and the customer
    -- read below would honour it. Refused at write time instead.
    ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_published_is_stamped
      CHECK (publication_state <> 'PUBLISHED' OR published_at IS NOT NULL);
  END IF;
END $$;

COMMENT ON COLUMN public.quote_comparisons.publication_state IS
  'O06. The publication contract a customer read is filtered on. DRAFT is the default, so a row '
  'written by any path that does not know about publication is invisible to a customer rather '
  'than visible -- absence fails closed.';

-- The predicate both BR-019 and GATE-018 consult, and the one a customer-facing read must call.
-- It answers ONE question -- may THIS caller see THIS comparison -- and says which of the two
-- reasons it refused for, because "not yours" and "not published yet" have different remedies.
CREATE OR REPLACE FUNCTION public.fn_phase_d_comparison_visible(
  p_comparison_id text, p_caller_customer_id text, p_caller_kind text DEFAULT 'customer')
 RETURNS TABLE(visible boolean, refusal_code text, reason text, publication_state text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.quote_comparisons%rowtype; v_kind text := lower(coalesce(btrim(p_caller_kind),'customer'));
begin
  if coalesce(btrim(p_comparison_id),'') = '' then
    visible := false; refusal_code := 'pd_comparison_not_named';
    reason := 'No comparison named.'; return next; return;
  end if;
  select * into c from public.quote_comparisons where id::text = btrim(p_comparison_id);
  if not found then
    visible := false; refusal_code := 'pd_comparison_not_named';
    reason := format('%L is not a comparison.', p_comparison_id); return next; return;
  end if;
  publication_state := c.publication_state;

  -- OWNERSHIP FIRST, AND IT IS NEVER SKIPPED FOR ANY CALLER KIND EXCEPT admin. An unrelated
  -- customer must be refused on a PUBLISHED comparison too, which is the arm that proves the
  -- publication leg did not replace the ownership leg.
  if v_kind <> 'admin'
     and c.customer_id::text is distinct from nullif(btrim(coalesce(p_caller_customer_id,'')),'') then
    visible := false; refusal_code := 'pd_comparison_not_the_owner';
    reason := format('comparison %s does not belong to the calling customer', c.id);
    return next; return;
  end if;

  -- The owning SUPPLIER-side and admin callers may read a comparison before publication; a
  -- customer may not. That is the whole of PD-QUOTE-004.
  if v_kind in ('admin','owner_supplier') then
    visible := true; refusal_code := null;
    reason := format('comparison %s read as %s: publication state %s is readable by this caller kind',
                     c.id, v_kind, c.publication_state);
    return next; return;
  end if;

  if c.publication_state <> 'PUBLISHED' then
    visible := false; refusal_code := 'pd_comparison_unpublished';
    reason := format('comparison %s is %s. A customer sees a comparison when it is published, not when it exists.',
                     c.id, c.publication_state);
    return next; return;
  end if;
  if c.superseded_by_comparison_id is not null then
    visible := false; refusal_code := 'pd_comparison_superseded';
    reason := format('comparison %s was superseded by %s', c.id, c.superseded_by_comparison_id);
    return next; return;
  end if;

  visible := true; refusal_code := null;
  reason := format('comparison %s belongs to the calling customer and was published at %s',
                   c.id, c.published_at);
  return next;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_comparison_visible(text, text, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- 3. PD-QUOTE-005 — NORMALISATION IS A SEPARATE RECORD OR IT IS AN EDIT.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.phase_d_quote_normalisation (
  normalisation_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_quote_ref      text NOT NULL,
  source_revision_ref   text NOT NULL,
  source_payload_sha256 text NOT NULL,
  schema_version        text NOT NULL,
  normalised            jsonb NOT NULL,
  transformation        jsonb NOT NULL,
  actor_role_id         text NOT NULL,
  capability_ref        text,
  trace_id              bigint,
  superseded_by         bigint REFERENCES public.phase_d_quote_normalisation(normalisation_id),
  supersession_reason   text,
  recorded_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_quote_normalisation_sha_ck CHECK (source_payload_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT phase_d_quote_normalisation_supersession_ck
    CHECK ((superseded_by IS NULL) = (COALESCE(supersession_reason,'') = '')),
  -- REPLAY MAKES NO DUPLICATE. The same revision at the same bytes under the same schema version is
  -- one normalisation, so a second identical run is an upsert and never a second row.
  CONSTRAINT phase_d_quote_normalisation_replay_uk
    UNIQUE (source_revision_ref, source_payload_sha256, schema_version)
);

COMMENT ON TABLE public.phase_d_quote_normalisation IS
  'O06. The derived comparison representation. It references the supplier revision and its exact '
  'payload digest and never writes to it: fn_phase_d_quote_original_intact re-reads the revision '
  'and refuses a normalisation whose stated source no longer hashes to what it claims.';

ALTER TABLE public.phase_d_quote_normalisation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_quote_normalisation FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_quote_normalisation TO service_role;

-- THE FIELDS A NORMALISATION MAY NEVER CLAIM TO HAVE CHANGED. This is a register rather than a
-- literal in a predicate, so extending it does not mean redeploying the check.
CREATE TABLE IF NOT EXISTS public.phase_d_supplier_authored_field (
  field_key   text PRIMARY KEY,
  description text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.phase_d_supplier_authored_field ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_supplier_authored_field FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_supplier_authored_field TO service_role;

INSERT INTO public.phase_d_supplier_authored_field (field_key, description) VALUES
  ('quote_amount',     'The amount the supplier quoted, in the currency they quoted it in.'),
  ('currency',         'The currency the supplier quoted in.'),
  ('commercial_terms', 'Payment and commercial terms as the supplier wrote them.'),
  ('payment_terms',    'Payment terms as the supplier wrote them.'),
  ('lead_time',        'Lead time as the supplier stated it.'),
  ('notes',            'The supplier''s own notes.'),
  ('scope',            'Scope as the supplier described it.'),
  ('evidence',         'Evidence the supplier attached.')
ON CONFLICT (field_key) DO NOTHING;

-- A normalisation may not carry a supplier-authored key at the top level of `normalised`: that is
-- what "the platform may normalise for comparison but never alter the original" means in a row.
-- Normalised values live under their own names (normalised_amount_aed, normalised_lead_time_days),
-- and the mapping from one to the other lives in `transformation`, where it can be read.
CREATE OR REPLACE FUNCTION public.fn_phase_d_normalisation_does_not_restate_the_original()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_bad text[];
begin
  select array_agg(f.field_key order by f.field_key) into v_bad
    from public.phase_d_supplier_authored_field f
   where NEW.normalised ? f.field_key;
  if v_bad is not null then
    raise exception 'phase_d_quote_normalisation: the normalised projection restates supplier-authored field(s) [%]. A derived record references the original; it does not republish it under the same name. (pd_normalisation_restates_original)',
      array_to_string(v_bad, ', ') using errcode = '23514';
  end if;
  if not (NEW.transformation ? 'source_fields') then
    raise exception 'phase_d_quote_normalisation: transformation must name source_fields -- which original values this projection was derived from. A derived value whose derivation nobody recorded is a new number. (pd_normalisation_transformation_absent)'
      using errcode = '23514';
  end if;
  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_normalisation_does_not_restate_the_original() FROM PUBLIC;

DROP TRIGGER IF EXISTS a10_phase_d_normalisation_shape ON public.phase_d_quote_normalisation;
CREATE TRIGGER a10_phase_d_normalisation_shape
  BEFORE INSERT OR UPDATE ON public.phase_d_quote_normalisation
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_d_normalisation_does_not_restate_the_original();

-- The predicate BR-018 consults. It COMPARES TWO RECORDS -- the normalisation's stated source
-- digest against the live revision payload -- instead of reading a platform_edited flag the caller
-- set about itself.
CREATE OR REPLACE FUNCTION public.fn_phase_d_quote_original_intact(p_revision_ref text)
 RETURNS TABLE(intact boolean, refusal_code text, reason text, normalisations bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_live text; v_n bigint; v_bad bigint;
begin
  if coalesce(btrim(p_revision_ref),'') = '' then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := 'No supplier revision named. Nothing can be certified unedited against nothing.';
    normalisations := 0; return next; return;
  end if;

  select encode(extensions.digest(convert_to(o.payload::text, 'UTF8'), 'sha256'), 'hex')
    into v_live
    from public.phase_d_object_record o
   where o.object_id = 'quotation_revision' and o.business_key = btrim(p_revision_ref)
     and o.superseded_by is null
   order by o.record_id desc limit 1;

  if v_live is null then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := format('%L is not a live quotation_revision record.', p_revision_ref);
    normalisations := 0; return next; return;
  end if;

  select count(*), count(*) filter (where n.source_payload_sha256 is distinct from v_live)
    into v_n, v_bad
    from public.phase_d_quote_normalisation n
   where n.source_revision_ref = btrim(p_revision_ref) and n.superseded_by is null;
  normalisations := v_n;

  if v_bad > 0 then
    intact := false; refusal_code := 'pd_quote_original_overwritten';
    reason := format('%s of %s live normalisation(s) of %s were derived from a payload that hashes to something other than the revision''s current %s. Either the original was edited after normalisation, or the projection is describing a revision that no longer exists.',
                     v_bad, v_n, p_revision_ref, left(v_live, 12));
    return next; return;
  end if;

  intact := true; refusal_code := null;
  reason := format('%s is unedited at %s and carries %s live normalised projection(s), none of which restates a supplier-authored field.',
                   p_revision_ref, left(v_live, 12), v_n);
  return next;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_quote_original_intact(text) FROM PUBLIC;
