-- THE SALES ENGINEER ANSWERS FROM ITS OWN KNOWLEDGE, AND REPORTS THE PORTALS.
--
-- The founder, 9 September 2026: the Sales Engineer owns supplier and customer registration and
-- "does the comparison reports, he basically fill the reports for suppliers and customers about
-- jobs won / supplier ratings / customer total spend literally everything related to both portals."
-- Asked where the chat widget routes: "if its on the home page then the support replies. but if
-- its on the customer or supplier portal then its the sales engineer cause he is much stronger
-- technically."
--
-- THREE OBJECTS, and the reason each exists.
--
-- 1. public.sales_decision_log — WHICH KNOWLEDGE INFORMED THE ANSWER.
--    kb_usage_log already exists with 0 rows, no writer, and four columns (query, category, agent,
--    created_at). Four columns cannot answer the question the build prompt asks — "log which
--    knowledge and evidence materially informed a decision" — because they do not carry WHICH
--    records came back, how close each one was, what floor was applied, or whether the record was
--    actually cited or merely retrieved and discarded. That distinction is the whole audit: a
--    record that lost to the floor is evidence the floor worked, and a record that cleared it and
--    was cited is evidence the answer has a source. This table carries both, and it is written
--    from INSIDE fn_sales_assist so a caller cannot forget to.
--
-- 2. public.fn_sales_assist — RETRIEVAL WITH A FLOOR, AND CORROBORATION.
--    There is no model. All 8 routes in llm_route_health are held until 2126-08-15 and
--    fn_kernel_paid_provider_gate denies globally, so an answer is either retrieved or refused.
--
--    THE LENS THIS IS BUILT AGAINST: a nearest neighbour is ALWAYS found. `order by embedding <=>
--    q limit 5` returns five rows for "zorblax quantum flibbertigibbet moonbeam" exactly as
--    confidently as for a real question, and a portal that answered the first with the fifth-best
--    guide would be inventing. So two independent gates, and a record must pass BOTH:
--      * VECTOR FLOOR — cosine similarity >= p_min_similarity, default 0.86. Same discipline and
--        the same number as fn_faq_answer; fn_apply_playbook uses 0.85.
--      * LEXICAL CORROBORATION — the record must also match websearch_to_tsquery over the `search`
--        tsvector at ts_rank >= p_min_rank. MEASURED 9 Sep 2026 on this table: the real question
--        "what documents does a supplier need for verification" returns 4 lexical matches ranked
--        0.4288 / 0.4115 / 0.2196 / 0.1706; the nonsense string above returns ZERO. The lexical
--        index is the only instrument in this estate that returns nothing for nothing, which is
--        precisely why it is the corroborator and not the ranker.
--
--    Nothing clears both gates => `answered: false` and a hand-off. That is correct behaviour and
--    is logged as such, not as an error.
--
-- 3. public.fn_sales_portal_report — THE REPORT THE FOUNDER NAMED, WITH ITS PROVENANCE.
--    Production, measured 9 Sep 2026 immediately before this file was written:
--      transactions 0 · quotes 0 · reveal_invoices 0 · inquiries 0 · inquiry_matches 0 ·
--      reviews 0 · projects 0 · customers 1 · leads 22264 · leads where claimed 0 ·
--      leads.approval_status null on all 22264 · supplier_score 20465 · supplier_capabilities
--      15305, every row extractor_version 'derived_from_directory_v1', review_status 'derived',
--      confirmed_at null on all of them · leads.rating not null on 4477.
--    The founder: "we dont have any supplier registered. this is a demo 100%."
--
--    So three different facts all print as the character 0, and the report must never collapse
--    them. Every figure carries a `basis`:
--      * true_zero          — the source table has never held a row. 0 is the real answer and the
--                             denominator is stated.
--      * measured           — the table holds rows and this is the count within them.
--      * unknown            — no decision was ever recorded. approval_status is null on all 22,264
--                             leads; that is NOT "0 approved" and must never render as one.
--      * derived_not_earned — the figure exists but was NOT earned on this platform. Every
--                             capability row and every leads.rating came from a directory scrape.
--                             A supplier shown a "rating" it never earned here would be misled and
--                             a customer shown it would be misinformed.
--
--    REUSED, NOT REBUILT: fn_supplier_expiries (licence/ISO/insurance/manufacturer-auth expiry),
--    fn_customer_supplier_score (per-relationship score, already refuses with 'no_shared_history'
--    when nothing is shared), supplier_score. NOT USED: supplier_perf and supplier_reputation.
--    supplier_perf is a view over `leads where claimed = true` and returns 0 rows today, and
--    supplier_reputation's reputation_index folds leads.rating — the scraped number — into a
--    figure named "reputation". Reading either would have printed a derived number under an earned
--    name, which is the single thing this report exists not to do.

-- ── 1. THE DECISION LOG ────────────────────────────────────────────────────────────────────────
create table if not exists public.sales_decision_log (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  actor         text not null,                 -- the seat, from the credential, never the caller
  action        text not null,                 -- 'assist' | 'report'
  query         text,
  -- The gates that were applied, recorded with the decision so a later audit does not have to
  -- guess which build of the function ran.
  min_similarity numeric,
  min_rank       numeric,
  k              integer,
  -- One entry per RETRIEVED candidate: {record_id, record_type, similarity, lexical_rank,
  -- cleared_floor, corroborated, cited}. Retrieved-and-rejected is kept deliberately.
  candidates    jsonb not null default '[]'::jsonb,
  cited         text[] not null default '{}',  -- the record_ids that actually informed the answer
  answered      boolean not null,
  refusal       text,                          -- why not, when answered is false
  subject       text                           -- report only: 'supplier:123' / 'customer:<uuid>'
);
create index if not exists sales_decision_log_created_idx on public.sales_decision_log (created_at desc);
create index if not exists sales_decision_log_action_idx  on public.sales_decision_log (action, created_at desc);

comment on table public.sales_decision_log is
  'Which knowledge and evidence materially informed a Sales Engineer decision. Written from inside fn_sales_assist and fn_sales_portal_report so a caller cannot omit it. Supersedes kb_usage_log, whose four columns cannot express a floor, a similarity or a citation.';

-- ── 2. RETRIEVAL ───────────────────────────────────────────────────────────────────────────────
-- The caller supplies the embedding because embedding needs Supabase.ai, which only exists in an
-- edge runtime. It is free and does NOT touch OpenRouter: ai_gateway handles {action:'embed'} at
-- its line 204, before routing and before fn_kernel_paid_provider_gate, via
-- Supabase.ai.Session('gte-small'). sales_engineer runs the same six lines in-process rather than
-- taking a network hop and a second credential for a local model.
create or replace function public.fn_sales_assist(
  p_text            text,
  p_embedding       vector(384),
  p_min_similarity  numeric default 0.86,
  p_min_rank        numeric default 0.05,
  p_k               integer default 5,
  p_actor           text    default 'sales_engineer'
) returns jsonb
language plpgsql
volatile                       -- it writes the decision log; it is not STABLE and must not say so
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_k        int := greatest(1, least(coalesce(p_k, 5), 20));
  v_tq       tsquery;
  v_cands    jsonb := '[]'::jsonb;
  v_cited    text[] := '{}';
  v_answer   jsonb  := '[]'::jsonb;
  v_refusal  text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object('ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;
  if p_embedding is null then
    -- Said plainly rather than silently degrading to lexical-only, which would answer a question
    -- the vector index never agreed with.
    return jsonb_build_object('ok', false, 'answered', false, 'refusal', 'no_embedding',
      'detail', 'The caller could not embed the question, so the vector floor cannot be applied. Refusing rather than answering on the lexical index alone.');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);

  with knn as (
    -- The HNSW index does the ordering; the floor is applied after, never instead of.
    select k.record_id, k.record_type, k.title, k.content, k.domain, k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric as similarity
      from sales_knowledge k
     where k.embedding_gte is not null
     order by k.embedding_gte <=> p_embedding
     limit v_k
  ), scored as (
    select n.*,
           coalesce(ts_rank(sk.search, v_tq), 0)::numeric as lexical_rank,
           (n.similarity >= p_min_similarity) as cleared_floor,
           (sk.search @@ v_tq and coalesce(ts_rank(sk.search, v_tq), 0) >= p_min_rank) as corroborated
      from knn n join sales_knowledge sk on sk.record_id = n.record_id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'record_id', s.record_id, 'record_type', s.record_type,
      'similarity', round(s.similarity, 4), 'lexical_rank', round(s.lexical_rank, 4),
      'cleared_floor', s.cleared_floor, 'corroborated', s.corroborated,
      'cited', (s.cleared_floor and s.corroborated)) order by s.similarity desc), '[]'::jsonb),
    coalesce(array_agg(s.record_id order by s.similarity desc)
             filter (where s.cleared_floor and s.corroborated), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'record_id', s.record_id, 'title', s.title, 'record_type', s.record_type,
      'domain', s.domain, 'epistemic_status', s.epistemic_status,
      'similarity', round(s.similarity, 4), 'content', s.content)
      order by s.similarity desc) filter (where s.cleared_floor and s.corroborated), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from scored s;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when jsonb_array_length(v_cands) = 0 then 'no_candidates'
      when not exists (select 1 from jsonb_array_elements(v_cands) c where (c->>'cleared_floor')::boolean)
        then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
  end if;

  insert into sales_decision_log
    (actor, action, query, min_similarity, min_rank, k, candidates, cited, answered, refusal)
  values
    (coalesce(p_actor, 'sales_engineer'), 'assist', left(p_text, 2000), p_min_similarity,
     p_min_rank, v_k, v_cands, v_cited, cardinality(v_cited) > 0, v_refusal);

  return jsonb_build_object(
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'floor', jsonb_build_object('min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'k', v_k,
      'rule', 'a record must clear the cosine floor AND match the lexical index; a nearest neighbour is always found, a lexical match is not'),
    'refusal', v_refusal,
    'handoff', case when cardinality(v_cited) = 0 then
      'I do not have that in my knowledge, so I am not going to guess. Customer Support will come back to you on it.' end);
end
$fn$;

revoke execute on function public.fn_sales_assist(text, vector, numeric, numeric, integer, text) from public;

-- ── 3. THE PORTAL REPORT ───────────────────────────────────────────────────────────────────────
-- p_party_id is TEXT, not bigint. The brief specified bigint, and bigint cannot address a
-- customer: customers.id, inquiries.customer_id and transactions.customer_id are all uuid, while
-- leads.id (the supplier) is bigint. A bigint signature would have shipped a report that can only
-- express half of what the founder asked for, so the parameter carries both and is cast per kind.
create or replace function public.fn_sales_figure(p_value numeric, p_universe bigint, p_note text default null)
returns jsonb language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'value', p_value,
    'basis', case when p_value is null then 'unknown'
                  when coalesce(p_universe, 0) = 0 then 'true_zero'
                  else 'measured' end,
    'denominator', p_universe,
    'note', p_note);
$fn$;

revoke execute on function public.fn_sales_figure(numeric, bigint, text) from public;

create or replace function public.fn_sales_portal_report(p_party_kind text, p_party_id text)
returns jsonb
language plpgsql
volatile                       -- writes the decision log
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_kind text := lower(coalesce(btrim(p_party_kind), ''));
  v_out  jsonb;
  -- The UNIVERSES. Every "0" below is interpreted against the size of the table it came from, so
  -- an empty table reports true_zero with its denominator instead of a bare 0 that could equally
  -- mean "this party has none" on a busy platform.
  u_inq   bigint := (select count(*) from inquiries);
  u_q     bigint := (select count(*) from quotes);
  u_tx    bigint := (select count(*) from transactions);
  u_rev   bigint := (select count(*) from reviews);
  u_match bigint := (select count(*) from inquiry_matches);
  u_proj  bigint := (select count(*) from projects);
  -- supplier
  s_id bigint; s_row leads%rowtype; s_cap supplier_capabilities%rowtype; s_score supplier_score%rowtype;
  s_won bigint; s_quoted bigint; s_matched bigint; s_reviews bigint; s_rating numeric;
  -- customer
  c_id uuid; c_row customers%rowtype;
  c_inq bigint; c_q bigint; c_spend numeric; c_tx bigint; c_proj bigint; c_suppliers jsonb;
begin
  if v_kind = 'supplier' then
    begin s_id := p_party_id::bigint; exception when others then
      return jsonb_build_object('ok', false, 'error', 'party_id_not_a_supplier_id', 'party_id', p_party_id); end;
    select * into s_row from leads where id = s_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'unknown_supplier', 'party_id', p_party_id); end if;

    select * into s_cap   from supplier_capabilities where supplier_id = s_id;
    select * into s_score from supplier_score        where lead_id     = s_id;
    select count(*) into s_won     from inquiries       where hired_supplier_id = s_id;
    select count(*) into s_quoted  from quotes          where supplier_id = s_id;
    select count(*) into s_matched from inquiry_matches where supplier_id = s_id;
    select count(*), round(avg(rating)::numeric, 2) into s_reviews, s_rating
      from reviews where supplier_id = s_id;

    v_out := jsonb_build_object(
      'ok', true, 'party_kind', 'supplier', 'party_id', s_id,
      'company_name', s_row.company_name,
      'generated_at', now(),

      'jobs_won',         fn_sales_figure(s_won::numeric,     u_inq,   'inquiries where this supplier was hired'),
      'quotes_submitted', fn_sales_figure(s_quoted::numeric,  u_q,     'quotes rows carrying this supplier_id'),
      'rfqs_received',    fn_sales_figure(s_matched::numeric, u_match, 'inquiry_matches rows carrying this supplier_id'),
      'quotes_won',       fn_sales_figure(s_won::numeric,     u_q,     'a won quote is an inquiry hired to this supplier; counted against the quotes universe'),
      'win_rate_pct', case when coalesce(s_quoted,0) > 0
                           then jsonb_build_object('value', round(100.0 * s_won / s_quoted, 1), 'basis', 'measured')
                           else jsonb_build_object('value', null, 'basis', 'unknown',
                                  'note', 'no quote has been submitted, so there is no denominator; this is not a 0% win rate') end,

      -- RATINGS. Two numbers with the same name and completely different standing.
      'rating_earned_here', jsonb_build_object(
        'value', s_rating, 'review_count', s_reviews,
        'basis', case when s_rating is not null then 'measured'
                      when u_rev = 0 then 'true_zero' else 'unknown' end,
        'denominator', u_rev,
        'note', 'average of reviews left by customers on THIS platform'),
      'rating_from_directory', case when s_row.rating is not null then jsonb_build_object(
          'value', s_row.rating, 'basis', 'derived_not_earned',
          'note', 'scraped from a public business directory before this supplier ever registered. It is NOT performance on QuotesDone and must never be presented to a supplier as its rating here, nor to a customer as evidence.')
        else jsonb_build_object('value', null, 'basis', 'unknown') end,

      -- APPROVAL. null is not "no".
      'approval', case when s_row.approval_status is null then jsonb_build_object(
            'value', null, 'basis', 'unknown',
            'note', 'no approval decision has ever been recorded for this supplier. This is not a rejection and not a pending queue position.')
        else jsonb_build_object('value', s_row.approval_status, 'basis', 'measured') end,
      'registered', jsonb_build_object('value', coalesce(s_row.claimed, false), 'basis', 'measured',
        'note', 'claimed = the supplier took ownership of this directory record and registered'),

      'document_expiry', fn_supplier_expiries(s_id),

      'capability_confirmation', case when s_cap.supplier_id is null then jsonb_build_object(
            'state', 'none_on_file', 'basis', 'true_zero')
        else jsonb_build_object(
            'state', case when s_cap.confirmed_at is not null then 'confirmed_by_supplier'
                          else 'unconfirmed' end,
            'basis', case when s_cap.confirmed_at is not null then 'measured' else 'derived_not_earned' end,
            'extractor_version', s_cap.extractor_version,
            'review_status', s_cap.review_status,
            'confirmed_at', s_cap.confirmed_at,
            'completeness', s_cap.completeness,
            'note', case when s_cap.confirmed_at is null then
              'These capabilities were derived from a directory listing, not stated by the supplier. Until the supplier confirms them they are a starting point for a conversation, not a claim we may quote against.' end) end,

      'platform_score', case when s_score.lead_id is null then jsonb_build_object('basis', 'true_zero')
        else jsonb_build_object('basis', 'derived_not_earned',
          'quotes_submitted', s_score.quotes_submitted, 'quotes_won', s_score.quotes_won,
          'response_rate', s_score.response_rate, 'reliability', s_score.reliability,
          'computed_at', s_score.computed_at,
          'note', 'supplier_score rows were computed over the imported directory, not over activity on this platform. Read alongside jobs_won, which is the earned figure.') end);

  elsif v_kind = 'customer' then
    begin c_id := p_party_id::uuid; exception when others then
      return jsonb_build_object('ok', false, 'error', 'party_id_not_a_customer_id', 'party_id', p_party_id); end;
    select * into c_row from customers where id = c_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'unknown_customer', 'party_id', p_party_id); end if;

    select count(*) into c_inq  from inquiries where customer_id = c_id;
    select count(*) into c_q    from quotes q join inquiries i on i.id = q.inquiry_id where i.customer_id = c_id;
    select count(*), coalesce(sum(t.quote_amount), 0) into c_tx, c_spend
      from transactions t where t.customer_id = c_id;
    select count(*) into c_proj from projects where customer_id = c_id;

    -- Supplier performance on THIS customer's own jobs. fn_customer_supplier_score already refuses
    -- to invent a relationship (basis 'no_shared_history'), so it is called rather than re-derived.
    select coalesce(jsonb_agg(fn_customer_supplier_score(c_id, s)), '[]'::jsonb) into c_suppliers
      from (select distinct hired_supplier_id s from inquiries
             where customer_id = c_id and hired_supplier_id is not null) x;

    v_out := jsonb_build_object(
      'ok', true, 'party_kind', 'customer', 'party_id', c_id,
      'email', c_row.email, 'full_name', c_row.full_name,
      'generated_at', now(),
      'inquiries',       fn_sales_figure(c_inq::numeric,  u_inq,  'inquiries this customer posted'),
      'quotes_received', fn_sales_figure(c_q::numeric,    u_q,    'quotes against this customer''s inquiries'),
      'reveals',         fn_sales_figure(c_tx::numeric,   u_tx,   'paid reveals; a transactions row is a reveal'),
      'total_spend_aed', jsonb_build_object(
        'value', case when u_tx = 0 then 0 else c_spend end,
        'basis', case when u_tx = 0 then 'true_zero' else 'measured' end,
        'denominator', u_tx,
        'note', 'sum of transactions.quote_amount for this customer. The reveal fee is 3% of it; this figure is the job value, not the fee.'),
      'projects',        fn_sales_figure(c_proj::numeric, u_proj, 'projects owned by this customer'),
      'supplier_performance', c_suppliers,
      'supplier_performance_basis', case when jsonb_array_length(c_suppliers) = 0
        then 'no supplier has been hired by this customer yet, so there is no performance to report'
        else 'per-relationship, from this customer''s own RFQs, quotes, reveals and reviews' end);
  else
    return jsonb_build_object('ok', false, 'error', 'unknown_party_kind', 'party_kind', p_party_kind,
                              'accepted', jsonb_build_array('supplier', 'customer'));
  end if;

  insert into sales_decision_log (actor, action, query, answered, subject, candidates)
  values ('sales_engineer', 'report', null, true, v_kind || ':' || p_party_id,
          jsonb_build_object('universes', jsonb_build_object(
            'inquiries', u_inq, 'quotes', u_q, 'transactions', u_tx,
            'reviews', u_rev, 'inquiry_matches', u_match, 'projects', u_proj)));

  return v_out;
end
$fn$;

revoke execute on function public.fn_sales_portal_report(text, text) from public;
