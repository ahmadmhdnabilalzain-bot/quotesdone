-- Seat: ceo. 13 Nov 2026. One index for fn_seat_pool_timeline / fn_seat_pool_context
-- (every_seat_reads_one_pool_and_every_hand_over_comes_back.sql), which every seat's model call reads by subject.
-- CONCURRENTLY, alone in its file (apply_sql sends it outside a transaction): no SHARE lock held on a live table; apply
-- it BEFORE the main file. Without it the subject read scans the table (measured: 715 ms a call before the array rewrite).
create index concurrently if not exists company_event_entity_idx on public.company_event (entity_type, entity_id, occurred_at desc) where entity_id is not null;
