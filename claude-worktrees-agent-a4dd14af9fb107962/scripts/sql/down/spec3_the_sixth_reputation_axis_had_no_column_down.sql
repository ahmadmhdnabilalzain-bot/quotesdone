-- Reverse of scripts/sql/spec3_the_sixth_reputation_axis_had_no_column.sql.
--
-- Dropping the column is the reverse of adding it and loses nothing that was measured before this
-- change, because nothing was: agent_reputation has never held a decision-quality reading. The
-- routine is NOT restored here — reverting a function body belongs to the file that owns it, and
-- the previous definition is in git. What this script guarantees is that the schema goes back.

begin;

alter table public.agent_reputation drop column if exists decision_quality;

commit;
