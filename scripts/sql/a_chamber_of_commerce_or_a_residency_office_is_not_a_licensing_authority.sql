-- Assigned: sales_engineer
-- A CHAMBER OF COMMERCE OR A RESIDENCY OFFICE IS NOT A LICENSING AUTHORITY (12 Nov 2026, sales_engineer; founder ruling 1668; second
-- review of #1985, W1).
--
-- MEASURED, read-only on production, 12 Nov 2026: fn_licence_authority_class answers 'uae' for any name that prints an emirate, so
-- "Dubai Chamber of Commerce and Industry", the Abu Dhabi and Sharjah chambers, "Dubai Municipality" and "GDRFA Dubai" (an
-- establishment card's issuer) all classed as UAE licensing authorities. Its one caller, fn_sales_engineer_verifies_supplier, approves on
-- 'uae' (with the name matching and auto-approval on), holds on 'foreign' (licence_authority_not_uae) and on 'unknown'
-- (licence_authority_unconfirmed, asked to name the authority). So a chamber membership certificate read as a licence, by code before
-- #1978 or by a model that fills every printed field, could be approved.
-- Now those bodies answer 'unknown' whatever emirate they print: such a file is held for a person and never approved by the gate.
-- WHICH NAMES CHANGE (every other name answers exactly as before; every licensing authority, mainland and free zone, is untouched):
--   chambers of commerce (English and Arabic غرفة), Dubai Municipality (بلدية دبي), the residency office GDRFA / General Directorate
--   of Residency and Foreigners Affairs (الإقامة وشؤون الأجانب), the Federal Tax Authority (الهيئة الاتحادية للضرائب).
-- LEFT AS THEY ARE, NOT SURE: the other emirates' municipalities (some issued licences historically, e.g. in Fujairah and Umm Al
-- Quwain), Dubai Economy's older names, and any "authority" of a free zone. Names are compared after fn_licence_authority_norm.
-- fn_licence_authority_class is replaced from its LIVE definition (pg_get_functiondef, 12 Nov 2026) with only the list and one line
-- added; CREATE OR REPLACE keeps its ACL (postgres, service_role). IMMUTABLE and search_path are unchanged.
-- Probe: scripts/sql/a_chamber_of_commerce_or_a_residency_office_is_not_a_licensing_authority_probe.sql

CREATE OR REPLACE FUNCTION public.fn_licence_authority_class(p_authority text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n text := ' ' || public.fn_licence_authority_norm(p_authority) || ' ';
  v_strong text[] := array['dubai','abu dhabi','sharjah','ajman','umm al quwain','umm al qaiwain','umm al qiwain','uaq','ras al khaimah','ras al khaima','rak','fujairah','fujeirah',
    'united arab emirates','uae','u a e',
    'jafza','jebel ali','dmcc','dafza','dso','dieza','silicon oasis','difc','adgm','ifza','international free zone authority','meydan','tecom','dwc',
    'rakez','rak economic zone','rak icc','rak ded','kezad','kizad','khalifa economic zones','khalifa industrial zone','zonescorp','masdar','twofour54','adafz',
    'saif','shams','spc','hamriyah','hfza','sedd','afz','fcc','ffz','creative city','added',
    'دبي','ابو ظبي','الشارقه','عجمان','ام القيوين','راس الخيمه','الفجيره','الامارات العربيه المتحده','الامارات'];
  -- Generic names that say nothing of a country: UAE unless a foreign country is printed beside them.
  v_weak text[] := array['department of economy and tourism','department of economic development','economic development department','department of industry and economy','ministry of economy','det','ded',
    'دائره الاقتصاد والسياحه','دائره التنميه الاقتصاديه','دائره الصناعه والاقتصاد','وزاره الاقتصاد'];
  v_foreign text[] := array['saudi','saudi arabia','ksa','qatar','qatari','oman','omani','kuwait','bahrain','egypt','jordan','iraq','lebanon','india','pakistan','bangladesh','china','turkey','iran',
    'united kingdom','england','companies house','united states','usa','germany','france','italy','singapore',
    'السعوديه','قطر','سلطنه عمان','الكويت','البحرين','مصر','الاردن','العراق','لبنان'];
  -- Bodies that are not licensing authorities but print an emirate in their name (second review of #1985, W1; see the header): a
  -- document they issue is not a trade licence, so its authority is never 'uae' by the emirate in its name. A person looks ('unknown').
  v_not_licensing text[] := array['chamber','chambers','chamber of commerce','غرفه','غرفه تجاره','dubai municipality','بلديه دبي',
    'gdrfa','general directorate of residency','residency and foreigners affairs','foreigners affairs','الاقامه وشوون الاجانب','الاقامه وشؤون الاجانب',
    'federal tax authority','الهيئه الاتحاديه للضرائب'];
  v_s boolean; v_w boolean; v_f boolean;
begin
  if btrim(n) = '' then return 'unread'; end if;
  if exists (select 1 from unnest(v_not_licensing) x where position(' ' || x || ' ' in n) > 0) then return 'unknown'; end if;
  v_s := exists (select 1 from unnest(v_strong) x where position(' ' || x || ' ' in n) > 0);
  v_w := exists (select 1 from unnest(v_weak) x where position(' ' || x || ' ' in n) > 0);
  v_f := exists (select 1 from unnest(v_foreign) x where position(' ' || x || ' ' in n) > 0);
  if v_f and v_s then return 'unknown'; end if;   -- both printed: a person looks
  if v_f then return 'foreign'; end if;
  if v_s or v_w then return 'uae'; end if;
  return 'unknown';
end $function$;
