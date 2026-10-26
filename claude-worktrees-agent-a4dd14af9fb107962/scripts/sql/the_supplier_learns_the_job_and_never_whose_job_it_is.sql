-- THE SUPPLIER LEARNS THE JOB, AND NEVER WHOSE JOB IT IS.
--
-- The founder, 10 September 2026, describing the drawing workflow:
--
--   "the sales agent need to make sure that whatever is in the legends or whatever in the drawings,
--    no matter what format it is, is not showing the project details in terms of, like, which
--    building it is, what location, who is the consultant, who is the... no details at all. That
--    all has to be removed."
--
-- He named six classes of identity: BUILDING, LOCATION, CONSULTANT, CLIENT, and by extension the
-- PROJECT NAME and the DRAWING NUMBERS that carry them. Measured against what the estate actually
-- masks today, none of the six is covered.
--
-- ── WHAT WAS ACTUALLY BEING MASKED ─────────────────────────────────────────────────────────────
--
-- `scrub_inquiry_contacts` fills six *_masked columns by calling mask_contacts, and mask_contacts
-- removes exactly five things: email addresses, http/www URLs, social and messenger short links,
-- +971 numbers, and local 05x numbers. mask_name additionally removes the customer's own name.
--
-- That is a CONTACT scrubber. It is good at what it does and it is not what step 6 asks for. Run it
-- over the title block of the one real drawing this estate has extracted and watch what survives:
--
--   AL HABTOOR CONSULTING ENGINEERS            <- consultant. SURVIVES.
--   PROJECT: Residential Villa for Mr. Ahmed Khan  <- project + client. SURVIVES.
--   LOCATION: Plot 234-11, Al Barsha South, Dubai  <- location + plot. SURVIVES.
--   CONTACT: +971 50 123 4567 | design@...ae   <- removed correctly.
--   DRAWING No: AH-2024-A-102 | MAKANI: 3011-92847 <- drawing no + makani. SURVIVE.
--
-- One line of six is removed. A supplier reading that brief knows the consultant, the client, the
-- building and the plot — which is the whole thing the anonymous marketplace exists to withhold
-- until the customer chooses to reveal.
--
-- ── AND ONE ROUTE HANDED OVER THE UNMASKED COPY ANYWAY ─────────────────────────────────────────
--
-- Measured: `fn_supplier_opportunities(bigint)`, which supplier_portal calls, reads RAW
-- public.inquiries. Asserted against pg_proc: uses_safe_view=false, uses_masked=false,
-- joins_inquiry_matches=false. It returns 'project_title' from r.summary and 'estimated_value' from
-- r.budget — the unmasked originals — for EVERY open inquiry in the estate, to any authenticated
-- supplier. The careful projection built into inquiries_supplier_safe and supplier_api sits beside
-- it, unused on this path.
--
-- Nothing has leaked: public.inquiries has 0 rows and the supplier portal is not finished. That is
-- exactly why this is the moment to fix it, and it is what the founder means by "confirm that what
-- I'm saying is being programmed correctly" rather than waiting for a test to fail.
--
-- ── WHAT THIS FILE DOES NOT DO, DELIBERATELY ───────────────────────────────────────────────────
--
-- 1. It does not restrict opportunities to matched suppliers. Showing a supplier a MASKED brief
--    they are not yet matched to is a liquidity decision, not a safety one, and it is the founder's
--    call. The safety half — that what they see is masked — is not a product decision and is fixed
--    here.
-- 2. It does not touch the drawing IMAGE. Pixel redaction lives in the drawing_redact edge function
--    and is changed separately; this file governs the TEXT the supplier reads.
-- 3. It does not attempt to recognise arbitrary company names from nothing. Deterministic masking
--    can only catch what has a shape. Labelled fields and identifier formats have a shape; "AL
--    HABTOOR" alone does not, and pretending otherwise would be the confident-wrong-answer failure
--    this estate keeps paying for. The company-suffix rule below catches the common UAE forms and
--    the label rule catches the rest; anything beyond that is the vision model's job in
--    drawing_redact, not a regex's.

create or replace function public.mask_project_identity(t text)
returns text language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;

  -- 1. LABELLED FIELDS. A title block labels its own secrets, in every format and every CAD
  --    template: "PROJECT:", "CLIENT:", "CONSULTANT:", "LOCATION:". The label is the reliable
  --    signal — far more reliable than trying to recognise the value — so the value after it is
  --    removed to end of line. This is what makes the rule format-independent, which is the
  --    founder's own requirement ("no matter what format it is").
  s := regexp_replace(s,
    '(?in)^[[:space:]]*(project|client|employer|owner|developer|consultant|architect|engineer|'
    || 'main[[:space:]]+contractor|contractor|sub[- ]?contractor|designer|surveyor|site|location|'
    || 'address|plot|building|tower|villa|community|district|drawing[[:space:]]*(no|number)?|'
    || 'dwg[[:space:]]*(no|number)?|sheet|makani|title|prepared[[:space:]]+by|issued[[:space:]]+to|'
    || 'checked[[:space:]]+by|approved[[:space:]]+by|drawn[[:space:]]+by)[[:space:]]*[:#][^\n]*',
    '[hidden]', 'g');

  -- Same labels appearing mid-line ("... | DRAWING No: AH-2024-A-102 | REV: C"), bounded to the
  -- segment so the rest of a sentence survives.
  --
  -- THE PEOPLE LABELS ARE IN THIS LIST BECAUSE THE FIRST VERSION MISSED THEM. Run over the real
  -- drawing, everything above was correctly hidden and this line came through untouched:
  --     DATE: 12/03/2024 | DRAWN BY: R. Fernandes | APPROVED: Eng. S. Malik
  -- The line-start rule did not fire because the line starts with DATE:, and the mid-line rule did
  -- not carry "drawn by" or "approved". Two named individuals — the draughtsman and the approving
  -- engineer — survived into the supplier-facing copy. A person's name is identity as surely as the
  -- consultant firm's is, and it is the kind of thing that identifies a project to anyone in the
  -- trade. Every label that can be followed by a person or a firm now appears in BOTH rules.
  s := regexp_replace(s,
    '(?i)(project|client|employer|consultant|architect|engineer|developer|owner|contractor|'
    || 'designer|surveyor|location|address|plot|building|tower|villa|community|makani|'
    || 'drawing[[:space:]]*no|dwg[[:space:]]*no|sheet[[:space:]]*no|'
    || 'drawn[[:space:]]+by|checked[[:space:]]+by|approved[[:space:]]+by|prepared[[:space:]]+by|'
    || 'reviewed[[:space:]]+by|issued[[:space:]]+to|approved|verified[[:space:]]+by)'
    || '[[:space:]]*[:#][[:space:]]*[^|\n]{1,80}', '[hidden]', 'g');

  -- 2. IDENTIFIERS WITH A SHAPE.
  --    Makani is Dubai's 10-digit address code, written 1234-56789 or as ten digits.
  s := regexp_replace(s, '(?i)\ymakani[[:space:]]*[:#]?[[:space:]]*[0-9]{4}[[:space:]-]?[0-9]{5,6}\y', '[hidden]', 'g');
  --    Plot / parcel numbers: "Plot 234-11", "Parcel 345-6789".
  s := regexp_replace(s, '(?i)\y(plot|parcel|land)[[:space:]]*(no\.?|number|#)?[[:space:]]*[0-9]{1,6}(-[0-9]{1,6})*\y', '[hidden]', 'g');
  --    Drawing / sheet numbers: "AH-2024-A-102", "DWG-01-A-203". Two or more hyphen-joined groups
  --    with at least one letter group, so a plain measurement or a date is not caught.
  s := regexp_replace(s, '\y[A-Z]{1,4}-[A-Z0-9]{1,6}-[A-Z0-9]{1,6}(-[A-Z0-9]{1,6})*\y', '[hidden]', 'g');

  -- 3. COMPANY NAMES BY THEIR SUFFIX. A UAE entity almost always announces itself: L.L.C, LLC,
  --    FZE, FZ-LLC, DMCC, Est., Trading, Contracting, Consultants, Consulting Engineers. Capture
  --    the run of capitalised words immediately before the suffix, which is the name itself.
  s := regexp_replace(s,
    '(?i)\y([A-Z][A-Za-z&''.\-]*[[:space:]]+){1,6}'
    || '(l\.?l\.?c\.?|llc|fz[- ]?llc|fze|fzco|dmcc|est\.?|establishment|trading|general[[:space:]]+trading|'
    || 'contracting|contractors?|consultants?|consulting[[:space:]]+engineers?|engineering[[:space:]]+consultants?|'
    || 'architects?|technical[[:space:]]+services|building[[:space:]]+materials)\y',
    '[hidden]', 'g');

  return s;
end $fn$;
revoke execute on function public.mask_project_identity(text) from public, anon, authenticated;

-- The jsonb sibling, so spec / boq / completeness get the same treatment as the text columns. It
-- walks strings only; numbers, keys and structure are untouched, because a quantity is the thing the
-- supplier is supposed to see.
create or replace function public.mask_project_identity_jsonb(j jsonb)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
begin
  if j is null then return j; end if;
  case jsonb_typeof(j)
    when 'string' then return to_jsonb(public.mask_project_identity(j #>> '{}'));
    when 'array'  then return (select coalesce(jsonb_agg(public.mask_project_identity_jsonb(e)), '[]'::jsonb)
                                 from jsonb_array_elements(j) e);
    when 'object' then return (select coalesce(jsonb_object_agg(k, public.mask_project_identity_jsonb(v)), '{}'::jsonb)
                                 from jsonb_each(j) as t(k, v));
    else return j;
  end case;
end $fn$;
revoke execute on function public.mask_project_identity_jsonb(jsonb) from public, anon, authenticated;

-- ── THE TRIGGER NOW REMOVES BOTH KINDS ─────────────────────────────────────────────────────────
-- Contacts first (unchanged), then project identity. Order matters only for readability; both are
-- idempotent. The founder_alerts row is kept and its wording widened, because "we masked something"
-- is worth seeing on the first real inquiry and its old text claimed contacts specifically.
create or replace function public.scrub_inquiry_contacts()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare changed boolean := false; v_name text;
begin
  new.summary_masked      := public.mask_project_identity(public.mask_contacts(new.summary));
  new.raw_input_masked    := public.mask_project_identity(public.mask_contacts(new.raw_input));
  new.budget_masked       := public.mask_project_identity(public.mask_contacts(new.budget));
  new.spec_masked         := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.spec));
  new.boq_masked          := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.boq));
  new.completeness_masked := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.completeness));

  if new.customer_id is not null then
    begin
      select nullif(btrim(c.full_name), '') into v_name from public.customers c where c.id = new.customer_id;
    exception when others then v_name := null; end;
    if v_name is not null then
      new.summary_masked   := public.mask_name(new.summary_masked, v_name);
      new.raw_input_masked := public.mask_name(new.raw_input_masked, v_name);
      new.budget_masked    := public.mask_name(new.budget_masked, v_name);
    end if;
  end if;

  changed := (new.summary_masked is distinct from new.summary)
          or (new.raw_input_masked is distinct from new.raw_input)
          or (new.budget_masked is distinct from new.budget)
          or (new.spec_masked is distinct from new.spec)
          or (new.boq_masked is distinct from new.boq)
          or (new.completeness_masked is distinct from new.completeness);
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'inquiry_contact_masked',
        'Masked customer contact details and/or project identity (consultant, client, building, '
        || 'location, plot, drawing numbers) in the supplier-facing copy of inquiry '
        || coalesce(new.id::text, '?') || ' from customer ' || coalesce(new.customer_id::text, '?') || '.',
        'system');
    exception when others then null; end;
  end if;
  return new;
end $fn$;

-- ── AND THE ROUTE THAT BYPASSED ALL OF IT ──────────────────────────────────────────────────────
-- Only the two identity-bearing fields change: project_title and estimated_value now read the
-- masked columns. Ranking, fit_score, ordering and every other field are untouched — the supplier
-- still sees the job, its trade, its emirate and its size, which is everything they need to decide
-- whether to bid.
-- WRITTEN OUT IN FULL, NOT REWRITTEN AT APPLY TIME. The first version of this file read the
-- live prosrc, did two string substitutions and installed the result with EXECUTE. It worked -- and
-- canonical_routine_manifest immediately reported DIFFERS, because a definition computed at apply
-- time is not a definition the repository contains. That is precisely the repo-and-database
-- disagreement the founder was getting failure emails about, so the corrected body is written here
-- literally and the file is what runs.
--
-- Only three columns changed from the previous definition, all inside the "cand" CTE so that every
-- downstream reference through s.* and r.* is covered at once: summary, budget and the requirement
-- built from raw_input now read the _masked siblings. There is deliberately NO coalesce back to the
-- raw column -- that would look defensive and would hand over the unmasked text on exactly the row
-- where masking failed.

create or replace function public.fn_supplier_opportunities(p_lead_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with me as (
    select l.id, lower(coalesce(l.sector, '')) sector, l.emirate,
           coalesce(l.service_emirates, '{}'::text[]) service_emirates,
           lower(coalesce(l.capability_summary, l.services, l.description, '')) capability,
           l.verified
      from public.leads l where l.id = p_lead_id
  ),
  -- Only inquiries this supplier could actually work: open, and not their own demo fence.
  cand as (
    select i.id, i.category, i.emirate, i.summary_masked as summary, i.scope_type, i.created_at, i.budget_masked as budget,
           -- WHAT THE CUSTOMER ACTUALLY NEEDS, which is not the project's title. raw_input is what
           -- they typed, in their words. `spec` is jsonb — the structured brief intake derived —
           -- and pouring that through ::text would put raw JSON in front of a supplier, so it is
           -- deliberately not a fallback. No brief typed means NULL, and the surface says so.
           nullif(btrim(coalesce(i.raw_input_masked, '')), '') requirement,
           lower(coalesce(i.category, '')) cat
      from public.inquiries i
     where coalesce(i.status, 'open') = 'open'
  ),
  scored as (
    select c.*,
      (c.cat = me.sector and me.sector <> '')                                    as trade_hit,
      (c.emirate is not null and (c.emirate = me.emirate
        or c.emirate = any(me.service_emirates)))                                as location_hit,
      -- Capacity is only ASKED when the supplier has declared a capability. An empty capability
      -- makes this unanswerable for them, not a failure by them.
      (me.capability <> '')                                                      as capacity_known,
      (me.capability <> '' and c.cat <> '' and position(c.cat in me.capability) > 0) as capacity_hit,
      -- History needs a concluded job. Counted rather than assumed so the reason can name it.
      (select count(*) from public.quotes q
         join public.inquiries qi on qi.id = q.inquiry_id
        where q.supplier_id = p_lead_id and lower(coalesce(qi.category,'')) = c.cat) as similar_jobs
      from cand c cross join me
  ),
  ranked as (
    select s.*,
      -- Weights that applied / weights that could apply. Capacity leaves the denominator when the
      -- supplier has declared nothing; history leaves it while the estate has no completed work.
      round(100.0 * (
        (case when s.trade_hit then 40 else 0 end)
      + (case when s.location_hit then 30 else 0 end)
      + (case when s.capacity_known and s.capacity_hit then 30 else 0 end)
      ) / nullif(40 + 30 + (case when s.capacity_known then 30 else 0 end), 0)) as fit_score
      from scored s
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from ranked),
    'ordered_by', 'fit_score desc — a ranked list, never chronological',
    'population', jsonb_build_object(
      'open_inquiries', (select count(*) from public.inquiries where coalesce(status,'open')='open'),
      'quotes_in_estate', (select count(*) from public.quotes)
    ),
    'note', case when (select count(*) from ranked) = 0
                 then 'no open opportunities yet — nothing to rank'
                 else null end,
    'opportunities', coalesce((
      select jsonb_agg(x order by x->>'fit_score' desc) from (
        select jsonb_build_object(
          'inquiry_id', r.id,
          'project_title', coalesce(nullif(btrim(coalesce(r.summary,'')),''), r.category, 'Untitled project'),
          'category', r.category,
          'emirate', r.emirate,
          -- NULL, not an empty string: an inquiry with no brief has not been described yet, and the
          -- surface must be able to say that rather than render a blank line.
          'requirement', r.requirement,
          'estimated_value', r.budget,
          'fit_score', r.fit_score,
          'match_pct', r.fit_score,
          -- THE "WHY". Each reason states whether it applied, and an unanswerable one says why it
          -- could not be asked rather than reading as a failed test.
          'reasons', jsonb_build_array(
            jsonb_build_object(
              'key', 'trade',
              'applies', r.trade_hit,
              'text', case when r.trade_hit
                           then 'This is your trade — ' || coalesce(r.category,'the same category')
                           else 'Outside your registered trade' end),
            jsonb_build_object(
              'key', 'location',
              'applies', r.location_hit,
              'text', case when r.location_hit
                           then 'Nearby location — ' || coalesce(r.emirate,'your service area')
                           else 'Outside the emirates you serve' end),
            jsonb_build_object(
              'key', 'capacity',
              'applies', r.capacity_known and r.capacity_hit,
              'available', r.capacity_known,
              'text', case when not r.capacity_known
                           then 'Your capacity fits: not assessable — you have not described your capability yet'
                           when r.capacity_hit
                           then 'Your capacity fits — you list this work in your capability'
                           else 'Not in your described capability' end),
            jsonb_build_object(
              'key', 'history',
              'applies', r.similar_jobs > 0,
              -- available:false is the whole point. 0 quotes exist in the estate, so this is
              -- unanswerable for EVERY supplier and must never read as "you have no experience".
              'available', (select count(*) from public.quotes) > 0,
              'similar_jobs', r.similar_jobs,
              'text', case when (select count(*) from public.quotes) = 0
                           then 'Previous similar project: no completed work has been recorded on QuotesDone yet, for anyone'
                           when r.similar_jobs > 0
                           then 'You worked on ' || r.similar_jobs || ' previous similar project(s)'
                           else 'No previous similar project on record' end)
          )
        ) x from ranked r
      ) s
    ), '[]'::jsonb)
  )
$fn$;
revoke execute on function public.fn_supplier_opportunities(bigint) from public, anon, authenticated;

-- ── PROVE IT ON THE REAL TITLE BLOCK ───────────────────────────────────────────────────────────
-- The probe reads and asserts only; it writes nothing, so there is nothing to clean up and it ends
-- in a notice rather than a raise, which would roll back the definitions above.
do $do$
declare
  v_block text;
  v_out   text;
  v_ok    boolean;
begin
  -- The exact text extracted from the one real drawing in this estate (documents.id 10).
  v_block := 'AL HABTOOR CONSULTING ENGINEERS' || chr(10)
          || 'PROJECT: Residential Villa for Mr. Ahmed Khan' || chr(10)
          || 'LOCATION: Plot 234-11, Al Barsha South, Dubai' || chr(10)
          || 'CONTACT: +971 50 123 4567 | design@alhabtoor-eng.ae' || chr(10)
          || 'DRAWING No: AH-2024-A-102 | REV: C | MAKANI: 3011-92847' || chr(10)
          -- The line that exposed the people gap. It is in the probe because an assertion against
          -- text that does not contain the thing it forbids passes for the wrong reason.
          || 'DATE: 12/03/2024 | DRAWN BY: R. Fernandes | APPROVED: Eng. S. Malik' || chr(10)
          || 'FINISHES: Floor - 600x600 porcelain tiles throughout. Ceiling - gypsum false ceiling.';

  v_out := public.mask_project_identity(public.mask_contacts(v_block));

  -- EACH OF THE FOUNDER'S SIX, ASSERTED SEPARATELY. A single "does it contain Habtoor" check would
  -- pass while five other classes leaked.
  if v_out ilike '%habtoor%'        then raise exception 'the consultant survived masking'; end if;
  if v_out ilike '%Ahmed Khan%'     then raise exception 'the client name survived masking'; end if;
  if v_out ilike '%Al Barsha%'      then raise exception 'the location survived masking'; end if;
  if v_out ilike '%234-11%'         then raise exception 'the plot number survived masking'; end if;
  if v_out ilike '%AH-2024-A-102%'  then raise exception 'the drawing number survived masking'; end if;
  if v_out ilike '%3011-92847%'     then raise exception 'the makani number survived masking'; end if;
  if v_out ilike '%alhabtoor-eng%'  then raise exception 'the consultant domain survived masking'; end if;
  if v_out ilike '%50 123 4567%'    then raise exception 'the phone survived masking'; end if;
  -- The two named individuals the first version let through.
  if v_out ilike '%Fernandes%'      then raise exception 'the draughtsman''s name survived masking'; end if;
  if v_out ilike '%Malik%'          then raise exception 'the approving engineer''s name survived masking'; end if;

  -- AND THE JOB MUST SURVIVE. A masker that removes the brief is not a masker, it is a shredder —
  -- the supplier still has to be able to price the work.
  if v_out not ilike '%porcelain tiles%' then
    raise exception 'masking destroyed the finishes schedule the supplier needs to quote';
  end if;
  if v_out not ilike '%gypsum false ceiling%' then
    raise exception 'masking destroyed the ceiling scope';
  end if;
  if v_out not ilike '%600x600%' then
    raise exception 'masking destroyed a tile dimension — an identifier rule is too greedy';
  end if;

  -- THE JSONB SIBLING must behave the same and must not disturb numbers or keys.
  if (public.mask_project_identity_jsonb(
        jsonb_build_object('item', 'CONSULTANT: AL HABTOOR CONSULTING ENGINEERS', 'qty', 42)
      ) ->> 'item') ilike '%habtoor%' then
    raise exception 'the jsonb masker let a consultant through';
  end if;
  if (public.mask_project_identity_jsonb(jsonb_build_object('qty', 42)) ->> 'qty') <> '42' then
    raise exception 'the jsonb masker altered a quantity';
  end if;

  -- THE BYPASS ROUTE now reads the masked columns. Asserted against the live source, because that is
  -- the thing that was wrong: the careful projection existed and this path did not use it.
  select p.prosrc ilike '%summary_masked%' and p.prosrc ilike '%budget_masked%'
         and p.prosrc ilike '%raw_input_masked%'
         -- and the raw columns must be GONE from the candidate list, not merely joined by a
         -- masked sibling. `i.summary,` surviving would mean the CTE still carries the original.
         and p.prosrc not like '%i.summary, i.scope_type%'
         and p.prosrc not like '%coalesce(i.raw_input, %'
    into v_ok
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_supplier_opportunities';
  if not coalesce(v_ok, false) then
    raise exception 'fn_supplier_opportunities still carries an unmasked inquiry column';
  end if;

  -- It must still RUN, and still be a ranked list rather than an error or an empty shell. There
  -- are 0 inquiries today, so this asserts the shape, and says so rather than implying more.
  if (public.fn_supplier_opportunities((select id from public.leads order by id limit 1)) ->> 'ordered_by') is null then
    raise exception 'the rewritten routine no longer returns its ranking contract';
  end if;

  raise notice 'THE SUPPLIER LEARNS THE JOB, NOT WHOSE IT IS. All six identity classes the founder named are removed from the real title block — consultant, client, location, plot, drawing number, makani — while the finishes, the ceiling scope and the 600x600 tile size survive intact. fn_supplier_opportunities now reads summary_masked and budget_masked instead of the raw columns. STILL OPEN, deliberately: the drawing IMAGE is redacted by the drawing_redact edge function, not here, and whether an unmatched supplier should see a masked brief at all is the founder''s product call.';
end
$do$;
