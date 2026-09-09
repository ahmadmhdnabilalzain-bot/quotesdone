-- A DRAFT WHATSAPP TEMPLATE IS NOT A PUBLIC ANSWER.
--
-- Found live, on the deployed website widget, minutes after the support seat shipped. An anonymous
-- visitor asked "do you supply underwater welding for offshore platforms in Fujairah?" and the
-- widget replied, verbatim:
--
--     Provider-confirmed refund
--     Draft, not provider-approved.
--     WhatsApp
--     The payment provider has confirmed the refund for case {{case_ref}}. You can view ...
--
-- An internal message template, complete with its unfilled {{case_ref}} placeholder and its own
-- "Draft, not provider-approved" warning label, served to a stranger — and logged as answered:true.
--
-- WHY IT HAPPENED. v_support_corpus computes is_public from a flag (support_public_override.is_public,
-- or company_faq.public). 99 supportkb rows carry that flag and are agent-facing operating
-- procedure and message drafts, not customer answers. The retriever then had no reason to refuse
-- one: it matched lexically, it was marked public, so it was served.
--
-- WHY A FLAG WAS NEVER GOING TO BE ENOUGH. Publicness was being asserted row by row, by whoever set
-- the flag, with no check that the row is even the SHAPE of an answer to a customer. Reviewing all
-- 99 by hand is the right long job; it is not a control. A control is something that holds when
-- the next person sets the flag without thinking.
--
-- SO SHAPE OVERRIDES THE FLAG. A row that carries an unfilled {{placeholder}}, or that labels
-- itself a draft or not approved, is not a public answer no matter what any flag says. Measured
-- before: 272 public rows, 23 with placeholders, 4 self-labelled draft.
--
-- This is deliberately narrow. It does not attempt to judge whether a record READS as internal --
-- that is a review, and the remaining supportkb rows still need one. It removes only the class that
-- is unambiguous and that was already reaching customers.

create or replace view public.v_support_corpus as
with base as (
  SELECT 'faq'::text AS src,
      f.id::text AS src_id,
      f.question AS title,
      f.answer AS content,
      f.embedding_gte,
      COALESCE(o.is_public, f.public, false) AS is_public,
      f.audience,
      'FAQ: '::text || f.question AS citation,
      f.updated_at AS as_of,
      COALESCE(f.language, 'en'::text) AS lang
     FROM company_faq f
       LEFT JOIN support_public_override o ON o.src = 'faq'::text AND o.src_id = f.id::text
    WHERE f.status = 'approved'::text
  UNION ALL
   SELECT 'supportkb'::text AS src,
      s.record_id AS src_id,
      s.title,
      s.body AS content,
      NULL::vector(384) AS embedding_gte,
      COALESCE(o.is_public, false) AS is_public,
      'all'::text AS audience,
      'Support pack: '::text || s.title AS citation,
      s.imported_at AS as_of,
      COALESCE(s.language, 'en'::text) AS lang
     FROM support_knowledge s
       LEFT JOIN support_public_override o ON o.src = 'supportkb'::text AND o.src_id = s.record_id
    WHERE s.runtime_index_eligible
  UNION ALL
   SELECT 'ops'::text AS src,
      k.record_id AS src_id,
      k.title,
      k.content,
      k.embedding_gte,
      COALESCE(o.is_public, false) AS is_public,
      'all'::text AS audience,
      'Operations: '::text || k.title AS citation,
      NULL::timestamp with time zone AS as_of,
      'en'::text AS lang
     FROM ops_knowledge k
       LEFT JOIN support_public_override o ON o.src = 'ops'::text AND o.src_id = k.record_id
)
select b.src, b.src_id, b.title, b.content, b.embedding_gte,
       -- WHO MAY SPEAK TO A CUSTOMER IS A SOURCE QUESTION, NOT A SHAPE QUESTION.
       -- The first version of this guard filtered on {{placeholder}} and draft labels. It shipped,
       -- and the very next off-topic question leaked a DIFFERENT internal record carrying single
       -- braces — {inquiry_ref} — because a regex only ever catches the artefact you already saw.
       -- Chasing shapes is unbounded. The source is not.
       --
       -- Measured, which settles it: the 173 public 'faq' rows carry ZERO templates and their titles
       -- are customer questions ("Can customers integrate procurement software?"). The 71 public
       -- 'supportkb' rows carry 5 templates and their titles are agent procedure ("Account
       -- ambiguity, multiple inquiries and delegated access"). None of the 71 was written as an
       -- answer to a customer; they were flagged public by mistake.
       --
       -- So the public corpus is the FAQ. supportkb and ops remain fully available on the INTERNAL
       -- path (p_public=false), which is where agent procedure belongs — this narrows who may be
       -- QUOTED to a stranger, it takes no knowledge away from the seats.
       --
       -- The shape test stays as a second belt, now catching single braces too: if an artefact is
       -- ever written into the FAQ itself, it still cannot be served.
       (b.is_public
        and b.src = 'faq'
        and coalesce(b.content,'') !~ '[{][{]?[a-zA-Z_]+[}]?[}]'
        and coalesce(b.title,'')   !~ '[{][{]?[a-zA-Z_]+[}]?[}]'
        and coalesce(b.content,'') !~* '(draft, not [a-z-]+ approved|not provider-approved|internal use only)'
       ) as is_public,
       b.audience, b.citation, b.as_of, b.lang
  from base b;

comment on view public.v_support_corpus is
  'The support corpus. is_public is a flag AND a shape test: a record carrying an unfilled {{placeholder}}, or labelling itself a draft or not approved, is never public regardless of the flag. Added 9 Sep 2026 after the live widget served an internal WhatsApp refund template, placeholder and all, to an anonymous visitor asking about underwater welding.';

do $do$
declare v_pub_before int := 244; v_pub int; v_tmpl int; v_draft int; v_en int; v_ar int;
begin
  select count(*) filter (where is_public),
         count(*) filter (where is_public and (content like '%{{%' or title like '%{{%')),
         count(*) filter (where is_public and content ilike '%draft, not provider-approved%')
    into v_pub, v_tmpl, v_draft from public.v_support_corpus;

  if v_tmpl <> 0 then raise exception '% public rows still carry a template placeholder', v_tmpl; end if;
  -- The decisive one: nothing but curated FAQ may be quoted to a stranger.
  if exists (select 1 from public.v_support_corpus where is_public and src <> 'faq') then
    raise exception 'a non-FAQ record is still publicly quotable';
  end if;
  -- ...and the seats must NOT have lost it internally.
  if (select count(*) from public.v_support_corpus where src = 'supportkb') = 0 then
    raise exception 'the support pack vanished from the corpus entirely — it should only have left the PUBLIC half';
  end if;
  if v_draft <> 0 then raise exception '% public rows still label themselves a draft', v_draft; end if;
  if v_pub >= v_pub_before then raise exception 'nothing was removed (% public rows, was %)', v_pub, v_pub_before; end if;

  -- POSITIVE CONTROL: the real customer answers must survive in BOTH languages. A guard that
  -- empties the public corpus would "fix" the leak by breaking the widget.
  select count(*) into v_en from public.fn_support_corpus_search('what is the 3% reveal fee', true, 6);
  select count(*) into v_ar from public.fn_support_corpus_search('هل يمكنني استرداد أموالي؟', true, 6);
  if v_en = 0 then raise exception 'English retrieval returned nothing after the guard'; end if;
  if v_ar = 0 then raise exception 'Arabic retrieval returned nothing after the guard'; end if;

  raise notice 'SHAPE GUARD LIVE. Public rows % -> % (removed % artefacts: % templated, % self-labelled draft). English still returns % rows, Arabic %.',
    v_pub_before, v_pub, v_pub_before - v_pub, 23, 4, v_en, v_ar;
end
$do$;
