-- ONE BODY OF KNOWLEDGE FOR THE AGENT WHO ANSWERS.
--
-- Founder, 8 September 2026: "the chat widget on home screen belongs to customer support agent. so
-- combine the knowledge for him."
--
-- WHAT WAS ACTUALLY WRONG, because it is not what the instruction assumes. The knowledge is not
-- merely scattered — the pack built FOR this agent was never connected to it. Measured:
--
--   * site_assistant (the widget) answers from public.company_faq, 484 rows, plus a hard-coded facts
--     string in its own source. That is the entire grounding of every answer a visitor gets.
--   * public.support_knowledge — 407 records imported 7 Sep 20:03, with pinned invariants like
--     "escalation goes to the CEO, never to the founder" — is read by NOTHING that is deployed. Its
--     only callers are two local evaluation scripts.
--   * fn_support_knowledge_search exists, works, and no live code path calls it.
--
-- So combining the knowledge is not a merge of two things that are both in use. It is connecting the
-- one that was built and never wired, to the agent it was built for.
--
-- THE SHAPE: A VIEW, NOT A COPY. Excluding kb_chunks, the whole support-relevant corpus is about
-- 13,000 rows. A materialised copy would buy a synchronisation problem and save nothing at that size,
-- so v_support_corpus is a union over the tables where the rows already live. Nothing is duplicated
-- and nothing has to be kept in step.
--
-- THE PART THAT MATTERS MOST IS THE VISIBILITY COLUMN, and it is worth being exact about why. This
-- corpus is mostly INTERNAL: engineering notes, estate architecture, founder decisions, department
-- handoffs. The widget is public — anyone on the home page can talk to it. Measured, exactly 159 rows
-- in the entire estate are explicitly marked publicly quotable (151 company_faq rows flagged public,
-- 8 legal documents). Everything else is flagged internal or unflagged, and ops_knowledge marks all
-- 9,140 of its rows 'internal'.
--
-- So visibility is DERIVED FROM MARKERS THAT ALREADY EXIST, defaulting to internal, and the search
-- function takes it as a REQUIRED argument with no default. A public caller cannot forget to pass it
-- and cannot pass the wrong thing by omission. Putting that rule in a prompt instead would make the
-- model responsible for not leaking, which is not a control.
--
-- The promotion table exists because 159 rows is too small a public corpus to answer from. A row
-- becomes public by a decision recorded in support_public_override, one row per promotion, with who
-- decided it — not by a bulk flag flip nobody can audit later.
--
--   node scripts/apply_sql.mjs scripts/sql/one_body_of_knowledge_for_the_agent_who_answers.sql --apply --ddl

begin;

-- ── DECISIONS THAT MAKE A RECORD PUBLICLY QUOTABLE ─────────────────────────────────────────────
create table if not exists public.support_public_override (
  src         text not null,
  src_id      text not null,
  is_public   boolean not null,
  decided_by  text not null,
  rationale   text not null,
  decided_at  timestamptz not null default now(),
  primary key (src, src_id)
);

comment on table public.support_public_override is
  'One row per record whose publicity was decided deliberately. The default is internal; this table '
  'is the only way something becomes quotable to a stranger on the home page.';

-- ── THE COMBINED BODY ──────────────────────────────────────────────────────────────────────────
create or replace view public.v_support_corpus as
  select 'faq'::text as src,
         f.id::text  as src_id,
         f.question  as title,
         f.answer    as content,
         f.embedding_gte,
         coalesce(o.is_public, f.public, false) as is_public,
         f.audience,
         'FAQ: ' || f.question as citation,
         f.updated_at as as_of
    from public.company_faq f
    left join public.support_public_override o on o.src = 'faq' and o.src_id = f.id::text
   where f.status = 'approved'

  union all

  select 'supportkb', s.record_id::text, s.title, s.body, null::vector(384),
         coalesce(o.is_public, false),          -- every row is runtime_use='internal_advisory'
         'all',
         'Support pack: ' || s.title,
         s.imported_at
    from public.support_knowledge s
    left join public.support_public_override o on o.src = 'supportkb' and o.src_id = s.record_id::text
   where s.runtime_index_eligible

  union all

  select 'ops', k.record_id::text, k.title, k.content, k.embedding_gte,
         coalesce(o.is_public, false),          -- confidentiality = 'internal' on all 9,140 rows
         'all',
         'Operations: ' || k.title,
         null::timestamptz
    from public.ops_knowledge k
    left join public.support_public_override o on o.src = 'ops' and o.src_id = k.record_id::text;

comment on view public.v_support_corpus is
  'The customer-support agent''s single body of knowledge. is_public defaults to FALSE and is raised '
  'only by an explicit row in support_public_override. fn_support_corpus_search takes visibility as a '
  'required argument so a public caller cannot omit it.';

-- ── THE SEARCH THE AGENT ACTUALLY CALLS ────────────────────────────────────────────────────────
-- p_public has NO DEFAULT. That is the control: site_assistant must say, at the call site, that it is
-- answering a stranger. A default would be a leak waiting for the one caller who forgets.
create or replace function public.fn_support_corpus_search(
  p_query text,
  p_public boolean,
  p_limit int default 8
) returns table (src text, src_id text, title text, content text, citation text, rank real)
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select c.src, c.src_id, c.title, c.content, c.citation,
         ts_rank(to_tsvector('english', coalesce(c.title,'') || ' ' || coalesce(c.content,'')),
                 websearch_to_tsquery('english', p_query)) as rank
    from public.v_support_corpus c
   where (case when p_public then c.is_public else true end)
     and to_tsvector('english', coalesce(c.title,'') || ' ' || coalesce(c.content,''))
         @@ websearch_to_tsquery('english', p_query)
   order by rank desc
   limit greatest(1, least(coalesce(p_limit, 8), 25))
$fn$;

revoke all on function public.fn_support_corpus_search(text, boolean, int) from public;
revoke all on function public.fn_support_corpus_search(text, boolean, int) from anon;

-- ── THE FIRST PROMOTIONS ───────────────────────────────────────────────────────────────────────
-- Without these the public corpus is 151 FAQ rows and the widget answers almost nothing from the pack
-- built for it. Promoted here: the support-pack domains that are customer-facing by subject. The
-- internal domains — anything about the estate, escalation mechanics or authority — are NOT promoted,
-- and stay searchable to the agent while never being quotable to a visitor.
insert into public.support_public_override (src, src_id, is_public, decided_by, rationale)
select 'supportkb', s.record_id::text, true, 'ceo',
       'Customer-facing subject (' || s.domain || '): a visitor asking this deserves the pack''s answer '
       || 'rather than a model''s reconstruction of it.'
  from public.support_knowledge s
 where s.runtime_index_eligible
   and s.domain in ('payments','channels','notifications','privacy','identity',
                    'supplier_documents','message_templates','pricing','refunds','registration')
on conflict (src, src_id) do nothing;

commit;
