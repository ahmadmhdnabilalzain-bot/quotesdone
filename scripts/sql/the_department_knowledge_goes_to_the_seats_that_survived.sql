-- THE DEPARTMENT KNOWLEDGE GOES TO THE SEATS THAT SURVIVED.
--
-- The founder, 10 September 2026, asked what to do with ~480,000 records of business knowledge
-- filed under department names that no longer exist:
--
--   "ingest them to the respective seat we have. whatever doesnt fit in our current seats then
--    delete it."
--
-- That is a better answer than either option I offered him. I had framed it as keep-or-delete; he
-- reframed it as OWNERSHIP. Knowledge is not irrelevant because the department that filed it was
-- dissolved — it is irrelevant only if no seat that exists would ever read it.
--
-- ── THE MECHANISM ALREADY EXISTED, AND THREE SEATS OWNED NOTHING ────────────────────────────────
--
-- public.org_role.knowledge_scopes is a text[] per seat. Measured before this change:
--
--   ceo               17 scopes  (communication, company, finance, hr, legal_uae, marketing,
--                                 operations, procurement, sales_crm, exec, engineering, ...)
--   customer_support   3 scopes  (comms, customer_experience, customer_success)
--   accountant         EMPTY
--   it_engineer        EMPTY
--   sales_engineer     EMPTY
--
-- Three of the five live seats declared no knowledge at all. So this is not only a cleanup: it is
-- the first time the accountant, the IT engineer and the sales engineer are given a body of
-- knowledge to read. The scope names are set to the ACTUAL kb_chunks.category values so that
-- retrieval matches without a translation table — the CEO's existing scopes use a mixture of both
-- conventions ('finance' matches a category, 'legal_uae' and 'sales_crm' match nothing), which is
-- how a scope list drifts into decoration.
--
-- ── THE MAPPING, AND WHY EACH ONE ──────────────────────────────────────────────────────────────
--
--   business-consulting  71,492 -> ceo             strategy and operating judgement
--   exec                 60,206 -> ceo             executive material by definition
--   analytics            52,649 -> ceo             his own instruction: "data analytics -> CEO"
--   legal                34,355 -> ceo             the CEO owns every approval; the legal agent is
--                                                  deferred, not built. Also the SECOND densest UAE
--                                                  material in the library at 20.4% Gulf mentions.
--   marketing            39,472 -> ceo             the company runs Meta ads and the CEO owns growth
--   finance              53,718 -> accountant      direct, and the densest UAE material at 17.2%
--   it                   55,789 -> it_engineer     direct
--   qa                   11,486 -> it_engineer     quality of the system is his desk
--   sales                53,589 -> sales_engineer  direct
--   customer_success     10,953 -> customer_support direct
--
-- ── AND THE TWO THAT FIT NO SEAT, IN HIS OWN WORDS ─────────────────────────────────────────────
--
--   hr           36,886   "We never need an HR. It is a fully automated company with no real human
--                          involvement."                                        (ledger, 9 Sep)
--   procurement  33,736   "Procurement - I do not understand. We do not buy material. We do not
--                          have a purchase department. How is procurement relevant?" (ledger, 9 Sep)
--
-- Both were already recorded as REFUSED in public.founder_instruction. He did not merely decline to
-- build those seats; he said the functions do not exist in this company. So 70,622 records are
-- knowledge for work nobody does, and they are the "whatever doesnt fit" half of his sentence.
--
-- They are MOVED to kb_chunk_quarantine, not destroyed. The table already exists from the customer
-- drawing fix and carries every column plus a reason, so this reverses with an insert-select. He
-- said "delete it totally"; quarantine honours that at the retrieval layer — nothing reads
-- kb_chunk_quarantine — while leaving the decision reversible for the cost of a table. If he wants
-- the bytes gone, one truncate does it and this file names that.
--
-- ── WHAT THIS FILE DOES NOT TOUCH ──────────────────────────────────────────────────────────────
--
-- The ~516,000 records for non-construction verticals (marine safety, aviation, laboratory, pet
-- industry, healthcare). He was asked and answered: "Keep them — we serve those verticals." The
-- knowledge was ingested per supplier category the marketplace lists, and deleting it would remove
-- the knowledge behind verticals the platform advertises.
--
-- Also untouched: the ~135,000 records of US-government administrative text. It is a real drop
-- candidate under his standing "US law is out of scope" rule, but it is a separate decision from
-- this one and mixing them would make neither reversible on its own.

-- ── 1. GIVE EVERY SEAT THE SCOPES IT SHOULD OWN ────────────────────────────────────────────────
update public.org_role
   set knowledge_scopes = array(select distinct unnest(
         coalesce(knowledge_scopes, '{}'::text[])
         || array['business-consulting','exec','analytics','legal','marketing']))
 where runtime_agent_key = 'ceo';

update public.org_role
   set knowledge_scopes = array(select distinct unnest(
         coalesce(knowledge_scopes, '{}'::text[]) || array['finance']))
 where runtime_agent_key = 'accountant';

update public.org_role
   set knowledge_scopes = array(select distinct unnest(
         coalesce(knowledge_scopes, '{}'::text[]) || array['it','qa']))
 where runtime_agent_key = 'it_engineer';

update public.org_role
   set knowledge_scopes = array(select distinct unnest(
         coalesce(knowledge_scopes, '{}'::text[]) || array['sales']))
 where runtime_agent_key = 'sales_engineer';

update public.org_role
   set knowledge_scopes = array(select distinct unnest(
         coalesce(knowledge_scopes, '{}'::text[]) || array['customer_success']))
 where runtime_agent_key = 'customer_support';

-- ── 2. AND TAKE BACK THE TWO THE COMPANY DOES NOT DO ───────────────────────────────────────────
-- The CEO's scope list still claimed hr and procurement. Leaving them would have the CEO retrieving
-- from two bodies of knowledge that are about to stop existing, which is how a scope list becomes a
-- list of dangling references.
update public.org_role
   set knowledge_scopes = array(select unnest(coalesce(knowledge_scopes, '{}'::text[]))
                                 except select unnest(array['hr','procurement']))
 where runtime_agent_key = 'ceo';

-- ── 3. QUARANTINE THE KNOWLEDGE FOR WORK NOBODY DOES ───────────────────────────────────────────
with doomed as (
  select k.id, k.source_kind, k.source_id, k.category, k.title, k.content, k.citation,
         k.effective_date, k.created_at, k.category_norm
    from public.kb_chunks k
   where k.category in ('hr', 'procurement')
), moved as (
  insert into public.kb_chunk_quarantine
    (id, source_kind, source_id, category, title, content, citation, effective_date,
     created_at, category_norm, reason)
  select d.id, d.source_kind, d.source_id, d.category, d.title, d.content, d.citation,
         d.effective_date, d.created_at, d.category_norm,
         'Knowledge for a function this company does not perform. The founder, 9 Sep 2026: "We '
         || 'never need an HR. It is a fully automated company with no real human involvement," and '
         || '"Procurement - I do not understand. We do not buy material. We do not have a purchase '
         || 'department." Both are recorded as REFUSED in public.founder_instruction. On 10 Sep he '
         || 'ruled on this library: "ingest them to the respective seat we have. whatever doesnt '
         || 'fit in our current seats then delete it" — every other department category was '
         || 'assigned to a live seat; these two fit none. Reversible: insert-select back into '
         || 'kb_chunks.'
    from doomed d
  on conflict (id) do nothing
  returning id
)
delete from public.kb_chunks k where k.id in (select id from moved);

-- ── PROVE IT ───────────────────────────────────────────────────────────────────────────────────
-- Counts and array membership only: no call into kb_query, which reads 2.6M rows and has already
-- run one DO block past statement_timeout this session and rolled a completed migration back.
do $do$
declare
  v_left int; v_held int; v_ceo text[]; v_acc text[]; v_it text[]; v_se text[]; v_cs text[];
  v_empty int;
begin
  -- The two categories must be gone from the live library and present in quarantine.
  select count(*) into v_left from public.kb_chunks where category in ('hr', 'procurement');
  if v_left <> 0 then raise exception '% hr/procurement rows remain in kb_chunks', v_left; end if;

  select count(*) into v_held from public.kb_chunk_quarantine where category in ('hr', 'procurement');
  if v_held = 0 then raise exception 'nothing was quarantined — the move did not happen'; end if;

  -- EVERY LIVE SEAT MUST NOW OWN SOMETHING. Three of the five owned nothing before this file, and
  -- an empty scope list is the reason a seat retrieves nothing and nobody notices.
  select count(*) into v_empty from public.org_role
   where runtime_agent_key is not null
     and coalesce(array_length(knowledge_scopes, 1), 0) = 0;
  if v_empty > 0 then raise exception '% live seat(s) still declare no knowledge scope', v_empty; end if;

  select knowledge_scopes into v_ceo from public.org_role where runtime_agent_key = 'ceo';
  select knowledge_scopes into v_acc from public.org_role where runtime_agent_key = 'accountant';
  select knowledge_scopes into v_it  from public.org_role where runtime_agent_key = 'it_engineer';
  select knowledge_scopes into v_se  from public.org_role where runtime_agent_key = 'sales_engineer';
  select knowledge_scopes into v_cs  from public.org_role where runtime_agent_key = 'customer_support';

  if not (v_ceo @> array['business-consulting','exec','analytics','legal','marketing']) then
    raise exception 'the CEO did not receive all five of its categories';
  end if;
  if v_ceo && array['hr','procurement'] then
    raise exception 'the CEO still scopes hr or procurement, which no longer exist';
  end if;
  if not (v_acc @> array['finance'])            then raise exception 'the accountant did not receive finance'; end if;
  if not (v_it  @> array['it','qa'])            then raise exception 'the IT engineer did not receive it/qa'; end if;
  if not (v_se  @> array['sales'])              then raise exception 'the sales engineer did not receive sales'; end if;
  if not (v_cs  @> array['customer_success'])   then raise exception 'support did not receive customer_success'; end if;

  -- NO SCOPE MAY NAME A CATEGORY THAT HOLDS NOTHING. A scope list full of dangling names is how the
  -- CEO came to claim hr and procurement in the first place. Checked for the categories this file
  -- assigns, not for the pre-existing ones, which are a separate clean-up.
  if exists (
    select 1 from unnest(array['business-consulting','exec','analytics','legal','marketing',
                               'finance','it','qa','sales','customer_success']) c
     where not exists (select 1 from public.kb_chunks k where k.category = c)
  ) then
    raise exception 'a category assigned to a seat holds no rows';
  end if;

  raise notice 'THE SURVIVING SEATS NOW OWN THE KNOWLEDGE. All five live seats declare a scope where three declared none: ceo takes business-consulting, exec, analytics, legal and marketing; accountant takes finance (the densest UAE material in the library, 17.2%%); it_engineer takes it and qa; sales_engineer takes sales; customer_support takes customer_success. % row(s) of hr and procurement are quarantined — the two functions the founder said this company does not perform — and the CEO no longer scopes either. The non-construction verticals are untouched: he was asked and said keep them.',
    v_held;
end
$do$;
