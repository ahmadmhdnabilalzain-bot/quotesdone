-- A SITE-VISIT CHECKLIST CARRIES THE PHOTOS TO ASK FOR. 15 Nov 2026.
-- Seat: sales_engineer.
-- Founder ledger 1704, verbatim: "For stuff that requires a site visit. The sales engineer should ask for photos. It will make it
-- easier for suppliers to quote."
--
-- WHAT WAS MISSING. Each checklist row of public.trade_spec_checklist carries the pack's site-visit sentence
-- (site_visit_required_when, a_trades_blocking_specs_and_their_guide_reach_the_interview.sql), and the request chat tells the
-- customer a final price needs a visit. Nothing said WHICH photos would let a supplier price without one. The packs now carry,
-- per checklist, the shots the visit would check (scripts/kb/photos_to_ask.mjs reads them off the sentence; each shot names the
-- words it came from). Measured on the repo 15 Nov 2026: 108 of the 250 checklists with a site-visit sentence ask for photos,
-- 333 shots, 2 to 6 each; the other 142 sentences name a file, a sample or a meeting, not a look at a site.
--
-- WHAT THIS ADDS: one column on the SAME table (the same row: one checklist of one trade; one writer,
-- scripts/kb/load_trade_spec_checklists.mjs, and one runtime reader, supabase/functions/_shared/inquiry_trades.ts).
--   * photos_to_ask jsonb  [{shot, shot_ar, from}], in the order they are asked; [] when the checklist asks for none.
--                          `from` is words of the row's own site_visit_required_when (the loader refuses a shot that is not).
-- Reader: _shared/inquiry_trades.ts checklistsOf (the request chat's one photo ask, inquiry_intake/site_photos.ts; WhatsApp).
--
-- WHAT IT DOES NOT DO. It loads no row (node scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply, AFTER this file:
-- the loader inserts the column). No routine, no policy change: the column inherits the table's RLS and its revoke. Until it is
-- applied the runtime's wide select is refused and inquiry_trades.ts reads the 10 Nov columns, so nothing else changes and no
-- photo is asked. Rehearsed LOCALLY (Postgres 16 from the mirror) with
-- a_site_visit_checklist_carries_the_photos_to_ask_for_probe.sql. Pending until applied:
-- scripts/sql/pending/a_site_visit_checklist_carries_the_photos_to_ask_for.txt.

alter table public.trade_spec_checklist
  add column if not exists photos_to_ask jsonb not null default '[]'::jsonb;

alter table public.trade_spec_checklist drop constraint if exists trade_spec_checklist_photos_to_ask_check;
alter table public.trade_spec_checklist add constraint trade_spec_checklist_photos_to_ask_check
  check (jsonb_typeof(photos_to_ask) = 'array' and jsonb_array_length(photos_to_ask) <= 6
         and (jsonb_array_length(photos_to_ask) = 0 or site_visit_required_when is not null));

comment on column public.trade_spec_checklist.photos_to_ask is
  'The photos a site-visit job asks for, once, so a supplier can price without a visit: [{shot, shot_ar, from}], from = words of site_visit_required_when. From the pack (scripts/kb/photos_to_ask.mjs). Optional for the customer; never blocks a request.';

-- Restated so this file alone leaves the table closed (the owning file's RLS, policy and revoke are unchanged).
alter table public.trade_spec_checklist enable row level security;
revoke all on public.trade_spec_checklist from anon, authenticated;
