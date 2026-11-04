# Document-reading qualification: code stage (no model spend)

2026-11-03T10:18:25.225Z · 116 gold items × 5 repeats · corpus scripts/e2e/document_reading_qualification_corpus.ts

| class | items | runs | gold lines reaching the model | trade recall | trade precision | forbidden proposed | model unavailable (runs) | licence fields exact | licence fields WRONG | honest outcome | partial read disclosed | same verdict every repeat |
|---|---|---:|---|---|---|---|---|---|---|---|---|---|
| edge_corrupt | E01_corrupt_pdf, E05_corrupt_licence | 10 | n/a | model stage not run | model stage not run | model stage not run | - | 100.0% (40/40) | 0 | 100.0% (10/10) | - | 100.0% (2/2) |
| edge_password | E02_password_pdf | 5 | n/a | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_30mb_text | E03_30mb_text | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_30mb_scan | E04_30mb_scan | 5 | 0.0% (0/5) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| gen_long_en | 24 items | 120 | 100.0% (310/310) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (120/120) | 100.0% (107/107) | 100.0% (24/24) |
| gen_long_mixed | G008_mixed_120p_prose_early, G018_mixed_300p_heading_deep, G028_mixed_300p_divisions_early | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (15/15) | 100.0% (12/12) | 100.0% (3/3) |
| gen_long_ar | G009_ar_120p_heading_middle, G019_ar_300p_divisions_last, G029_ar_300p_prose_middle | 15 | 100.0% (30/30) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (15/15) | 100.0% (10/10) | 100.0% (3/3) |
| gen_mid_en | 24 items | 120 | 100.0% (310/310) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (120/120) | 100.0% (1/1) | 100.0% (24/24) |
| gen_mid_mixed | G038_mixed_60p_prose_deep, G048_mixed_60p_heading_early, G058_mixed_60p_divisions_deep | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_mid_ar | G039_ar_20p_heading_last, G049_ar_20p_divisions_middle, G059_ar_20p_prose_last | 15 | 100.0% (30/30) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_short_en | 18 items | 90 | 100.0% (235/235) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (90/90) | - | 100.0% (18/18) |
| gen_short_ar | G069_ar_2p_heading_middle, G079_ar_2p_divisions_last | 10 | 100.0% (20/20) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (10/10) | - | 100.0% (2/2) |
| gen_scan | 8 items | 40 | 100.0% (105/105) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (40/40) | - | 100.0% (8/8) |
| gen_scan_over_30p | G083_scan_40p_heading_last, G087_scan_40p_heading_last | 10 | 0.0% (0/20) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (10/10) | 100.0% (10/10) | 100.0% (2/2) |
| licence_text | 7 items | 35 | 91.7% (55/60) | model stage not run | model stage not run | model stage not run | - | 92.9% (260/280) | 5 | 100.0% (35/35) | - | 100.0% (7/7) |
| licence_scan | L08_scan_jpeg | 5 | 0.0% (0/5) | model stage not run | model stage not run | model stage not run | - | 12.5% (5/40) | 0 | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_short | P01_2p_text | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_20 | P02_20p_text | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_120 | P03_120p_text | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_300 | P04_300p_text_p40 | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | 100.0% (4/4) | 100.0% (1/1) |
| profile_text_300_deep | P05_300p_text_p155, P06_300p_text_p160_divisions, P07_300p_text_p270 | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (15/15) | 100.0% (12/12) | 100.0% (3/3) |
| profile_text_arabic | P08_20p_text_arabic | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_mixed | P09_20p_text_mixed | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_scan | S01_2p_scan | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_scan_deep | S02_20p_scan_p15 | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo | S03_photo_jpeg | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo_arabic | S04_photo_arabic | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | - | 100.0% (5/5) | - | 100.0% (1/1) |

## Per item (first repeat)

| item | status | reached | proposed | missed | wrong | sent to the model | pages read (first repeat) | fields wrong | reason |
|---|---|---|---|---|---|---|---|---|---|
| E01_corrupt_pdf | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| E02_password_pdf | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: No password given |
| E03_30mb_text | read | 2/2 | - | thermal_insulation waterproofing | - | 9149 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| E04_30mb_scan | needs_ocr | 0/1 | - | signage | - | - | all | - | The scanned PDF is larger than 12 MB. Upload a smaller file. |
| E05_corrupt_licence | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| G000_en_120p_heading_early | read | 2/2 | - | hvac fire_fighting | - | 58484 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G001_en_120p_divisions_middle | read | 3/3 | - | gypsum cleaning signage | - | 57210 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G002_en_120p_prose_deep | read | 3/3 | - | cleaning labour_supply painting | - | 57366 characters | 95/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G003_en_120p_heading_last | read | 2/2 | - | road_works interior_fitout | - | 56948 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G004_en_120p_divisions_early | read | 3/3 | - | plumbing thermal_insulation fire_fighting | - | 57357 characters | 78/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G005_en_120p_prose_middle | read | 3/3 | - | joinery painting security_systems | - | 57278 characters | 84/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G006_en_120p_heading_deep | read | 1/1 | - | pest_control | - | 57609 characters | 103/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G007_en_120p_divisions_last | read | 3/3 | - | masonry_blockwork facilities_management pest_control | - | 56958 characters | 103/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G008_mixed_120p_prose_early | read | 3/3 | - | electrical aluminium plumbing | - | 57473 characters | 100/120 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G009_ar_120p_heading_middle | read | 2/2 | - | fire_fighting electrical | - | 58168 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G010_en_300p_divisions_deep | read | 3/3 | - | security_systems waterproofing hvac | - | 145089 characters | 117/300 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G011_en_300p_prose_last | read | 3/3 | - | curtains_blinds security_systems landscaping | - | 144994 characters | 200/300 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G012_en_300p_heading_early | read | 2/2 | - | fire_fighting hvac | - | 146241 characters | 202/300 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G013_en_300p_divisions_middle | read | 3/3 | - | aluminium glazing steel | - | 145092 characters | 108/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G014_en_300p_prose_deep | read | 3/3 | - | scaffolding masonry_blockwork labour_supply | - | 145086 characters | 110/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G015_en_300p_heading_last | read | 2/2 | - | water_treatment flooring | - | 145107 characters | 122/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G016_en_300p_divisions_early | read | 3/3 | - | painting scaffolding water_treatment | - | 145119 characters | 123/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G017_en_300p_prose_middle | read | 3/3 | - | glazing plumbing aluminium | - | 145119 characters | 103/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G018_mixed_300p_heading_deep | read | 2/2 | - | signage steel | - | 146312 characters | 103/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G019_ar_300p_divisions_last | read | 2/2 | - | fire_fighting electrical | - | 144880 characters | 82/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G020_en_300p_prose_early | read | 3/3 | - | waterproofing gypsum masonry_blockwork | - | 145107 characters | 83/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G021_en_300p_heading_middle | read | 2/2 | - | steel signage | - | 146406 characters | 115/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G022_en_300p_divisions_deep | read | 3/3 | - | marble_stone electrical road_works | - | 145122 characters | 80/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G023_en_300p_prose_last | read | 3/3 | - | facilities_management landscaping gypsum | - | 145059 characters | 81/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G024_en_300p_heading_early | read | 2/2 | - | flooring water_treatment | - | 146265 characters | 82/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G025_en_300p_divisions_middle | read | 3/3 | - | landscaping joinery flooring | - | 145141 characters | 69/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G026_en_300p_prose_deep | read | 2/2 | - | thermal_insulation marble_stone | - | 145049 characters | 114/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G027_en_300p_heading_last | read | 2/2 | - | hvac fire_fighting | - | 145151 characters | 131/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G028_mixed_300p_divisions_early | read | 3/3 | - | gypsum cleaning signage | - | 145186 characters | 73/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G029_ar_300p_prose_middle | read | 2/2 | - | fire_fighting electrical | - | 145009 characters | 54/300 in run 1, all after 4 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G030_en_60p_heading_deep | read | 2/2 | - | road_works interior_fitout | - | 29215 characters | 59/60 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G031_en_20p_divisions_last | read | 3/3 | - | plumbing thermal_insulation fire_fighting | - | 8819 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G032_en_60p_prose_early | read | 3/3 | - | joinery painting security_systems | - | 28339 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G033_en_20p_heading_middle | read | 1/1 | - | pest_control | - | 9730 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G034_en_60p_divisions_deep | read | 3/3 | - | masonry_blockwork facilities_management pest_control | - | 28278 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G035_en_20p_prose_last | read | 3/3 | - | electrical aluminium plumbing | - | 8844 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G036_en_60p_heading_early | read | 2/2 | - | interior_fitout road_works | - | 29405 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G037_en_20p_divisions_middle | read | 3/3 | - | security_systems waterproofing hvac | - | 8935 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G038_mixed_60p_prose_deep | read | 3/3 | - | curtains_blinds security_systems landscaping | - | 28325 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G039_ar_20p_heading_last | read | 2/2 | - | fire_fighting electrical | - | 8770 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G040_en_60p_divisions_early | read | 3/3 | - | aluminium glazing steel | - | 28321 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G041_en_20p_prose_middle | read | 3/3 | - | scaffolding masonry_blockwork labour_supply | - | 8898 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G042_en_60p_heading_deep | read | 2/2 | - | water_treatment flooring | - | 29249 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G043_en_20p_divisions_last | read | 3/3 | - | painting scaffolding water_treatment | - | 8790 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G044_en_60p_prose_early | read | 3/3 | - | glazing plumbing aluminium | - | 28348 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G045_en_20p_heading_middle | read | 2/2 | - | signage steel | - | 9821 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G046_en_60p_divisions_deep | read | 3/3 | - | labour_supply curtains_blinds interior_fitout | - | 28295 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G047_en_20p_prose_last | read | 3/3 | - | waterproofing gypsum masonry_blockwork | - | 8812 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G048_mixed_60p_heading_early | read | 2/2 | - | steel signage | - | 29471 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G049_ar_20p_divisions_middle | read | 2/2 | - | fire_fighting electrical | - | 8779 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G050_en_60p_prose_deep | read | 3/3 | - | facilities_management landscaping gypsum | - | 28288 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G051_en_20p_heading_last | read | 2/2 | - | flooring water_treatment | - | 8877 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G052_en_60p_divisions_early | read | 3/3 | - | landscaping joinery flooring | - | 28336 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G053_en_20p_prose_middle | read | 2/2 | - | thermal_insulation marble_stone | - | 8861 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G054_en_60p_heading_deep | read | 2/2 | - | hvac fire_fighting | - | 29293 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G055_en_20p_divisions_last | read | 3/3 | - | gypsum cleaning signage | - | 8802 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G056_en_60p_prose_early | read | 3/3 | - | cleaning labour_supply painting | - | 28352 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G057_en_20p_heading_middle | read | 2/2 | - | road_works interior_fitout | - | 9755 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G058_mixed_60p_divisions_deep | read | 3/3 | - | plumbing thermal_insulation fire_fighting | - | 28353 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G059_ar_20p_prose_last | read | 2/2 | - | fire_fighting electrical | - | 8701 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G060_en_5p_heading_early | read | 1/1 | - | pest_control | - | 1342 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G061_en_2p_divisions_middle | read | 3/3 | - | masonry_blockwork facilities_management pest_control | - | 458 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G062_en_5p_prose_deep | read | 3/3 | - | electrical aluminium plumbing | - | 1474 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G063_en_2p_heading_last | read | 2/2 | - | interior_fitout road_works | - | 327 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G064_en_5p_divisions_early | read | 3/3 | - | security_systems waterproofing hvac | - | 1538 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G065_en_2p_prose_middle | read | 3/3 | - | curtains_blinds security_systems landscaping | - | 471 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G066_en_5p_heading_deep | read | 2/2 | - | fire_fighting hvac | - | 1357 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G067_en_2p_divisions_last | read | 3/3 | - | aluminium glazing steel | - | 457 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G068_en_5p_prose_early | read | 3/3 | - | scaffolding masonry_blockwork labour_supply | - | 1501 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G069_ar_2p_heading_middle | read | 2/2 | - | fire_fighting electrical | - | 288 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G070_en_5p_divisions_deep | read | 3/3 | - | painting scaffolding water_treatment | - | 1420 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G071_en_2p_prose_last | read | 3/3 | - | glazing plumbing aluminium | - | 484 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G072_en_5p_heading_early | read | 2/2 | - | signage steel | - | 1419 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G073_en_2p_divisions_middle | read | 3/3 | - | labour_supply curtains_blinds interior_fitout | - | 475 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G074_en_5p_prose_deep | read | 3/3 | - | waterproofing gypsum masonry_blockwork | - | 1442 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G075_en_2p_heading_last | read | 2/2 | - | steel signage | - | 360 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G076_en_5p_divisions_early | read | 3/3 | - | marble_stone electrical road_works | - | 1503 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G077_en_2p_prose_middle | read | 3/3 | - | facilities_management landscaping gypsum | - | 468 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G078_en_5p_heading_deep | read | 2/2 | - | flooring water_treatment | - | 1335 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G079_ar_2p_divisions_last | read | 2/2 | - | fire_fighting electrical | - | 323 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G080_scan_3p_heading_early | needs_ocr | 2/2 | - | thermal_insulation marble_stone | - | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G081_scan_12p_heading_middle | needs_ocr | 2/2 | - | hvac fire_fighting | - | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G082_scan_25p_heading_deep | needs_ocr | 3/3 | - | gypsum cleaning signage | - | pdf 25 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G083_scan_40p_heading_last | needs_ocr | 0/3 | - | cleaning labour_supply painting | - | pdf 30 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G084_scan_3p_heading_early | needs_ocr | 2/2 | - | road_works interior_fitout | - | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G085_scan_12p_heading_middle | needs_ocr | 3/3 | - | plumbing thermal_insulation fire_fighting | - | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G086_scan_25p_heading_deep | needs_ocr | 3/3 | - | joinery painting security_systems | - | pdf 25 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G087_scan_40p_heading_last | needs_ocr | 0/1 | - | pest_control | - | pdf 30 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G088_scan_3p_heading_early | needs_ocr | 3/3 | - | masonry_blockwork facilities_management pest_control | - | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G089_scan_12p_heading_middle | needs_ocr | 3/3 | - | electrical aluminium plumbing | - | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| L01_text_single | read | 0/1 | - | hvac | - | - | all | activities (WRONG) |  |
| L02_text_general_trading | read | 0/0 | - | - | - | - | all | - |  |
| L03_text_multi_per_line | read | 4/4 | - | plumbing electrical flooring painting | - | - | all | - |  |
| L04_text_multi_comma | read | 3/3 | - | aluminium steel glazing | - | - | all | - |  |
| L05_text_expired | read | 1/1 | - | general_contracting | - | - | all | - |  |
| L06_text_embedded_font | read | 2/2 | - | plumbing pest_control | - | - | all | - |  |
| L07_text_arabic | read | 1/1 | - | joinery | - | - | all | licence_no, issue_date, expiry_date |  |
| L08_scan_jpeg | needs_ocr | 0/1 | - | electrical | - | - | all | licence_no, legal_name_en, authority, emirate, issue_date, expiry_date, activities | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
| P01_2p_text | read | 2/2 | - | interior_fitout joinery | - | 411 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P02_20p_text | read | 3/3 | - | hvac plumbing fire_fighting | - | 10222 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P03_120p_text | read | 3/3 | - | painting waterproofing flooring | - | 58378 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P04_300p_text_p40 | read | 3/3 | - | steel aluminium glazing | - | 145240 characters | 295/300 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P05_300p_text_p155 | read | 3/3 | - | landscaping swimming_pools fencing_shades | - | 146051 characters | 145/300 in run 1, all after 2 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P06_300p_text_p160_divisions | read | 3/3 | - | electrical security_systems home_automation | - | 144821 characters | 109/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P07_300p_text_p270 | read | 2/2 | - | pest_control cleaning | - | 146449 characters | 110/300 in run 1, all after 3 runs | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P08_20p_text_arabic | read | 2/2 | - | plumbing hvac | - | 4580 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P09_20p_text_mixed | read | 2/2 | - | aluminium glazing | - | 8880 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| S01_2p_scan | needs_ocr | 2/2 | - | steel scaffolding | - | pdf 2 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| S02_20p_scan_p15 | needs_ocr | 2/2 | - | landscaping swimming_pools | - | pdf 20 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| S03_photo_jpeg | needs_ocr | 2/2 | - | pest_control cleaning | - | images 1 pages | all | - | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
| S04_photo_arabic | needs_ocr | 2/2 | - | painting gypsum | - | images 1 pages | all | - | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
