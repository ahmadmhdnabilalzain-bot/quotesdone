-- Staging's kb_chunks identity sequence sits behind max(id), so any insert collides on the
-- primary key. That is the classic residue of rows having been copied in with explicit ids.
-- Reset it to the real high-water mark before deploying the corpus here.
select setval(pg_get_serial_sequence('public.kb_chunks','id'),
              coalesce((select max(id) from public.kb_chunks), 1));
