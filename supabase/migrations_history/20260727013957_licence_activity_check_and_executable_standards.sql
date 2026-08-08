-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727013957   name: licence_activity_check_and_executable_standards
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ---- the licence-activity check the wrong_trade_licence scenario found missing ----
alter table public.leads add column if not exists license_activity text;

create table if not exists public.category_licence_activity (
  catalog_slug   text primary key,
  activity_regex text not null,
  note           text
);

insert into public.category_licence_activity (catalog_slug, activity_regex, note) values
('fire-fighting-equipment-suppliers','(?i)(fire ?(fighting|safety|protection|alarm)|safety equipment|extinguisher)','Dubai Civil Defence approval also required for installation.'),
('electrical-suppliers','(?i)(electric|electro ?mechanical|cable|switchgear|lighting)',null),
('plumbing-and-sanitaryware-suppliers','(?i)(plumb|sanitary|sanitaryware|water|drainage|pipe)',null),
('hvac-suppliers','(?i)(air ?condition|hvac|ventilat|refrigerat|electro ?mechanical|cooling)',null),
('cleaning-companies','(?i)(clean|facility|facilities|housekeep|pest)',null),
('catering-companies','(?i)(cater|food|kitchen|restaurant)','Municipality food licence also required.'),
('law-firms','(?i)(legal|advocat|law|attorney)','Legal Affairs / MOJ registration also required.'),
('accounting-and-audit-firms','(?i)(account|audit|book ?keep|financial consult)','MoE auditor registration also required.'),
('tax-consultants','(?i)(tax|account|audit|financial consult)','FTA tax agent registration also required.'),
('real-estate-agencies','(?i)(real ?estate|property|brokerage|broker)','RERA broker card also required in Dubai.'),
('travel-agencies','(?i)(travel|tourism|tour operat|holiday)','DET tourism licence also required.'),
('logistics-and-freight-forwarding-companies','(?i)(logistic|freight|forward|shipping|transport|customs clear)',null),
('security-services-companies','(?i)(security|guard|manpower security)','SIRA licence also required in Dubai.'),
('elv-and-security-systems-suppliers','(?i)(security system|cctv|low current|elv|electronic security|access control)','SIRA approval also required in Dubai.'),
('steel-and-reinforcement-suppliers','(?i)(steel|metal|reinforc|fabricat|iron)',null),
('joinery-and-carpentry-suppliers','(?i)(joinery|carpent|wood|furniture|decor)',null),
('flooring-suppliers','(?i)(floor|tile|marble|carpet|parquet|building material)',null),
('paints-and-finishing-materials-suppliers','(?i)(paint|coating|finish|building material)',null),
('chemical-suppliers','(?i)(chemical|industrial chemical|solvent|lubricant)','Some chemicals require MOIAT or Civil Defence clearance.'),
('pet-care-and-veterinary-services','(?i)(veterinar|pet|animal)','MOCCAE veterinary licence also required.')
on conflict (catalog_slug) do update set activity_regex = excluded.activity_regex, note = excluded.note;

-- A check_fn returns {"passed": bool, "detail": text}. It reads DATA, not prose.
create or replace function public.fn_check_licence_activity(p_subject_id text, p_content text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare v_lead leads%rowtype; v_cat text; v_rx text; v_note text;
begin
  begin
    select * into v_lead from leads where id = p_subject_id::bigint;
  exception when others then
    return jsonb_build_object('passed', false, 'detail', 'subject_id "' || p_subject_id || '" is not a lead id, so the licence activity cannot be checked');
  end;
  if v_lead.id is null then
    return jsonb_build_object('passed', false, 'detail', 'no lead ' || p_subject_id);
  end if;

  v_cat := (select unnest from unnest(v_lead.invite_trades) limit 1);
  if v_cat is null then
    return jsonb_build_object('passed', false, 'detail', 'supplier has declared no category, so no licence activity can be matched against it');
  end if;

  select activity_regex, note into v_rx, v_note from category_licence_activity where catalog_slug = v_cat;
  if v_rx is null then
    return jsonb_build_object('passed', false,
      'detail', 'no licence-activity rule recorded for category "' || v_cat || '" - cannot verify cover, so this application must be reviewed by a person');
  end if;

  if coalesce(trim(v_lead.license_activity), '') = '' then
    return jsonb_build_object('passed', false,
      'detail', 'trade licence activity was never captured for this supplier - request the licence and record its activity before approving');
  end if;

  if v_lead.license_activity ~ v_rx then
    return jsonb_build_object('passed', true,
      'detail', 'licence activity "' || v_lead.license_activity || '" covers ' || v_cat || coalesce('. ' || v_note, ''));
  end if;

  return jsonb_build_object('passed', false,
    'detail', 'MISMATCH: licence activity "' || v_lead.license_activity || '" does not cover the category applied for ("' || v_cat || '"). Request a licence whose activity includes that trade, or an amendment adding it.');
end; $fn$;

revoke execute on function public.fn_check_licence_activity(text,text) from anon, authenticated, public;

create or replace function public.fn_check_licence_expiry(p_subject_id text, p_content text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare v_exp date; v_no text;
begin
  begin
    select license_expiry, trade_license_no into v_exp, v_no from leads where id = p_subject_id::bigint;
  exception when others then
    return jsonb_build_object('passed', false, 'detail', 'subject_id is not a lead id');
  end;
  if coalesce(trim(v_no),'') = '' then
    return jsonb_build_object('passed', false, 'detail', 'no trade licence number recorded');
  end if;
  if v_exp is null then
    return jsonb_build_object('passed', false, 'detail', 'licence expiry date not recorded');
  end if;
  if v_exp < current_date then
    return jsonb_build_object('passed', false, 'detail', 'trade licence expired on ' || v_exp);
  end if;
  return jsonb_build_object('passed', true, 'detail', 'licence ' || v_no || ' valid to ' || v_exp);
end; $fn$;

revoke execute on function public.fn_check_licence_expiry(text,text) from anon, authenticated, public;

-- ---- make the standards executable where a check is honest, and explicit where it is not ----
update public.quality_standard set criteria = $j$[
  {"rule":"trade_licence_valid","severity":"critical","check_fn":"fn_check_licence_expiry",
   "why":"No licence, no verification. Nothing else matters until this passes."},
  {"rule":"licence_activity_covers_category","severity":"critical","check_fn":"fn_check_licence_activity",
   "why":"A licence whose activity does not cover the category applied for is a rejection with a specific named mismatch."},
  {"rule":"category_declared","severity":"major","check_fn":"fn_check_licence_activity",
   "why":"Suppliers must declare categories so matching works."},
  {"rule":"contactable","severity":"major","pattern":"(?i)(email|phone|mobile|whatsapp|contact)","fails_when":"no_match",
   "why":"An unreachable supplier cannot quote."}
]$j$::jsonb where work_type = 'supplier_application';

update public.quality_standard set criteria = $j$[
  {"rule":"scope_matches_rfq","severity":"critical","enforced_by":"human",
   "why":"A quote for different scope is not comparable and misleads the buyer. No deterministic check exists yet, so this routes to a person rather than passing silently."},
  {"rule":"no_supplier_identity","severity":"critical","pattern":"(?i)(LLC|L[.]L[.]C|Trading Est|Contracting Co|General Trading|Est[.])","fails_when":"match",
   "why":"Anonymity. A quote must not carry the supplier's identity before a paid reveal."},
  {"rule":"no_unmet_delivery_promise","severity":"critical","pattern":"(?i)(guarantee[a-z]* delivery|we can guarantee|no extra cost|best price in uae|cheapest)","fails_when":"match",
   "why":"Constitution article 6: never publish a delivery or price promise a supplier has not made."},
  {"rule":"price_breakdown","severity":"major","pattern":"(?i)(breakdown|itemis|itemiz|unit rate|line item|per (unit|sqm|m2|piece|point))","fails_when":"no_match",
   "why":"A single lump sum cannot be compared or value-engineered."},
  {"rule":"lead_time_stated","severity":"major","pattern":"(?i)(lead ?time|delivery|weeks|working days)","fails_when":"no_match",
   "why":"Delivery is half the decision."},
  {"rule":"validity_period","severity":"major","pattern":"(?i)(valid (for|until|till)|validity)","fails_when":"no_match",
   "why":"An undated price is not an offer."},
  {"rule":"exclusions_stated","severity":"major","pattern":"(?i)(exclusion|excludes|excluding|not included)","fails_when":"no_match",
   "why":"Undeclared exclusions are the most common source of dispute after award."}
]$j$::jsonb where work_type = 'quote';

update public.quality_standard set criteria = $j$[
  {"rule":"category_identified","severity":"critical","enforced_by":"human",
   "why":"An RFQ with no category cannot be routed to a specialist or matched to suppliers. No deterministic check exists yet."},
  {"rule":"mandatory_fields_present","severity":"critical","enforced_by":"human",
   "why":"Each category defines required fields in category_specs. No deterministic check exists yet."},
  {"rule":"no_supplier_named","severity":"critical","pattern":"(?i)(LLC|L[.]L[.]C|Trading Est|Contracting Co|General Trading|Est[.])","fails_when":"match",
   "why":"Anonymity. Constitution article 6."},
  {"rule":"quantity_and_location","severity":"major","pattern":"(?i)(dubai|abu dhabi|sharjah|ajman|fujairah|ras al khaimah|umm al quwain|jebel ali|emirate)","fails_when":"no_match",
   "why":"Suppliers cannot price without quantity and emirate."},
  {"rule":"timeline_stated","severity":"major","pattern":"(?i)(lead ?time|timeline|by [0-9]|weeks|working days|handover|deadline)","fails_when":"no_match",
   "why":"Lead time is a primary price driver in every category."}
]$j$::jsonb where work_type = 'rfq';
