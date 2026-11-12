-- PROBE for a_supplier_reads_every_answer_the_customer_gave_in_english.sql (sales_engineer, 12 Nov 2026; final audit
-- customer_journey B2). A pure probe: it always ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row it
-- writes rolls back. Before the apply, run it after the file it proves (node scripts/ci/rehearse_sql.mjs <file> <probe>);
-- after, alone. Run alone against the routine of 12 Nov 2026 it answers PROBE FAILED (the key is dropped).
--
-- Its customer is a ZZ DEMO fixture at an .invalid address; no supplier is matched, so nothing is offered to anyone.
-- The spec is the one the audit's villa HVAC request carried (run d9a04dbc), with an e-mail added to an English answer
-- and one answer written only in Arabic:
--   1. the supplier copy keeps customer_requirements, with display.en, required_by, warranty and installation exactly;
--   2. no Arabic anywhere in the supplier copy (display.ar, label_ar, choice_ar and the Arabic-only answer are gone);
--   3. the identity scrub still runs: the e-mail in an English answer is hidden;
--   4. an English answer at the top level is unchanged;
--   5. the customer's name, a phone and an e-mail typed into an answer never reach the supplier copy (review note 9).
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  ar constant text := '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]';
  c1 uuid; i1 uuid; m jsonb; v_bad text := '';
  v_req jsonb := $j${"display": {"ar": [{"key": "material.brand", "label": "ماركة المكيفات", "value": "ماركات فاخرة"}, {"key": "warranty", "label": "الضمان", "value": "نعم، سنتان على الأقل"}, {"key": "required_by", "label": "مطلوب بحلول", "value": "بحلول 2027-01-31"}],
    "en": [{"key": "material.brand", "label": "Air-conditioning brand", "value": "Premium brands"}, {"key": "installation", "label": "Installation", "value": "Yes, install it"}, {"key": "warranty", "label": "Warranty", "value": "Yes, at least 2 years"}, {"key": "required_by", "label": "Needed by", "value": "By 2027-01-31"}]},
    "version": 2, "category": "hvac", "warranty": {"required": "yes", "min_months": 24},
    "materials": [{"note": null, "choice": "premium", "label_ar": "ماركة المكيفات", "label_en": "Air-conditioning brand", "choice_ar": "ماركات فاخرة", "choice_en": "Premium brands", "component": "brand"}],
    "recorded_at": "2026-11-11T23:52:51.839Z", "recorded_by": "sales_engineer",
    "required_by": {"date": "2027-01-31", "text": "2027-01-31", "flexible": false}, "installation": {"required": "yes"}}$j$::jsonb;
begin
  insert into public.customers (email, full_name, locale) values
    ('zz-reqs-' || v_tag || '@example.invalid', 'Zebulon Quartermaine', 'en') returning id into c1;
  v_req := jsonb_set(v_req, '{materials,0,note}', to_jsonb('Ask Zebulon Quartermaine on 050 000 0094 or zeb-' || v_tag || '@example.invalid'));
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, scope_type) values
    (c1, 'hvac', 'Dubai', 'ZZ DEMO villa HVAC', 'draft', 'en',
     jsonb_build_object('customer_requirements', v_req, 'spec_refrigerant', 'R32',
       'spec_brand_preference_or_equivalent_tier', 'Japanese brand, call zz-leak-' || v_tag || '@example.invalid',
       'spec_notes_ar', 'وحدات مخفية في السقف'), 'single')
    returning id into i1;
  select spec_masked into m from public.inquiries where id = i1;

  if not coalesce(m ? 'customer_requirements', false) then v_bad := v_bad || 'customer_requirements is missing from the supplier copy; '; end if;
  if m #> '{customer_requirements,display,en}' is distinct from v_req #> '{display,en}' then v_bad := v_bad || 'display.en changed: ' || coalesce((m #> '{customer_requirements,display,en}')::text, 'null') || '; '; end if;
  if m #> '{customer_requirements,required_by}' is distinct from v_req -> 'required_by' then v_bad := v_bad || 'required_by changed; '; end if;
  if m #> '{customer_requirements,warranty}' is distinct from v_req -> 'warranty' then v_bad := v_bad || 'warranty changed; '; end if;
  if m #>> '{customer_requirements,materials,0,choice_en}' is distinct from 'Premium brands' then v_bad := v_bad || 'materials lost choice_en; '; end if;
  if m::text ~ ar then v_bad := v_bad || 'the supplier copy carries Arabic: ' || left(m::text, 300) || '; '; end if;
  if m ? 'spec_notes_ar' then v_bad := v_bad || 'the Arabic-only answer reached the supplier copy; '; end if;
  if m::text like '%zz-leak-' || v_tag || '%' then v_bad := v_bad || 'the e-mail in an English answer was not hidden; '; end if;
  if m::text ~* ('(zebulon|quartermaine|050 000 0094|zeb-' || v_tag || ')') then v_bad := v_bad || 'a name, phone or e-mail typed into an answer reached the supplier copy: ' || coalesce(m #>> '{customer_requirements,materials,0,note}', 'null') || '; '; end if;
  if m ->> 'spec_refrigerant' is distinct from 'R32' then v_bad := v_bad || 'an English top-level answer changed; '; end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: the supplier copy keeps customer_requirements in English, carries no Arabic, and still hides contacts';
end $probe$;
