-- O03. A LEGAL OR TAX AUTHORITY THAT NOTHING IN THIS ESTATE COULD CALL STALE.
--
-- PD-LEGAL-004 asks whether a current tax or legal position can be asserted from a static file that
-- has expired. Measured across the whole estate before building anything:
--
--   public.compliance_sources      17 rows, all UAE building/fire/electrical/telecom/health codes.
--                                  Zero tax authorities. Zero legal-interpretation authorities.
--   public.legal_documents         12 rows, all OUR OWN published policies and agreements.
--   public.reg_catalog / regulations  38 / 17 rows, technical codes.
--   public.ops_knowledge           8,256 rows, every one source_authority 'quotesdone_delivery'
--                                  or null -- that is us citing ourselves.
--
-- And no predicate anywhere judges any of them stale. Four routines compare a date to now()
-- (fn_knowledge_freshness_sweep, fn_knowledge_decay, fn_legal_ai's policies_stale subquery,
-- fn_regulation_watch) and every one of them SETS A COLUMN or RAISES A FLAG. None refuses anything.
-- BR-025 reads legal_documents for version and hash equality and never for currency.
--
-- So the control did not exist, and the case was right to be NOT_RUN. This file builds it.
--
-- WHAT PHASE D OWNS HERE AND WHAT IT DOES NOT. Phase D does not supply the legal interpretation --
-- that is Phase E's professional work, and the capability boundary already refuses it:
-- fn_phase_d_handler_execute raises pd_capability_unavailable (23514) for W28-S03, W28-S04, W28-S06
-- and W17-S05 because those steps declare capability_dependency REASONING and
-- public.phase_d_capability_result holds no answer. Phase D owns the question ONE LEVEL DOWN:
-- IS THE EVIDENCE CURRENT AND AUTHORITATIVE ENOUGH TO SUPPORT AN INTERPRETATION AT ALL. That is a
-- deterministic date-and-classification test, it needs no model, and it costs nothing.
--
-- THE FIXTURES ARE COMMITTED BY THIS MIGRATION, NOT BY THE PROBE. A probe that creates the stale
-- source and then asks whether the stale source is refused has answered its own question. The two
-- rows below differ in EXACTLY ONE respect -- review_by -- so the arm that separates them is the
-- freshness predicate and nothing else. They carry the estate's own demo convention (ZZ DEMO,
-- example.invalid) so no reader can mistake either for a real authority.

CREATE TABLE IF NOT EXISTS public.phase_d_legal_source (
  source_id            text PRIMARY KEY,
  jurisdiction         text NOT NULL,
  subject              text NOT NULL,
  source_type          text NOT NULL,
  authority_tier       text NOT NULL,
  authority_name       text NOT NULL,
  source_reference     text NOT NULL,
  content_sha256       text NOT NULL,
  published_on         date,
  effective_from       date,
  retrieved_at         timestamptz NOT NULL,
  review_by            date,
  freshness_policy     text NOT NULL DEFAULT 'REVIEW_BY_DATE',
  superseded_by        text REFERENCES public.phase_d_legal_source(source_id),
  supersession_reason  text,
  evidence_owner       text NOT NULL,
  reviewer_role_id     text,
  trace_id             bigint,
  note                 text,
  recorded_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT phase_d_legal_source_tier_ck
    CHECK (authority_tier IN ('AUTHORITATIVE_PRIMARY','AUTHORITATIVE_SECONDARY','NON_AUTHORITATIVE')),
  CONSTRAINT phase_d_legal_source_type_ck
    CHECK (source_type IN ('STATUTE','REGULATION','TAX_AUTHORITY_GUIDANCE','CASE_LAW',
                           'REGULATOR_CIRCULAR','PROFESSIONAL_OPINION','SECONDARY_COMMENTARY',
                           'INTERNAL_POLICY')),
  CONSTRAINT phase_d_legal_source_policy_ck
    CHECK (freshness_policy IN ('REVIEW_BY_DATE','NEVER_EXPIRES')),
  -- A source with no review_by under REVIEW_BY_DATE is exactly the "missing source date" case the
  -- predicate must BLOCK, so it is admitted into the table and refused by the predicate. It is not
  -- refused here: a registry that cannot hold the bad case cannot be used to test the control.
  CONSTRAINT phase_d_legal_source_supersession_ck
    CHECK ((superseded_by IS NULL) = (COALESCE(supersession_reason,'') = '')),
  CONSTRAINT phase_d_legal_source_sha_ck
    CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT phase_d_legal_source_not_self_superseding
    CHECK (superseded_by IS DISTINCT FROM source_id)
);

COMMENT ON TABLE public.phase_d_legal_source IS
  'O03. The evidence contract behind a legal or tax assertion. Phase D judges whether a source is '
  'current and authoritative enough to support an interpretation; Phase E supplies the '
  'interpretation. Read by fn_phase_d_legal_source_current and, through it, by GATE-027 and '
  'GATE-028 in fn_phase_d_gate_evaluate.';

ALTER TABLE public.phase_d_legal_source ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.phase_d_legal_source FROM PUBLIC;
GRANT SELECT ON TABLE public.phase_d_legal_source TO service_role;

-- ---------------------------------------------------------------------------------------------
-- THE PREDICATE. Deterministic. One row in, one verdict out, and the verdict says WHICH failure
-- it is -- stale, undated, not authoritative, superseded -- because a caller that cannot tell them
-- apart fixes the wrong one.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_legal_source_current(
  p_source_id text, p_require_authoritative boolean DEFAULT true, p_as_of date DEFAULT current_date)
 RETURNS TABLE(usable boolean, refusal_code text, reason text, authority_tier text, review_by date)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s public.phase_d_legal_source%rowtype;
begin
  if coalesce(btrim(p_source_id),'') = '' then
    usable := false; refusal_code := 'pd_legal_source_missing';
    reason := 'No legal or tax source named. An interpretation resting on a source nobody cited is not evidence.';
    return next; return;
  end if;

  select * into s from public.phase_d_legal_source where source_id = btrim(p_source_id);
  if not found then
    usable := false; refusal_code := 'pd_legal_source_missing';
    reason := format('%L is not a registered legal or tax source.', p_source_id);
    return next; return;
  end if;
  authority_tier := s.authority_tier;
  review_by      := s.review_by;

  if s.superseded_by is not null then
    usable := false; refusal_code := 'pd_legal_source_superseded';
    reason := format('%s was superseded by %s: %s', s.source_id, s.superseded_by, s.supersession_reason);
    return next; return;
  end if;

  -- A DATE THAT IS ABSENT IS NOT A DATE THAT IS FINE. This is the arm the estate has been caught by
  -- before in another shape: a missing input scoring as satisfied.
  if s.freshness_policy = 'REVIEW_BY_DATE'
     and (s.review_by is null or s.published_on is null or s.effective_from is null) then
    usable := false; refusal_code := 'pd_legal_source_missing';
    reason := format('%s carries no %s. A source whose currency cannot be established may not support a current position.',
      s.source_id,
      concat_ws(' and ',
        case when s.published_on   is null then 'published date'  end,
        case when s.effective_from is null then 'effective date'  end,
        case when s.review_by      is null then 'review-by date'  end));
    return next; return;
  end if;

  if s.freshness_policy = 'REVIEW_BY_DATE' and s.review_by < p_as_of then
    usable := false; refusal_code := 'pd_legal_source_stale';
    reason := format('%s was due for review on %s and it is %s. A current legal or tax position may not rest on it.',
                     s.source_id, s.review_by, p_as_of);
    return next; return;
  end if;

  if s.effective_from is not null and s.effective_from > p_as_of then
    usable := false; refusal_code := 'pd_legal_source_not_yet_effective';
    reason := format('%s does not take effect until %s.', s.source_id, s.effective_from);
    return next; return;
  end if;

  if p_require_authoritative
     and s.authority_tier not in ('AUTHORITATIVE_PRIMARY','AUTHORITATIVE_SECONDARY') then
    usable := false; refusal_code := 'pd_legal_source_not_authoritative';
    reason := format('%s is %s (%s by %s). This step requires an authoritative source.',
                     s.source_id, s.authority_tier, s.source_type, s.authority_name);
    return next; return;
  end if;

  usable := true; refusal_code := null;
  reason := format('%s: %s by %s, effective %s, in review until %s, digest %s.',
                   s.source_id, s.source_type, s.authority_name, s.effective_from, s.review_by,
                   left(s.content_sha256, 12));
  return next;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_legal_source_current(text, boolean, date) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- THE COMMITTED FIXTURES. Five rows, each isolating exactly one arm of the predicate. The dates are
-- absolute so the rows mean the same thing whenever they are read; the stale one is stale by five
-- years rather than by a day, so it cannot become current by the passage of time and quietly turn
-- a red arm green.
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.phase_d_legal_source
  (source_id, jurisdiction, subject, source_type, authority_tier, authority_name, source_reference,
   content_sha256, published_on, effective_from, retrieved_at, review_by, freshness_policy,
   evidence_owner, reviewer_role_id, note)
VALUES
  ('zz-demo-fta-corporate-tax-current', 'AE', 'corporate tax on marketplace commission',
   'TAX_AUTHORITY_GUIDANCE', 'AUTHORITATIVE_PRIMARY', 'ZZ DEMO Federal Tax Authority',
   'https://zz-demo.example.invalid/fta/ct-guide-current',
   repeat('a', 64), date '2026-01-15', date '2026-02-01', timestamptz '2026-08-24 00:00:00+00',
   date '2027-12-31', 'REVIEW_BY_DATE', 'general_counsel', 'compliance_and_privacy_officer',
   'ZZ DEMO. The CURRENT arm. Differs from zz-demo-fta-corporate-tax-expired only in review_by.'),

  ('zz-demo-fta-corporate-tax-expired', 'AE', 'corporate tax on marketplace commission',
   'TAX_AUTHORITY_GUIDANCE', 'AUTHORITATIVE_PRIMARY', 'ZZ DEMO Federal Tax Authority',
   'https://zz-demo.example.invalid/fta/ct-guide-2019',
   repeat('b', 64), date '2019-03-01', date '2019-04-01', timestamptz '2026-08-24 00:00:00+00',
   date '2021-03-31', 'REVIEW_BY_DATE', 'general_counsel', 'compliance_and_privacy_officer',
   'ZZ DEMO. The STALE arm: review_by 2021-03-31, five years past. pd_legal_source_stale.'),

  ('zz-demo-blog-vat-opinion', 'AE', 'VAT treatment of introducer fees',
   'SECONDARY_COMMENTARY', 'NON_AUTHORITATIVE', 'ZZ DEMO consultancy blog',
   'https://zz-demo.example.invalid/blog/vat-introducer-fees',
   repeat('c', 64), date '2026-05-01', date '2026-05-01', timestamptz '2026-08-24 00:00:00+00',
   date '2027-05-01', 'REVIEW_BY_DATE', 'general_counsel', 'compliance_and_privacy_officer',
   'ZZ DEMO. The NON-AUTHORITATIVE arm: in date, and still not something a tax position may rest on.'),

  ('zz-demo-undated-circular', 'AE', 'escrow and client money',
   'REGULATOR_CIRCULAR', 'AUTHORITATIVE_PRIMARY', 'ZZ DEMO Central Bank',
   'https://zz-demo.example.invalid/cb/circular-undated',
   repeat('d', 64), NULL, NULL, timestamptz '2026-08-24 00:00:00+00',
   NULL, 'REVIEW_BY_DATE', 'general_counsel', 'compliance_and_privacy_officer',
   'ZZ DEMO. The UNDATED arm. Authoritative, and its currency cannot be established at all. '
   'pd_legal_source_missing -- absence is refused rather than scored as satisfied.'),

  ('zz-demo-fta-corporate-tax-2024', 'AE', 'corporate tax on marketplace commission',
   'TAX_AUTHORITY_GUIDANCE', 'AUTHORITATIVE_PRIMARY', 'ZZ DEMO Federal Tax Authority',
   'https://zz-demo.example.invalid/fta/ct-guide-2024',
   repeat('e', 64), date '2024-02-01', date '2024-03-01', timestamptz '2026-08-24 00:00:00+00',
   date '2027-02-01', 'REVIEW_BY_DATE', 'general_counsel', 'compliance_and_privacy_officer',
   'ZZ DEMO. The SUPERSEDED arm: in date and authoritative, and replaced. pd_legal_source_superseded.')
ON CONFLICT (source_id) DO NOTHING;

UPDATE public.phase_d_legal_source
   SET superseded_by = 'zz-demo-fta-corporate-tax-current',
       supersession_reason = 'ZZ DEMO. Replaced by the 2026 guide.'
 WHERE source_id = 'zz-demo-fta-corporate-tax-2024' AND superseded_by IS NULL;
