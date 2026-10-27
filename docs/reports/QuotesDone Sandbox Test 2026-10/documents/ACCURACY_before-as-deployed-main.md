# Supplier document intake accuracy — before-as-deployed-main

Measured 2026-10-07T02:27:09.742Z · model: none
Corpus: 59 synthetic documents, 50 licences (22 with a text layer). Leftover rows after the rollback: leads 0, storage 0.

## Verdict

| measure | result |
|---|---|
| gate decisions correct | 17/50 · held safely 32 · wrong reason 0 · **UNSAFE approvals 1** |
| licence no. / name / expiry on readable licences | licence_no 0% · legal_name_en 50% · expiry_date 100% |
| any field read WRONG (guessed) | 1 |
| trade proposals wrong (not exact) | 14 · missed 82 |
| match: wrong supplier reached | 10 · right supplier missed (not held) 10 |

## Per field (all licences / text-layer licences)

| field | correct | held | wrong | accuracy | readable accuracy |
|---|---|---|---|---|---|
| activities | 0 | 47 | 0 | 0% | 0% |
| authority | 0 | 47 | 0 | 0% | 0% |
| emirate | 0 | 47 | 0 | 0% | 0% |
| expiry_date | 22 | 25 | 0 | 46.8% | 100% |
| issue_date | 0 | 47 | 0 | 0% | 0% |
| legal_form | 0 | 47 | 0 | 0% | 0% |
| legal_name_ar | 0 | 2 | 0 | 0% | – |
| legal_name_en | 11 | 33 | 1 | 24.4% | 50% |
| licence_no | 0 | 47 | 0 | 0% | 0% |
| trade_name | 0 | 47 | 0 | 0% | 0% |

## Per authority (all fields · licence no./name/expiry)

| authority | correct | held | wrong | accuracy | critical accuracy |
|---|---|---|---|---|---|
| abu_dhabi_added | 2 | 25 | 0 | 7.4% | 22.2% |
| adgm | 1 | 17 | 0 | 5.6% | 16.7% |
| ajman_ded | 1 | 25 | 1 | 3.7% | 12.5% |
| dafza | 1 | 17 | 0 | 5.6% | 16.7% |
| difc | 2 | 16 | 0 | 11.1% | 33.3% |
| dmcc | 4 | 23 | 0 | 14.8% | 44.4% |
| dso | 2 | 16 | 0 | 11.1% | 33.3% |
| dubai_ded_old | 4 | 23 | 0 | 14.8% | 44.4% |
| dubai_det | 2 | 34 | 0 | 5.6% | 16.7% |
| fujairah_ded | 2 | 25 | 0 | 7.4% | 25% |
| ifza | 1 | 17 | 0 | 5.6% | 16.7% |
| jafza | 2 | 25 | 0 | 7.4% | 22.2% |
| meydan | 2 | 16 | 0 | 11.1% | 33.3% |
| none | 0 | 0 | 0 | – | – |
| rak_ded | 2 | 16 | 0 | 11.1% | 33.3% |
| rakez | 1 | 26 | 0 | 3.7% | 11.1% |
| shams | 1 | 17 | 0 | 5.6% | 16.7% |
| sharjah_sedd | 1 | 35 | 0 | 2.8% | 8.3% |
| uaq_ded | 2 | 16 | 0 | 11.1% | 33.3% |

## Per format

| format | correct | held | wrong | accuracy | critical accuracy |
|---|---|---|---|---|---|
| arabic_only_jpg | 0 | 9 | 0 | 0% | 0% |
| arabic_only_png | 0 | 9 | 0 | 0% | 0% |
| bilingual_jpg | 0 | 9 | 0 | 0% | 0% |
| bilingual_phone | 0 | 9 | 0 | 0% | 0% |
| bilingual_scan_pdf | 0 | 9 | 0 | 0% | 0% |
| blank_pdf | 0 | 0 | 0 | – | – |
| blank_photo | 0 | 0 | 0 | – | – |
| jpg | 0 | 36 | 0 | 0% | 0% |
| lowdpi | 0 | 18 | 0 | 0% | 0% |
| multipage_pdf | 3 | 15 | 0 | 16.7% | 50% |
| no_file | 0 | 0 | 0 | – | – |
| phone | 0 | 18 | 0 | 0% | 0% |
| png | 0 | 36 | 0 | 0% | 0% |
| rotated90 | 0 | 27 | 0 | 0% | 0% |
| scan_pdf | 0 | 27 | 0 | 0% | 0% |
| skewed | 0 | 18 | 0 | 0% | 0% |
| text_pdf_colon | 21 | 77 | 1 | 21.2% | 63.6% |
| text_pdf_table | 9 | 72 | 0 | 11.1% | 33.3% |

## Gate decisions (fn_sales_engineer_verifies_supplier)

| document | format | expected | got | verdict |
|---|---|---|---|---|
| lic_dubai_ded_old_text | text_pdf_colon | approve | approved | correct |
| lic_dubai_ded_old_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_dubai_det_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_dubai_det_png | png | approve | pending (licence_unreadable) | held |
| lic_abu_dhabi_added_text | text_pdf_colon | approve | approved | correct |
| lic_abu_dhabi_added_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_adgm_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_adgm_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_sharjah_sedd_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_sharjah_sedd_skewed | skewed | approve | pending (licence_unreadable) | held |
| lic_ajman_ded_text | text_pdf_colon | approve | approved | UNSAFE |
| lic_ajman_ded_lowdpi | lowdpi | approve | pending (licence_unreadable) | held |
| lic_rak_ded_text | text_pdf_colon | approve | approved | correct |
| lic_rak_ded_phone | phone | approve | pending (licence_unreadable) | held |
| lic_rakez_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_rakez_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_uaq_ded_text | text_pdf_colon | approve | approved | correct |
| lic_uaq_ded_png | png | approve | pending (licence_unreadable) | held |
| lic_fujairah_ded_text | text_pdf_colon | approve | approved | correct |
| lic_fujairah_ded_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_jafza_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_jafza_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_dmcc_text | text_pdf_colon | approve | approved | correct |
| lic_dmcc_skewed | skewed | approve | pending (licence_unreadable) | held |
| lic_dafza_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_dafza_lowdpi | lowdpi | approve | pending (licence_unreadable) | held |
| lic_dso_text | text_pdf_colon | approve | approved | correct |
| lic_dso_phone | phone | approve | pending (licence_unreadable) | held |
| lic_ifza_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_ifza_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_meydan_text | text_pdf_colon | approve | approved | correct |
| lic_meydan_png | png | approve | pending (licence_unreadable) | held |
| lic_shams_text | text_pdf_table | approve | pending (licence_unreadable) | held |
| lic_shams_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_difc_text | text_pdf_colon | approve | approved | correct |
| lic_difc_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_dubai_det_bi_jpg | bilingual_jpg | approve | pending (licence_unreadable) | held |
| lic_sharjah_sedd_bi_phone | bilingual_phone | approve | pending (licence_unreadable) | held |
| lic_abu_dhabi_added_bi_scan_pdf | bilingual_scan_pdf | approve | pending (licence_unreadable) | held |
| lic_ajman_ded_ar_png | arabic_only_png | hold_name | pending (licence_unreadable) | correct |
| lic_fujairah_ded_ar_jpg | arabic_only_jpg | hold_name | pending (licence_unreadable) | correct |
| lic_dmcc_multipage | multipage_pdf | approve | approved | correct |
| lic_jafza_multipage | multipage_pdf | approve | pending (licence_unreadable) | held |
| lic_expired_text | text_pdf_table | licence_expired | action_required (licence_expired) | correct |
| lic_expired_scan | jpg | licence_expired | pending (licence_unreadable) | held |
| lic_mismatch_text | text_pdf_colon | licence_name_mismatch | action_required (licence_name_mismatch) | correct |
| lic_mismatch_scan | png | licence_name_mismatch | pending (licence_unreadable) | held |
| lic_blank_pdf | blank_pdf | licence_unreadable | pending (licence_unreadable) | correct |
| lic_blank_photo | blank_photo | licence_unreadable | pending (licence_unreadable) | correct |
| lic_missing | no_file | reg_licence | action_required (reg_licence) | correct |

## Trades proposed from the documents (exact trade or none)

| document | kind | truth | proposed | wrong | missed |
|---|---|---|---|---|---|
| lic_dubai_ded_old_text | licence | aluminium, joinery | – |  | aluminium, joinery |
| lic_dubai_ded_old_scan_pdf | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_dubai_det_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_dubai_det_png | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_abu_dhabi_added_text | licence | flooring, glazing | cleaning_chemicals, flooring, glass_containers, glazing, racking_storage | cleaning_chemicals, glass_containers, racking_storage |  |
| lic_abu_dhabi_added_jpg | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_adgm_text | licence | fire_fighting, painting | – |  | fire_fighting, painting |
| lic_adgm_rotated90 | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_sharjah_sedd_text | licence | electrical, landscaping | electrical |  | landscaping |
| lic_sharjah_sedd_skewed | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_ajman_ded_text | licence | elevators, hvac | hvac |  | elevators |
| lic_ajman_ded_lowdpi | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_rak_ded_text | licence | aluminium, joinery | – |  | aluminium, joinery |
| lic_rak_ded_phone | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_rakez_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_rakez_scan_pdf | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_uaq_ded_text | licence | flooring, glazing | cleaning_chemicals, flooring, glass_containers, glazing | cleaning_chemicals, glass_containers |  |
| lic_uaq_ded_png | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_fujairah_ded_text | licence | fire_fighting, painting | – |  | fire_fighting, painting |
| lic_fujairah_ded_jpg | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_jafza_text | licence | electrical, landscaping | electrical |  | landscaping |
| lic_jafza_rotated90 | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_dmcc_text | licence | elevators, hvac | hvac |  | elevators |
| lic_dmcc_skewed | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_dafza_text | licence | aluminium, joinery | – |  | aluminium, joinery |
| lic_dafza_lowdpi | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_dso_text | licence | plumbing, waterproofing | plumbing, waterproofing |  |  |
| lic_dso_phone | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_ifza_text | licence | flooring, glazing | cleaning_chemicals, flooring, glass_containers, glazing, racking_storage | cleaning_chemicals, glass_containers, racking_storage |  |
| lic_ifza_scan_pdf | licence | elevators, joinery | (no text layer) |  | elevators, joinery |
| lic_meydan_text | licence | fire_fighting, painting | – |  | fire_fighting, painting |
| lic_meydan_png | licence | aluminium, waterproofing | (no text layer) |  | aluminium, waterproofing |
| lic_shams_text | licence | electrical, landscaping | electrical |  | landscaping |
| lic_shams_jpg | licence | glazing, plumbing | (no text layer) |  | glazing, plumbing |
| lic_difc_text | licence | elevators, hvac | hvac |  | elevators |
| lic_difc_rotated90 | licence | fire_fighting, flooring | (no text layer) |  | fire_fighting, flooring |
| lic_dubai_det_bi_jpg | licence | aluminium, joinery | (no text layer) |  | aluminium, joinery |
| lic_sharjah_sedd_bi_phone | licence | electrical, painting | (no text layer) |  | electrical, painting |
| lic_abu_dhabi_added_bi_scan_pdf | licence | plumbing, waterproofing | (no text layer) |  | plumbing, waterproofing |
| lic_ajman_ded_ar_png | licence | hvac, landscaping | (no text layer) |  | hvac, landscaping |
| lic_fujairah_ded_ar_jpg | licence | flooring, glazing | (no text layer) |  | flooring, glazing |
| lic_dmcc_multipage | licence | elevators, joinery | elevators |  | joinery |
| lic_jafza_multipage | licence | fire_fighting, painting | – |  | fire_fighting, painting |
| lic_expired_text | licence | aluminium, waterproofing | waterproofing |  | aluminium |
| lic_expired_scan | licence | electrical, landscaping | (no text layer) |  | electrical, landscaping |
| lic_mismatch_text | licence | glazing, plumbing | glass_containers, glazing, plumbing | glass_containers |  |
| lic_mismatch_scan | licence | elevators, hvac | (no text layer) |  | elevators, hvac |
| lic_blank_pdf | licence |  | (no text layer) |  |  |
| lic_blank_photo | licence |  | (no text layer) |  |  |
| profile_pdf | profile | aluminium, glazing | glazing, iso_certification | iso_certification | aluminium |
| profile_docx | profile | electrical, fire_fighting | iso_certification | iso_certification | electrical, fire_fighting |
| profile_pptx | profile | hvac, plumbing | iso_certification | iso_certification | hvac, plumbing |
| profile_png | profile | flooring, joinery | (no text layer) |  | flooring, joinery |
| profile_pdf_paint | profile | painting, waterproofing | iso_certification, painting, waterproofing | iso_certification |  |
| profile_docx_land | profile | landscaping | iso_certification | iso_certification | landscaping |
| catalogue_pdf | catalogue | aluminium, glazing | – |  | aluminium, glazing |

## Matching probe (fn_match_capability, one request per trade)

| trade | should reach | reached | wrong supplier | missed (held) | missed: named, no exact trade |
|---|---|---|---|---|---|
| hvac | 7 | 3 |  | 3 | profile_pptx |
| glazing | 8 | 3 |  | 5 |  |
| joinery | 9 | 0 |  | 8 | lic_dmcc_multipage |
| flooring | 7 | 2 |  | 5 |  |
| painting | 9 | 1 |  | 8 |  |
| plumbing | 8 | 1 |  | 6 | profile_pptx |
| aluminium | 9 | 0 |  | 8 | profile_pdf |
| elevators | 7 | 1 |  | 3 | lic_ajman_ded_text, lic_dmcc_text, lic_difc_text |
| electrical | 8 | 0 |  | 7 | profile_docx |
| landscaping | 7 | 0 |  | 6 | profile_docx_land |
| tax_advisory | 0 | 0 |  | 0 |  |
| fire_fighting | 8 | 0 |  | 7 | profile_docx |
| waterproofing | 8 | 2 |  | 6 |  |
| racking_storage | 0 | 1 | lic_abu_dhabi_added_text | 0 |  |
| glass_containers | 0 | 2 | lic_abu_dhabi_added_text, lic_uaq_ded_text | 0 |  |
| iso_certification | 0 | 5 | profile_pdf, profile_docx, profile_pptx, profile_pdf_paint, profile_docx_land | 0 |  |
| cleaning_chemicals | 0 | 2 | lic_abu_dhabi_added_text, lic_uaq_ded_text | 0 |  |
| corporate_training | 0 | 0 |  | 0 |  |

## Certificates (expiry only)

| document | truth | read | verdict |
|---|---|---|---|
| vat_certificate | null | null | n/a |
| iso_certificate | 2028-05-11 | 2028-05-11 | correct |

## Every failure and its cause (95)

- **field** `lic_dubai_ded_old_text` licence_no: held — truth "507919" — code did not read this label/layout, and the model was not asked
- **field** `lic_dubai_det_text` licence_no: held — truth "1023757" — code did not read this label/layout, and the model was not asked
- **field** `lic_dubai_det_text` legal_name_en: held — truth "ZZ DEMO Dune Plumbing LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_abu_dhabi_added_text` licence_no: held — truth "CN-1523645" — code did not read this label/layout, and the model was not asked
- **field** `lic_adgm_text` licence_no: held — truth "000010259" — code did not read this label/layout, and the model was not asked
- **field** `lic_adgm_text` legal_name_en: held — truth "ZZ DEMO Marina Painting Ltd" — code did not read this label/layout, and the model was not asked
- **field** `lic_sharjah_sedd_text` licence_no: held — truth "705517" — code did not read this label/layout, and the model was not asked
- **field** `lic_sharjah_sedd_text` legal_name_en: held — truth "ZZ DEMO Ghaf Landscaping LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_ajman_ded_text` licence_no: held — truth "12981" — code did not read this label/layout, and the model was not asked
- **field** `lic_ajman_ded_text` legal_name_en: wrong — truth "ZZ DEMO Sidra Lifts Est" — code read "ZZ DEMO Sidra Lifts"
- **field** `lic_rak_ded_text` licence_no: held — truth "24303" — code did not read this label/layout, and the model was not asked
- **field** `lic_rakez_text` licence_no: held — truth "5115755" — code did not read this label/layout, and the model was not asked
- **field** `lic_rakez_text` legal_name_en: held — truth "ZZ DEMO Wadi Plumbing FZ LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_uaq_ded_text` licence_no: held — truth "4649" — code did not read this label/layout, and the model was not asked
- **field** `lic_fujairah_ded_text` licence_no: held — truth "42147" — code did not read this label/layout, and the model was not asked
- **field** `lic_jafza_text` licence_no: held — truth "189691" — code did not read this label/layout, and the model was not asked
- **field** `lic_jafza_text` legal_name_en: held — truth "ZZ DEMO Dune Landscaping FZE" — code did not read this label/layout, and the model was not asked
- **field** `lic_dmcc_text` licence_no: held — truth "DMCC-238161" — code did not read this label/layout, and the model was not asked
- **field** `lic_dafza_text` licence_no: held — truth "1925" — code did not read this label/layout, and the model was not asked
- **field** `lic_dafza_text` legal_name_en: held — truth "ZZ DEMO Marina Aluminium FZ LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_dso_text` licence_no: held — truth "21043" — code did not read this label/layout, and the model was not asked
- **field** `lic_ifza_text` licence_no: held — truth "24587" — code did not read this label/layout, and the model was not asked
- **field** `lic_ifza_text` legal_name_en: held — truth "ZZ DEMO Sidra Floor FZ LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_meydan_text` licence_no: held — truth "MFZ-7541" — code did not read this label/layout, and the model was not asked
- **field** `lic_shams_text` licence_no: held — truth "2033429" — code did not read this label/layout, and the model was not asked
- **field** `lic_shams_text` legal_name_en: held — truth "ZZ DEMO Wadi Landscaping FZE" — code did not read this label/layout, and the model was not asked
- **field** `lic_difc_text` licence_no: held — truth "CL2015" — code did not read this label/layout, and the model was not asked
- **field** `lic_dmcc_multipage` licence_no: held — truth "DMCC-352294" — code did not read this label/layout, and the model was not asked
- **field** `lic_jafza_multipage` licence_no: held — truth "183654" — code did not read this label/layout, and the model was not asked
- **field** `lic_jafza_multipage` legal_name_en: held — truth "ZZ DEMO Marina Painting FZE" — code did not read this label/layout, and the model was not asked
- **field** `lic_expired_text` licence_no: held — truth "1348436" — code did not read this label/layout, and the model was not asked
- **field** `lic_expired_text` legal_name_en: held — truth "ZZ DEMO Crescent Building LLC" — code did not read this label/layout, and the model was not asked
- **field** `lic_mismatch_text` licence_no: held — truth "864274" — code did not read this label/layout, and the model was not asked
- **gate** `lic_dubai_ded_old_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dubai_det_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_dubai_det_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_abu_dhabi_added_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_adgm_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_adgm_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_sharjah_sedd_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_sharjah_sedd_skewed`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_ajman_ded_text`: UNSAFE (expected approve, got approved) — approved on a wrong reading of legal_name_en
- **gate** `lic_ajman_ded_lowdpi`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_rak_ded_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_rakez_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_rakez_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_uaq_ded_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_fujairah_ded_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_jafza_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_jafza_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dmcc_skewed`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dafza_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_dafza_lowdpi`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dso_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_ifza_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_ifza_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_meydan_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_shams_text`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_shams_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_difc_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dubai_det_bi_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_sharjah_sedd_bi_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_abu_dhabi_added_bi_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_jafza_multipage`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en not read)
- **gate** `lic_expired_scan`: held (expected licence_expired, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_mismatch_scan`: held (expected licence_name_mismatch, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **match** `profile_pptx` hvac: MISSING — not reached by a hvac request (proposed ["iso_certification"])
- **match** `lic_dmcc_multipage` joinery: MISSING — not reached by a joinery request (proposed ["elevators"])
- **match** `profile_pptx` plumbing: MISSING — not reached by a plumbing request (proposed ["iso_certification"])
- **match** `profile_pdf` aluminium: MISSING — not reached by a aluminium request (proposed ["glazing","iso_certification"])
- **match** `lic_ajman_ded_text` elevators: MISSING — not reached by a elevators request (proposed ["hvac"])
- **match** `lic_dmcc_text` elevators: MISSING — not reached by a elevators request (proposed ["hvac"])
- **match** `lic_difc_text` elevators: MISSING — not reached by a elevators request (proposed ["hvac"])
- **match** `profile_docx` electrical: MISSING — not reached by a electrical request (proposed ["iso_certification"])
- **match** `profile_docx_land` landscaping: MISSING — not reached by a landscaping request (proposed ["iso_certification"])
- **match** `profile_docx` fire_fighting: MISSING — not reached by a fire_fighting request (proposed ["iso_certification"])
- **match** `lic_abu_dhabi_added_text` racking_storage: EXTRA — reached by a racking_storage request it does not do (proposed ["cleaning_chemicals","flooring","glass_containers","glazing","racking_storage"], truth ["flooring","glazing"])
- **match** `lic_abu_dhabi_added_text` glass_containers: EXTRA — reached by a glass_containers request it does not do (proposed ["cleaning_chemicals","flooring","glass_containers","glazing","racking_storage"], truth ["flooring","glazing"])
- **match** `lic_uaq_ded_text` glass_containers: EXTRA — reached by a glass_containers request it does not do (proposed ["cleaning_chemicals","flooring","glass_containers","glazing"], truth ["flooring","glazing"])
- **match** `profile_pdf` iso_certification: EXTRA — reached by a iso_certification request it does not do (proposed ["glazing","iso_certification"], truth ["aluminium","glazing"])
- **match** `profile_docx` iso_certification: EXTRA — reached by a iso_certification request it does not do (proposed ["iso_certification"], truth ["electrical","fire_fighting"])
- **match** `profile_pptx` iso_certification: EXTRA — reached by a iso_certification request it does not do (proposed ["iso_certification"], truth ["hvac","plumbing"])
- **match** `profile_pdf_paint` iso_certification: EXTRA — reached by a iso_certification request it does not do (proposed ["iso_certification","painting","waterproofing"], truth ["painting","waterproofing"])
- **match** `profile_docx_land` iso_certification: EXTRA — reached by a iso_certification request it does not do (proposed ["iso_certification"], truth ["landscaping"])
- **match** `lic_abu_dhabi_added_text` cleaning_chemicals: EXTRA — reached by a cleaning_chemicals request it does not do (proposed ["cleaning_chemicals","flooring","glass_containers","glazing","racking_storage"], truth ["flooring","glazing"])
- **match** `lic_uaq_ded_text` cleaning_chemicals: EXTRA — reached by a cleaning_chemicals request it does not do (proposed ["cleaning_chemicals","flooring","glass_containers","glazing"], truth ["flooring","glazing"])
- **trades** `lic_abu_dhabi_added_text`: wrong — proposed cleaning_chemicals, glass_containers, racking_storage which the document does not do — meaning "Company Name: ZZ DEMO Horizon Floor LLC" -> floor & surface cleaners; meaning "Activities: Floor and Wall Tiling Works, Glass and Glazing Works" -> cosmetic & perfume glass; meaning "Trade Name: ZZ DEMO Horizon Floor" -> mezzanine floors
- **trades** `lic_uaq_ded_text`: wrong — proposed cleaning_chemicals, glass_containers which the document does not do — meaning "Company Name: ZZ DEMO Najm Floor LLC" -> floor & surface cleaners; meaning "Activities: Floor and Wall Tiling Works, Glass and Glazing Works" -> cosmetic & perfume glass
- **trades** `lic_ifza_text`: wrong — proposed cleaning_chemicals, glass_containers, racking_storage which the document does not do — meaning "Trade Name ZZ DEMO Sidra Floor" -> floor & surface cleaners; meaning "Activities Floor and Wall Tiling Works, Glass and Glazing Works" -> cosmetic & perfume glass; meaning "Company Name ZZ DEMO Sidra Floor FZ LLC" -> mezzanine floors
- **trades** `lic_mismatch_text`: wrong — proposed glass_containers which the document does not do — meaning "Activities: Glass and Glazing Works, Plumbing and Sanitary Installation" -> decoration & printing on glass/cosmetic & perfume glass
- **trades** `profile_pdf`: wrong — proposed iso_certification which the document does not do — meaning "- ISO 9001:2015 quality management" -> iso 9001/product conformity certification
- **trades** `profile_docx`: wrong — proposed iso_certification which the document does not do — meaning "- ISO 9001:2015 quality management" -> iso 9001/product conformity certification
- **trades** `profile_pptx`: wrong — proposed iso_certification which the document does not do — meaning "- ISO 9001:2015 quality management" -> iso 9001/product conformity certification
- **trades** `profile_pdf_paint`: wrong — proposed iso_certification which the document does not do — meaning "- ISO 9001:2015 quality management" -> iso 9001/product conformity certification
- **trades** `profile_docx_land`: wrong — proposed iso_certification which the document does not do — meaning "- ISO 9001:2015 quality management" -> iso 9001/product conformity certification
