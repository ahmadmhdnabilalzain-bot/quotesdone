-- THE PLACEHOLDER RAN FIRST, SO THE REAL CITATION COULD NEVER BE WRITTEN.
--
-- 13 Aug 2026, found by generalising the §36 trigger-order defect into a query: which BEFORE
-- trigger reads a NEW column that a LATER-SORTING BEFORE trigger on the same table assigns? Two
-- hits, both on agent_knowledge, and this is the mirror image of the §36 one — there a reader gave
-- up because the value was still NULL; here a writer fills it so early that the routine which knows
-- the real answer finds nothing left to do.
--
--   a00_agent_knowledge_metadata     BEFORE INSERT, sorts FIRST  (tgtype 7)
--   trg_knowledge_provenance_stamp   BEFORE INSERT, sorts LATER  (tgtype 7)
--
-- a00 opened with:
--
--     if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
--       NEW.source_ref := 'unattributed: no provenance was recorded when this item was written';
--     end if;
--
-- and the provenance stamp, which derives a REAL citation from the row's own topic and content —
-- dropbox_asset:<path>, org_memory:<id>, rfq_case:<n>, knowledge_exam:<name> — is guarded by
-- `if NEW.source_ref is null`. By the time it runs, source_ref is never null. Its citation logic
-- has never executed on an insert.
--
-- ITS OWN COMMENT PREDICTED THIS, VERBATIM: "A source_ref that says 'unknown' is worse than one
-- that is absent, because the check counts it as present." A trigger sorting three letters earlier
-- then did precisely that.
--
-- MEASURED ON PRODUCTION BEFORE CHANGING ANYTHING:
--   agent_knowledge                    2,049 rows
--   source_ref like 'unattributed%'    1,084  (52.9%)
--   source_ref like 'dropbox_asset:%'      0  — that branch has never produced a single row
--   source_ref like 'org_memory:%'        28  — written by callers, not by the stamp
--
-- AND IT POISONED THE CONFIDENCE LADDER TOO. a00 derived confidence FROM source_ref, one line after
-- setting it to the placeholder, so the ladder matched the word "unattributed" against every
-- pattern, failed them all, and fell to `else 0.50`. Half the knowledge base is scored on a string
-- the same trigger had just invented.
--
-- ── THE FIX: FALLBACK LAST, NOT FIRST ──────────────────────────────────────────────────────────
-- a00 keeps what only it can do — the review cadence from the topic, validation_status, review_due,
-- valid_until. It no longer touches source_ref, confidence, owner_agent or supporting_evidence.
-- Those move to the provenance stamp, which sorts later and runs AFTER the derivation, so:
--
--   1. owner_agent mapping                  (already there)
--   2. derive a real citation               (already there — now reachable)
--   3. fall back to 'unattributed' ONLY if step 2 could not derive one
--   4. score confidence off the FINAL source_ref, not the placeholder
--   5. build supporting_evidence from the final source_ref and owner
--
-- Both triggers are BEFORE INSERT FOR EACH ROW on the same table (tgtype 7 both), so anything that
-- fires a00 fires the stamp: nothing can now escape with a NULL source_ref.
--
-- ONE JUDGEMENT, STATED. dropbox_asset: and rfq_case: are new arrivals at the ladder because they
-- could never reach it before. They are classified with their existing peers in the 0.60 tier —
-- org_memory, knowledge_exam, auto_chat, session — all first-party internal records carrying a
-- specific identifier. No new tier and no new number was invented.
--
-- Existing rows are untouched; this is insert-time logic.
create or replace function public.trg_agent_knowledge_metadata()
returns trigger
language plpgsql
as $function$
declare v_days int; begin
  v_days := case when coalesce(NEW.topic,'') ~* 'regulat|authorit|licen|complian|price|pricing|tax|vat|fee' then 90
                 when coalesce(NEW.topic,'') ~* 'market|supplier|commercial|brand|manufactur|competitor'    then 180
                 else 365 end;
  -- source_ref, confidence, owner_agent and supporting_evidence are deliberately NOT set here.
  -- They belong after trg_knowledge_provenance_stamp has had its chance to derive a real citation;
  -- setting them here is what stopped it running at all. See the header.
  if NEW.validation_status is null then NEW.validation_status := 'unvalidated'; end if;
  if NEW.review_due  is null then NEW.review_due  := (now() + (v_days     || ' days')::interval)::date; end if;
  if NEW.valid_until is null then NEW.valid_until := (now() + (v_days * 2 || ' days')::interval)::date; end if;
  return NEW;
end
$function$;

create or replace function public.fn_knowledge_provenance_stamp()
returns trigger
language plpgsql
as $function$
begin
  -- OWNER. Only when the writer did not name one.
  if NEW.owner_agent is null and coalesce(NEW.agent_key,'') <> '' then
    NEW.owner_agent := case
      when NEW.agent_key like 'cat:%' then 'learning_dev_mgr'
      when NEW.agent_key = '_global'  then 'docs'
      else NEW.agent_key
    end;
  end if;
  if NEW.owner_agent is null then NEW.owner_agent := NEW.agent_key; end if;

  -- CITATION. Each branch reads a reference the writer itself put in the row; anything else is
  -- left NULL here and handled by the fallback below. A source_ref that says "unknown" is worse
  -- than one that is absent, because the check counts it as present — which is exactly why the
  -- fallback now comes after this block instead of before it.
  if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
    NEW.source_ref := case
      -- assets_ingest: content opens 'From company asset "X" (Dropbox: /path)'
      when NEW.topic like 'Asset text: %'
        then 'dropbox_asset:' || coalesce(substring(NEW.content from 'Dropbox: ([^)]+)'),
                                          substring(NEW.topic   from 'Asset text: (.*)'))
      when NEW.topic = 'Company assets (auto-synced from Dropbox)'
        then 'dropbox_asset:manifest'
      -- fn_experience_promote stamps the org_memory id into the topic as [org#123]
      when NEW.topic ~ '\[org#[0-9]+\]'
        then 'org_memory:' || substring(NEW.topic from '\[org#([0-9]+)\]')
      -- trg_ingest_case_lessons: 'Closed-case lesson (RFQ-45)'
      when NEW.topic like 'Closed-case lesson (RFQ-%'
        then 'rfq_case:' || substring(NEW.topic from 'RFQ-([0-9]+)')
      when NEW.topic like 'exam:%'
        then 'knowledge_exam:' || substring(NEW.topic from 'exam:(.*)')
      else null
    end;
  end if;

  -- LAST RESORT, and only now. Nothing above could name a source, so say so honestly.
  if NEW.source_ref is null or btrim(NEW.source_ref) = '' then
    NEW.source_ref := 'unattributed: no provenance was recorded when this item was written';
  end if;

  -- CONFIDENCE, SCORED OFF THE FINAL source_ref. This ran one line after the placeholder was set,
  -- so it matched nothing and fell to 0.50 on every row that had no writer-supplied reference.
  if NEW.confidence is null then
    NEW.confidence := case
      when NEW.source_ref ~* '^(pack|corpus|import|kb_stage|ops_kb_stage|v2026)' then 0.90
      when NEW.source_ref ~* '^authored'     then 0.85
      when NEW.source_ref ~* '^web_research' then 0.70
      when NEW.source_ref ~* '^(knowledge_exam|org_memory|auto_chat|session|dropbox_asset|rfq_case)' then 0.60
      else 0.50 end;
  end if;

  if NEW.supporting_evidence is null then
    NEW.supporting_evidence := 'Basis: ' || NEW.source_ref
      || ' | layer: ' || coalesce(NEW.layer,'unspecified')
      || ' | owner: ' || coalesce(NEW.owner_agent,'unassigned')
      || ' | validation: ' || coalesce(NEW.validation_status,'unvalidated')
      || case when coalesce(NEW.content,'') ~ 'https?://' then ' | the item itself cites at least one URL'
              else ' | the item cites no external source; treat it as internal know-how, not as an authority' end;
  end if;

  return NEW;
end
$function$;
