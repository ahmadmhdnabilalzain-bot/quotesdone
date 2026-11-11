-- whatsapp_messages_are_read_by_sender_and_time_so_a_burst_is_one_turn.sql
-- Assigned: it_engineer (11 Nov 2026). Serves founder ruling 1636 and the burst rule (several WhatsApp messages in a few
-- seconds get one reply), both in supabase/functions/wa_inbound/burst.ts.
--
-- MEASURED (production, 11 Nov 2026, read-only): public.wa_messages has 75 rows, 232 kB, and ONE index, its primary key.
-- Every WhatsApp turn already reads this number's earlier rows by wa_from and created_at (_shared/wa_history.ts), and the
-- turn gate now reads them again: the burst wait (one read when the message arrives, one when it is quiet, one claim per
-- merged message) and the auto-reply loop cap (the last hour). With no index each of those is a sequential scan of the whole
-- table. Harmless at 75 rows; at a few hundred thousand (one year of a busy number pool) it is several scans per message on
-- the reply's path, inside the 4 s quiet window.
--
-- WHAT THIS CHANGES: one btree index on (wa_from, created_at). Nothing else: no routine, no table, no data.
-- WHAT IT DOES NOT CHANGE: the code works without it (it is a speed, not a rule), so applying it later loses nothing.
-- Plain CREATE INDEX (not CONCURRENTLY: apply_sql runs a file as one transaction). At 75 rows the lock lasts milliseconds.
-- Probe: whatsapp_messages_are_read_by_sender_and_time_so_a_burst_is_one_turn_probe.sql (pure, rolls back).
create index if not exists wa_messages_from_created_idx on public.wa_messages using btree (wa_from, created_at);

select case
  when not exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'wa_messages' and indexname = 'wa_messages_from_created_idx')
    then 'PROBE FAILED: wa_messages_from_created_idx is not on public.wa_messages'
  else 'PROBE OK' end as verdict;
