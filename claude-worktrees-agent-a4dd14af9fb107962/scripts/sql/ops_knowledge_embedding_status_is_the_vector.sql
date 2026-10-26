-- ops_knowledge.embedding_status REPORTS THE VECTOR, NOT THE IMPORTER'S GUESS (4 Sep 2026).
--
-- Measured on production before this file: 9,046 rows, 0 with embedding_gte null — every row is
-- embedded by the free in-region gte-small path (kb_embed, cron 315) — yet embedding_status said
-- 'pending' on 5,301 rows (197 decision_playbook, 240 decision_rule, 236 SOP, ...) and 'embedded' on 0.
-- MASTER_PLAN §4.2 / A4 read the label ("437 pending playbooks") as unembedded rows. They were not:
-- the label is written ONCE at intake (v3_import.mjs: deterministic ? 'not_required' : 'pending';
-- ingest_deep_knowledge.mjs: 'pending') and nothing ever advanced it — kb_embed selects on
-- `embedding_gte is null` and writes only the vector. An instrument reporting on the wrong subject.
--
-- Second defect on the same column: v3_import.mjs resets embedding_status to 'pending' when a
-- record's checksum changes but leaves the OLD vector in place, so a re-imported rule keeps the
-- embedding of the text it no longer carries and kb_embed (null-only picker) never re-embeds it.
--
-- One BEFORE trigger fixes both at the table, for every writer: a title/content change without a
-- new vector drops the vector (so cron 315 re-embeds it within a minute), and the status is derived
-- from the vector on every write. 'not_required' is retired: kb_embed embeds every null row
-- regardless of it and fn_ops_knowledge_match / fn_apply_playbook never read it, so the 240
-- exception_playbook rows it labelled were already embedded and retrievable — the label now says so.
--
--   node scripts/apply_sql.mjs scripts/sql/ops_knowledge_embedding_status_is_the_vector.sql --apply --ddl

begin;

create or replace function public.fn_ops_knowledge_embedding_status()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- content changed and the writer did not supply a fresh vector: the old vector describes text
  -- that no longer exists, so drop it and let the backfill picker (embedding_gte is null) re-embed.
  if tg_op = 'UPDATE'
     and (new.title is distinct from old.title or new.content is distinct from old.content)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  new.embedding_status := case when new.embedding_gte is null then 'pending' else 'embedded' end;
  return new;
end
$function$;

drop trigger if exists a10_ops_knowledge_embedding_status on public.ops_knowledge;
create trigger a10_ops_knowledge_embedding_status
  before insert or update on public.ops_knowledge
  for each row execute function public.fn_ops_knowledge_embedding_status();

-- One-time reconcile of the rows written before the trigger existed. The trigger derives the value;
-- the WHERE keeps this a no-op on a re-apply.
update public.ops_knowledge
   set embedding_status = embedding_status
 where embedding_status is distinct from
       (case when embedding_gte is null then 'pending' else 'embedded' end);

commit;
