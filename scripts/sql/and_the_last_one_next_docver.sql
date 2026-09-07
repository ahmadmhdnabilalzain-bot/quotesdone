-- AND THE LAST ONE: _next_docver
--
-- The underscore prefix is why it survived every scan I ran: I was looking for public.fn_* and this
-- is public._next_docver. public.inquiries refused every insert because a document-versioning
-- trigger calls it. A naming convention is not a guarantee, and a search built on one finds only
-- what follows it.
--
-- Recovered verbatim from supabase/migrations_history.

create or replace function public._next_docver(p_type text, p_id text) returns int
language sql stable security definer set search_path=public,pg_temp as
$$ select coalesce(max(version),0)+1 from public.doc_versions where entity_type=p_type and entity_id=p_id $$;
