-- RE-DERIVING PROVENANCE ONLY WHERE THE ROW ITSELF CARRIES IT.
--
-- 13 Aug 2026. fn_knowledge_provenance_stamp was fixed forward earlier today: an a00_ trigger
-- sorting three letters earlier had already written the 'unattributed' placeholder, so the branch
-- that derives a REAL citation from the row's own topic was guarded by `if NEW.source_ref is null`
-- and could never fire. New rows are correct now - the one agent_knowledge row written since the
-- 19:50 deploy carries knowledge_exam:q630 - but the rows written while it was broken still say
-- 'unattributed', and dropbox_asset: has never appeared on a single row.
--
-- WHAT IS AND IS NOT DERIVABLE. Measured before writing this, on production:
--
--   unattributed rows                                          1,084
--     topic like 'Asset text: %'                                  55   <- derivable
--     topic = 'Company assets (auto-synced from Dropbox)'           1   <- derivable
--     topic ~ '[org#<id>]'                                          0
--     topic like 'Closed-case lesson (RFQ-%'                        0
--     topic like 'exam:%'                                           0
--     ------------------------------------------------------------------
--     derivable                                                    56  (5.2%)
--     genuinely unrecorded                                      1,028  (94.8%)
--
-- The other 1,028 stay 'unattributed', and that is the point. Their provenance was not recorded
-- when they were written; there is nothing in the row to recover it from, and a citation invented
-- to make a number go up is worse than an absent one because every downstream check would then
-- count it as present. The founder's instruction was explicit: "only where the pattern genuinely
-- matches. Do not invent a citation."
--
-- THE DERIVATION IS THE TRIGGER'S OWN, COPIED VERBATIM, so a row backfilled here is
-- indistinguishable from one the trigger would write today - the Dropbox path out of the content
-- where the writer put it, falling back to the asset name in the topic.
--
-- The guard `btrim(derived) <> 'dropbox_asset:'` matters: a row whose content has no
-- `Dropbox: …` AND whose topic has nothing after `Asset text: ` would otherwise be stamped with a
-- bare prefix and no path - a citation pointing at nothing, which is the same defect wearing a
-- better label.
--
-- VERIFIED BY ABORTED-TRANSACTION PROBE BEFORE COMMITTING: 56 rows updated, 0 rows left
-- unattributed in this class afterwards, sample 'dropbox_asset:manifest'.

begin;

with cand as (
  select id,
    case
      when topic like 'Asset text: %'
        then 'dropbox_asset:' || coalesce(substring(content from 'Dropbox: ([^)]+)'),
                                          substring(topic   from 'Asset text: (.*)'))
      when topic = 'Company assets (auto-synced from Dropbox)'
        then 'dropbox_asset:manifest'
    end as derived
  from public.agent_knowledge
  where source_ref like 'unattributed%'
    and (topic like 'Asset text: %' or topic = 'Company assets (auto-synced from Dropbox)')
)
update public.agent_knowledge k
   set source_ref = c.derived
  from cand c
 where k.id = c.id
   and c.derived is not null
   and btrim(c.derived) <> 'dropbox_asset:';

-- Confidence was scored off the placeholder at write time and fell to the 0.50 "else" arm. The
-- trigger scores dropbox_asset: at 0.60. Only rows this migration just re-cited are touched, and
-- only where confidence is still exactly the placeholder-era default, so a value a human or a
-- later routine set deliberately is never overwritten.
update public.agent_knowledge
   set confidence = 0.60
 where source_ref like 'dropbox_asset:%'
   and confidence = 0.50;

commit;
