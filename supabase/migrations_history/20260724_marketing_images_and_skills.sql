-- ============================================================================
-- MARKETING: in-house branded images + ingested social/brand skills.
-- The agent now writes better posts (ingested skills) AND makes its own on-brand images
-- (SVG->PNG rendered in-edge, no external image model, no per-image cost).
-- ============================================================================

-- Per-draft image (a self-made branded card URL) so each post carries its own image.
alter table public.content_drafts add column if not exists image_url text;

-- Public bucket for the generated cards (create via SQL; Storage API used for object writes).
insert into storage.buckets (id, name, public) values ('social-media','social-media', true)
on conflict (id) do update set public=true;

-- Ingested social + visual prompt-craft skills (distilled to QuotesDone; techniques drawn from the
-- open-source blacktwist/social-media-skills and smixs/visual-skills). Loaded as marketing agent knowledge.
insert into public.agent_knowledge(agent_key, topic, content, priority)
select v.agent_key, v.topic, v.content, v.priority from (values
('marketing','social:content_strategy','QuotesDone content pillars: (1) Buyer education — how anonymous RFQs get fairer prices; (2) Supplier value — steady qualified leads, no cold-calling; (3) UAE market/trade insight — procurement norms, licensing, category tips; (4) Proof/how-it-works — the intake->match->quote->reveal flow. Audience: UAE SME buyers (owners, procurement) and verified suppliers/contractors. Voice: practical, trustworthy, pro-SME, plain UAE-aware English; never hypey. Always end with a clear next step (post an RFQ / join as a supplier).',90),
('marketing','social:hooks','Open with a concrete, specific hook in the first line — it decides whether the post is read. Strong patterns: a sharp contrast, a specific pain, a surprising mechanic, or a direct question to the target buyer. Ban generic openers ("In today''s fast-paced world", "We are excited to"). One idea per post. No emoji spam.',88),
('marketing','social:post_structures','LinkedIn: hook line, blank line, 2-4 short lines making ONE point with a concrete example, then a single CTA; under ~150 words. X: one tight idea <=270 chars, or a thread (hook first, one step per tweet, 5-7 max, last = CTA+link). Carousel: slide 1 hook, 2-5 one point each, final CTA. Never invent statistics, prices, or client names.',88),
('marketing','social:platform_rules','LinkedIn is the primary B2B channel: professional, insight-led, 0-3 relevant tags. X: concise, threads for depth. Instagram/Facebook: visual-first, a branded card or product image is required (Instagram will not post text-only). Cadence 3-5x/week; repurpose one strong idea across formats rather than three unrelated posts.',85),
('marketing','social:image_brief','Briefs must be concrete and visual, never abstract. Banned words that do not render: "cinematic", "epic", "stunning", "masterpiece", "high quality". Specify subject, composition, setting, mood in plain terms. For QuotesDone prefer clean typographic branded cards: one bold headline (<=8 words), brand mark, generous whitespace, brand blue accent — these outperform generic AI stock for B2B. One focal point beats clutter.',82)
) as v(agent_key, topic, content, priority)
where not exists (select 1 from public.agent_knowledge k where k.agent_key=v.agent_key and k.topic=v.topic);

insert into public.org_memory(scope,kind,content,source) values
('marketing','policy','Marketing makes its own images in-house: marketing_draft returns a card_headline + eyebrow and calls marketing_image (SVG branded card rendered to PNG in the edge runtime via resvg-wasm, uploaded to the public social-media bucket) — no external image model, no per-image cost. postiz_publish uploads the image to Postiz (required — Postiz only accepts uploads.postiz.com media) and attaches it, so Instagram (which needs media) is postable. Photoreal AI images (fal.ai) remain an optional future add-on.','founder_directive')
on conflict do nothing;