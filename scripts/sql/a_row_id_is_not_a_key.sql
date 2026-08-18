-- ============================================================================================
-- A ROW ID IS NOT A KEY
--
-- trg_contact_message_to_kernel discharges edge:contact_submit into the kernel, and built both
-- dedupe values from NEW.id:
--
--     source_ref  NEW.id::text        -> inbox key defaults to edge:contact_submit:<id>
--     case_ref    'contact:'||NEW.id  -> run dedupe key W18:customer_case:contact:<id>:1
--
-- contact_messages.id is GENERATED ALWAYS AS IDENTITY. It is minted at INSERT, so it is a NEW value
-- for every arrival — including the second copy of ONE arrival. Both kernel dedupe layers were
-- keyed on it, so both missed.
--
-- MEASURED, not argued. The same name, email, phone and message inserted twice in one aborted
-- transaction on production, 18 Aug 2026:
--
--     workflow runs   18 -> 19 -> 20
--     tasks           52 -> 54
--     inbox keys      edge:contact_submit:9 || edge:contact_submit:10
--
-- One person filling in the contact form once and double-tapping submit opens TWO W18 customer
-- cases and TWO tasks on customer_support. src/components/ContactInner.tsx does not disable the
-- control while the request is in flight, so this is the ordinary case, not the edge case.
--
-- THE IDENTITY OF AN ARRIVAL is who wrote, through which channel, and what they wrote.
--
--   * source is included because contact_messages is also written by site_assistant and
--     wa_inbound: the same sentence from the same person through the web form and through WhatsApp
--     is two arrivals, not one.
--   * name and phone are EXCLUDED so a typo corrected on the retry does not split one arrival in
--     two — the retry is the same case.
--   * case_ref is derived from the same hash as the key, deliberately. Keying only the inbox would
--     dedupe layer 1 and still mint a second business object at layer 2.
--
-- WHAT THIS DOES NOT CHANGE. It adds no emitter. The trigger already called the door; only the
-- value it passed was wrong. So the two-creators trap does not apply here — there is still exactly
-- one creator, and the probe below is what says so rather than the sentence.
--
-- NO BACKFILL. Runs already created under customer_case:contact:<id> keep that shape; new ones use
-- customer_case:contact:<sha256>. The two coexist without collision. Split any post-deploy
-- measurement by the deploy timestamp or pre-fix rows will hold the check open.
--
-- source_ref STAYS NEW.id::text. fn_kernel_source_emit raises 22023 on a null source_ref, and it is
-- the pointer from the inbox row back to the exact contact_messages row. Once idempotency_key is
-- supplied explicitly it no longer feeds the key, so it is free to stay the precise row pointer.
--
-- Stays AFTER INSERT returning NEW. A BEFORE trigger returning NULL would give the edge function
-- 201 with no row, and its `if (!error)` would read a deliberate refusal as a successful write.
-- ============================================================================================

create or replace function public.trg_contact_message_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $ck$
declare
  v_ident text := encode(sha256(convert_to(
      lower(btrim(coalesce(NEW.email, '')))               || '|' ||
      lower(btrim(coalesce(NEW.source, 'contact_page')))  || '|' ||
      btrim(coalesce(NEW.message, '')), 'UTF8')), 'hex');
begin
  perform public.fn_kernel_source_emit('edge:contact_submit', jsonb_build_object(
    'source_ref',      NEW.id::text,
    'idempotency_key', 'edge:contact_submit:' || v_ident,
    'raw_payload', jsonb_build_object(
      'case_ref',           'contact:' || v_ident,
      'email',              NEW.email,
      'source',             NEW.source,
      'name',               NEW.name,
      'contact_message_id', NEW.id)));
  return NEW;
end
$ck$;

revoke all on function public.trg_contact_message_to_kernel() from public;
