-- ============================================================================
-- MARKETING KNOWLEDGE — UAE marketing library, two layers.
--   Layer 1 (always-on): distilled QuotesDone-specific rows in agent_knowledge, loaded every run.
--   Layer 2 (on-demand): the full library as searchable chunks in marketing_library, retrieved per
--            task via fn_marketing_library_search and injected by marketing_draft. Keeps depth
--            available without paying the context cost of loading 340KB on every generation.
-- Source: UAE_Marketing_Knowledge_Library (18 domains; e-commerce Domain 12 intentionally excluded
--         as low-relevance for a services RFQ marketplace).
-- NOTE: the 317 library chunks are DATA loaded via the REST API (see project doc), not this DDL.
--       This migration recreates the SCHEMA, the search function, and the always-on rows.
-- ============================================================================

-- Layer 2 store -------------------------------------------------------------
create table if not exists public.marketing_library (
  id          bigserial primary key,
  category    text not null,
  domain      text,
  title       text not null,
  content     text not null,
  tags        text,
  source_file text,
  tsv tsvector generated always as (
    to_tsvector('english', coalesce(title,'') || ' ' || coalesce(tags,'') || ' ' || coalesce(content,''))
  ) stored,
  created_at  timestamptz default now()
);
create index if not exists idx_marketing_library_tsv on public.marketing_library using gin(tsv);
create index if not exists idx_marketing_library_category on public.marketing_library(category);
alter table public.marketing_library enable row level security;  -- service_role (edge fns) bypasses; no public access

-- Retrieval: OR-ranked full-text search (chunks matching more query terms rank higher).
create or replace function public.fn_marketing_library_search(p_query text, p_limit int default 5)
returns table(id bigint, category text, title text, content text, rank real)
language plpgsql stable as $$
declare q_or tsquery; words text[];
begin
  words := array(
    select w from unnest(
      regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')), '\s+')
    ) w where length(w) > 2);
  if array_length(words,1) is null then return; end if;
  begin
    q_or := to_tsquery('english', array_to_string(words, ' | '));
  exception when others then return; end;
  return query
    select l.id, l.category, l.title, l.content, ts_rank(l.tsv, q_or) as rank
    from public.marketing_library l
    where l.tsv @@ q_or
    order by ts_rank(l.tsv, q_or) desc, l.id
    limit greatest(1, least(coalesce(p_limit,5), 20));
end;
$$;

-- Layer 1 always-on distilled rows (idempotent) -----------------------------
insert into public.agent_knowledge(agent_key,topic,priority,content)
select v.agent_key, v.topic, v.priority, v.content from (values
('marketing','uae_ad_compliance',86,'UAE ad law: never make unverifiable/misleading claims about suppliers, quote speed, savings or supplier counts; respect Media Content Standards (nothing offending Islam, national symbols or UAE values); label paid/sponsored content even when gifted; regulated-sector RFQs (property/health/finance) may need their own permits — verify; comparative claims must be fair. Verify current UAE Media Council rules before relying on specifics.'),
('marketing','pdpl_consent',86,'Treat every buyer/supplier email, phone and WhatsApp number as PDPL personal data. Marketing contacts require clear opt-in consent with provable records; provide easy opt-out and honor objection to direct marketing immediately; keep a preference centre (channel, language, source, timestamp, unsubscribe). Do not reuse operational RFQ data for unrelated marketing without a lawful basis. Verify current PDPL executive-regulation specifics with counsel.'),
('marketing','whatsapp_lifecycle',84,'WhatsApp is the UAE''s primary business channel and QuotesDone''s conversion layer. Promotional WhatsApp/SMS only to opted-in contacts via an authorized BSP with approved templates; promo SMS 07:00-21:00 GST, AD- prefix, free opt-out. Favor cheaper utility/service messages (RFQ/quote alerts) in the 24h window over billed marketing templates. Click-to-WhatsApp ads cut cost-per-lead. Keep SPF/DKIM/DMARC valid for email. Verify current TDRA rules before a blast.'),
('marketing','ramadan_timing',82,'Plan the UAE calendar: Ramadan (verify dates yearly), Eid, National Day (Dec 2). Sourcing intent spikes in Ramadan — plan ~6 weeks out; shift tone to community/family/charity, drop hard-sell; acquire in the two weeks BEFORE Ramadan (higher LTV). Engagement peaks post-Iftar and Suhoor (~9pm-3am) — schedule then, but promo SMS still stops 9pm GST. Avoid food/drink imagery in daylight fasting hours; pivot to conversion as Eid nears.'),
('marketing','cro_landing_uae',82,'Trust is the UAE conversion currency: put local proof above the fold (trade-licence/DED badge, +971 landline, physical address, verified supplier counts). Make WhatsApp the primary CTA and track its clicks as a core conversion. Cut form friction (few fields, unchecked consent, privacy link). For an anonymous marketplace, reassure buyers supplier identity stays hidden until reveal+pay. Fix message-match and page speed (<3s) before buying more traffic; A/B test the hook first.'),
('marketing','seo_uae_local',80,'Target buyer sourcing intent (''get quotes for X in Dubai'', ''suppliers for Y UAE'', ''RFQ [category]''), separate buyer/supplier keyword maps. Google dominates UAE search; aim for position one on core terms. Build E-E-A-T with real UAE signals (trade licence, address, landline); complete a Google Business Profile (no P.O. boxes); add LocalBusiness schema and correct hreflang (ar-ae/en-ae) on bilingual pages. A large share of UAE search is Arabic — plan for localization. Track AI-search referrals separately.'),
('marketing','paid_search_uae',80,'Google Ads by buyer intent: bid high-intent sourcing terms, match emirate-level location, add negatives (job-seekers/DIY). Separate Arabic and English campaigns; idiomatic copy, never machine-translated. Quality Score hinges on message match — mirror each ad on its landing page; pages need a PDPL cookie banner + privacy policy. Regulated categories face extra Google verification/permits — verify. Schedule for late-night Ramadan activity. Verify current CPC/CTR benchmarks before budgeting.'),
('marketing','b2b_linkedin_uae',80,'LinkedIn drives most UAE B2B leads and fits QuotesDone''s procurement audience — bridge it to WhatsApp for conversion. Lead with trust (local case studies, real testimonials, GCC-specific proof), not reach. Target by title and free zone (DIFC/ADGM/DMCC/JLT) and named accounts for ABM; Lead Gen Forms with PDPL privacy link + opt-in. Promotional thought-leadership may need an advertiser permit — verify. Respect etiquette (H.E., Eng., Dr.; avoid prayer/fasting windows). Short-form video performs best.'),
('marketing','analytics_attribution',78,'UTM discipline: one taxonomy (source_medium_campaign_content_term), lowercase, Latin only even for Arabic campaigns, in one master sheet. Set GA4 to AED + Gulf Standard Time. Server-side GTM to redact PII before US servers and recover ad-blocker/iOS signal loss. Prefer data-driven over last-click. Measure real outcomes (RFQs posted, quotes submitted, supplier reveals/paid unlocks), not vanity reach. PDPL cookie banner with genuine Reject All. Every report states the decision it changes.'),
('marketing','arabic_localization',76,'English-only for now, but build Arabic-ready. A large share of UAE search is Arabic — English-only leaves demand on the table. When Arabic launches, transcreate not machine-translate: Khaleeji dialect for local buyers, MSA for formal/government copy; Levantine/North African read as foreign; native-speaker review for register. Design RTL now (mirrored layout, right-aligned forms, swapped nav) so retrofit is cheap. Code-switching suits younger users. Keep UTMs/tags Latin regardless of content language.'),
('marketing','influencer_uae',74,'Before any UAE creator: verify a trade/freelance licence AND a valid UAE Media Council Advertiser Permit (covers paid, gifted, barter). Require contractual warranty of both plus a morality clause and usage rights. Disclose sponsored content prominently (#ad/#sponsored/Paid Partnership), never buried. Vet on audience fit, genuine UAE follower share, engagement and brand safety — not follower count; micro/nano creators fit a niche B2B marketplace. Respect Islamic values/national symbols. Verify current Media Council rules before contracting.'),
('marketing','pr_crisis_uae',72,'Protect reputation with government and cultural sensitivity. Never publish rumors, unverified claims, or anything harming UAE unity, religion or leadership (Cybercrimes Law). Use correct full leader titles/protocol; avoid political/patriotic themes unless authorized. In a crisis (supplier scam, data incident, bad-actor buyer): acknowledge awareness fast, avoid speculation, confirm facts are being verified, give a next-update time, log every decision and evidence source. Measure sentiment and outcomes, not vanity/AVE metrics.'),
('marketing','library_reference',70,'A deep UAE marketing knowledge library (regulation/PDPL, SEO, paid search, social, influencer, analytics, WhatsApp/email/SMS lifecycle, B2B/LinkedIn, PR/crisis) is stored as ~317 searchable chunks and retrieved on demand via fn_marketing_library_search(query, limit). marketing_draft auto-injects the top matches for each task. When a task needs depth beyond the always-on rows, rely on that retrieved reference rather than guessing. Treat any legal, regulated-sector, or paid-media specific as verify-before-acting, not settled fact.')
) as v(agent_key,topic,priority,content)
where not exists (select 1 from public.agent_knowledge k where k.agent_key=v.agent_key and k.topic=v.topic);

-- marketing_draft (edge fn) now retrieves Layer 2 per task and injects it into the generation prompt.
insert into public.org_memory(scope,kind,content,source) values
('marketing','policy','Marketing knowledge is two-layer: always-on distilled rows in agent_knowledge (UAE compliance/PDPL, WhatsApp lifecycle, Ramadan timing, SEO, paid search, CRO, B2B/LinkedIn, analytics, influencer, PR, Arabic localization) + an on-demand queryable library (marketing_library, ~317 chunks) retrieved via fn_marketing_library_search and injected by marketing_draft. Legal/regulated/paid-media specifics are guidance to verify, not settled fact.','founder_directive')
on conflict do nothing;
