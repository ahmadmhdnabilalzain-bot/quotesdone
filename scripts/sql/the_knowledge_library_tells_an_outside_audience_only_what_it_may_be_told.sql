-- THE KNOWLEDGE LIBRARY TELLS AN OUTSIDE AUDIENCE ONLY WHAT IT MAY BE TOLD.
-- Seat: customer_support (what a customer or a supplier is told); the routines are owned by it_engineer. 27 Oct 2026.
-- Founder rulings 1338 (27 Oct 2026, "Withhold from customers.") and 7 Oct 2026 (a fact not read on a page actually
-- opened is never stated to a customer; internal facts are never told outside).
--
-- MEASURED on production 27 Oct 2026 14:43 UTC, read-only:
--   * fn_knowledge_library_source_sql, fn_reason_retrieve_library and fn_reason_retrieve_ml_library are byte-equal to
--     their only definer, one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag.sql (MANIFEST).
--   * fn_knowledge_library_source_sql maps EVERY kb_chunks row to verified = true, the 1,317 'generated' (model-written)
--     and 53 'memory' (agent notes) rows included. kb_chunks has 0 rows with a NULL or blank source_kind.
--   * The library readers take NO audience. They are (text,vector,integer,text,text,text) and
--     (text,vector,vector,integer,integer,text,text,text); every customer-branch rule of the legacy readers is missing:
--     kb_chunks generated/memory (#1640), agent_knowledge other seats' notes (only '_global' outside), the seat stores'
--     audience:internal / kind:company / internal:founder_instruction/ / internal:memory/ rows (#1567), unapproved
--     research, and the own-row reservation (internal only).
--   * Nothing calls them today: fn_reason_retrieve / _ml carry no dispatch line (0 live routines call a library reader),
--     fn_knowledge_library_read() = 'legacy'. But the fill is running (library 5,910 origins: sales 5,852, support 322,
--     accountant 280, ops 39, agent 17, kb 2) and the_seats_read_the_knowledge_library_once_it_holds_every_row.sql
--     switches the read to the library as soon as a reconciliation is recorded. The day a dispatch is restored, every
--     internal, unverified and AI-written row would reach a customer through these two readers.
--
-- WHAT THIS CHANGES
--   (a) fn_knowledge_library_source_sql: a kb_chunks row is verified exactly when its source_kind is neither 'generated'
--       nor 'memory'; a NULL or blank source_kind is NOT verified. Every other line is the canonical body, byte for byte.
--       Library rows already holding a kb_chunks origin of those kinds are recomputed once below (0 today; at most the
--       1,370 such kb rows once filled), under the library's shared lock as the writers' triggers take it.
--   (b) fn_knowledge_library_customer_facing(library id): ONE place for the rule an outside audience is held to. A row
--       is told outside only when ALL of: it is verified; no tag or citation of the row or of any origin marks it internal
--       (audience:internal, kind:company, internal:founder_instruction/, internal:memory/); NO kb_chunks origin is
--       generated, memory, blank or gone; and AT LEAST ONE origin passes its own store's customer rule (kb_chunks: the
--       above; ops_knowledge: not draft, no dept_key; agent_knowledge: '_global' and validated; the seat stores: their
--       verified status). A library row merges identical texts from kb_chunks / ops / agent, so a text an AI wrote stays
--       internal even when an agent copy of it is validated. It reads the stores directly (the library does not carry
--       source_kind, dept_key or agent_key); phase 2's rename of the stores must move this rule with them.
--       THE FAST PATH, and why it is at every call site rather than inside (b): a routine with a pinned search_path is
--       never inlined, and (b) measured 1,042 ms over the 5,852 sales rows (0.18 ms a call; an outside sales_engineer
--       call went from 131 ms to 808 ms). The seat stores never merge, so their library row carries the store's own
--       verified status, tags and citations: verified, not kb/ops/agent, no internal tag and no 'internal:' citation at
--       all is exactly (b) for them, read from columns (21 ms, the same 5,844 rows, measured). Anything that does not
--       clear it, every kb/ops/agent row included, still goes through (b). The check holds every call site to the one text.
--   (c) fn_reason_retrieve_library / fn_reason_retrieve_ml_library take p_audience (last, DEFAULT NULL), as the legacy
--       readers do. v_internal is true ONLY for 'internal' or 'founder'; customer, supplier, visitor, NULL, blank or any
--       other value is outside (fails closed). Outside: every knowledge_library row passes (b), research only when
--       approved, and the fused reader reserves no own rows. Internal callers read exactly what they read before.
--       The old signatures are DROPPED (an unguarded overload beside a guarded one is what #1567 removed on 19 Oct);
--       CREATE grants EXECUTE to PUBLIC, so both are revoked and granted to service_role only, as before.
--
-- NOT CHANGED, said plainly: no dispatch is added to fn_reason_retrieve / _ml (that is phase 2, and the check below now
-- refuses one that does not pass p_audience); the legacy readers are not touched (#1640 owns their kb_chunks rule); the
-- library's internal predicates are not brought to legacy parity (ops dept_key is still unread for internal callers);
-- no row of any store is changed. Seat stores read by an outside audience now need their verified status, which the
-- legacy readers do not ask for: support_knowledge 322 of 730 verified_sourced, sales_knowledge 5,852 of 7,044.
--
-- PROVED (rolled back): the_knowledge_library_tells_an_outside_audience_only_what_it_may_be_told_probe.sql, run in ONE
--   query after this file. Fixture rows (ZZ DEMO, knowledge tables only, contact no one) of every class go through the
--   real mirror triggers; a customer, supplier, visitor, blank or NULL audience gets none of generated, memory, blank,
--   agent-private, agent-unvalidated, support-internal, support-unverified or pending research, from either reader,
--   while internal and founder get every one, and a verified read-source row still reaches a customer.
-- Prevented by: scripts/checks/every_customer_reachable_reader_carries_the_audience_rules.test.mjs (known-bad controls
--   included: the phase-1 readers and a dispatch without p_audience both fail it).
-- APPLY at merge (release operator), AFTER #1640's knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql:
--   node scripts/apply_sql.mjs scripts/sql/the_knowledge_library_tells_an_outside_audience_only_what_it_may_be_told.sql --apply --ddl
--   then delete its pending note and append it to the END of MANIFEST.txt.

select '[1]'::vector <-> '[1]'::vector as loads_pgvector;

-- ---------------------------------------------------------------------------------------------------------------------
-- (a) The canonical body; ONE expression changed: the kb_chunks verified column (was the literal true).
create or replace function public.fn_knowledge_library_source_sql(p_store text, out sel text, out key text)
language plpgsql immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_lang constant text := 'case when %s like ''%%@ar'' or %s ~ ''^[^A-Za-z]*[\u0621-\u064A]'' then ''ar'' else ''en'' end';
begin
  case p_store
  when 'kb_chunks' then
    key := 'c.id = any($1::bigint[])';
    sel := 'select ''kb_chunks''::text, c.id::text, c.title, c.content, c.category_norm, ''{}''::text[], ''{*}''::text[], '
          || format(v_lang, 'c.id::text', 'c.content') || ', c.citation, ''{}''::text[],
                    coalesce(nullif(btrim(c.source_kind), '''') not in (''generated'', ''memory''), false), true, c.embedding_gte
               from public.kb_chunks c
              where /*KEY*/ not (c.source_kind is not distinct from ''qd_kb_pack''
                                 and c.id not in (select split_part(x, '':'', 2)::bigint from public.sales_decision_log s, unnest(s.cited) x
                                                   where x ~ ''^kb_chunks:[0-9]+$''))';   -- a hashed subplan, read once
  when 'ops_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''ops_knowledge''::text, c.record_id, c.title, c.content, c.category_key, ''{}''::text[], ''{*}''::text[], '
          || format(v_lang, 'c.record_id', 'c.content') || ', c.source_path, coalesce(c.source_ids, ''{}''), c.validation_status <> ''draft'',
                    coalesce(c.runtime_eligible and c.supersession_state = ''current''
                             and c.scope_type in (''company'', ''external_source'', ''category''), false), c.embedding_gte
               from public.ops_knowledge c where /*KEY*/ true';
  when 'agent_knowledge' then
    key := 'c.id = any($1::bigint[])';
    sel := 'select ''agent_knowledge''::text, c.id::text, c.topic, c.content, null::text, ''{}''::text[],
                    case when c.agent_key = ''_global'' then ''{*}''::text[] else array[c.agent_key] end, '
          || format(v_lang, 'c.id::text', 'c.content') || ', c.source_ref, ''{}''::text[],
                    coalesce(c.validation_status not in (''unsourced'', ''unvalidated'', ''quarantined''), false), true, c.embedding_gte
               from public.agent_knowledge c where /*KEY*/ true';
  when 'sales_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''sales_knowledge''::text, c.record_id, c.title, c.content,
                    (select substr(t, 7) from unnest(c.tags) t where t like ''trade:%%'' limit 1), coalesce(c.tags, ''{}''),
                    case when c.pack_id like ''verified:trade:%%'' or exists (select 1 from unnest(c.tags) t where t like ''trade:%%'')
                         then array[''sales_engineer'', ''customer_support''] else array[''sales_engineer''] end, '
          || format(v_lang, 'c.record_id', 'c.content') || ', c.pack_id, coalesce(c.source_ids, ''{}''),
                    c.epistemic_status = ''verified_pack_sourced'', coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.sales_knowledge c where /*KEY*/ true';
  when 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge' then
    key := 'c.record_id = any($1)';
    sel := format('select %L::text, c.record_id, c.title, c.content, null::text, coalesce(c.tags, ''{}''), array[%L], ',
                    p_store, case p_store when 'accountant_knowledge' then 'accountant' when 'it_engineer_knowledge' then 'it_engineer'
                                          else 'marketing' end)
          || format(v_lang, 'c.record_id', 'c.content') || ', c.pack_id, coalesce(c.source_ids, ''{}''),
                    c.epistemic_status = ''verified_pack_sourced'', coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.' || p_store || ' c where /*KEY*/ true';
  when 'ceo_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''ceo_knowledge''::text, c.record_id, c.title, c.body, null::text, coalesce(c.tags, ''{}''), array[''ceo''],
                    coalesce(nullif(c.language, ''''), ' || format(v_lang, 'c.record_id', 'c.body') || '),
                    coalesce(c.source_path, c.pack_fingerprint), coalesce(c.source_ids, ''{}''), c.review_status = ''verified_sourced'',
                    coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.ceo_knowledge c where /*KEY*/ true';
  when 'support_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''support_knowledge''::text, c.record_id, c.title, c.body, null::text, coalesce(c.tags, ''{}''), array[''customer_support''],
                    coalesce(nullif(c.language, ''''), ' || format(v_lang, 'c.record_id', 'c.body') || '),
                    coalesce(c.source_path, c.pack_id), coalesce(c.source_ids, ''{}''), c.review_status = ''verified_sourced'',
                    coalesce(c.runtime_index_eligible, true), c.embedding_gte
               from public.support_knowledge c where /*KEY*/ true';
  else
    raise exception 'fn_knowledge_library_source: % is not one of the nine stores', p_store;
  end case;
  -- columns: origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref, source_ids, verified,
  -- runtime_eligible, embedding_gte. key: the predicate that picks the origins listed in $1 (text[]).
  -- A row with no text yet (a placeholder a loader fills later) is not knowledge: it waits outside the library, so the
  -- mirror trigger can never fail the writer's own insert on the library's NOT NULL.
  sel := 'select * from (' || sel || ') s (origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref, '
      || 'source_ids, verified, runtime_eligible, embedding_gte) where s.content is not null';
end $fn$;
-- CREATE OR REPLACE keeps the existing ACL (postgres, service_role); restated as in the canonical file.
revoke execute on function public.fn_knowledge_library_source_sql(text) from public, anon, authenticated;

-- The library rows already filled from a kb_chunks row a model or an agent wrote (or with no source_kind) were marked
-- verified by the old mapping: recompute them once, from all their origins, with the corrected one.
do $resync$
begin
  perform pg_advisory_xact_lock_shared(hashtext('public.knowledge_library'));   -- as the writers' triggers take it
  perform public.fn_knowledge_library_recompute(x.library_id)
     from (select distinct o.library_id from public.knowledge_library_origin o join public.kb_chunks c
             on o.origin_store = 'kb_chunks' and c.id = o.origin_id::bigint
            where not coalesce(nullif(btrim(c.source_kind), '') not in ('generated', 'memory'), false)) x;
end $resync$;

-- ---------------------------------------------------------------------------------------------------------------------
-- (b) May an outside audience (customer, supplier, visitor, unknown) be told this library row? FAILS CLOSED: a row
-- that is missing, or whose origins cannot be read, is not told.
create or replace function public.fn_knowledge_library_customer_facing(p_library_id bigint)
returns boolean
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((
    select l.verified
       -- internal by its own tags or citations (the legacy readers' customer branch, #1567)
       and not (l.tags && array['audience:internal', 'kind:company'])
       and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')
       and not exists (select 1 from public.knowledge_library_origin o, unnest(o.source_ids) x
                        where o.library_id = l.id and (x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))
       -- founder ruling 1338 (27 Oct 2026): a text a model or an agent wrote is never told outside, whichever store
       -- also carries it; a blank source_kind, or a kb row that is gone, is not trusted
       and not exists (select 1 from public.knowledge_library_origin o
                        where o.library_id = l.id and o.origin_store = 'kb_chunks'
                          and not exists (select 1 from public.kb_chunks c where c.id = o.origin_id::bigint
                                            and coalesce(nullif(btrim(c.source_kind), '') not in ('generated', 'memory'), false)))
       -- at least one origin passes its own store's customer rule
       and exists (select 1 from public.knowledge_library_origin o where o.library_id = l.id and (
             o.origin_store = 'kb_chunks'
          or (o.origin_store = 'ops_knowledge' and exists (select 1 from public.ops_knowledge x where x.record_id = o.origin_id
                and x.dept_key is null and x.validation_status <> 'draft'))
          or (o.origin_store = 'agent_knowledge' and exists (select 1 from public.agent_knowledge x where x.id = o.origin_id::bigint
                and x.agent_key = '_global' and x.validation_status not in ('unsourced', 'unvalidated', 'quarantined')))
          or (o.origin_store = 'sales_knowledge' and exists (select 1 from public.sales_knowledge x where x.record_id = o.origin_id
                and x.epistemic_status = 'verified_pack_sourced'))
          or (o.origin_store = 'accountant_knowledge' and exists (select 1 from public.accountant_knowledge x where x.record_id = o.origin_id
                and x.epistemic_status = 'verified_pack_sourced'))
          or (o.origin_store = 'it_engineer_knowledge' and exists (select 1 from public.it_engineer_knowledge x where x.record_id = o.origin_id
                and x.epistemic_status = 'verified_pack_sourced'))
          or (o.origin_store = 'marketing_knowledge' and exists (select 1 from public.marketing_knowledge x where x.record_id = o.origin_id
                and x.epistemic_status = 'verified_pack_sourced'))
          or (o.origin_store = 'ceo_knowledge' and exists (select 1 from public.ceo_knowledge x where x.record_id = o.origin_id
                and x.review_status = 'verified_sourced'))
          or (o.origin_store = 'support_knowledge' and exists (select 1 from public.support_knowledge x where x.record_id = o.origin_id
                and x.review_status = 'verified_sourced'))))
      from public.knowledge_library l where l.id = p_library_id), false);
$fn$;
-- A new routine: CREATE grants EXECUTE to PUBLIC.
revoke execute on function public.fn_knowledge_library_customer_facing(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- (c) The readers. The old (audience-less) signatures go; the new ones take p_audience last, as the legacy readers do.
drop function if exists public.fn_reason_retrieve_library(text, vector, integer, text, text, text);
drop function if exists public.fn_reason_retrieve_ml_library(text, vector, vector, integer, integer, text, text, text);

-- THE GTE READER OVER THE LIBRARY. Line for line fn_reason_retrieve: per store k nearest, then the best 2k.
create or replace function public.fn_reason_retrieve_library(p_seat text, p_embedding vector, p_k integer default 6,
  p_trade text default null, p_kind text default null, p_area text default null, p_audience text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
  v_seats constant text[] := array[p_seat, '*'];
  v_trade text[];
  v_kind  text;
  v_area  text;
  -- ONLY AN AUDIENCE NAMED internal OR founder reads internal, unverified and AI-written rows. customer, supplier,
  -- visitor, a NULL or any other value: outside (fails closed, as the legacy readers and settledFacts() in think.ts).
  v_internal constant boolean := lower(btrim(coalesce(p_audience, ''))) in ('internal', 'founder');
begin
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = 'sales_knowledge' and x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = public.fn_knowledge_library_seat_store(p_seat) and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  if p_embedding is null then return out; end if;

  with hits as (
    (select 'kb_chunks' src, l.origin_id id, l.title, left(l.content, 1200) excerpt, l.source_ref citation,
            1 - (l.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.knowledge_library l
      where l.origin_store = 'kb_chunks' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'ops_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'agent_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'sales_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_trade is null or not exists (select 1 from unnest(l.tags) t where t like 'trade:%')
             or (l.tags && v_trade and (v_kind is null or l.tags @> array['kind:' || v_kind])))
        and (v_area is null or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select l.origin_store, l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = public.fn_knowledge_library_seat_store(p_seat) and l.origin_store <> 'sales_knowledge'
        and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_area is null or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected' and (v_internal or r.status = 'approved')
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve_library(text, vector, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_library(text, vector, integer, text, text, text, text) to service_role;

-- THE FUSED READER OVER THE LIBRARY. Line for line fn_reason_retrieve_ml: per store n candidates in each space, both
-- similarities, reciprocal-rank fusion weighted by decisiveness, per store k, the seat's own rows reserved (internal
-- only), then 2k. The outside rule is applied to the candidates (so a withheld row does not take a candidate slot) and
-- again where every library row reaches the result (lib_hits), which is the line no library row can pass around.
create or replace function public.fn_reason_retrieve_ml_library(p_seat text, p_embedding vector, p_embedding_gte vector default null,
  p_k integer default 6, p_own integer default 3, p_trade text default null, p_kind text default null, p_area text default null,
  p_audience text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'extensions', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  -- ONLY AN AUDIENCE NAMED internal OR founder reads internal, unverified and AI-written rows and gets the own-row
  -- reservation. customer, supplier, visitor, a NULL or any other value: outside (fails closed).
  v_internal constant boolean := lower(btrim(coalesce(p_audience, ''))) in ('internal', 'founder');
  k    integer := greatest(1, least(coalesce(p_k, 6), 12));
  own  integer := case when v_internal then greatest(0, least(coalesce(p_own, 3), 2 * k)) else 0 end;
  n    constant integer := 20;
  g    vector(384) := p_embedding_gte;
  m    vector(384) := p_embedding;
  out  jsonb := '[]'::jsonb;
  v_seats constant text[] := array[p_seat, '*'];
  v_own_store constant text := public.fn_knowledge_library_seat_store(p_seat);
  v_trade text[];
  v_kind  text;
  v_area  text;
begin
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = 'sales_knowledge' and x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = v_own_store and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  if m is null then return out; end if;
  with elig as materialized (
    -- every non-kb library row this seat may read, with the legacy reader's store predicates: the trade only on
    -- sales_knowledge, the area only on the seat stores (sales_knowledge and the seat's own); outside, only what (b) allows
    select l.id, l.origin_store, l.origin_id from public.knowledge_library l
     where l.origin_store in ('ops_knowledge', 'agent_knowledge', 'sales_knowledge', v_own_store)
       and l.runtime_eligible and l.seats && v_seats
       and (l.origin_store <> 'sales_knowledge' or v_trade is null or not exists (select 1 from unnest(l.tags) t where t like 'trade:%')
            or (l.tags && v_trade and (v_kind is null or l.tags @> array['kind:' || v_kind])))
       and (l.origin_store in ('ops_knowledge', 'agent_knowledge') or v_area is null
            or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
       and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
  ), cand as (
    (select 'kb_chunks' src, l.origin_id row_id, l.id lib_id from public.knowledge_vector_ml v
       join public.knowledge_library l on v.src = 'knowledge_library' and l.id = v.row_id::bigint
      where l.origin_store = 'kb_chunks' and l.runtime_eligible and l.seats && v_seats
        and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
      order by v.embedding <=> m limit n)
    union (select 'kb_chunks', l.origin_id, l.id from public.knowledge_library l
            where g is not null and l.origin_store = 'kb_chunks' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
              and (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
            order by l.embedding_gte <=> g limit n)
    union (select x.src, x.row_id, x.lib_id from (
             select e.origin_store src, e.origin_id row_id, e.id lib_id, row_number() over (partition by e.origin_store order by e.d) rn
               from (select e.*, (select v.embedding <=> m from public.knowledge_vector_ml v      -- one pkey probe a row: a join
                                   where v.src = 'knowledge_library' and v.row_id = e.id::text) d -- here was planned as 2,303
                       from elig e) e                                                             -- seq scans (4.5 s)
              where e.d is not null) x
            where x.rn <= n)
    union (select x.src, x.row_id, x.lib_id from (
             select e.origin_store src, e.origin_id row_id, e.id lib_id,
                    row_number() over (partition by e.origin_store order by l.embedding_gte <=> g) rn
               from elig e join public.knowledge_library l on l.id = e.id
              where g is not null and l.embedding_gte is not null) x
            where x.rn <= n)
    union (select 'company_faq', f.id::text, null::bigint from public.knowledge_vector_ml v join public.company_faq f on v.src = 'company_faq' and f.id::text = v.row_id
            where f.status = 'approved' order by v.embedding <=> m limit n)
    union (select 'company_faq', f.id::text, null::bigint from public.company_faq f
            where g is not null and f.embedding_gte is not null and f.status = 'approved' order by f.embedding_gte <=> g limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text, null::bigint from public.knowledge_vector_ml v
             join public.reasoning_knowledge_candidate r on v.src = 'reasoning_knowledge_candidate' and r.id::text = v.row_id
            where r.status <> 'rejected' and (v_internal or r.status = 'approved') order by v.embedding <=> m limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text, null::bigint from public.reasoning_knowledge_candidate r
            where g is not null and r.embedding_gte is not null and r.status <> 'rejected' and (v_internal or r.status = 'approved')
            order by r.embedding_gte <=> g limit n)
  ), sims as (
    select c.src, c.row_id, c.lib_id,
           case when c.lib_id is not null
                then (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = 'knowledge_library' and v.row_id = c.lib_id::text)
                else (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = c.src and v.row_id = c.row_id) end s_ml,
           case when g is null then null
                when c.lib_id is not null then (select 1 - (x.embedding_gte <=> g) from public.knowledge_library x where x.id = c.lib_id)
                when c.src = 'company_faq' then (select 1 - (x.embedding_gte <=> g) from public.company_faq x where x.id = c.row_id::bigint)
                else (select 1 - (x.embedding_gte <=> g) from public.reasoning_knowledge_candidate x where x.id = c.row_id::bigint)
           end s_gte
      from cand c
  ), ranked as (
    select s.*,
           case when s_ml is not null then row_number() over (order by s_ml desc nulls last) end r_ml,
           case when s_gte is not null then row_number() over (order by s_gte desc nulls last) end r_gte
      from sims s
  ), gaps as (
    select coalesce(max(s_ml) - coalesce(max(s_ml) filter (where r_ml = n + 1), min(s_ml)), 0) d_ml,
           coalesce(max(s_gte) - coalesce(max(s_gte) filter (where r_gte = n + 1), min(s_gte)), 0) d_gte
      from ranked
  ), scored as materialized (
    select r.*,
           coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_ml / (gp.d_ml + gp.d_gte) else 1 end / (60 + r.r_ml), 0)
         + coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_gte / (gp.d_ml + gp.d_gte) else 0 end / (60 + r.r_gte), 0) score
      from ranked r cross join gaps gp
  ), lib_hits as (
    select l.origin_store src, l.origin_id id, l.title, left(l.content, 1200) excerpt, l.source_ref citation, sc.s_ml, sc.score,
           'reviewed' trust, not ('*' = any(l.seats)) mine,
           row_number() over (partition by l.origin_store order by sc.score desc) rn
      from scored sc join public.knowledge_library l on l.id = sc.lib_id
     where (v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))
  ), hits as (
    select src, id, title, excerpt, citation, s_ml, score, trust, mine from lib_hits where rn <= k
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id, sc.s_ml, sc.score, 'reviewed', false
       from (select *, row_id::bigint key from scored where src = 'company_faq') sc join public.company_faq f on f.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url', sc.s_ml, sc.score,
            case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from (select *, row_id::bigint key from scored where src = 'reasoning_knowledge_candidate') sc join public.reasoning_knowledge_candidate r on r.id = sc.key
      where r.status <> 'rejected' and (v_internal or r.status = 'approved')
      order by sc.score desc limit k)
  ), own_rows as (
    select * from hits where mine order by score desc limit own
  ), chosen as (
    select o.*, true reserved from own_rows o
    union all
    select *, false from (select h.* from hits h where not exists (select 1 from own_rows o where o.src = h.src and o.id = h.id)
                    order by h.score desc limit greatest(k * 2 - (select count(*) from own_rows), 0)) rest
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(coalesce(s_ml, 0)::numeric, 4), 'score', round(score::numeric, 6),
           'trust', trust, 'own', mine) order by reserved desc, score desc), '[]'::jsonb)
    into out
    from chosen;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve_ml_library(text, vector, vector, integer, integer, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_ml_library(text, vector, vector, integer, integer, text, text, text, text) to service_role;
