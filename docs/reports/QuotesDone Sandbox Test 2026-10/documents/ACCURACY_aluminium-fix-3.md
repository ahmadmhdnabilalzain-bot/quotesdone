# Supplier document intake accuracy — aluminium-fix-3

Measured 2026-10-12T13:24:22.845Z · model: none
Corpus: 60 synthetic documents, 51 licences (23 with a text layer). Leftover rows after the rollback: leads 0, storage 0.

## Verdict

| measure | result |
|---|---|
| gate decisions correct | 28/51 · held safely 23 · wrong reason 0 · **UNSAFE approvals 0** |
| licence no. / name / expiry on readable licences | licence_no 100% · legal_name_en 100% · expiry_date 100% |
| any field read WRONG (guessed) | 0 |
| trade proposals wrong (not exact) | 0 · missed 52 |
| match: wrong supplier reached | 0 · right supplier missed (not held) 0 |

## Per field (all licences / text-layer licences)

| field | correct | held | wrong | accuracy | readable accuracy |
|---|---|---|---|---|---|
| activities | 23 | 25 | 0 | 47.9% | 100% |
| authority | 23 | 25 | 0 | 47.9% | 100% |
| emirate | 23 | 25 | 0 | 47.9% | 100% |
| expiry_date | 23 | 25 | 0 | 47.9% | 100% |
| issue_date | 23 | 25 | 0 | 47.9% | 100% |
| legal_form | 23 | 25 | 0 | 47.9% | 100% |
| legal_name_ar | 0 | 2 | 0 | 0% | – |
| legal_name_en | 23 | 23 | 0 | 50% | 100% |
| licence_no | 23 | 25 | 0 | 47.9% | 100% |
| trade_name | 23 | 25 | 0 | 47.9% | 100% |

## Per authority (all fields · licence no./name/expiry)

| authority | correct | held | wrong | accuracy | critical accuracy |
|---|---|---|---|---|---|
| abu_dhabi_added | 9 | 18 | 0 | 33.3% | 33.3% |
| adgm | 9 | 9 | 0 | 50% | 50% |
| ajman_ded | 9 | 18 | 0 | 33.3% | 37.5% |
| dafza | 9 | 9 | 0 | 50% | 50% |
| difc | 9 | 9 | 0 | 50% | 50% |
| dmcc | 18 | 9 | 0 | 66.7% | 66.7% |
| dso | 9 | 9 | 0 | 50% | 50% |
| dubai_ded_old | 27 | 9 | 0 | 75% | 75% |
| dubai_det | 18 | 18 | 0 | 50% | 50% |
| fujairah_ded | 9 | 18 | 0 | 33.3% | 37.5% |
| ifza | 9 | 9 | 0 | 50% | 50% |
| jafza | 18 | 9 | 0 | 66.7% | 66.7% |
| meydan | 9 | 9 | 0 | 50% | 50% |
| none | 0 | 0 | 0 | – | – |
| rak_ded | 9 | 9 | 0 | 50% | 50% |
| rakez | 9 | 18 | 0 | 33.3% | 33.3% |
| shams | 9 | 9 | 0 | 50% | 50% |
| sharjah_sedd | 9 | 27 | 0 | 25% | 25% |
| uaq_ded | 9 | 9 | 0 | 50% | 50% |

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
| multipage_pdf | 18 | 0 | 0 | 100% | 100% |
| no_file | 0 | 0 | 0 | – | – |
| phone | 0 | 18 | 0 | 0% | 0% |
| png | 0 | 36 | 0 | 0% | 0% |
| rotated90 | 0 | 27 | 0 | 0% | 0% |
| scan_pdf | 0 | 27 | 0 | 0% | 0% |
| skewed | 0 | 18 | 0 | 0% | 0% |
| text_pdf_colon | 108 | 0 | 0 | 100% | 100% |
| text_pdf_table | 81 | 0 | 0 | 100% | 100% |

## Gate decisions (fn_sales_engineer_verifies_supplier)

| document | format | expected | got | verdict |
|---|---|---|---|---|
| lic_dubai_ded_old_text | text_pdf_colon | approve | approved | correct |
| lic_dubai_ded_old_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_dubai_det_text | text_pdf_table | approve | approved | correct |
| lic_dubai_det_png | png | approve | pending (licence_unreadable) | held |
| lic_abu_dhabi_added_text | text_pdf_colon | approve | approved | correct |
| lic_abu_dhabi_added_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_adgm_text | text_pdf_table | approve | approved | correct |
| lic_adgm_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_sharjah_sedd_text | text_pdf_table | approve | approved | correct |
| lic_sharjah_sedd_skewed | skewed | approve | pending (licence_unreadable) | held |
| lic_ajman_ded_text | text_pdf_colon | approve | approved | correct |
| lic_ajman_ded_lowdpi | lowdpi | approve | pending (licence_unreadable) | held |
| lic_rak_ded_text | text_pdf_colon | approve | approved | correct |
| lic_rak_ded_phone | phone | approve | pending (licence_unreadable) | held |
| lic_rakez_text | text_pdf_table | approve | approved | correct |
| lic_rakez_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_uaq_ded_text | text_pdf_colon | approve | approved | correct |
| lic_uaq_ded_png | png | approve | pending (licence_unreadable) | held |
| lic_fujairah_ded_text | text_pdf_colon | approve | approved | correct |
| lic_fujairah_ded_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_jafza_text | text_pdf_table | approve | approved | correct |
| lic_jafza_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_dmcc_text | text_pdf_colon | approve | approved | correct |
| lic_dmcc_skewed | skewed | approve | pending (licence_unreadable) | held |
| lic_dafza_text | text_pdf_table | approve | approved | correct |
| lic_dafza_lowdpi | lowdpi | approve | pending (licence_unreadable) | held |
| lic_dso_text | text_pdf_colon | approve | approved | correct |
| lic_dso_phone | phone | approve | pending (licence_unreadable) | held |
| lic_ifza_text | text_pdf_table | approve | approved | correct |
| lic_ifza_scan_pdf | scan_pdf | approve | pending (licence_unreadable) | held |
| lic_meydan_text | text_pdf_colon | approve | approved | correct |
| lic_meydan_png | png | approve | pending (licence_unreadable) | held |
| lic_shams_text | text_pdf_table | approve | approved | correct |
| lic_shams_jpg | jpg | approve | pending (licence_unreadable) | held |
| lic_difc_text | text_pdf_colon | approve | approved | correct |
| lic_difc_rotated90 | rotated90 | approve | pending (licence_unreadable) | held |
| lic_dubai_det_bi_jpg | bilingual_jpg | approve | pending (licence_unreadable) | held |
| lic_sharjah_sedd_bi_phone | bilingual_phone | approve | pending (licence_unreadable) | held |
| lic_abu_dhabi_added_bi_scan_pdf | bilingual_scan_pdf | approve | pending (licence_unreadable) | held |
| lic_ajman_ded_ar_png | arabic_only_png | hold_name | pending (licence_unreadable) | correct |
| lic_fujairah_ded_ar_jpg | arabic_only_jpg | hold_name | pending (licence_unreadable) | correct |
| lic_dmcc_multipage | multipage_pdf | approve | approved | correct |
| lic_jafza_multipage | multipage_pdf | approve | approved | correct |
| lic_expired_text | text_pdf_table | licence_expired | action_required (licence_expired) | correct |
| lic_expired_scan | jpg | licence_expired | pending (licence_unreadable) | held |
| lic_mismatch_text | text_pdf_colon | name_autofilled | approved · name now "ZZ DEMO Mirage Contracting LLC" | correct |
| lic_mismatch_text_approved_swap | text_pdf_colon | name_autofilled | approved · name now "ZZ DEMO Mirage Contracting LLC" | correct |
| lic_mismatch_scan | png | name_autofilled | pending (licence_unreadable) · name now "ZZ DEMO Zenith Maintenance FZ LLC" | held |
| lic_blank_pdf | blank_pdf | licence_unreadable | pending (licence_unreadable) | correct |
| lic_blank_photo | blank_photo | licence_unreadable | pending (licence_unreadable) | correct |
| lic_missing | no_file | reg_licence | action_required (reg_licence) | correct |

## Trades proposed from the documents (exact trade or none)

| document | kind | truth | proposed | wrong | missed |
|---|---|---|---|---|---|
| lic_dubai_ded_old_text | licence | aluminium, joinery | aluminium, joinery |  |  |
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
| lic_rak_ded_text | licence | aluminium, joinery | aluminium, joinery |  |  |
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
| lic_dafza_text | licence | aluminium, joinery | aluminium, joinery |  |  |
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
| lic_expired_text | licence | aluminium, waterproofing | aluminium, waterproofing |  |  |
| lic_expired_scan | licence | electrical, landscaping | (no text layer) |  | electrical, landscaping |
| lic_mismatch_text | licence | glazing, plumbing | glazing, plumbing |  |  |
| lic_mismatch_text_approved_swap | licence | glazing, plumbing | glazing, plumbing |  |  |
| lic_mismatch_scan | licence | elevators, hvac | (no text layer) |  | elevators, hvac |
| lic_blank_pdf | licence |  | (no text layer) |  |  |
| lic_blank_photo | licence |  | (no text layer) |  |  |
| profile_pdf | profile | aluminium, glazing | aluminium, glazing |  |  |
| profile_docx | profile | electrical, fire_fighting | electrical, fire_fighting |  |  |
| profile_pptx | profile | hvac, plumbing | hvac, plumbing |  |  |
| profile_png | profile | flooring, joinery | (no text layer) |  | flooring, joinery |
| profile_pdf_paint | profile | painting, waterproofing | painting, waterproofing |  |  |
| profile_docx_land | profile | landscaping | landscaping |  |  |
| catalogue_pdf | catalogue | aluminium, glazing | aluminium, glazing |  |  |

## Matching probe (fn_match_capability, one request per trade)

| trade | should reach | reached | wrong supplier | missed (held) | missed: named, no exact trade |
|---|---|---|---|---|---|
| hvac | 8 | 4 |  | 4 |  |
| glazing | 10 | 7 |  | 3 |  |
| joinery | 9 | 4 |  | 5 |  |
| flooring | 7 | 3 |  | 4 |  |
| painting | 9 | 5 |  | 4 |  |
| plumbing | 10 | 6 |  | 4 |  |
| aluminium | 9 | 5 |  | 4 |  |
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

## Every failure and its cause (23)

- **gate** `lic_dubai_ded_old_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dubai_det_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_abu_dhabi_added_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_adgm_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_sharjah_sedd_skewed`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_ajman_ded_lowdpi`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_rak_ded_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_rakez_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_uaq_ded_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_fujairah_ded_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_jafza_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dmcc_skewed`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dafza_lowdpi`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dso_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_ifza_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_meydan_png`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_shams_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_difc_rotated90`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_dubai_det_bi_jpg`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_sharjah_sedd_bi_phone`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_abu_dhabi_added_bi_scan_pdf`: held (expected approve, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_expired_scan`: held (expected licence_expired, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
- **gate** `lic_mismatch_scan`: held (expected name_autofilled, got pending (licence_unreadable)) — held: licence_unreadable (licence_no, legal_name_en, expiry_date not read)
