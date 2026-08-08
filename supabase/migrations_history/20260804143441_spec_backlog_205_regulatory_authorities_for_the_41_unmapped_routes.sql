-- spec_backlog#205. The ticket named five routes (38, 39, 41, 61, 62). The live query named 41 with
-- zero authorities in the corpus, out of 86 blocked. Measured again before this ran:
--   no_mapped_subcategory = 0, no_arabic_alias = 0, reg_blocked = 86.
-- Regulatory status is the ONLY thing blocking activation, so this is not an inert change.
--
-- Provenance is deliberate: reviewed_by is 'claude-research-2026-08-04', NOT 'founder'. Routes
-- 38/39/41/61/62 carry the founder's own identifications. Everything else was researched against
-- official UAE government sources on 4 Aug 2026 and should be spot-checked before any route here
-- carries real regulated trade.
--
-- Two routes are DELIBERATELY LEFT BLOCKED at requires_review: 48 (business centres/coworking) and
-- 55 (fasteners & fixings). Research could not establish the position with confidence, and #207's
-- lesson applies — "no named authority" is not "no regulation".

update public.kb_operational_route set
  regulatory_coverage_status = 'confirmed_covered',
  regulatory_reviewed_by = 'claude-research-2026-08-04',
  regulatory_reviewed_at = now(),
  regulatory_coverage_note = v.note
from (values
 (17,'Dubai Municipality Buildings Regulation and Permits Agency (contractor registration, Dubai Law 7/2025); Dubai Central Laboratory product certification; Dubai Civil Defence (UAE Fire and Life Safety Code); Abu Dhabi DMT engineering classification. Ceiling systems need fire classification; contractor needs DM registration. Confidence: medium.'),
 (18,'Dubai Central Laboratory Ceramic Tiles Certification (ISO 13006:2018) and Low Emitting Materials scheme; DM Buildings Regulation and Permits Agency; Dubai Civil Defence interior floor finish classification. Confidence: medium.'),
 (19,'Dubai Central Laboratory product certification (glazed glass expressly in scope); Dubai Green Building Regulations (glazing U-value); Dubai Civil Defence (facade/cladding, fire-rated glazing); Abu Dhabi DMT. Confidence: medium.'),
 (20,'DM Buildings Regulation and Permits Agency (contractor registration); Dubai Civil Defence (fire-rated doorsets, interior finishes); Abu Dhabi DMT. No joinery-specific product scheme found beyond fire-rated elements. Confidence: medium.'),
 (21,'Dubai Central Laboratory Low Emitting Materials certification — paints, coatings, adhesives and sealants are expressly listed; Dubai Green Building Regulations (VOC limits); MOCCAE hazardous/chemical controls on solvent-based products (Federal Law 24/1999). Confidence: high.'),
 (22,'DM Buildings Regulation and Permits Agency (decor/fit-out permit and contractor registration, Dubai Law 7/2025); Dubai Civil Defence; Abu Dhabi DMT. Confidence: medium.'),
 (23,'Dubai Civil Defence (UAE Fire and Life Safety Code — interior furnishings and upholstery fire performance in regulated occupancies); MOIAT ECAS conformity for electrical items in FF&E packages. NOTE: there is no dedicated UAE furniture regulator; DM consumer-product registration does not cover furniture. See spec_backlog#207 for the scope-level triggers that make this route safe. Confidence: medium.'),
 (26,'MOIAT ECAS and Energy Efficiency Standardisation and Labelling; MOCCAE import permits for ODS/HFC refrigerants; Dubai Municipality Food Safety Department or ADAFSA where the cold room stores food; DM Health and Safety pressure-vessel certification. Confidence: medium.'),
 (27,'Dubai Municipality Food Safety Department (food establishment permit, Food Watch registration, certified Person in Charge); Abu Dhabi Agriculture and Food Safety Authority (ADAFSA). Confidence: high.'),
 (28,'DM Health and Safety Product Control Section via Montaji (food contact materials, cosmetics/amenities, detergents, biocides); MOIAT ECAS for electrical hospitality equipment. No hospitality-supplier-specific regulator. Confidence: medium.'),
 (29,'DM Health and Safety Product Control (food contact materials registration); MOIAT ECAS/EESL; DM boiler and pressure vessel certification for steam ovens and provers. Confidence: medium.'),
 (31,'Dubai Department of Economy and Tourism / DTCM ePermits event permit; Department of Culture and Tourism Abu Dhabi Events Licensing System; Dubai Development Authority within its zones; UAE Media Council / National Media Authority for content and performance permits. A genuine per-event permit regime, not just a trade licence. Confidence: high.'),
 (32,'DM Buildings Regulation and Permits Agency (temporary structure approval); Dubai Civil Defence; DET/DTCM ePermits for the event itself; venue technical accreditation (contractual, e.g. DWTC). Confidence: medium.'),
 (33,'TDRA Telecommunications Equipment Type Approval — binds dealers, importers and distributors of radio equipment (wireless mics, radio links); MOIAT ECAS for mains-powered equipment; UAE Media Council / NMA for broadcast activity. Type approval does not extend to non-radio AV. Confidence: medium.'),
 (34,'UAE Media Council and National Media Authority (media licence of a commercial nature / advertiser permit under Federal Decree-Law 55/2023); Dubai Media Office; Creative Media Authority Abu Dhabi. The federal body has been renamed more than once — anchor on the licence, not the label. Confidence: medium.'),
 (35,'CONDITIONAL, not uniformly regulated: generic DED/DET or free zone licence, plus TDRA only where telecom services are provided or radio equipment resold; UAE Data Office under Federal Decree-Law 45/2021 (PDPL) where personal data is processed; Dubai Electronic Security Center where serving Dubai Government. Confidence: medium.'),
 (36,'Dubai Electronic Security Center Cloud Service Provider Security Standard / ISR certification (annual); TDRA telecom and ICT service licensing; UAE Data Office PDPL including cross-border transfer rules. Confidence: medium.'),
 (38,'Ministry of Economy and Tourism; ADGM; DIFC. Founder-confirmed. Accounting and audit firms are a supervised DNFBP category with mandatory goAML registration. Confidence: high.'),
 (39,'Federal Tax Authority (FTA). Founder-confirmed. FTA maintains the tax agent register and administers VAT, excise and corporate tax. Confidence: high.'),
 (40,'Ministry of Economy and Tourism — DNFBP supervision of Trust and Company Service Providers (goAML, Federal Decree-Law 20/2018); MOHRE Tasheel for PRO/labour transactions; DIFC Registrar of Companies and ADGM Registration Authority for free-zone CSPs. Confidence: high.'),
 (41,'Dubai Legal Affairs Department; Abu Dhabi Judicial Department (ADJD). Founder-confirmed. Advocate and legal-consultancy licensing is emirate-level. Confidence: high.'),
 (43,'MOHRE licence for a Recruitment / Temporary Employment and Mediation Agency — the mandatory federal permission to broker or mediate employment on the mainland. Confidence: high.'),
 (44,'MOHRE Temporary Employment Agency licence. Supplying workers who stay on the supplier sponsorship while working for a client is temporary employment under UAE labour law. Confidence: high.'),
 (45,'No single FM regulator. Caught through component activities: DM Buildings Regulation and Permits Agency (maintenance contracting, Dubai Law 7/2025); Dubai Civil Defence company approval for fire-system installation and maintenance; DM Health and Safety approved cleaning and disinfection companies; Abu Dhabi DMT. Confidence: medium.'),
 (46,'Dubai Municipality Health and Safety Department approved list of cleaning and disinfection companies, and approval of professional biocides; Abu Dhabi Public Health Centre (ADPHC) for public health pest control; DM Public Health Pest Control approved list. DM Health and Safety NOC covers salons, spas and laundries — NOT general cleaning, so the approved-list route is the correct gate. See spec_backlog#207 for scope-level triggers. Confidence: medium.'),
 (49,'Dubai Customs business registration and clearing agent licensing via Dubai Trade; Federal Customs Authority; MOEI land transport licensing and national transportation vehicle permits (Federal Law 9/2011); RTA permits within Dubai. GCAA/IATA air cargo agency requirements NOT verified. Confidence: medium.'),
 (50,'Dubai Customs Customs (bonded/private) Warehouse Licence; Dubai Civil Defence warehouse fire approval; DM Health and Safety consumer products storage requirements and Food Safety Department food storage permits; MOCCAE for hazardous materials and waste. Confidence: medium.'),
 (51,'PROCUREMENT ELIGIBILITY REGIME, NOT A LICENCE: ADNOC supplier registration plus a Unified In-Country Value certificate issued by MOIAT-accredited certifying bodies. No UAE product regulator specific to oil and gas equipment. Confidence: medium.'),
 (53,'MOIAT Emirates Conformity Assessment Scheme (ECAS) for low-voltage electrical equipment; TDRA type approval where automation products contain radio modules. Regulated as product, not as an activity. Confidence: medium.'),
 (57,'DM Health and Safety Examination and Certification of Boilers and Pressure Vessels — compressed air receivers are pressure vessels requiring statutory periodic examination; MOIAT ECAS and EESL for the compressor unit. Confidence: medium.'),
 (58,'MOCCAE under Federal Law 24/1999 — import/export permits for ODS, HFCs, pesticides and hazardous waste; DM Health and Safety Product Control (detergents, biocides) and hazardous waste management; Dubai Civil Defence for storage and handling of flammable/hazardous materials; Environment Agency Abu Dhabi (EAD) in Abu Dhabi. Regulated by substance class, not trade licence. Confidence: medium.'),
 (59,'FANR licence and import permit for radiation sources and radiation-generating equipment (X-ray, XRF, irradiators); MOHAP / Emirates Drug Establishment where the equipment is a medical or IVD device; MOIAT ECAS for ordinary electrical lab equipment. Regulated by what it emits or what it is used for. Confidence: medium.'),
 (60,'No cleanroom-specific regulator. The contractor is regulated as a fit-out contractor (DM Buildings Regulation and Permits Agency, Dubai Civil Defence); the cleanroom is regulated indirectly through the licence of the facility it serves — MOHAP/EDE GMP for pharmaceutical plants, DoH Abu Dhabi or DHA for healthcare facilities. ISO 14644 is a standard, not a licence. Confidence: medium.'),
 (61,'MOHAP; DHA; DoH Abu Dhabi. Founder-confirmed. NOTE: MOHAP transferred a large block of medicine and medical-device services to the federal Emirates Drug Establishment (EDE) in 2025, so device registration is increasingly transacted through EDE. Confidence: high.'),
 (62,'MOHAP; DHA; DoH Abu Dhabi. Founder-confirmed. Same caveat as route 61 — pharmaceutical facility licensing and drug registration have been migrating from MOHAP to the Emirates Drug Establishment (EDE) since 2025. Confidence: high.'),
 (63,'DM Health and Safety Product Control — mandatory registration of children toys (products for under-14s); MOIAT ECAS for electrical educational equipment. NOTE: KHDA, ADEK and the Ministry of Education license schools, NOT their vendors. Confidence: medium.'),
 (67,'GENUINELY EMIRATE-SPLIT: DEWA Shams Dubai / DRRG enrolment for solar PV consultants and contractors, and the EV Charging Infrastructure Regulation with its Charge Point Operator licence; Abu Dhabi Department of Energy licensing for generation, storage and renewables; MOIAT ECAS federally for PV modules, inverters and batteries; DM registration of solar water heating systems. Confidence: medium.')
) as v(catalog_num, note)
where public.kb_operational_route.catalog_num = v.catalog_num;

-- Verified as having no specialist regulator beyond generic commercial licensing.
update public.kb_operational_route set
  regulatory_coverage_status = 'confirmed_none',
  regulatory_reviewed_by = 'claude-research-2026-08-04',
  regulatory_reviewed_at = now(),
  regulatory_coverage_note = v.note
from (values
 (42,'No specialist UAE regulator. Governed by the generic DED/DET or free zone commercial licence only. Specialist regulation attaches ONLY if an engagement crosses into audit (Ministry of Economy and Tourism), tax agency (FTA) or legal advice (emirate legal affairs departments) — those are different routes with their own gates. Confidence: medium.'),
 (54,'No UAE product-conformity scheme or specialist regulator found for bearings and power transmission components. Generic DED/DET or free zone trading licence; ISO/API standards are customer-imposed, not regulatory. Confidence: medium.')
) as v(catalog_num, note)
where public.kb_operational_route.catalog_num = v.catalog_num;

-- Left blocked on purpose. Record why, so the next session does not re-derive it.
update public.kb_operational_route set
  regulatory_coverage_note = v.note
from (values
 (48,'DELIBERATELY LEFT AT requires_review 4 Aug 2026. No specialist regulator for business centres or coworking operators could be established. Dubai Land Department Ejari registration applies to the underlying tenancy, not to the operator as a regulated activity — asserting DLD here would be wrong. Needs a human check before activation. Confidence: low.'),
 (55,'DELIBERATELY LEFT AT requires_review 4 Aug 2026. General fasteners appear to sit outside any UAE conformity scheme, but it could not be established whether STRUCTURAL ANCHORS and construction fixings are captured by Dubai Central Laboratory building-material technical approval. That specific question is open. Confidence: low.')
) as v(catalog_num, note)
where public.kb_operational_route.catalog_num = v.catalog_num;;
