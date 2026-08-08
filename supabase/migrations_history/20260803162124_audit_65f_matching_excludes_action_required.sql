-- AUDIT 6.5(f) — action_required suppliers were still being sent RFQs.
--
-- submit_quote forbids them from quoting; matching did not know. So the supplier receives a request
-- they are structurally unable to answer: the customer waits for a quote that cannot come, and the
-- supplier's silence is counted against them. The worst kind of bug — it is invisible on both sides
-- and looks like disinterest.
--
-- Patched surgically with an asserted occurrence count rather than by rewriting the function bodies,
-- because these carry scoring logic that has been tuned and is not what is being changed here.
do $mig$
declare d text; n int;
  kw_before constant text := $f$and coalesce(l.approval_status,'') <> 'rejected'$f$;
  kw_after  constant text := $f$and coalesce(l.approval_status,'') not in ('rejected','action_required')$f$;
  vec_before constant text := $f$  order by ( (1 - (l.embedding_gte <=> query_embedding))$f$;
  vec_after  constant text := $f$    and coalesce(l.approval_status,'') not in ('rejected','action_required')
  order by ( (1 - (l.embedding_gte <=> query_embedding))$f$;
begin
  -- 7-arg match_suppliers_kw: the live keyword matcher, already excludes rejected.
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
   where n2.nspname='public' and p.proname='match_suppliers_kw' and p.pronargs=7;
  n := (length(d) - length(replace(d, kw_before, ''))) / length(kw_before);
  if n <> 1 then raise exception 'match_suppliers_kw/7: expected 1 rejected-exclusion, found % - refusing', n; end if;
  execute replace(d, kw_before, kw_after);

  -- match_suppliers (vector): approval_status appeared ONLY as an ordering boost, so this matcher
  -- had no approval exclusion at all - not even for rejected suppliers.
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
   where n2.nspname='public' and p.proname='match_suppliers';
  n := (length(d) - length(replace(d, vec_before, ''))) / length(vec_before);
  if n <> 1 then raise exception 'match_suppliers: expected 1 order-by anchor, found % - refusing', n; end if;
  execute replace(d, vec_before, vec_after);
end $mig$;;
