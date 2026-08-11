-- THE KNOWLEDGE CONFIDENCE LAYER (OS 2.txt section 27).
--
-- "Every piece of knowledge has metadata: Confidence, Source, Last validation, Owner, Expiry,
--  Review date, Supporting evidence. Employees should never rely on stale information without
--  warning."
--
-- MEASURED 11 Aug 2026 over 2,040 agent_knowledge rows:
--   confidence     1786 / 2040
--   source_ref     1012 / 2040
--   validation     2040 / 2040   present
--   owner_agent    2040 / 2040   present
--   review_due     1786 / 2040
--   expiry         NO COLUMN AT ALL
--   evidence       NO COLUMN AT ALL
--
-- Two of the seven. The two that are complete are complete; the other five are either partial or
-- absent, and a knowledge layer where 254 items carry no confidence is one where an employee cannot
-- tell what it is safe to act on.
--
-- NOTHING HERE IS INVENTED PER ROW. Every value is derived from a stated rule applied to what the
-- row already carries, and the rule is written down here so it can be argued with:
--
--   CONFIDENCE, from provenance, because provenance is what actually predicts reliability:
--     0.90  the imported v2026.07.31 knowledge packs — authored source material
--     0.85  authored: — written deliberately by a named framework in this repository
--     0.70  web_research: — grounded in real sources but assembled by a model
--     0.60  knowledge_exam: / org_memory: — the company's own inference from its own behaviour
--     0.50  dropbox_asset: and anything with no provenance at all — believed, not verified
--
--   REVIEW DATE and EXPIRY, from how fast the subject matter actually moves:
--     regulations, authorities, prices, licences  90 days  / expire at 180
--     market, supplier and commercial knowledge  180 days  / expire at 365
--     technical, product and process knowledge   365 days  / expire at 730
--   Dated from updated_at, not from today, so a two-year-old row does not get a fresh clock. That
--   is deliberate: back-dating the review of stale knowledge is precisely the failure this layer
--   exists to prevent, and some rows will therefore land already past review — which is the true
--   answer and is what fn_knowledge_decay is for.
--
--   SUPPORTING EVIDENCE is the row's own citable basis, assembled from what it has: its source
--   reference, its layer, its owner and its version. Where the row cites nothing, it says so in
--   those words rather than being given a citation it does not have.

begin;

alter table public.agent_knowledge
  add column if not exists valid_until          date,
  add column if not exists supporting_evidence  text;

comment on column public.agent_knowledge.valid_until is
  'Expiry (OS 2.txt s27). Past this date the item is not merely due for review, it should not be relied on. Derived from subject-matter volatility, dated from updated_at.';
comment on column public.agent_knowledge.supporting_evidence is
  'What this item rests on (OS 2.txt s27). Where an item cites nothing, this says so in those words rather than manufacturing a citation.';

-- CONFIDENCE — provenance-derived, only where absent. An existing measured confidence is never
-- overwritten by a rule.
update public.agent_knowledge set confidence =
  case
    when source_ref ~* '^(pack|corpus|import|kb_stage|ops_kb_stage|v2026)' then 0.90
    when source_ref ~* '^authored'        then 0.85
    when source_ref ~* '^web_research'    then 0.70
    when source_ref ~* '^(knowledge_exam|org_memory|auto_chat|session)' then 0.60
    else 0.50
  end
 where confidence is null;

-- SOURCE — every row must say where it came from. A row with no provenance says exactly that
-- rather than being assigned one.
update public.agent_knowledge
   set source_ref = 'unattributed: no provenance was recorded when this item was written'
 where source_ref is null or btrim(source_ref) = '';

-- REVIEW DATE and EXPIRY — volatility-derived, dated from the row's own updated_at.
update public.agent_knowledge k
   set review_due = (coalesce(k.updated_at, k.created_at, now())
                     + (case when k.topic ~* 'regulat|authorit|licen|complian|price|pricing|tax|vat|fee' then 90
                             when k.topic ~* 'market|supplier|commercial|brand|manufactur|competitor'    then 180
                             else 365 end || ' days')::interval)::date
 where k.review_due is null;

update public.agent_knowledge k
   set valid_until = (coalesce(k.updated_at, k.created_at, now())
                      + (case when k.topic ~* 'regulat|authorit|licen|complian|price|pricing|tax|vat|fee' then 180
                              when k.topic ~* 'market|supplier|commercial|brand|manufactur|competitor'    then 365
                              else 730 end || ' days')::interval)::date
 where k.valid_until is null;

-- SUPPORTING EVIDENCE — assembled from what the row actually has.
update public.agent_knowledge k
   set supporting_evidence =
     'Basis: ' || coalesce(nullif(k.source_ref,''), 'no source recorded')
     || ' | layer: ' || coalesce(k.layer, 'unspecified')
     || ' | owner: ' || coalesce(k.owner_agent, 'unassigned')
     || ' | version: ' || coalesce(k.version::text, '1')
     || ' | validation: ' || coalesce(k.validation_status, 'unvalidated')
     || case when k.content ~ 'https?://' then ' | the item itself cites at least one URL'
             else ' | the item cites no external source; treat it as internal know-how, not as an authority' end
 where k.supporting_evidence is null;

-- The layer must stay complete as new knowledge arrives, or this is a one-off tidy-up that decays
-- from the next INSERT. Defaults cannot express the volatility rule, so a trigger does.
create or replace function public.trg_agent_knowledge_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_days int; begin
  v_days := case when coalesce(NEW.topic,'') ~* 'regulat|authorit|licen|complian|price|pricing|tax|vat|fee' then 90
                 when coalesce(NEW.topic,'') ~* 'market|supplier|commercial|brand|manufactur|competitor'    then 180
                 else 365 end;
  if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
    NEW.source_ref := 'unattributed: no provenance was recorded when this item was written';
  end if;
  if NEW.confidence is null then
    NEW.confidence := case
      when NEW.source_ref ~* '^(pack|corpus|import|kb_stage|ops_kb_stage|v2026)' then 0.90
      when NEW.source_ref ~* '^authored'     then 0.85
      when NEW.source_ref ~* '^web_research' then 0.70
      when NEW.source_ref ~* '^(knowledge_exam|org_memory|auto_chat|session)' then 0.60
      else 0.50 end;
  end if;
  if NEW.owner_agent is null then NEW.owner_agent := NEW.agent_key; end if;
  if NEW.validation_status is null then NEW.validation_status := 'unvalidated'; end if;
  if NEW.review_due  is null then NEW.review_due  := (now() + (v_days     || ' days')::interval)::date; end if;
  if NEW.valid_until is null then NEW.valid_until := (now() + (v_days * 2 || ' days')::interval)::date; end if;
  if NEW.supporting_evidence is null then
    NEW.supporting_evidence := 'Basis: ' || NEW.source_ref
      || ' | layer: ' || coalesce(NEW.layer,'unspecified')
      || ' | owner: ' || coalesce(NEW.owner_agent,'unassigned')
      || ' | validation: ' || NEW.validation_status
      || case when coalesce(NEW.content,'') ~ 'https?://' then ' | the item itself cites at least one URL'
              else ' | the item cites no external source; treat it as internal know-how, not as an authority' end;
  end if;
  return NEW;
end $function$;

drop trigger if exists a00_agent_knowledge_metadata on public.agent_knowledge;
-- a00_ so it sorts FIRST. Postgres fires BEFORE triggers in NAME order, and this estate has already
-- been bitten once by a gate trigger reading a column another trigger had not yet filled.
create trigger a00_agent_knowledge_metadata
  before insert on public.agent_knowledge
  for each row execute function public.trg_agent_knowledge_metadata();

commit;
