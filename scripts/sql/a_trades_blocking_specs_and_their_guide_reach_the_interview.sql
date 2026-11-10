-- A TRADE'S BLOCKING SPECS AND THEIR GUIDE REACH THE INTERVIEW. 10 Nov 2026.
-- Seat: sales_engineer.
-- Founder ledger 1587: the interview with the customer happens ONCE, with no back-and-forth, and the inquiry must be
-- complete enough that every supplier can quote without asking for a missing detail.
--
-- WHAT WAS WRONG. Every spec_checklist entry of the 223 trade packs (knowledge/packs/<trade>.json) now says which of its
-- required specs BLOCK a firm price (`blocking`), why each spec is needed to price, the UAE options and what to ask next
-- (`spec_guide`), and when a site visit is needed before a final price (`site_visit_required_when`). Measured on the repo
-- 10 Nov 2026, after the two supplier ask-back reviews were merged: 305 checklists with required specs, 305 with a guide
-- (4,545 rows, one per spec) and a blocking list (1,604 specs, every one among its checklist's required specs), 250 with a
-- site-visit condition. public.trade_spec_checklist (owner:
-- a_trade_without_a_line_reader_is_held_on_its_packs_required_specs.sql; live 10 Nov 2026: 305 rows, 223 trades, columns
-- trade_code, topic_id, topic, specs, source_pack, loaded_at) held none of it, so the request chat asked "the first six
-- specs" of a trade with no category_specs slug and nothing decided which spec must be answered before "ready".
--
-- WHAT THIS ADDS: four columns on the SAME table, because they describe the same row (one checklist of one trade) and
-- that table already has one writer (scripts/kb/load_trade_spec_checklists.mjs) and its readers. A sibling table would be
-- a second owner of "what a trade's checklist says".
--   * spec_guide jsonb   one object per spec, in the checklist's order: {code, spec, why_needed_to_price, uae_options,
--                        follow_up_if, blocking}. code is the spec's code in specs[] (the loader's specCode).
--   * blocking text[]    the CODES of the specs that block a firm price; each one is the code of an element of specs[]
--                        (enforced below, so a blocking spec can never name something the checklist does not ask).
--   * site_visit_required_when text   the pack's sentence, or null when the trade can be priced without a visit.
--   * pack_order smallint  the checklist's position in its pack (0 first). The pack lists the core job first (split AC
--                        before chiller), so a request whose job has not been matched to one checklist yet uses that one.
-- Readers: supabase/functions/_shared/inquiry_trades.ts tradeContext (the request chat, the portal assistant, WhatsApp).
--
-- WHAT IT DOES NOT DO. It loads no row: the rows come from the packs (node scripts/kb/load_trade_spec_checklists.mjs
-- knowledge/packs --apply, after this file). fn_trade_spec_checklist (the quote gate's reader) is unchanged: a quote is
-- still held on every required spec, blocking or not. Until the loader runs, the 305 live rows carry an empty guide and an
-- empty blocking list, and inquiry_trades.ts keeps the earlier rule for them (first six specs required for a trade with no
-- slug), so nothing reads a half-loaded table as "nothing blocks".
-- Rehearsed with a_trades_blocking_specs_and_their_guide_reach_the_interview_probe.sql (rolled back). Pending until
-- applied: scripts/sql/pending/a_trades_blocking_specs_and_their_guide_reach_the_interview.txt.

alter table public.trade_spec_checklist
  add column if not exists spec_guide jsonb not null default '[]'::jsonb,
  add column if not exists blocking text[] not null default '{}'::text[],
  add column if not exists site_visit_required_when text,
  add column if not exists pack_order smallint not null default 0;

alter table public.trade_spec_checklist drop constraint if exists trade_spec_checklist_spec_guide_check;
alter table public.trade_spec_checklist add constraint trade_spec_checklist_spec_guide_check
  check (jsonb_typeof(spec_guide) = 'array');
-- every blocking code is the code of one of the checklist's own specs (jsonb array containment: ["a"] <@ ["a","b"])
alter table public.trade_spec_checklist drop constraint if exists trade_spec_checklist_blocking_check;
alter table public.trade_spec_checklist add constraint trade_spec_checklist_blocking_check
  check (to_jsonb(blocking) <@ jsonb_path_query_array(specs, '$[*].code'));
alter table public.trade_spec_checklist drop constraint if exists trade_spec_checklist_site_visit_check;
alter table public.trade_spec_checklist add constraint trade_spec_checklist_site_visit_check
  check (site_visit_required_when is null or btrim(site_visit_required_when) <> '');
alter table public.trade_spec_checklist drop constraint if exists trade_spec_checklist_pack_order_check;
alter table public.trade_spec_checklist add constraint trade_spec_checklist_pack_order_check
  check (pack_order >= 0);

comment on column public.trade_spec_checklist.spec_guide is
  'Per spec of the checklist, in order: {code, spec, why_needed_to_price, uae_options, follow_up_if, blocking}. From the pack''s spec_guide; shown to the interview for the trades a request is placed in.';
comment on column public.trade_spec_checklist.blocking is
  'Codes (specs[].code) of the specs that block a firm price. A request is not ready until each is answered or recorded as "customer does not know: supplier to advise".';
comment on column public.trade_spec_checklist.site_visit_required_when is
  'When a site visit is needed before a final price (the pack''s sentence), or null. Stated in the brief as a known condition.';
comment on column public.trade_spec_checklist.pack_order is
  'The checklist''s position in its pack (0 = first, the core job); the default checklist of a trade until the job is matched to one.';

-- The table's RLS, its service-role-only policy and its revoke are the owning file's and unchanged: an added column
-- inherits them. Restated so this file alone leaves the table closed.
alter table public.trade_spec_checklist enable row level security;
revoke all on public.trade_spec_checklist from anon, authenticated;
