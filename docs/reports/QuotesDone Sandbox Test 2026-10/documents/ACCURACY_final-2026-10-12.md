# Supplier document intake accuracy — final-2026-10-12

Measured 2026-10-12T12:34:57.422Z · model: deployed · model spend 28 calls, AED 0.0494
Corpus: 60 synthetic documents, 51 licences (23 with a text layer). Leftover rows after the rollback: leads 0, storage 0.

## Verdict

| measure | result |
|---|---|
| gate decisions correct | 51/51 · held safely 0 · wrong reason 0 · **UNSAFE approvals 0** |
| licence no. / name / expiry on readable licences | licence_no 100% · legal_name_en 100% · expiry_date 100% |
| any field read WRONG (guessed) | 1 |
| trade proposals wrong (not exact) | 0 · missed 56 |
| match: wrong supplier reached | 0 · right supplier missed (not held) 5 |

## Per field (all licences / text-layer licences)

| field | correct | held | wrong | accuracy | readable accuracy |
|---|---|---|---|---|---|
| activities | 48 | 0 | 0 | 100% | 100% |
| authority | 48 | 0 | 0 | 100% | 100% |
| emirate | 48 | 0 | 0 | 100% | 100% |
| expiry_date | 48 | 0 | 0 | 100% | 100% |
| issue_date | 48 | 0 | 0 | 100% | 100% |
| legal_form | 48 | 0 | 0 | 100% | 100% |
| legal_name_ar | 0 | 2 | 0 | 0% | – |
| legal_name_en | 46 | 0 | 0 | 100% | 100% |
| licence_no | 48 | 0 | 0 | 100% | 100% |
| trade_name | 47 | 0 | 1 | 97.9% | 100% |

## Per authority (all fields · licence no./name/expiry)

| authority | correct | held | wrong | accuracy | critical accuracy |
|---|---|---|---|---|---|
| abu_dhabi_added | 27 | 0 | 0 | 100% | 100% |
| adgm | 18 | 0 | 0 | 100% | 100% |
| ajman_ded | 25 | 1 | 1 | 92.6% | 100% |
| dafza | 18 | 0 | 0 | 100% | 100% |
| difc | 18 | 0 | 0 | 100% | 100% |
| dmcc | 27 | 0 | 0 | 100% | 100% |
| dso | 18 | 0 | 0 | 100% | 100% |
| dubai_ded_old | 36 | 0 | 0 | 100% | 100% |
| dubai_det | 36 | 0 | 0 | 100% | 100% |
| fujairah_ded | 26 | 1 | 0 | 96.3% | 100% |
| ifza | 18 | 0 | 0 | 100% | 100% |
| jafza | 27 | 0 | 0 | 100% | 100% |
| meydan | 18 | 0 | 0 | 100% | 100% |
| none | 0 | 0 | 0 | – | – |
| rak_ded | 18 | 0 | 0 | 100% | 100% |
| rakez | 27 | 0 | 0 | 100% | 100% |
| shams | 18 | 0 | 0 | 100% | 100% |
| sharjah_sedd | 36 | 0 | 0 | 100% | 100% |
| uaq_ded | 18 | 0 | 0 | 100% | 100% |

## Per format

| format | correct | held | wrong | accuracy | critical accuracy |
|---|---|---|---|---|---|
| arabic_only_jpg | 8 | 1 | 0 | 88.9% | 100% |
| arabic_only_png | 7 | 1 | 1 | 77.8% | 100% |
| bilingual_jpg | 9 | 0 | 0 | 100% | 100% |
| bilingual_phone | 9 | 0 | 0 | 100% | 100% |
| bilingual_scan_pdf | 9 | 0 | 0 | 100% | 100% |
| blank_pdf | 0 | 0 | 0 | – | – |
| blank_photo | 0 | 0 | 0 | – | – |
| jpg | 36 | 0 | 0 | 100% | 100% |
| lowdpi | 18 | 0 | 0 | 100% | 100% |
| multipage_pdf | 18 | 0 | 0 | 100% | 100% |
| no_file | 0 | 0 | 0 | – | – |
| phone | 18 | 0 | 0 | 100% | 100% |
| png | 36 | 0 | 0 | 100% | 100% |
| rotated90 | 27 | 0 | 0 | 100% | 100% |
| scan_pdf | 27 | 0 | 0 | 100% | 100% |
| skewed | 18 | 0 | 0 | 100% | 100% |
| text_pdf_colon | 108 | 0 | 0 | 100% | 100% |
| text_pdf_table | 81 | 0 | 0 | 100% | 100% |

## Gate decisions (fn_sales_engineer_verifies_supplier)

| document | format | expected | got | verdict |
|---|---|---|---|---|
| lic_dubai_ded_old_text | text_pdf_colon | approve | approved | correct |
| lic_dubai_ded_old_scan_pdf | scan_pdf | approve | approved | correct |
| lic_dubai_det_text | text_pdf_table | approve | approved | correct |
| lic_dubai_det_png | png | approve | approved | correct |
| lic_abu_dhabi_added_text | text_pdf_colon | approve | approved | correct |
| lic_abu_dhabi_added_jpg | jpg | approve | approved | correct |
| lic_adgm_text | text_pdf_table | approve | approved | correct |
| lic_adgm_rotated90 | rotated90 | approve | approved | correct |
| lic_sharjah_sedd_text | text_pdf_table | approve | approved | correct |
| lic_sharjah_sedd_skewed | skewed | approve | approved | correct |
| lic_ajman_ded_text | text_pdf_colon | approve | approved | correct |
| lic_ajman_ded_lowdpi | lowdpi | approve | approved | correct |
| lic_rak_ded_text | text_pdf_colon | approve | approved | correct |
| lic_rak_ded_phone | phone | approve | approved | correct |
| lic_rakez_text | text_pdf_table | approve | approved | correct |
| lic_rakez_scan_pdf | scan_pdf | approve | approved | correct |
| lic_uaq_ded_text | text_pdf_colon | approve | approved | correct |
| lic_uaq_ded_png | png | approve | approved | correct |
| lic_fujairah_ded_text | text_pdf_colon | approve | approved | correct |
| lic_fujairah_ded_jpg | jpg | approve | approved | correct |
| lic_jafza_text | text_pdf_table | approve | approved | correct |
| lic_jafza_rotated90 | rotated90 | approve | approved | correct |
| lic_dmcc_text | text_pdf_colon | approve | approved | correct |
| lic_dmcc_skewed | skewed | approve | approved | correct |
| lic_dafza_text | text_pdf_table | approve | approved | correct |
| lic_dafza_lowdpi | lowdpi | approve | approved | correct |
| lic_dso_text | text_pdf_colon | approve | approved | correct |
| lic_dso_phone | phone | approve | approved | correct |
| lic_ifza_text | text_pdf_table | approve | approved | correct |
| lic_ifza_scan_pdf | scan_pdf | approve | approved | correct |
| lic_meydan_text | text_pdf_colon | approve | approved | correct |
| lic_meydan_png | png | approve | approved | correct |
| lic_shams_text | text_pdf_table | approve | approved | correct |
| lic_shams_jpg | jpg | approve | approved | correct |
| lic_difc_text | text_pdf_colon | approve | approved | correct |
| lic_difc_rotated90 | rotated90 | approve | approved | correct |
| lic_dubai_det_bi_jpg | bilingual_jpg | approve | approved | correct |
| lic_sharjah_sedd_bi_phone | bilingual_phone | approve | approved | correct |
| lic_abu_dhabi_added_bi_scan_pdf | bilingual_scan_pdf | approve | approved | correct |
| lic_ajman_ded_ar_png | arabic_only_png | hold_name | pending (licence_unreadable) | correct |
| lic_fujairah_ded_ar_jpg | arabic_only_jpg | hold_name | pending (licence_unreadable) | correct |
| lic_dmcc_multipage | multipage_pdf | approve | approved | correct |
| lic_jafza_multipage | multipage_pdf | approve | approved | correct |
| lic_expired_text | text_pdf_table | licence_expired | action_required (licence_expired) | correct |
| lic_expired_scan | jpg | licence_expired | action_required (licence_expired) | correct |
| lic_mismatch_text | text_pdf_colon | name_autofilled | approved · name now "ZZ DEMO Mirage Contracting LLC" | correct |
| lic_mismatch_text_approved_swap | text_pdf_colon | name_autofilled | approved · name now "ZZ DEMO Mirage Contracting LLC" | correct |
| lic_mismatch_scan | png | name_autofilled | approved · name now "ZZ DEMO Atlas Building Works FZ LLC" | correct |
| lic_blank_pdf | blank_pdf | licence_unreadable | pending (licence_unreadable) | correct |
| lic_blank_photo | blank_photo | licence_unreadable | pending (licence_unreadable) | correct |
| lic_missing | no_file | reg_licence | action_required (reg_licence) | correct |

## Trades proposed from the documents (exact trade or none)

| document | kind | truth | proposed | wrong | missed |
|---|---|---|---|---|---|
| lic_dubai_ded_old_text | licence | aluminium, joinery | joinery |  | aluminium |
| lic_dubai_ded_old_scan_pdf | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_dubai_det_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_dubai_det_png | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_abu_dhabi_added_text | licence | flooring, glazing | flooring, glazing |  |  |
| lic_abu_dhabi_added_jpg | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_adgm_text | licence | fire_fighting, painting | fire_fighting, painting |  |  |
| lic_adgm_rotated90 | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_sharjah_sedd_text | licence | electrical, landscaping | electrical, landscaping |  |  |
| lic_sharjah_sedd_skewed | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_ajman_ded_text | licence | elevators, hvac | elevators, hvac |  |  |
| lic_ajman_ded_lowdpi | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_rak_ded_text | licence | aluminium, joinery | joinery |  | aluminium |
| lic_rak_ded_phone | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_rakez_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_rakez_scan_pdf | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_uaq_ded_text | licence | flooring, glazing | flooring, glazing |  |  |
| lic_uaq_ded_png | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_fujairah_ded_text | licence | fire_fighting, painting | fire_fighting, painting |  |  |
| lic_fujairah_ded_jpg | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_jafza_text | licence | electrical, landscaping | electrical, landscaping |  |  |
| lic_jafza_rotated90 | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_dmcc_text | licence | elevators, hvac | elevators, hvac |  |  |
| lic_dmcc_skewed | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_dafza_text | licence | aluminium, joinery | joinery |  | aluminium |
| lic_dafza_lowdpi | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_dso_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_dso_phone | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_ifza_text | licence | flooring, glazing | flooring, glazing |  |  |
| lic_ifza_scan_pdf | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_meydan_text | licence | fire_fighting, painting | fire_fighting, painting |  |  |
| lic_meydan_png | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_shams_text | licence | electrical, landscaping | electrical, landscaping |  |  |
| lic_shams_jpg | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_difc_text | licence | elevators, hvac | elevators, hvac |  |  |
| lic_difc_rotated90 | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_dubai_det_bi_jpg | licence | aluminium, joinery | (no text layer) |  | aluminium, joinery |
| lic_sharjah_sedd_bi_phone | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_abu_dhabi_added_bi_scan_pdf | licence | plumbing, waterproofing | (no text layer) |  | plumbing, waterproofing |
| lic_ajman_ded_ar_png | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_fujairah_ded_ar_jpg | licence | flooring, glazing | (no text layer) |  | flooring, glazing |
| lic_dmcc_multipage | licence | elevators, joinery | elevators, joinery |  |  |
| lic_jafza_multipage | licence | fire_fighting, painting | fire_fighting, painting |  |  |
| lic_expired_text | licence | aluminium, waterproofing | waterproofing |  | aluminium |
| lic_expired_scan | licence | electrical, landscaping | (no text layer) |  | electrical, landscaping |
| lic_mismatch_text | licence | glazing, plumbing | glazing, plumbing |  |  |
| lic_mismatch_text_approved_swap | licence | glazing, plumbing | glazing, plumbing |  |  |
| lic_mismatch_scan | licence | elevators, hvac | (no text layer) |  | elevators, hvac |
| lic_blank_pdf | licence |  | (no text layer) |  |  |
| lic_blank_photo | licence |  | (no text layer) |  |  |
| profile_pdf | profile | aluminium, glazing | glazing |  | aluminium |
| profile_docx | profile | electrical, fire_fighting | electrical, fire_fighting |  |  |
| profile_pptx | profile | hvac, plumbing | hvac, plumbing |  |  |
| profile_png | profile | flooring, joinery | flooring, joinery |  |  |
| profile_pdf_paint | profile | painting, waterproofing | painting, waterproofing |  |  |
| profile_docx_land | profile | landscaping | landscaping |  |  |
| catalogue_pdf | catalogue | aluminium, glazing | glazing |  | aluminium |

## Matching probe (fn_match_capability, one request per trade)

| trade | should reach | reached | wrong supplier | missed (held) | missed: named, no exact trade |
|---|---|---|---|---|---|
| hvac | 8 | 4 |  | 4 |  |
| glazing | 10 | 7 |  | 3 |  |
| joinery | 9 | 5 |  | 4 |  |
| flooring | 7 | 4 |  | 3 |  |
| painting | 9 | 5 |  | 4 |  |
| plumbing | 10 | 6 |  | 4 |  |
| aluminium | 9 | 0 |  | 4 | lic_dubai_ded_old_text, lic_rak_ded_text, lic_dafza_text, profile_pdf, catalogue_pdf |
| elevators | 8 | 4 |  | 4 |  |
| electrical | 8 | 4 |  | 4 |  |
| landscaping | 7 | 4 |  | 3 |  |
| tax_advisory | 0 | 0 |  | 0 |  |
| fire_fighting | 8 | 5 |  | 3 |  |
| waterproofing | 8 | 4 |  | 4 |  |
| legal_services | 0 | 0 |  | 0 |  |
| corporate_training | 0 | 0 |  | 0 |  |

## Certificates (expiry only)

| document | truth | read | verdict |
|---|---|---|---|
| vat_certificate | null | null | n/a |
| iso_certificate | 2028-05-11 | 2028-05-11 | correct |

## Every failure and its cause (6)

- **field** `lic_ajman_ded_ar_png` trade_name: wrong — truth "زد زد ديمو الواحة" — model read "ز د ز ديمو الواحة"
- **match** `lic_dubai_ded_old_text` aluminium: MISSING — not reached by a aluminium request (proposed ["joinery"])
- **match** `lic_rak_ded_text` aluminium: MISSING — not reached by a aluminium request (proposed ["joinery"])
- **match** `lic_dafza_text` aluminium: MISSING — not reached by a aluminium request (proposed ["joinery"])
- **match** `profile_pdf` aluminium: MISSING — not reached by a aluminium request (proposed ["glazing"])
- **match** `catalogue_pdf` aluminium: MISSING — not reached by a aluminium request (proposed ["glazing"])
