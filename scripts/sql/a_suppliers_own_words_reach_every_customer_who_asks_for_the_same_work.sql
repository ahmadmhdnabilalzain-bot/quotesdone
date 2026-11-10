-- A SUPPLIER'S OWN WORDS REACH EVERY CUSTOMER WHO ASKS FOR THE SAME WORK, IN ANY TRADE (10 Nov 2026, sales_engineer).
-- Seat: sales_engineer. Founder ledger 1573 ("those keywords drive the cross-matching of customer inquiries to suppliers
-- (e.g. PVC decorative panels)"), 1579 ("must work the same way for every trade, product and service, not just that case")
-- and 1586 (every UAE trade except food and beverage: all 223 taxonomy codes in 12 groups, not the 32 intake slugs).
--
-- MEASURED (design audit 10 Nov 2026, docs/reports/2026-11-10-design-sales-intake-and-matching.md section 3; production
-- htdblwldjkcgjvmqkbeh, read-only):
--   * fn_match_capability gates on an EXACT trade overlap (sc.trades && p_trades) and, when the request names services, on
--     the supplier's stated services plus one level of service_implication. The PVC dry-run returned 0 suppliers for every
--     variant (wallpaper, joinery, fit-out codes) while the aluminium control returned 4: a request classified under a
--     neighbouring trade never reached the supplier who does the work, even when it named that supplier's exact service.
--   * names reach codes only through curated taxonomy_trade_service.aliases, compared whole. Run on the live vocabulary
--     (1,103 services) the 44-row matrix of supabase/functions/_shared/general_matching.fixtures.json resolved the
--     supplier's own words on 4 rows and the customer's words on 5; "PVC decorative panels", "vinyl wrap", "roller
--     shades", "forklift on rent", "sworn translation", "workers transportation" named nothing.
--   * there was no way for a phrase a supplier confirmed to become a name: taxonomy_trade_proposal holds TRADES only.
--   * there is no film-wrap service anywhere (architectural film, vinyl wrap, wrap sticker).
--
-- WHAT THIS CHANGES (matching stays on CODES; ruling 890: no word decides a match; founder 14 Sep: exact or none):
--   1. wallpaper.film_wrap, the missing service.
--   2. public.service_alias_proposal: the review queue that turns a phrase a supplier CONFIRMED for a service (or read off
--      his profile and then confirmed) into a curated alias. fn_service_alias_propose files it; fn_service_alias_decide is
--      the sales engineer's decision, and only an approved row is appended to taxonomy_trade_service.aliases, after a
--      check that the phrase is not already a name of another service (a name two services share names neither). Text
--      becomes a code here, once, by a reviewed row; nothing reads free text at match time.
--   3. 427 curated aliases on 44 services across all 12 groups, written as approved rows of that queue (source curated),
--      so each carries who decided it. English and Arabic. None is a name of another live service (checked offline over
--      the whole vocabulary; three that were, عزل الأسطح, ستائر رول, مظلات سيارات, were left out).
--   4. public.taxonomy_trade_adjacent: curated pairs of trades whose firms do each other's work (wall panels <-> joinery
--      <-> fit-out, forklift rental <-> heavy equipment ...), each with its reason in both languages.
--   5. fn_match_capability, when the request names a service, considers the suppliers of (a) the request's trades, (b)
--      the trade each named service belongs to (a code the request itself named) and (c) the curated adjacent trades of
--      either, ONE level, never adjacency of adjacency. A supplier reached through (b) or (c) is matched only when he
--      holds a named service (stated, or one level of service_implication): the "trade level" pass stays for the
--      request's own trades only. With no service named, the gate is p_trades exactly, as before.
--   6. a ranking signal, never a gate: score_w_service_similarity (decision_policy, 10) times the best cosine between a
--      named service's stored gte-small vector and one the supplier stated. It orders the suppliers the gates admitted;
--      it cannot admit one (the probe sets the weight to 1000 and the set does not change).
--   7. supplier_capabilities.service_phrases: the supplier's own phrases for the services he confirmed ([{phrase, key,
--      at}]), kept on his capability as the evidence the alias queue cites.
--
-- WHAT THIS DOES NOT DO:
--   * no plural or stem folding: a curated alias names each form it covers ("pvc panel", "pvc panels"). The no-word-matching
--     test "a plural is not the name" (service_rewrite.test.ts) stands.
--   * the authority requirement stays on the request's trades and the services it names; an adjacent trade adds none.
--   * no vectors for wallpaper.film_wrap, and the 44 services whose aliases grew carry a stale embedding sha: the release
--     backfill (scripts/kb/embed_taxonomy_services.mjs) re-embeds them; until then meaning skips film_wrap and the
--     similarity signal reads 0 for it, and exact names work at once.
--   * the 32 intake slugs are not the gate: callers pass taxonomy codes (fn_taxonomy_trades_for maps a slug to a code,
--     a code to itself), and every one of the 223 codes is matchable here.
--
-- SECURITY: both new tables RLS on with a deliberate service-role-only policy and every grant to anon and authenticated
-- revoked; both new routines SECURITY DEFINER with search_path pinned and EXECUTE revoked from public, anon and
-- authenticated (CREATE grants EXECUTE to PUBLIC). fn_match_capability is CREATE OR REPLACE (its ACL is kept) and stays
-- SECURITY INVOKER, executable by service_role only.
-- prevented by: supabase/functions/_shared/general_matching.test.ts (the 44-row matrix, text -> codes, over this file's
--               aliases) and scripts/checks/a_suppliers_own_words_reach_every_customer_in_every_trade.test.mjs (this file's
--               shape and the probe's matrix equal to the fixture); probe:
--               a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work_probe.sql (codes -> suppliers, on
--               production, rolled back: 44 positives, 44 cross-group negatives, 9 confusables, the alias loop).

-- ── 1. the missing service ──────────────────────────────────────────────────────────────────────────────────────────
insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
values ('wallpaper', 'film_wrap', 'Architectural film & vinyl wrap', 'أفلام الديكور المعمارية وتغليف الفينيل', 60)
on conflict (trade_code, code) do update set label_en = excluded.label_en, label_ar = excluded.label_ar, active = true;

-- ── 2. the alias queue ──────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.service_alias_proposal (
  id            bigint generated always as identity primary key,
  phrase        text not null check (char_length(btrim(phrase)) between 3 and 120),
  phrase_norm   text not null,
  trade_code    text not null,
  code          text not null,
  source        text not null check (source in ('supplier_confirmed', 'profile', 'curated')),
  supplier_ids  bigint[] not null default '{}',
  seen          integer not null default 1,
  status        text not null default 'proposed' check (status in ('proposed', 'approved', 'rejected')),
  decided_by    text,
  decided_at    timestamptz,
  reason        text,
  created_at    timestamptz not null default now(),
  foreign key (trade_code, code) references public.taxonomy_trade_service (trade_code, code),
  unique (phrase_norm, trade_code, code)
);
create index if not exists service_alias_proposal_open_idx on public.service_alias_proposal (created_at) where status = 'proposed';
alter table public.service_alias_proposal enable row level security;
drop policy if exists service_alias_proposal_service_role_only on public.service_alias_proposal;
create policy service_alias_proposal_service_role_only on public.service_alias_proposal
  as permissive for all to public using (false) with check (false);
revoke all on public.service_alias_proposal from anon, authenticated;

-- the name as the queue compares it: Arabic folded as fn_ar_norm folds it, lower case, one space
create or replace function public.fn_service_alias_norm(p_text text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select btrim(regexp_replace(lower(public.fn_ar_norm(coalesce(p_text, ''))), '[\s_\-]+', ' ', 'g'));
$fn$;
revoke execute on function public.fn_service_alias_norm(text) from public, anon, authenticated;
grant execute on function public.fn_service_alias_norm(text) to service_role;

-- The services a name already names (key, code, labels, aliases), as the queue compares it.
create or replace function public.fn_service_alias_owners(p_norm text)
returns text[]
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(array_agg(distinct s.trade_code || '.' || s.code order by s.trade_code || '.' || s.code), '{}'::text[])
    from public.taxonomy_trade_service s
   where s.active
     and (p_norm in (public.fn_service_alias_norm(s.trade_code || '.' || s.code), public.fn_service_alias_norm(s.code),
                     public.fn_service_alias_norm(s.label_en), public.fn_service_alias_norm(s.label_ar))
          or exists (select 1 from unnest(coalesce(s.aliases, '{}'::text[])) a where public.fn_service_alias_norm(a) = p_norm));
$fn$;
revoke execute on function public.fn_service_alias_owners(text) from public, anon, authenticated;
grant execute on function public.fn_service_alias_owners(text) to service_role;

-- A supplier's confirmed phrases -> the queue. p_pairs: [{"phrase": "...", "key": "<trade>.<code>"}]. A phrase that is
-- already a name of that service is skipped (nothing to learn); one seen before adds this supplier and counts again.
create or replace function public.fn_service_alias_propose(p_supplier_id bigint, p_pairs jsonb, p_source text default 'supplier_confirmed')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_norm text; v_trade text; v_code text; v_new int := 0; v_seen int := 0; v_skip int := 0; v_id bigint;
begin
  if p_source not in ('supplier_confirmed', 'profile') then raise exception 'fn_service_alias_propose: source % is not a supplier source', p_source; end if;
  for r in select btrim(coalesce(x->>'phrase', '')) as phrase, btrim(coalesce(x->>'key', '')) as key
             from jsonb_array_elements(case when jsonb_typeof(p_pairs) = 'array' then p_pairs else '[]'::jsonb end) x
            limit 40
  loop
    v_trade := split_part(r.key, '.', 1); v_code := split_part(r.key, '.', 2);
    v_norm := public.fn_service_alias_norm(r.phrase);
    if char_length(r.phrase) not between 3 and 120 or v_code = ''
       or not exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code = v_trade and s.code = v_code)
       or (v_trade || '.' || v_code) = any(public.fn_service_alias_owners(v_norm)) then
      v_skip := v_skip + 1; continue;
    end if;
    insert into public.service_alias_proposal (phrase, phrase_norm, trade_code, code, source, supplier_ids)
    values (r.phrase, v_norm, v_trade, v_code, p_source, case when p_supplier_id is null then '{}'::bigint[] else array[p_supplier_id] end)
    on conflict (phrase_norm, trade_code, code) do nothing
    returning id into v_id;
    if v_id is not null then v_new := v_new + 1;
    else
      update public.service_alias_proposal
         set seen = seen + 1,
             supplier_ids = case when p_supplier_id is null or p_supplier_id = any(supplier_ids) then supplier_ids else supplier_ids || p_supplier_id end
       where phrase_norm = v_norm and trade_code = v_trade and code = v_code;
      v_seen := v_seen + 1;
    end if;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'proposed', v_new, 'seen_again', v_seen, 'skipped', v_skip);
end
$fn$;
revoke execute on function public.fn_service_alias_propose(bigint, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_service_alias_propose(bigint, jsonb, text) to service_role;

-- The sales engineer's decision. Approved: the phrase joins the service's aliases, unless it already names ANOTHER
-- service (then nothing changes and the answer says which). Rejected: kept, so the same phrase is not asked again.
create or replace function public.fn_service_alias_decide(p_id bigint, p_decision text, p_by text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p public.service_alias_proposal; v_other text[];
begin
  if p_decision not in ('approved', 'rejected') then return jsonb_build_object('ok', false, 'code', 'bad_decision'); end if;
  if coalesce(btrim(p_by), '') = '' then return jsonb_build_object('ok', false, 'code', 'decider_required'); end if;
  select * into p from public.service_alias_proposal where id = p_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  if p.status <> 'proposed' then return jsonb_build_object('ok', false, 'code', 'already_decided', 'status', p.status); end if;
  if p_decision = 'approved' then
    v_other := array(select o from unnest(public.fn_service_alias_owners(p.phrase_norm)) o where o <> p.trade_code || '.' || p.code);
    if cardinality(v_other) > 0 then
      return jsonb_build_object('ok', false, 'code', 'alias_names_another_service', 'other', to_jsonb(v_other));
    end if;
    update public.taxonomy_trade_service s
       set aliases = coalesce(s.aliases, '{}'::text[]) || lower(btrim(p.phrase))
     where s.trade_code = p.trade_code and s.code = p.code
       and not (lower(btrim(p.phrase)) = any(coalesce(s.aliases, '{}'::text[])));
  end if;
  update public.service_alias_proposal
     set status = p_decision, decided_by = p_by, decided_at = now(), reason = nullif(btrim(coalesce(p_reason, '')), '')
   where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id, 'status', p_decision, 'key', p.trade_code || '.' || p.code, 'phrase', p.phrase);
end
$fn$;
revoke execute on function public.fn_service_alias_decide(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_service_alias_decide(bigint, text, text, text) to service_role;

-- ── 3. the curated aliases (approved rows of the queue; appended, never replacing what a service already has) ──────────
with seed(trade_code, code, aliases) as (values
  ('wallpaper','wall_panels', array['wall panels','pvc panel','pvc panels','pvc wall panel','pvc wall panels','pvc decorative panel','pvc decorative panels','decorative panels','wpc panels','wpc wall panel','wpc wall panels','fluted panel','fluted panels','3d panels','3d wall panel','3d wall panels','ألواح pvc','بانوهات pvc','ألواح wpc','ديكور pvc','بانوهات ديكور']::text[]),
  ('wallpaper','film_wrap', array['film wrap','vinyl wrap','vinyl wraps','architectural film','architectural films','architectural vinyl film','wrap sticker','wrap stickers','furniture wrap','kitchen wrap','kitchen cabinet wrap','surface wrap','interior film','interior wrap film','ستيكر خشب','تغليف حراري','تغليف أثاث','ستيكر تغليف','تغليف مطابخ']::text[]),
  ('aluminium','windows_doors', array['aluminium windows','aluminum windows','aluminium doors','aluminum doors','aluminium sliding window','aluminium sliding windows','aluminum sliding window','aluminum sliding windows','aluminium windows and doors','شبابيك ألمنيوم','نوافذ ألمنيوم','أبواب ألمنيوم','شبابيك المنيوم']::text[]),
  ('glazing','partitions', array['glass partitions','shower glass partition','shower glass partitions','glass shower partition','glass shower partitions','shower enclosures','frameless shower enclosure','frameless shower enclosures','shower screens','shower cabin','shower cabins','كابينة شاور','قواطع زجاج','زجاج شاور','فاصل زجاج للحمام']::text[]),
  ('gypsum','false_ceiling', array['false ceilings','suspended ceilings','gypsum false ceiling','gypsum false ceilings','gypsum ceilings','drop ceilings','سقف جبس','أسقف جبس','سقف معلق','أسقف معلقة']::text[]),
  ('painting','interior', array['interior wall painting','internal wall painting','interior paint works','wall paint','house painting','apartment painting','villa painting','دهان جدران','دهان شقة','صبغ جدران','دهان داخلي للشقة']::text[]),
  ('flooring','epoxy', array['epoxy floor coating','epoxy floor coatings','epoxy floors','resin floor','resin floors','pu flooring','polyurethane flooring','self levelling epoxy','أرضيات ايبوكسي','أرضيات إيبوكسي','ايبوكسي']::text[]),
  ('waterproofing','roof', array['roof waterproofing membrane','roof waterproofing membranes','roof membranes','roof leak repair','roof leakage','leaking roof','عزل أسطح','عزل مائي للسطح','تسريب السطح']::text[]),
  ('hvac','maintenance_amc', array['ac maintenance contract','ac maintenance contracts','ac annual maintenance','air conditioner servicing','air conditioning servicing','ac service','ac services','صيانة مكيفات','صيانة المكيفات','عقد صيانة مكيفات']::text[]),
  ('plumbing','maintenance', array['water leak','water leaks','water leakage','pipe leak','bathroom leak','bathroom water leak','plumbing repairs','leak detection and repair','تسريب مياه','كشف تسريبات','تصليح تسريب','تصليح سباكة']::text[]),
  ('electrical','lighting', array['led lighting','led lighting installation','led lights','light fixtures','light fittings','lighting fixtures','lighting installation','downlights','spot lights','إنارة','تركيب إنارة','تركيب إضاءة','إضاءة ليد']::text[]),
  ('joinery','kitchens', array['kitchens','kitchen cabinets','kitchen cupboard','kitchen cupboards','kitchen cabinets manufacturing','fitted kitchens','kitchen units','مطابخ','خزائن مطبخ','دواليب مطبخ','مطابخ خشب']::text[]),
  ('curtains_blinds','roller_blinds', array['roller blinds','blackout blinds','blackout roller blind','blackout roller blinds','roller shade','roller shades','ستائر رول بلاك اوت','ستائر بلاك اوت']::text[]),
  ('upholstery','sofa', array['sofa reupholstery','sofa upholstery','couch upholstery','couch reupholstery','sofa recovering','re-cover sofa','sofa repair','تنجيد كنب','تنجيد الكنب','تغيير قماش الكنب']::text[]),
  ('landscaping','irrigation', array['drip irrigation systems','irrigation systems','garden sprinklers','lawn sprinklers','garden irrigation','شبكة ري','ري بالتنقيط','رشاشات حديقة','شبكات ري']::text[]),
  ('swimming_pools','pool_maintenance', array['swimming pool maintenance','pool maintenance','pool cleaning','swimming pool cleaning','weekly pool cleaning','pool servicing','صيانة مسابح','تنظيف مسبح','تنظيف المسابح','صيانة حمام سباحة']::text[]),
  ('pest_control','termite_treatment', array['anti-termite treatment','anti termite treatment','termite control','pre-construction termite treatment','مكافحة النمل الأبيض','رش النمل الأبيض']::text[]),
  ('cleaning','deep_cleaning', array['villa deep cleaning','apartment deep cleaning','move-out cleaning','move-in cleaning','end of tenancy cleaning','تنظيف عميق','تنظيف فلل','تنظيف شقق']::text[]),
  ('security_systems','cctv', array['cctv camera installation','cctv cameras','cctv installation','security cameras','surveillance cameras','ip cameras','cctv system','تركيب كاميرات مراقبة','كاميرات أمان']::text[]),
  ('signage','shop_signs', array['shop signboards','shop signs','signboards','shop front signage','storefront signage','restaurant signage','لوحات محلات','يافطات','لافتات محلات','لوحات إعلانية للمحلات']::text[]),
  ('marble_stone','worktops_vanities', array['granite kitchen worktops','granite worktops','marble worktops','kitchen worktops','marble countertop','marble countertops','granite countertops','kitchen countertops','vanity tops','رخام مطبخ','سطح مطبخ رخام','كاونتر رخام']::text[]),
  ('steel','structural_steel', array['steel structures','steel structures fabrication','steel frame building','steel frame warehouse','steel buildings','steel warehouse','pre-engineered buildings','هياكل حديدية','هناجر حديد','مباني حديدية']::text[]),
  ('tents_shades','car_park_shades', array['car parking shades','car parking shade','parking shades','parking shade','مظلات مواقف سيارات']::text[]),
  ('elevators','home_lifts', array['villa lifts','home elevators','home lifts','residential elevator','residential elevators','مصعد فيلا','مصاعد منزلية','مصعد منزلي']::text[]),
  ('solar','pv_install', array['solar panels installation','solar panel installation','solar panels','rooftop solar','rooftop solar system','solar systems','solar power systems','ألواح شمسية','طاقة شمسية','تركيب ألواح شمسية']::text[]),
  ('fire_fighting','fire_alarm', array['fire alarm systems','fire alarms','smoke detectors','fire detection systems','إنذار حريق','كواشف دخان','نظام إنذار حريق']::text[]),
  ('power_generators','generator_rental', array['diesel generator hire','diesel generator rental','generator on rent','generators on rent','genset rental','genset hire','silent generator rental','silent generator hire','مولد للإيجار','تأجير مولدات']::text[]),
  ('water_treatment','ro_plants', array['ro plant','ro plants','ro water purification plant','ro water purification plants','reverse osmosis system','reverse osmosis systems','reverse osmosis plant','water purification plant','محطة تحلية مياه','محطات تحلية','فلتر ار او']::text[]),
  ('medical_equipment','patient_monitors', array['patient monitor','patient monitoring system','patient monitoring systems','vital signs monitor','vital signs monitors','bedside monitor','bedside monitors','أجهزة مراقبة المرضى','شاشات مراقبة المريض']::text[]),
  ('safety_equipment','fall_protection', array['safety harnesses','full body harness','full body harnesses','fall arrest system','fall arrest systems','lifelines','أحزمة سلامة','معدات الحماية من السقوط']::text[]),
  ('material_handling','forklifts_sale_rent', array['forklift sales','forklift rental','forklifts rental','forklift on rent','forklifts on rent','forklift hire','forklifts for sale','بيع رافعات شوكية','تأجير رافعات شوكية']::text[]),
  ('cnc_machining','laser_waterjet_cutting', array['laser cutting','waterjet cutting','water jet cutting','cnc laser cutting','cnc laser cutting services','fiber laser cutting','قص ليزر','قص بالليزر','قص ووتر جت']::text[]),
  ('commercial_printing','brochures_catalogues', array['catalogue printing','catalog printing','brochures','catalogues','product catalogues','product brochures','طباعة كتالوجات','طباعة الكتالوجات']::text[]),
  ('exhibition_stands','custom_stands', array['exhibition stand','exhibition stands','custom exhibition stand','bespoke exhibition stands','bespoke exhibition stand building','exhibition booth','exhibition booths','trade show booth','stand building','أجنحة معارض','جناح معرض','تنفيذ أجنحة المعارض']::text[]),
  ('corrugated_packaging','regular_slotted_cartons', array['corrugated carton boxes','corrugated carton boxes manufacturing','corrugated cartons','rsc cartons','master cartons','كراتين مموجة','كراتين شحن مموجة']::text[]),
  ('labels_sleeves','self_adhesive_labels', array['self adhesive label printing','self adhesive labels','sticker labels','product labels','product stickers','label rolls','ملصقات منتجات','ستيكرات منتجات']::text[]),
  ('land_survey','topographic_survey', array['topographical survey','topographical surveying','topo survey','topographic surveying','plot survey','مسح طبوغرافي','رفع مساحي']::text[]),
  ('translation_interpretation','certified_legal_translation', array['legal translation','legal translation services','certified translation','sworn translation','attested translation','ترجمة قانونية','ترجمة معتمدة','ترجمة محلفة']::text[]),
  ('it_services','network_install', array['lan networking','office network setup','wifi coverage','wi-fi coverage','wireless coverage','network installation services','تمديد شبكة واي فاي']::text[]),
  ('pos_retail','pos_terminals', array['pos systems','pos terminals','point of sale systems','cashier machines','cashier system','cashier systems','أنظمة نقاط البيع','نظام كاشير']::text[]),
  ('staff_transport','labour_transport', array['labour transportation','labour transportation buses','labor transport','labor transportation','worker transport','workers transport','workers transportation','نقل عمال','نقل العمال','باصات نقل عمال']::text[]),
  ('vehicle_leasing','long_term_leasing', array['corporate car leasing','car leasing','vehicle leasing','long term car rental','monthly car rental','fleet leasing','تأجير سيارات شهري','تأجير سيارات للشركات']::text[]),
  ('scaffolding','rental', array['cuplock scaffolding','ringlock scaffolding','scaffolding on rent','scaffold on rent','سقالات كبلوك']::text[]),
  ('heavy_equipment','crane_hire', array['mobile crane rental','mobile crane hire','crane on rent','cranes on rent','رافعة للإيجار','تأجير رافعات']::text[])
),
pairs as (
  select s.trade_code, s.code, lower(btrim(a)) as alias
    from seed s, unnest(s.aliases) a
),
queued as (
  insert into public.service_alias_proposal (phrase, phrase_norm, trade_code, code, source, status, decided_by, decided_at, reason)
  select p.alias, public.fn_service_alias_norm(p.alias), p.trade_code, p.code, 'curated', 'approved', 'sales_engineer', now(),
         'curated 10 Nov 2026 (founder ledger 1573/1579/1586): the general-matching matrix'
    from pairs p
  on conflict (phrase_norm, trade_code, code) do nothing
  returning 1
)
update public.taxonomy_trade_service t
   set aliases = coalesce(t.aliases, '{}'::text[])
              || array(select p.alias from pairs p
                        where p.trade_code = t.trade_code and p.code = t.code
                          and not (p.alias = any(coalesce(t.aliases, '{}'::text[])))
                        order by p.alias)
 where exists (select 1 from pairs p where p.trade_code = t.trade_code and p.code = t.code
                 and not (p.alias = any(coalesce(t.aliases, '{}'::text[]))));

-- Every key the seed names is a live service (a typo would silently curate nothing): raises, rolling this file back.
do $$
declare v_missing text;
begin
  select string_agg(k, ', ') into v_missing
    from unnest(array['wallpaper.wall_panels','wallpaper.film_wrap','aluminium.windows_doors','glazing.partitions','gypsum.false_ceiling','painting.interior','flooring.epoxy','waterproofing.roof','hvac.maintenance_amc','plumbing.maintenance','electrical.lighting','joinery.kitchens','curtains_blinds.roller_blinds','upholstery.sofa','landscaping.irrigation','swimming_pools.pool_maintenance','pest_control.termite_treatment','cleaning.deep_cleaning','security_systems.cctv','signage.shop_signs','marble_stone.worktops_vanities','steel.structural_steel','tents_shades.car_park_shades','elevators.home_lifts','solar.pv_install','fire_fighting.fire_alarm','power_generators.generator_rental','water_treatment.ro_plants','medical_equipment.patient_monitors','safety_equipment.fall_protection','material_handling.forklifts_sale_rent','cnc_machining.laser_waterjet_cutting','commercial_printing.brochures_catalogues','exhibition_stands.custom_stands','corrugated_packaging.regular_slotted_cartons','labels_sleeves.self_adhesive_labels','land_survey.topographic_survey','translation_interpretation.certified_legal_translation','it_services.network_install','pos_retail.pos_terminals','staff_transport.labour_transport','vehicle_leasing.long_term_leasing','scaffolding.rental','heavy_equipment.crane_hire']) k
   where not exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code || '.' || s.code = k);
  if v_missing is not null then raise exception 'the curated aliases name services that are not active: %', v_missing; end if;
end $$;

-- ── 4. adjacent trades: whose firms do each other's work (one level; the service gate still decides) ──────────────────
create table if not exists public.taxonomy_trade_adjacent (
  a_code     text not null references public.taxonomy_trade (code),
  b_code     text not null references public.taxonomy_trade (code),
  reason_en  text not null check (char_length(reason_en) >= 10),
  reason_ar  text not null check (reason_ar ~ '[ء-ي]'),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (a_code, b_code),
  check (a_code < b_code)
);
alter table public.taxonomy_trade_adjacent enable row level security;
drop policy if exists taxonomy_trade_adjacent_service_role_only on public.taxonomy_trade_adjacent;
create policy taxonomy_trade_adjacent_service_role_only on public.taxonomy_trade_adjacent
  as permissive for all to public using (false) with check (false);
revoke all on public.taxonomy_trade_adjacent from anon, authenticated;

insert into public.taxonomy_trade_adjacent (a_code, b_code, reason_en, reason_ar)
select least(x.a, x.b), greatest(x.a, x.b), x.en, x.ar
from (values
  ('wallpaper','interior_fitout','Fit-out and decoration firms supply and fix wall finishes: wallpaper, wall panels and film.','شركات التشطيب والديكور تورّد وتركّب تشطيبات الجدران: ورق الجدران والألواح والأفلام.'),
  ('wallpaper','joinery','Joinery workshops make and fix decorative wall panelling and cladding.','ورش النجارة تصنع وتركّب ألواح الجدران الديكورية والتكسيات.'),
  ('joinery','interior_fitout','Fit-out contractors build the joinery of a space, and joinery firms take fit-out packages.','مقاولو التشطيب ينفذون أعمال النجارة، وشركات النجارة تتولى حزم التشطيب.'),
  ('gypsum','interior_fitout','Gypsum ceilings and partitions are the core of most interior fit-outs.','الأسقف والقواطع الجبسية هي أساس معظم أعمال التشطيب الداخلي.'),
  ('painting','interior_fitout','Fit-out contractors paint, and painting contractors finish fit-out packages.','مقاولو التشطيب يقومون بالدهان، ومقاولو الدهان ينهون حزم التشطيب.'),
  ('flooring','interior_fitout','Flooring is laid by fit-out contractors and by flooring specialists alike.','تُركّب الأرضيات من مقاولي التشطيب ومن المتخصصين في الأرضيات على حد سواء.'),
  ('curtains_blinds','interior_fitout','Fit-out and decoration firms supply curtains and blinds with the interior.','شركات التشطيب والديكور توفر الستائر والبلايند مع الأعمال الداخلية.'),
  ('curtains_blinds','upholstery','In the UAE the same workshops make curtains, blinds and upholstery.','في الإمارات تصنع الورش نفسها الستائر والبلايند والتنجيد.'),
  ('upholstery','interior_fitout','Decoration firms re-upholster and supply soft furnishings with the fit-out.','شركات الديكور تنفذ التنجيد وتوفر المفروشات مع التشطيب.'),
  ('doors','joinery','Joinery workshops make and fix wooden doors.','ورش النجارة تصنع وتركّب الأبواب الخشبية.'),
  ('aluminium','glazing','Aluminium fabricators glaze their windows, doors and facades; glaziers work in aluminium frames.','مصنّعو الألمنيوم يركّبون الزجاج في نوافذهم وأبوابهم وواجهاتهم، والزجّاجون يعملون بإطارات الألمنيوم.'),
  ('aluminium','tents_shades','Aluminium fabricators build pergolas and car-park shades.','مصنّعو الألمنيوم ينفذون البرجولات ومظلات المواقف.'),
  ('tents_shades','fencing_shades','Both trades build car-park shades, sail shades and tensile structures.','كلتا المهنتين تنفذ مظلات المواقف والمظلات الشراعية والهياكل المشدودة.'),
  ('steel','fencing_shades','Steel fabricators build the frames of shades and fencing.','مصنّعو الحديد ينفذون هياكل المظلات والأسوار.'),
  ('marble_stone','flooring','Stone firms lay marble and granite floors; flooring firms install stone.','شركات الحجر تركّب أرضيات الرخام والجرانيت، وشركات الأرضيات تركّب الحجر.'),
  ('landscaping','swimming_pools','Landscaping contractors build and maintain pools with the garden.','مقاولو تنسيق الحدائق ينفذون المسابح ويصونونها مع الحديقة.'),
  ('cleaning','pest_control','Cleaning companies offer pest control and disinfection, and the reverse.','شركات التنظيف تقدم مكافحة الحشرات والتعقيم، والعكس صحيح.'),
  ('cleaning','facilities_management','Facilities managers deliver cleaning; cleaning companies run soft FM.','شركات إدارة المرافق تقدم التنظيف، وشركات التنظيف تدير الخدمات اللينة.'),
  ('waterproofing','thermal_insulation','Roof waterproofing and roof insulation are laid by the same crews.','عزل الأسطح المائي والحراري ينفذه الطاقم نفسه.'),
  ('electrical','lighting_fixtures','Electrical contractors supply and fix the lighting; lighting suppliers install.','مقاولو الكهرباء يوردون الإنارة ويركّبونها، وموردو الإنارة يركّبون.'),
  ('hvac','mep_general','MEP contractors deliver the HVAC package.','مقاولو الأعمال الكهروميكانيكية ينفذون حزمة التكييف.'),
  ('plumbing','mep_general','MEP contractors deliver the plumbing package.','مقاولو الأعمال الكهروميكانيكية ينفذون حزمة السباكة.'),
  ('electrical','mep_general','MEP contractors deliver the electrical package.','مقاولو الأعمال الكهروميكانيكية ينفذون حزمة الكهرباء.'),
  ('fire_fighting','mep_general','MEP contractors deliver fire alarm and fire fighting.','مقاولو الأعمال الكهروميكانيكية ينفذون إنذار ومكافحة الحريق.'),
  ('security_systems','home_automation','Smart-home integrators fit cameras, access control and alarms.','مركّبو المنازل الذكية يركّبون الكاميرات والتحكم بالدخول والإنذار.'),
  ('it_services','av_it','IT and AV integrators install networks, cabling and screens for each other.','مزودو تقنية المعلومات والصوتيات والمرئيات يركّبون الشبكات والكابلات والشاشات.'),
  ('material_handling','heavy_equipment','Plant-hire firms rent forklifts; forklift dealers rent other plant.','شركات تأجير المعدات تؤجر الرافعات الشوكية، ووكلاء الرافعات يؤجرون معدات أخرى.'),
  ('heavy_equipment','scaffolding','Plant-hire firms rent access platforms and scaffolding firms rent lifting plant.','شركات تأجير المعدات تؤجر منصات العمل، وشركات السقالات تؤجر معدات الرفع.'),
  ('tool_equipment_rental','heavy_equipment','Equipment-rental yards hire tools and plant alike.','ساحات تأجير المعدات تؤجر العدد والآليات معًا.'),
  ('power_generators','event_equipment_rental','Event-equipment renters supply generators, and generator renters serve events.','مؤجرو معدات الفعاليات يوفرون المولدات، ومؤجرو المولدات يخدمون الفعاليات.'),
  ('exhibition_stands','event_management','Event managers build stands, and stand builders run event packages.','منظمو الفعاليات ينفذون الأجنحة، ومنفذو الأجنحة يديرون حزم الفعاليات.'),
  ('commercial_printing','marketing_advertising','Agencies print what they design; printers sell design with the print.','الوكالات تطبع ما تصممه، والمطابع تقدم التصميم مع الطباعة.'),
  ('commercial_printing','signage','Large-format printers make signage, and sign makers print.','مطابع الأحجام الكبيرة تصنع اللافتات، وصانعو اللافتات يطبعون.'),
  ('corrugated_packaging','packaging','Packaging suppliers sell corrugated cartons; carton plants sell packaging.','موردو التغليف يبيعون الكراتين المموجة، ومصانع الكرتون تبيع التغليف.'),
  ('labels_sleeves','packaging','Packaging suppliers print labels; label printers supply packaging.','موردو التغليف يطبعون الملصقات، وطابعو الملصقات يوردون التغليف.'),
  ('staff_transport','vehicle_leasing','Leasing firms hire buses with drivers; staff-transport firms lease vehicles.','شركات التأجير توفر حافلات بسائقين، وشركات نقل الموظفين تؤجر المركبات.'),
  ('water_treatment','water_treatment_services','Water-treatment suppliers service the plants they sell.','موردو معالجة المياه يصونون المحطات التي يبيعونها.'),
  ('medical_equipment','laboratory_equipment','Medical and laboratory equipment are sold and serviced by the same distributors.','الجهات الموزعة نفسها تبيع الأجهزة الطبية والمخبرية وتصونها.'),
  ('safety_equipment','fire_fighting','Safety-equipment suppliers sell extinguishers; fire contractors sell PPE.','موردو معدات السلامة يبيعون الطفايات، ومقاولو الحريق يبيعون معدات الوقاية.'),
  ('cnc_machining','steel','Steel fabricators cut and bend sheet; machine shops fabricate.','مصنّعو الحديد يقصّون ويثنون الصاج، والورش تصنّع.'),
  ('land_survey','engineering_consultancy','Engineering consultants survey sites, and surveyors work for them.','الاستشاريون الهندسيون يمسحون المواقع، والمساحون يعملون معهم.'),
  ('translation_interpretation','legal_services','Legal-services firms arrange certified translation.','مكاتب الخدمات القانونية ترتب الترجمة المعتمدة.'),
  ('pos_retail','it_services','IT suppliers install POS terminals and their networks.','موردو تقنية المعلومات يركّبون أجهزة نقاط البيع وشبكاتها.')
) as x(a, b, en, ar)
on conflict (a_code, b_code) do update set reason_en = excluded.reason_en, reason_ar = excluded.reason_ar, active = true;

-- ── 4b. in the daily export: the queue is the record of who named what; the adjacency is curated data; and the service
--     taxonomy now HAS a writer (fn_service_alias_decide appends an approved alias), so it leaves no_writer and is exported.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('service_alias_proposal', true, 'supplier', 'Phrases suppliers confirmed for a service and the sales engineer''s decision on each (alias queue), 10 Nov 2026, ledger 1573.', 'sales_engineer'),
  ('taxonomy_trade_adjacent', true, 'company', 'Curated pairs of trades whose firms do each other''s work, with both reasons; fn_match_capability reads them one level, 10 Nov 2026.', 'sales_engineer'),
  ('taxonomy_trade_service', true, 'company', 'The service taxonomy every match reads; fn_service_alias_decide appends approved aliases to it since 10 Nov 2026 (no longer frozen).', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── 5. the supplier's own phrases, kept on his capability ───────────────────────────────────────────────────────────
alter table public.supplier_capabilities add column if not exists service_phrases jsonb not null default '[]'::jsonb;

-- ── 6. the ranking signal's weight ──────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description)
values ('score_w_service_similarity', '10'::jsonb,
        'fn_match_capability: weight of the best cosine (stored gte-small vectors) between a service the request names and one the supplier stated. RANKING ONLY: it orders the suppliers the code gates admitted and can never admit one (10 Nov 2026, sales_engineer). 0 switches it off.')
on conflict (key) do nothing;

-- ── 7. the matcher: the body of a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.sql
--    (MANIFEST 1881) with the reach (named services' trades + curated adjacent trades, ONE level, only when a service is
--    named), "trade level" for the request's own trades only, the authority of the named services' trades, and the
--    similarity ranking term. Every other gate, the return shape and the ordering keys are unchanged. ──────────────────
create or replace function public.fn_match_capability(p_trades text[], p_need text default 'executes',
  p_products text[] default '{}', p_brands text[] default '{}', p_project_type text default null,
  p_value numeric default null, p_emirate text default null, p_limit integer default 12, p_services text[] default '{}')
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer,
  brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[])
set search_path to 'public', 'pg_temp'
language sql
stable
as $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size,
         -- 10 Nov 2026: RANKING ONLY (see the header); absent = 0 = off.
         coalesce((select value::text::numeric from decision_policy where key='score_w_service_similarity'),0) as w_sim
),
-- EXACT (23 Sep 2026, decision point 25): the request's terms and the supplier's, each lower-cased and
-- trimmed, then compared for equality. A substring is not a match: "door" is not "door closer".
q as (
  select array(select distinct lower(btrim(x)) from unnest(coalesce(p_products, '{}'::text[])) x where nullif(btrim(x), '') is not null) as products,
         array(select distinct lower(btrim(x)) from unnest(coalesce(p_brands, '{}'::text[])) x where nullif(btrim(x), '') is not null) as brands,
         nullif(lower(btrim(coalesce(p_project_type, ''))), '') as ptype,
         nullif(lower(btrim(coalesce(p_emirate, ''))), '') as emirate
),
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
n as (select count(*)::int as k from named),
-- THE REACH (10 Nov 2026, founder ledger 1573/1579/1586). With no service named it is the request's trades, exactly as
-- before. With a service named it adds the trade that service belongs to (a code the request itself named) and the
-- curated adjacent trades of either (public.taxonomy_trade_adjacent), ONE level: an adjacent trade's own neighbours are
-- not followed. A supplier found only through the reach must hold a named service (scored, below).
asked as (
  select distinct t from (select unnest(coalesce(p_trades, '{}'::text[])) as t union select tr from named) x where t is not null
),
reach as (
  select coalesce(array_agg(distinct c), '{}'::text[]) as codes from (
    select t as c from asked
    union
    select case when j.a_code = a.t then j.b_code else j.a_code end
      from asked a join public.taxonomy_trade_adjacent j on j.active and (j.a_code = a.t or j.b_code = a.t)
     where (select k from n) > 0
  ) r
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades) or t.code in (select tr from named)
),
loc as (
  select sc.supplier_id,
         array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
                                           || coalesce(l.service_emirates, '{}'::text[])) e
                where nullif(btrim(e), '') is not null) as stated
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         -- 23 Sep 2026 (sales_engineer.supplier_performance): the measured score comes first; the view's quote rate
         -- and perf_score remain the fallback for a supplier the platform has not measured yet.
         least(1, greatest(0, coalesce(pf.score, sp.quote_rate, sp.perf_score, 0))) as track,
         ((select emirate from q) is not null and (select emirate from q) = any(loc.stated)) as in_emirate,
         cardinality(loc.stated) as stated_n,
         -- the request's own trade (the trade-level pass applies to these only)
         coalesce(sc.trades && p_trades, false) as direct
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  left join public.supplier_performance pf on pf.lead_id = sc.supplier_id
  left join public.supplier_availability av on av.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && (select codes from reach)
    and not (sc.excluded_trades && p_trades)
    and not (sc.excluded_trades && array(select tr from named))
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    -- 29 Sep 2026 (ledger 1033): a supplier who said he is busy or paused is not sent a request. No row = available;
    -- a busy date that has come reads as available here, whether or not the duty has rewritten the row yet.
    and public.fn_supplier_available(av.state, av.busy_until)
    and exists (
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and ((select emirate from q) is null
      or cardinality(loc.stated) = 0
      or (select emirate from q) = any(loc.stated))
),
eff as (
  select c.*,
         case when (select k from n) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    not exists (select 1 from named t where t.tr = any(coalesce(e.trades, '{}'::text[]))) as never_asked,
    -- ponytail: one scan of service_implication per candidate (113 curated rows); batch it with a single
    -- unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)
        and (i.implies_trade || '.' || i.implies_code) in (select key from named)
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    -- EXACT: a requested product counts when the supplier declares that same product.
    (select count(*) from unnest((select products from q)) pq
      where pq = any(array(select lower(btrim(pp)) from unnest(coalesce(c.products_norm, '{}'::text[])) pp)))::int as product_hits,
    (cardinality((select brands from q)) > 0 and exists (
       select 1 from unnest(coalesce(c.brands, '{}'::text[])) bb where lower(btrim(bb)) in (select unnest(q.brands) from q)
     )) as brand_hit,
    ((select ptype from q) is not null and exists (
       select 1 from unnest(coalesce(c.project_types, '{}'::text[])) pt where lower(btrim(pt)) = (select ptype from q)
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known,
    -- THE SIMILARITY SIGNAL (ranking only): the best cosine between a named service and a service this supplier stated,
    -- over the stored gte-small vectors. 1 for an exact hit; 0 when either side has no vector or the weight is 0.
    case when (select k from n) = 0 or (select w_sim from w) = 0 then 0::numeric else coalesce((
      select max(greatest(0, least(1, 1 - (a.embedding_gte <=> b.embedding_gte))))::numeric
        from public.taxonomy_trade_service a
        join named nm on a.trade_code || '.' || a.code = nm.key
        join public.taxonomy_trade_service b on b.active and b.trade_code || '.' || b.code = any(coalesce(c.services, '{}'::text[]))
       where a.embedding_gte is not null and b.embedding_gte is not null), 0) end as sim
  from svc c
  -- THE GATE. A supplier of the request's own trades passes at trade level when the request names no service of his
  -- trades (founder 857); one reached only through a named service's trade or an adjacent trade must hold a named
  -- service. The similarity above is computed for those already through and decides nothing here.
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or (c.never_asked and c.direct)
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality((select products from q)) > 0
                          then s.product_hits::numeric / cardinality((select products from q)) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
      + w.w_sim   * s.sim
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    case when r.direct then 'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+') end,
    case when not r.direct then 'reached through '
      || array_to_string(array(select unnest(r.trades) intersect select unnest((select codes from reach))), '+')
      || ' (the named service''s trade or a curated adjacent trade)' end,
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality((select products from q))||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when r.sim > 0 and r.sim < 1 then 'service similarity ' || round(r.sim, 2) end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;
