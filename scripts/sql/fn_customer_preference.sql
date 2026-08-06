-- CUSTOMER PREFERENCES — the last unmet requirement in spec file #1.
--
-- Architecture file, "Company Memory": "Every employee remembers: ... Customer preferences ...".
-- public.customer_preference existed with 0 rows and 0 readers on both projects.
--
-- IT IS NOT BLOCKED ON THE PORTAL, which is what I assumed before measuring. fn_ws_customer_360
-- ALREADY derives a customer's preferences — categories and emirates — on every call, live, from
-- their inquiry history. The company was computing the memory and then throwing it away rather than
-- remembering it. That is the same defect as everything else closed this session, one table over.
--
-- WRITER: a trigger, not an Edge Function. `customers` rows are created at four unrelated call
-- sites (kyc x2, customer_api, mobile_otp) so there is no TypeScript chokepoint, and `urgency` is
-- the standing proof of what happens when a signal is computed in an edge function and expected to
-- survive the trip: inquiry_intake sets it and inquiries.urgency is still NULL.
--
-- THE SHAPE IS stated-OVER-inferred, and that is what stops spec file #4 having to replace this.
-- The portal's settings screen calls the SAME function with p_stated; the nightly inference can
-- then never silently overwrite something a customer typed. Read precedence is one coalesce.
--
-- NO KEY SHIPS WITHOUT A READER. The portal spec §17 also names "60-day payment terms" and
-- "ISO-certified companies"; both are deliberately absent, because quote_compare takes no
-- customer-side payment-term input and match_suppliers_kw has no certification parameter. Storing
-- them would reproduce customers.wa_optin — a recorded choice nothing enforces. They arrive when
-- their consumers do.

-- ---------------------------------------------------------------------------------------------
-- 1. THE WRITER.
create or replace function public.fn_customer_preference_learn(
  p_customer_id uuid,
  p_stated jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_consent timestamptz;
  v_existing jsonb;
  v_inferred jsonb;
begin
  if p_customer_id is null then return 0; end if;

  -- CONSENT IS THE GATE, and it reuses the consent the customer already gave. No new column, no
  -- new UI, no second consent vocabulary.
  --
  -- WITHDRAWAL DELETES. The fixture caught this: clearing customer_preference.consented_at is not
  -- withdrawing consent, because consent lives on customers.tos_accepted_at and the next inquiry
  -- simply re-learned and restored the copy. So the absence of consent actively REMOVES the
  -- profile rather than merely declining to refresh it — row absent is indistinguishable from
  -- never consented, which is the property the readers rely on.
  select c.tos_accepted_at into v_consent from customers c where c.id = p_customer_id;
  if v_consent is null then
    delete from customer_preference where customer_id = p_customer_id;
    return 0;
  end if;

  select p.preferences into v_existing from customer_preference p where p.customer_id = p_customer_id;

  -- The same aggregates fn_ws_customer_360 computes live today, persisted instead of recomputed.
  select jsonb_build_object(
           'categories', coalesce(jsonb_agg(distinct i.category) filter (where i.category is not null), '[]'::jsonb),
           'emirates',   coalesce(jsonb_agg(distinct i.emirate)  filter (where i.emirate  is not null), '[]'::jsonb),
           'scope_type', mode() within group (order by i.scope_type),
           'budget_aed_avg', round(avg(nullif(i.expected_value, 0))::numeric, 2),
           'rfqs_seen', count(*))
    into v_inferred
    from inquiries i where i.customer_id = p_customer_id;

  insert into customer_preference (customer_id, preferences, consented_at, updated_at)
  values (p_customer_id,
          jsonb_build_object(
            -- stated is merged, never replaced: an inference must not clear a typed choice.
            'stated',   coalesce(v_existing->'stated', '{}'::jsonb) || coalesce(p_stated, '{}'::jsonb),
            'inferred', coalesce(v_inferred, '{}'::jsonb),
            'source',   'fn_customer_preference_learn'),
          v_consent, now())
  on conflict (customer_id) do update
    set preferences = excluded.preferences,
        consented_at = excluded.consented_at,
        updated_at   = now();
  return 1;
end $function$;

comment on function public.fn_customer_preference_learn(uuid, jsonb) is
  'Remembers a customer''s preferences: `inferred` re-derived from their inquiry history, `stated` '
  'merged from whatever the customer explicitly set. Writes nothing unless customers.tos_accepted_at '
  'is present. Deterministic, no model call. The p_stated argument is the seam the customer portal '
  '(spec #4) uses, so a typed choice can never be overwritten by an inference.';

-- The trigger. AFTER INSERT so the row being learned from is already visible to the aggregate.
create or replace function public.trg_learn_customer_preference()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
begin
  -- Never let remembering a preference fail the RFQ that taught it.
  begin
    perform public.fn_customer_preference_learn(NEW.customer_id);
  exception when others then null;
  end;
  return NEW;
end $function$;

drop trigger if exists learn_customer_preference on public.inquiries;
create trigger learn_customer_preference
after insert on public.inquiries
for each row execute function public.trg_learn_customer_preference();

-- ---------------------------------------------------------------------------------------------
-- 2. READER A — BEHAVIOUR. This is the one that makes the memory matter rather than display.
--
-- A returning customer who does not name a location now gets their remembered emirate on the RFQ.
-- That value is load-bearing downstream: route_inquiry passes p_emirate to match_suppliers and
-- match_suppliers_kw, narrows the approved-supplier fallback on it, and puts it in the
-- adjudicator's job text. Portal spec §17: "Future RFQs automatically consider this."
--
-- Everything else in this function is byte-identical to the deployed definition, taken from live
-- pg_get_functiondef rather than from supabase/schema/full_schema.sql, which is demonstrably stale.
create or replace function public.trg_inquiry_enrich()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare dup int;
begin
  if NEW.urgency is null and NEW.spec is not null and (NEW.spec ? 'urgency') then NEW.urgency := NEW.spec->>'urgency'; end if;
  if NEW.plausibility is null and NEW.spec is not null and (NEW.spec ? 'plausibility') then NEW.plausibility := NEW.spec->'plausibility'; end if;
  if NEW.provenance is null and NEW.spec is not null and (NEW.spec ? 'provenance') then NEW.provenance := NEW.spec->'provenance'; end if;

  -- REMEMBERED PREFERENCE. Only fills a GAP — an emirate the customer stated on this RFQ always
  -- wins. `stated` beats `inferred`, and consent is re-checked on the read as well as the write.
  if NEW.emirate is null and NEW.customer_id is not null then
    select coalesce(p.preferences->'stated'->'emirates'->>0,
                    p.preferences->'inferred'->'emirates'->>0)
      into NEW.emirate
      from customer_preference p
      join customers c on c.id = p.customer_id
     -- Consent is read from customers.tos_accepted_at, where it actually lives, not from the copy
     -- on the preference row. A stale copy would keep a withdrawn profile readable.
     where p.customer_id = NEW.customer_id and c.tos_accepted_at is not null;
  end if;

  select count(*) into dup from inquiries i
    where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
      and coalesce(i.category,'') = coalesce(NEW.category,'')
      and (i.summary = NEW.summary or (length(coalesce(NEW.summary,'')) > 8 and i.summary ilike '%' || left(NEW.summary, 40) || '%'));
  if dup > 0 then
    NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true);
  end if;
  return NEW;
end $function$;
