-- PROBE: knowledge the AI wrote itself is withheld from customers (founder ruling 1338, 27 Oct 2026). Pure probe, no DDL,
-- no write: run AFTER knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql in the SAME query through
-- node scripts/qsql.mjs, so the routine replace is rolled back with it; it always ends in raise exception CHK<<...>>.
-- Run alone, it reads the LIVE routines (the "before"). Reads kb_chunks and knowledge_vector_ml only; contacts no one.
-- PROBE OK only if, for both fn_reason_retrieve and fn_reason_retrieve_ml, asked with the row's own vectors (so the row
-- ranks first wherever it is allowed):
--   1. a 'generated' kb_chunks row IS returned to an internal and a founder caller;
--   2. it is NOT returned to a customer, a supplier, a visitor or a NULL audience;
--   3. a 'memory' row is NOT returned to a customer;
--   4. a 'standard' row (a read source) IS still returned to a customer.
do $probe$
declare
  v_gen bigint; v_gen_g vector; v_gen_m vector;
  v_mem bigint; v_mem_g vector; v_mem_m vector;
  v_std bigint; v_std_g vector; v_std_m vector;
  v_aud text; v_fail text := ''; v_seen text := '';
  has_gte boolean; has_ml boolean;
  -- does a result carry kb_chunks:<id>?
  hit constant text := 'select coalesce($1 @> jsonb_build_array(jsonb_build_object(''source'', ''kb_chunks'', ''id'', $2::text)), false)';
begin
  select c.id, c.embedding_gte, v.embedding into v_gen, v_gen_g, v_gen_m from public.kb_chunks c
    join public.knowledge_vector_ml v on v.src = 'kb_chunks' and v.row_id = c.id::text
   where c.source_kind = 'generated' and c.embedding_gte is not null order by c.id limit 1;
  select c.id, c.embedding_gte, v.embedding into v_mem, v_mem_g, v_mem_m from public.kb_chunks c
    join public.knowledge_vector_ml v on v.src = 'kb_chunks' and v.row_id = c.id::text
   where c.source_kind = 'memory' and c.embedding_gte is not null order by c.id limit 1;
  select c.id, c.embedding_gte, v.embedding into v_std, v_std_g, v_std_m from public.kb_chunks c
    join public.knowledge_vector_ml v on v.src = 'kb_chunks' and v.row_id = c.id::text
   where c.source_kind = 'standard' and c.embedding_gte is not null order by c.id limit 1;
  if v_gen is null or v_mem is null or v_std is null then
    raise exception 'CHK<<PROBE FAILED: no fixture row (generated %, memory %, standard %)>>', v_gen, v_mem, v_std;
  end if;

  foreach v_aud in array array['internal', 'founder', 'customer', 'supplier', 'visitor', '<null>'] loop
    execute hit into has_gte using public.fn_reason_retrieve(p_seat => 'customer_support', p_embedding => v_gen_g, p_k => 6,
      p_audience => nullif(v_aud, '<null>')), v_gen;
    execute hit into has_ml using public.fn_reason_retrieve_ml(p_seat => 'customer_support', p_embedding => v_gen_m,
      p_embedding_gte => v_gen_g, p_k => 6, p_audience => nullif(v_aud, '<null>')), v_gen;
    v_seen := v_seen || format(' %s:gte=%s,ml=%s;', v_aud, has_gte, has_ml);
    if v_aud in ('internal', 'founder') and not (has_gte and has_ml) then v_fail := v_fail || format(' %s lost the generated row;', v_aud); end if;
    if v_aud not in ('internal', 'founder') and (has_gte or has_ml) then v_fail := v_fail || format(' %s got the generated row;', v_aud); end if;
  end loop;

  execute hit into has_gte using public.fn_reason_retrieve(p_seat => 'customer_support', p_embedding => v_mem_g, p_k => 6, p_audience => 'customer'), v_mem;
  execute hit into has_ml using public.fn_reason_retrieve_ml(p_seat => 'customer_support', p_embedding => v_mem_m, p_embedding_gte => v_mem_g, p_k => 6, p_audience => 'customer'), v_mem;
  v_seen := v_seen || format(' memory->customer:gte=%s,ml=%s;', has_gte, has_ml);
  if has_gte or has_ml then v_fail := v_fail || ' customer got the memory row;'; end if;

  execute hit into has_gte using public.fn_reason_retrieve(p_seat => 'customer_support', p_embedding => v_std_g, p_k => 6, p_audience => 'customer'), v_std;
  execute hit into has_ml using public.fn_reason_retrieve_ml(p_seat => 'customer_support', p_embedding => v_std_m, p_embedding_gte => v_std_g, p_k => 6, p_audience => 'customer'), v_std;
  v_seen := v_seen || format(' standard->customer:gte=%s,ml=%s', has_gte, has_ml);
  if not (has_gte and has_ml) then v_fail := v_fail || ' a read source (standard) no longer reaches a customer;'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK: generated kb_chunks:% internal-only; memory kb_chunks:% withheld; standard kb_chunks:% still served |%>>', v_gen, v_mem, v_std, v_seen;
  end if;
  raise exception 'CHK<<PROBE FAILED:% |%>>', v_fail, v_seen;
end $probe$;
