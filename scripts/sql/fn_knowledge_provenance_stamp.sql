-- s27-knowledge-seven-fields — owner and provenance, at the one chokepoint every writer passes.
--
-- MEASURED ON PRODUCTION 2026-08-09. agent_knowledge holds 1,986 rows and the check reads
-- 1 of 7 metadata fields "present on EVERY row". Only validation_status is covered, and only
-- because it carries DEFAULT 'unvalidated'.
--
--   owner_agent      1,148 null
--   source_ref       1,148 null
--   confidence         200 null
--   review_due         200 null
--   expiry / evidence  NO COLUMN AT ALL
--
-- FIVE DB FUNCTIONS AND FOURTEEN EDGE FUNCTIONS WRITE THIS TABLE AND NOT ONE SETS EITHER FIELD.
-- fn_experience_promote, trg_ingest_case_lessons, fn_category_knowledge_promote,
-- fn_company_facts_sync, fn_company_faq_sync, plus assets_ingest / knowledge_exam /
-- gen_category_knowledge and the rest. The newest cohort — 200 rows dated 29 Jul to 9 Aug — is
-- still growing, so a backfill alone would be undone by tomorrow's cron. One BEFORE INSERT
-- trigger covers all nineteen writers; nineteen edits would not have covered the twentieth.
--
-- THIS DERIVES, IT DOES NOT INVENT. Both values are already present in the row being inserted:
-- agent_key names the owner, and the topic/content carries the citation. Nothing is stamped that
-- the row did not already assert. Contrast fn_governance_stamp, which writes confidence := 0.9 on
-- every agent_actions row — a constant that makes s36 read "confidence covered" on 1,165 rows that
-- were never scored. confidence and review_due are deliberately NOT touched here for exactly that
-- reason: agent_knowledge.confidence is 0.70 on 1,711 of its 1,786 non-null rows, so filling the
-- remaining 200 would turn the check green on a number nothing measures.
--
-- THE OWNER RULE IS READ OUT OF THE TABLE, NOT CHOSEN. On the 838 rows that already carry an
-- owner the convention is exact:
--   a named agent   -> owner_agent = agent_key   marketing 48/48, it 23/23, legal 22/22,
--                                                cfo 17/17, security 10/10, followup 9/9,
--                                                brief 8/8, analytics 8/8
--   cat:* brain     -> learning_dev_mgr          558 of 559
--   _global         -> docs                      46/46
-- A category brain and _global are not people, which is why the estate already assigns their
-- knowledge to a steward rather than to the key that authored it.

create or replace function public.fn_knowledge_provenance_stamp()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
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

  -- CITATION. Each branch reads a reference the writer itself put in the row; anything else is
  -- left NULL on purpose. A source_ref that says "unknown" is worse than one that is absent,
  -- because the check counts it as present.
  if NEW.source_ref is null then
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

  return NEW;
end $function$;

drop trigger if exists trg_knowledge_provenance_stamp on public.agent_knowledge;
create trigger trg_knowledge_provenance_stamp
  before insert on public.agent_knowledge
  for each row execute function public.fn_knowledge_provenance_stamp();

-- BACKFILL, same rule, applied only where the row already carries the answer.
-- owner_agent reaches 1,148 of 1,148. source_ref reaches 132 of 1,148 and the remaining 1,016 are
-- left NULL: they are the 26-27 Jul category-knowledge batch, and the estate's existing labels for
-- that batch distinguish expert_framework_v1 from v2 from authored. Which row came from which run
-- is not recoverable from the row, so it is not written.
update public.agent_knowledge
   set owner_agent = case
         when agent_key like 'cat:%' then 'learning_dev_mgr'
         when agent_key = '_global'  then 'docs'
         else agent_key
       end
 where owner_agent is null and coalesce(agent_key,'') <> '';

update public.agent_knowledge
   set source_ref = case
         when topic like 'Asset text: %'
           then 'dropbox_asset:' || coalesce(substring(content from 'Dropbox: ([^)]+)'),
                                             substring(topic   from 'Asset text: (.*)'))
         when topic = 'Company assets (auto-synced from Dropbox)' then 'dropbox_asset:manifest'
         when topic ~ '\[org#[0-9]+\]'      then 'org_memory:' || substring(topic from '\[org#([0-9]+)\]')
         when topic like 'Closed-case lesson (RFQ-%' then 'rfq_case:' || substring(topic from 'RFQ-([0-9]+)')
         when topic like 'exam:%'           then 'knowledge_exam:' || substring(topic from 'exam:(.*)')
       end
 where source_ref is null
   and (topic like 'Asset text: %'
     or topic = 'Company assets (auto-synced from Dropbox)'
     or topic ~ '\[org#[0-9]+\]'
     or topic like 'Closed-case lesson (RFQ-%'
     or topic like 'exam:%');
