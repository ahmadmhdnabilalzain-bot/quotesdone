-- NO EXTERNAL ANSWER CAN STATE AN INTERNAL NUMBER (19 Oct 2026). Assigned: customer_support (the reply path);
-- the knowledge rows are written by ceo's company-knowledge sync and are only withheld here, not rewritten.
--
-- WHAT HAPPENED: in the qualification exam (knowledge/exams/customer_support.json, customer_support-exam-06, expected
-- rule customer_support:never-reveal-internal-numbers) the support seat told a SUPPLIER our registered supplier count.
--
-- ROOT CAUSE, MEASURED 19 Oct 2026 (production, read-only):
--   * ops_knowledge 'qd-company:business-entities' (written by fn_company_org_directory_sync through
--     fn_company_knowledge_upsert) carries "THE BUSINESS RIGHT NOW (live counts): ... Suppliers: <n> total, <n>
--     approved, <n> prospective; sendable pool <n>". 'qd-company:live-state' (revenue, customers, approved suppliers,
--     sendable pool) and 'qd-company:supplier-loops' (invited / registered counts), from fn_company_self_knowledge_sync,
--     are the same kind of row. All 9,143 ops_knowledge rows are confidentiality='internal' and runtime_eligible=true,
--     so neither flag separates a live-figure row from an operating rule.
--   * Those rows reach external answers by doors that never look at audience: fn_sales_assist (the portal sales chat;
--     filters only supersession_state='current') and v_support_corpus (supportReply's corpus; its ops branch had no
--     filter, and fn_support_corpus_search reads every row when p_public is false, i.e. on the portal).
--   * company_faq 310 and 361 (approved) state the directory size ("20,000+") and are labelled internal only in prose.
--   * The reply prompt already says not to state how many suppliers or customers we have: a prompt rule, which is
--     exactly what founder instruction 781 says will leak. Nothing in code refused such a reply.
--
-- THE FIX, at the points every path shares:
--   1. public.knowledge_internal_figure_record names the rows that carry live business figures. A BEFORE trigger on
--      ops_knowledge holds every row it names at supersession_state='withdrawn', runtime_eligible=false on every
--      write, so the next sync cannot put the figure back into a corpus. Every runtime reader of ops_knowledge already
--      filters supersession_state='current' (fn_sales_assist, the knowledge_vector_ml paths); v_support_corpus did not,
--      and now does (step 2). Internal readers that need live numbers read them live (fn_company_context).
--   2. v_support_corpus: the ops branch admits only current, runtime-eligible rows (the supportkb branch already
--      filtered runtime_index_eligible). Column list unchanged.
--   3. company_faq 310 and 361 are withheld from the public corpus by support_public_override (the text is the CEO's;
--      this does not edit it).
--   4. CODE BACKSTOP for every channel: supabase/functions/_shared/support_reply_guard.ts gains the violation
--      'internal_number' (a count of suppliers, customers, companies, leads, registrations, listings or entries, other
--      than the published 1,000 / 1,001 programme figures). aiReply rewrites a reply that has it; guardSupportReply
--      drops the sentence as the last line. One file, every channel (widget, portal, WhatsApp, email).
--
-- WHAT THIS DOES NOT DO: it does not delete or rewrite the knowledge rows (ceo's sync still writes them for internal
-- use), and it does not change a published programme figure.
--
-- Prevented by: supabase/functions/_shared/support_reply_guard_internal_number.test.ts (the guard refuses the exam's kind
-- of answer, English and Arabic, and passes the published figures) and scripts/checks/customer_support_senior_
-- contributions_are_working_duties.test.mjs (the trigger and the view filter, and in production the row withdrawn).
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/no_external_answer_can_state_an_internal_number.sql --apply --ddl

create table if not exists public.knowledge_internal_figure_record (
  record_id text primary key,
  why       text not null,
  added_at  timestamptz not null default now()
);
comment on table public.knowledge_internal_figure_record is
  'ops_knowledge rows that carry live business figures (counts, revenue, pools). fn_knowledge_internal_figures_withheld keeps each one withdrawn and not runtime-eligible, so no external answer can retrieve it.';
alter table public.knowledge_internal_figure_record enable row level security;
drop policy if exists knowledge_internal_figure_record_service_role_only on public.knowledge_internal_figure_record;
create policy knowledge_internal_figure_record_service_role_only on public.knowledge_internal_figure_record
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_internal_figure_record from anon, authenticated;

insert into public.knowledge_internal_figure_record (record_id, why) values
  ('qd-company:business-entities', 'live customer and supplier counts, sendable pool (fn_company_org_directory_sync)'),
  ('qd-company:live-state',        'revenue, customers, approved suppliers, sendable pool (fn_company_self_knowledge_sync)'),
  ('qd-company:supplier-loops',    'invited and registered supplier counts (fn_company_self_knowledge_sync)')
on conflict (record_id) do nothing;

create or replace function public.fn_knowledge_internal_figures_withheld()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if exists (select 1 from public.knowledge_internal_figure_record r where r.record_id = new.record_id) then
    new.supersession_state := 'withdrawn';
    new.runtime_eligible := false;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_knowledge_internal_figures_withheld() from public, anon, authenticated;

drop trigger if exists a05_knowledge_internal_figures_withheld on public.ops_knowledge;
create trigger a05_knowledge_internal_figures_withheld before insert or update on public.ops_knowledge
  for each row execute function public.fn_knowledge_internal_figures_withheld();

-- the rows as they are today
update public.ops_knowledge k set supersession_state = 'withdrawn', runtime_eligible = false
 where k.record_id in (select record_id from public.knowledge_internal_figure_record)
   and (k.supersession_state is distinct from 'withdrawn' or k.runtime_eligible);

insert into public.support_public_override (src, src_id, is_public, decided_by, rationale) values
  ('faq', '310', false, 'customer_support', 'states the supplier directory size, an internal number (exam leak, 19 Oct 2026)'),
  ('faq', '361', false, 'customer_support', 'states the supplier directory size, an internal number (exam leak, 19 Oct 2026)')
on conflict (src, src_id) do update set is_public = false, decided_by = excluded.decided_by, rationale = excluded.rationale, decided_at = now();

-- 2. the support corpus: only current, runtime-eligible operating knowledge (column list unchanged)
create or replace view public.v_support_corpus AS  WITH base AS (
         SELECT 'faq'::text AS src,
            (f.id)::text AS src_id,
            f.question AS title,
            f.answer AS content,
            f.embedding_gte,
            COALESCE(o.is_public, f.public, false) AS is_public,
            f.audience,
            ('FAQ: '::text || f.question) AS citation,
            f.updated_at AS as_of,
            COALESCE(f.language, 'en'::text) AS lang
           FROM (company_faq f
             LEFT JOIN support_public_override o ON (((o.src = 'faq'::text) AND (o.src_id = (f.id)::text))))
          WHERE (f.status = 'approved'::text)
        UNION ALL
         SELECT 'supportkb'::text AS src,
            s.record_id AS src_id,
            s.title,
            s.body AS content,
            NULL::vector(384) AS embedding_gte,
            COALESCE(o.is_public, false) AS is_public,
            'all'::text AS audience,
            ('Support pack: '::text || s.title) AS citation,
            s.imported_at AS as_of,
            COALESCE(s.language, 'en'::text) AS lang
           FROM (support_knowledge s
             LEFT JOIN support_public_override o ON (((o.src = 'supportkb'::text) AND (o.src_id = s.record_id))))
          WHERE s.runtime_index_eligible
        UNION ALL
         SELECT 'ops'::text AS src,
            k.record_id AS src_id,
            k.title,
            k.content,
            k.embedding_gte,
            COALESCE(o.is_public, false) AS is_public,
            'all'::text AS audience,
            ('Operations: '::text || k.title) AS citation,
            NULL::timestamp with time zone AS as_of,
            'en'::text AS lang
           FROM (ops_knowledge k
             LEFT JOIN support_public_override o ON (((o.src = 'ops'::text) AND (o.src_id = k.record_id))))
          WHERE ((COALESCE(k.supersession_state, 'current'::text) = 'current'::text) AND k.runtime_eligible)
        )
 SELECT src,
    src_id,
    title,
    content,
    embedding_gte,
    (is_public AND (src = 'faq'::text) AND (COALESCE(content, ''::text) !~ '[{][{]?[a-zA-Z_]+[}]?[}]'::text) AND (COALESCE(title, ''::text) !~ '[{][{]?[a-zA-Z_]+[}]?[}]'::text) AND (COALESCE(content, ''::text) !~* '(draft, not [a-z-]+ approved|not provider-approved|internal use only)'::text)) AS is_public,
    audience,
    citation,
    as_of,
    lang
   FROM base b;
revoke all on public.v_support_corpus from public, anon, authenticated;
