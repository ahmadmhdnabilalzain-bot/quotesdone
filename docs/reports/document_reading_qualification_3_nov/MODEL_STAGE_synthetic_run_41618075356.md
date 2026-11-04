# Document-reading qualification: with the model

2026-11-03T11:47:29.642Z · 116 gold items × 5 repeats · corpus scripts/e2e/document_reading_qualification_corpus.ts

| class | items | runs | gold lines reaching the model | trade recall | trade precision | forbidden proposed | model unavailable (runs) | licence fields exact | licence fields WRONG | honest outcome | partial read disclosed | same verdict every repeat |
|---|---|---:|---|---|---|---|---|---|---|---|---|---|
| edge_corrupt | E01_corrupt_pdf, E05_corrupt_licence | 10 | n/a | n/a | n/a | 0 of 0 proposed | 0 | 100.0% (40/40) | 0 | 100.0% (10/10) | - | 100.0% (2/2) |
| edge_password | E02_password_pdf | 5 | n/a | n/a | n/a | 0 of 0 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_30mb_text | E03_30mb_text | 5 | 100.0% (10/10) | 80.0% (8/10) | 100.0% (8/8) | 0 of 8 proposed | 0 | - | - | 100.0% (5/5) | - | 0.0% (0/1) |
| edge_30mb_scan | E04_30mb_scan | 5 | 0.0% (0/5) | 0.0% (0/5) | n/a | 0 of 0 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| gen_long_en | 24 items | 120 | 100.0% (310/310) | 80.6% (250/310) | 100.0% (250/250) | 0 of 250 proposed | 0 | - | - | 100.0% (120/120) | - | 41.7% (10/24) |
| gen_long_mixed | G008_mixed_120p_prose_early, G018_mixed_300p_heading_deep, G028_mixed_300p_divisions_early | 15 | 100.0% (40/40) | 70.0% (28/40) | 100.0% (28/28) | 0 of 28 proposed | 0 | - | - | 100.0% (15/15) | - | 33.3% (1/3) |
| gen_long_ar | G009_ar_120p_heading_middle, G019_ar_300p_divisions_last, G029_ar_300p_prose_middle | 15 | 100.0% (30/30) | 46.7% (14/30) | 100.0% (14/14) | 0 of 14 proposed | 0 | - | - | 100.0% (15/15) | - | 66.7% (2/3) |
| gen_mid_en | 24 items | 120 | 100.0% (310/310) | 87.1% (270/310) | 100.0% (270/270) | 0 of 270 proposed | 0 | - | - | 100.0% (120/120) | - | 50.0% (12/24) |
| gen_mid_mixed | G038_mixed_60p_prose_deep, G048_mixed_60p_heading_early, G058_mixed_60p_divisions_deep | 15 | 100.0% (40/40) | 72.5% (29/40) | 100.0% (29/29) | 0 of 29 proposed | 0 | - | - | 100.0% (15/15) | - | 33.3% (1/3) |
| gen_mid_ar | G039_ar_20p_heading_last, G049_ar_20p_divisions_middle, G059_ar_20p_prose_last | 15 | 100.0% (30/30) | 86.7% (26/30) | 100.0% (26/26) | 0 of 26 proposed | 0 | - | - | 100.0% (15/15) | - | 33.3% (1/3) |
| gen_short_en | 18 items | 90 | 100.0% (235/235) | 80.4% (189/235) | 100.0% (189/189) | 0 of 189 proposed | 0 | - | - | 100.0% (90/90) | - | 33.3% (6/18) |
| gen_short_ar | G069_ar_2p_heading_middle, G079_ar_2p_divisions_last | 10 | 100.0% (20/20) | 90.0% (18/20) | 100.0% (18/18) | 0 of 18 proposed | 0 | - | - | 100.0% (10/10) | - | 50.0% (1/2) |
| gen_scan | 8 items | 40 | 100.0% (105/105) | 100.0% (105/105) | 100.0% (105/105) | 0 of 105 proposed | 0 | - | - | 100.0% (40/40) | - | 100.0% (8/8) |
| gen_scan_over_30p | G083_scan_40p_heading_last, G087_scan_40p_heading_last | 10 | 0.0% (0/20) | 0.0% (0/20) | n/a | 0 of 0 proposed | 0 | - | - | 100.0% (10/10) | 100.0% (10/10) | 0.0% (0/2) |
| licence_text | 7 items | 35 | 91.7% (55/60) | 75.0% (45/60) | 100.0% (45/45) | 0 of 45 proposed | 0 | 96.4% (270/280) | 10 | 100.0% (35/35) | - | 100.0% (7/7) |
| licence_scan | L08_scan_jpeg | 5 | 100.0% (5/5) | 100.0% (5/5) | 100.0% (5/5) | 0 of 5 proposed | 0 | 100.0% (40/40) | 0 | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_short | P01_2p_text | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_20 | P02_20p_text | 5 | 100.0% (15/15) | 100.0% (15/15) | 100.0% (15/15) | 0 of 15 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_120 | P03_120p_text | 5 | 100.0% (15/15) | 0.0% (0/15) | n/a | 0 of 0 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_300 | P04_300p_text_p40 | 5 | 100.0% (15/15) | 100.0% (15/15) | 100.0% (15/15) | 0 of 15 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_300_deep | P05_300p_text_p155, P06_300p_text_p160_divisions, P07_300p_text_p270 | 15 | 100.0% (40/40) | 100.0% (40/40) | 100.0% (40/40) | 0 of 40 proposed | 0 | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| profile_text_arabic | P08_20p_text_arabic | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_mixed | P09_20p_text_mixed | 5 | 100.0% (10/10) | 80.0% (8/10) | 100.0% (8/8) | 0 of 8 proposed | 0 | - | - | 100.0% (5/5) | - | 0.0% (0/1) |
| profile_scan | S01_2p_scan | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_scan_deep | S02_20p_scan_p15 | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo | S03_photo_jpeg | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo_arabic | S04_photo_arabic | 5 | 100.0% (10/10) | 100.0% (10/10) | 100.0% (10/10) | 0 of 10 proposed | 0 | - | - | 100.0% (5/5) | - | 100.0% (1/1) |

## Per item (first repeat)

| item | status | reached | proposed | missed | wrong | sent to the model | pages read (first repeat) | fields wrong | reason |
|---|---|---|---|---|---|---|---|---|---|
| E01_corrupt_pdf | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| E02_password_pdf | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: No password given |
| E03_30mb_text | read | 2/2 | thermal_insulation waterproofing | - | - | 9149 characters | all | - |  |
| E04_30mb_scan | needs_ocr | 0/1 | - | signage | - | - | all | - | The scanned PDF is larger than 12 MB. Upload a smaller file. |
| E05_corrupt_licence | unreadable | 0/0 | - | - | - | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| G000_en_120p_heading_early | read | 2/2 | fire_fighting hvac | - | - | 58484 characters | all | - |  |
| G001_en_120p_divisions_middle | read | 3/3 | cleaning gypsum signage | - | - | 57210 characters | all | - |  |
| G002_en_120p_prose_deep | read | 3/3 | - | cleaning labour_supply painting | - | 57332 characters | all | - |  |
| G003_en_120p_heading_last | read | 2/2 | interior_fitout road_works | - | - | 56948 characters | all | - |  |
| G004_en_120p_divisions_early | read | 3/3 | fire_fighting plumbing thermal_insulation | - | - | 57323 characters | all | - |  |
| G005_en_120p_prose_middle | read | 3/3 | joinery painting security_systems | - | - | 57244 characters | all | - |  |
| G006_en_120p_heading_deep | read | 1/1 | - | pest_control | - | 58427 characters | all | - |  |
| G007_en_120p_divisions_last | read | 3/3 | facilities_management masonry_blockwork pest_control | - | - | 56924 characters | all | - |  |
| G008_mixed_120p_prose_early | read | 3/3 | aluminium electrical plumbing | - | - | 57428 characters | all | - |  |
| G009_ar_120p_heading_middle | read | 2/2 | - | fire_fighting electrical | - | 58168 characters | all | - |  |
| G010_en_300p_divisions_deep | read | 3/3 | hvac security_systems waterproofing | - | - | 145055 characters | all | - |  |
| G011_en_300p_prose_last | read | 3/3 | curtains_blinds landscaping security_systems | - | - | 144960 characters | all | - |  |
| G012_en_300p_heading_early | read | 2/2 | fire_fighting hvac | - | - | 146207 characters | all | - |  |
| G013_en_300p_divisions_middle | read | 3/3 | aluminium glazing steel | - | - | 145024 characters | all | - |  |
| G014_en_300p_prose_deep | read | 3/3 | labour_supply masonry_blockwork scaffolding | - | - | 145018 characters | all | - |  |
| G015_en_300p_heading_last | read | 2/2 | flooring water_treatment | - | - | 145005 characters | all | - |  |
| G016_en_300p_divisions_early | read | 3/3 | painting scaffolding water_treatment | - | - | 145017 characters | all | - |  |
| G017_en_300p_prose_middle | read | 3/3 | aluminium glazing plumbing | - | - | 145051 characters | all | - |  |
| G018_mixed_300p_heading_deep | read | 2/2 | signage steel | - | - | 146244 characters | all | - |  |
| G019_ar_300p_divisions_last | read | 2/2 | electrical fire_fighting | - | - | 144812 characters | all | - |  |
| G020_en_300p_prose_early | read | 3/3 | gypsum masonry_blockwork waterproofing | - | - | 145039 characters | all | - |  |
| G021_en_300p_heading_middle | read | 2/2 | signage steel | - | - | 146304 characters | all | - |  |
| G022_en_300p_divisions_deep | read | 3/3 | electrical marble_stone road_works | - | - | 145020 characters | all | - |  |
| G023_en_300p_prose_last | read | 3/3 | facilities_management gypsum landscaping | - | - | 144957 characters | all | - |  |
| G024_en_300p_heading_early | read | 2/2 | - | flooring water_treatment | - | 146163 characters | all | - |  |
| G025_en_300p_divisions_middle | read | 3/3 | flooring joinery landscaping | - | - | 145039 characters | all | - |  |
| G026_en_300p_prose_deep | read | 2/2 | marble_stone thermal_insulation | - | - | 144981 characters | all | - |  |
| G027_en_300p_heading_last | read | 2/2 | fire_fighting hvac | - | - | 145049 characters | all | - |  |
| G028_mixed_300p_divisions_early | read | 3/3 | - | gypsum cleaning signage | - | 145084 characters | all | - |  |
| G029_ar_300p_prose_middle | read | 2/2 | electrical fire_fighting | - | - | 144907 characters | all | - |  |
| G030_en_60p_heading_deep | read | 2/2 | interior_fitout road_works | - | - | 29215 characters | all | - |  |
| G031_en_20p_divisions_last | read | 3/3 | fire_fighting plumbing thermal_insulation | - | - | 8819 characters | all | - |  |
| G032_en_60p_prose_early | read | 3/3 | joinery painting security_systems | - | - | 28339 characters | all | - |  |
| G033_en_20p_heading_middle | read | 1/1 | - | pest_control | - | 9730 characters | all | - |  |
| G034_en_60p_divisions_deep | read | 3/3 | facilities_management masonry_blockwork pest_control | - | - | 28278 characters | all | - |  |
| G035_en_20p_prose_last | read | 3/3 | aluminium plumbing | electrical | - | 8844 characters | all | - |  |
| G036_en_60p_heading_early | read | 2/2 | interior_fitout road_works | - | - | 29405 characters | all | - |  |
| G037_en_20p_divisions_middle | read | 3/3 | hvac security_systems waterproofing | - | - | 8935 characters | all | - |  |
| G038_mixed_60p_prose_deep | read | 3/3 | curtains_blinds landscaping security_systems | - | - | 28325 characters | all | - |  |
| G039_ar_20p_heading_last | read | 2/2 | electrical fire_fighting | - | - | 8770 characters | all | - |  |
| G040_en_60p_divisions_early | read | 3/3 | aluminium glazing steel | - | - | 28321 characters | all | - |  |
| G041_en_20p_prose_middle | read | 3/3 | labour_supply masonry_blockwork scaffolding | - | - | 8898 characters | all | - |  |
| G042_en_60p_heading_deep | read | 2/2 | flooring water_treatment | - | - | 29249 characters | all | - |  |
| G043_en_20p_divisions_last | read | 3/3 | painting scaffolding water_treatment | - | - | 8790 characters | all | - |  |
| G044_en_60p_prose_early | read | 3/3 | aluminium glazing plumbing | - | - | 28348 characters | all | - |  |
| G045_en_20p_heading_middle | read | 2/2 | signage steel | - | - | 9821 characters | all | - |  |
| G046_en_60p_divisions_deep | read | 3/3 | curtains_blinds interior_fitout labour_supply | - | - | 28295 characters | all | - |  |
| G047_en_20p_prose_last | read | 3/3 | gypsum masonry_blockwork waterproofing | - | - | 8812 characters | all | - |  |
| G048_mixed_60p_heading_early | read | 2/2 | - | steel signage | - | 29471 characters | all | - |  |
| G049_ar_20p_divisions_middle | read | 2/2 | electrical fire_fighting | - | - | 8779 characters | all | - |  |
| G050_en_60p_prose_deep | read | 3/3 | facilities_management gypsum landscaping | - | - | 28288 characters | all | - |  |
| G051_en_20p_heading_last | read | 2/2 | - | flooring water_treatment | - | 8877 characters | all | - |  |
| G052_en_60p_divisions_early | read | 3/3 | flooring joinery landscaping | - | - | 28336 characters | all | - |  |
| G053_en_20p_prose_middle | read | 2/2 | marble_stone thermal_insulation | - | - | 8861 characters | all | - |  |
| G054_en_60p_heading_deep | read | 2/2 | fire_fighting hvac | - | - | 29293 characters | all | - |  |
| G055_en_20p_divisions_last | read | 3/3 | - | gypsum cleaning signage | - | 8802 characters | all | - |  |
| G056_en_60p_prose_early | read | 3/3 | cleaning labour_supply painting | - | - | 28352 characters | all | - |  |
| G057_en_20p_heading_middle | read | 2/2 | - | road_works interior_fitout | - | 9755 characters | all | - |  |
| G058_mixed_60p_divisions_deep | read | 3/3 | fire_fighting plumbing thermal_insulation | - | - | 28348 characters | all | - |  |
| G059_ar_20p_prose_last | read | 2/2 | electrical fire_fighting | - | - | 8701 characters | all | - |  |
| G060_en_5p_heading_early | read | 1/1 | - | pest_control | - | 1342 characters | all | - |  |
| G061_en_2p_divisions_middle | read | 3/3 | - | masonry_blockwork facilities_management pest_control | - | 458 characters | all | - |  |
| G062_en_5p_prose_deep | read | 3/3 | aluminium plumbing | electrical | - | 1474 characters | all | - |  |
| G063_en_2p_heading_last | read | 2/2 | interior_fitout road_works | - | - | 327 characters | all | - |  |
| G064_en_5p_divisions_early | read | 3/3 | hvac security_systems waterproofing | - | - | 1538 characters | all | - |  |
| G065_en_2p_prose_middle | read | 3/3 | curtains_blinds landscaping security_systems | - | - | 471 characters | all | - |  |
| G066_en_5p_heading_deep | read | 2/2 | fire_fighting hvac | - | - | 1357 characters | all | - |  |
| G067_en_2p_divisions_last | read | 3/3 | aluminium glazing steel | - | - | 457 characters | all | - |  |
| G068_en_5p_prose_early | read | 3/3 | labour_supply masonry_blockwork scaffolding | - | - | 1501 characters | all | - |  |
| G069_ar_2p_heading_middle | read | 2/2 | electrical fire_fighting | - | - | 288 characters | all | - |  |
| G070_en_5p_divisions_deep | read | 3/3 | painting scaffolding water_treatment | - | - | 1420 characters | all | - |  |
| G071_en_2p_prose_last | read | 3/3 | aluminium glazing plumbing | - | - | 484 characters | all | - |  |
| G072_en_5p_heading_early | read | 2/2 | signage steel | - | - | 1419 characters | all | - |  |
| G073_en_2p_divisions_middle | read | 3/3 | curtains_blinds interior_fitout labour_supply | - | - | 475 characters | all | - |  |
| G074_en_5p_prose_deep | read | 3/3 | gypsum masonry_blockwork | waterproofing | - | 1442 characters | all | - |  |
| G075_en_2p_heading_last | read | 2/2 | signage steel | - | - | 360 characters | all | - |  |
| G076_en_5p_divisions_early | read | 3/3 | electrical marble_stone road_works | - | - | 1503 characters | all | - |  |
| G077_en_2p_prose_middle | read | 3/3 | facilities_management gypsum landscaping | - | - | 468 characters | all | - |  |
| G078_en_5p_heading_deep | read | 2/2 | flooring water_treatment | - | - | 1335 characters | all | - |  |
| G079_ar_2p_divisions_last | read | 2/2 | electrical fire_fighting | - | - | 323 characters | all | - |  |
| G080_scan_3p_heading_early | read | 2/2 | marble_stone thermal_insulation | - | - | pdf 3 pages | all | - |  |
| G081_scan_12p_heading_middle | read | 2/2 | fire_fighting hvac | - | - | pdf 12 pages | all | - |  |
| G082_scan_25p_heading_deep | read | 3/3 | cleaning gypsum signage | - | - | pdf 25 pages | all | - |  |
| G083_scan_40p_heading_last | needs_ocr | 0/3 | - | cleaning labour_supply painting | - | pdf 30 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G084_scan_3p_heading_early | read | 2/2 | interior_fitout road_works | - | - | pdf 3 pages | all | - |  |
| G085_scan_12p_heading_middle | read | 3/3 | fire_fighting plumbing thermal_insulation | - | - | pdf 12 pages | all | - |  |
| G086_scan_25p_heading_deep | read | 3/3 | joinery painting security_systems | - | - | pdf 25 pages | all | - |  |
| G087_scan_40p_heading_last | read | 0/1 | - | pest_control | - | pdf 30 pages | 30/40 in run 1, all after 1 runs | - | the readings did not agree on any trade: held for the sales engineer (read 30 of 40 pages; the rest of the doc |
| G088_scan_3p_heading_early | read | 3/3 | facilities_management masonry_blockwork pest_control | - | - | pdf 3 pages | all | - |  |
| G089_scan_12p_heading_middle | read | 3/3 | aluminium electrical plumbing | - | - | pdf 12 pages | all | - |  |
| L01_text_single | read | 0/1 | - | hvac | - | - | all | activities (WRONG) |  |
| L02_text_general_trading | read | 0/0 | - | - | - | - | all | - |  |
| L03_text_multi_per_line | read | 4/4 | electrical flooring painting plumbing | - | - | - | all | - |  |
| L04_text_multi_comma | read | 3/3 | glazing steel | aluminium | - | - | all | - |  |
| L05_text_expired | read | 1/1 | - | general_contracting | - | - | all | - |  |
| L06_text_embedded_font | read | 2/2 | pest_control plumbing | - | - | - | all | - |  |
| L07_text_arabic | read | 1/1 | joinery | - | - | - | all | licence_no (WRONG) |  |
| L08_scan_jpeg | read | 1/1 | electrical | - | - | 43 characters | all | - |  |
| P01_2p_text | read | 2/2 | interior_fitout joinery | - | - | 411 characters | all | - |  |
| P02_20p_text | read | 3/3 | fire_fighting hvac plumbing | - | - | 10222 characters | all | - |  |
| P03_120p_text | read | 3/3 | - | painting waterproofing flooring | - | 58378 characters | all | - |  |
| P04_300p_text_p40 | read | 3/3 | aluminium glazing steel | - | - | 145538 characters | all | - |  |
| P05_300p_text_p155 | read | 3/3 | fencing_shades landscaping swimming_pools | - | - | 146017 characters | all | - |  |
| P06_300p_text_p160_divisions | read | 3/3 | electrical home_automation security_systems | - | - | 144753 characters | all | - |  |
| P07_300p_text_p270 | read | 2/2 | cleaning pest_control | - | - | 146381 characters | all | - |  |
| P08_20p_text_arabic | read | 2/2 | hvac plumbing | - | - | 4580 characters | all | - |  |
| P09_20p_text_mixed | read | 2/2 | aluminium glazing | - | - | 8880 characters | all | - |  |
| S01_2p_scan | read | 2/2 | scaffolding steel | - | - | pdf 2 pages | all | - |  |
| S02_20p_scan_p15 | read | 2/2 | landscaping swimming_pools | - | - | pdf 20 pages | all | - |  |
| S03_photo_jpeg | read | 2/2 | cleaning pest_control | - | - | images 1 pages | all | - |  |
| S04_photo_arabic | read | 2/2 | gypsum painting | - | - | images 1 pages | all | - |  |
