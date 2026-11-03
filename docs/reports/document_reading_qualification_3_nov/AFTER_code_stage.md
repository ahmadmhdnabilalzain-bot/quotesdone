# Document-reading qualification: code stage (no model spend)

2026-11-03T09:36:09.740Z · 116 gold items × 5 repeats · corpus scripts/e2e/document_reading_qualification_corpus.ts

| class | items | runs | gold lines reaching the model | trade recall | trade precision | forbidden proposed | licence fields exact | licence fields WRONG | honest outcome | partial read disclosed | same verdict every repeat |
|---|---|---:|---|---|---|---|---|---|---|---|---|
| profile_text_short | P01_2p_text | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_20 | P02_20p_text | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_120 | P03_120p_text | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_300 | P04_300p_text_p40 | 5 | 100.0% (15/15) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_300_deep | P05_300p_text_p155, P06_300p_text_p160_divisions, P07_300p_text_p270 | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| profile_text_arabic | P08_20p_text_arabic | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_text_mixed | P09_20p_text_mixed | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_scan | S01_2p_scan | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_scan_deep | S02_20p_scan_p15 | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo | S03_photo_jpeg | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| profile_photo_arabic | S04_photo_arabic | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| licence_text | L01_text_single, L02_text_general_trading, L03_text_multi_per_line, L04_text_multi_comma, L05_text_expired, L06_text_embedded_font, L07_text_arabic | 35 | 91.7% (55/60) | model stage not run | model stage not run | model stage not run | 92.9% (260/280) | 5 | 100.0% (35/35) | - | 100.0% (7/7) |
| licence_scan | L08_scan_jpeg | 5 | 0.0% (0/5) | model stage not run | model stage not run | model stage not run | 12.5% (5/40) | 0 | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_corrupt | E01_corrupt_pdf, E05_corrupt_licence | 10 | n/a | model stage not run | model stage not run | model stage not run | 100.0% (40/40) | 0 | 100.0% (10/10) | - | 100.0% (2/2) |
| edge_password | E02_password_pdf | 5 | n/a | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_30mb_text | E03_30mb_text | 5 | 100.0% (10/10) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| edge_30mb_scan | E04_30mb_scan | 5 | 0.0% (0/5) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (5/5) | - | 100.0% (1/1) |
| gen_long_en | G000_en_120p_heading_early, G001_en_120p_divisions_middle, G002_en_120p_prose_deep, G003_en_120p_heading_last, G004_en_120p_divisions_early, G005_en_120p_prose_middle, G006_en_120p_heading_deep, G007_en_120p_divisions_last, G010_en_300p_divisions_deep, G011_en_300p_prose_last, G012_en_300p_heading_early, G013_en_300p_divisions_middle, G014_en_300p_prose_deep, G015_en_300p_heading_last, G016_en_300p_divisions_early, G017_en_300p_prose_middle, G020_en_300p_prose_early, G021_en_300p_heading_middle, G022_en_300p_divisions_deep, G023_en_300p_prose_last, G024_en_300p_heading_early, G025_en_300p_divisions_middle, G026_en_300p_prose_deep, G027_en_300p_heading_last | 120 | 100.0% (310/310) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (120/120) | - | 100.0% (24/24) |
| gen_long_mixed | G008_mixed_120p_prose_early, G018_mixed_300p_heading_deep, G028_mixed_300p_divisions_early | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_long_ar | G009_ar_120p_heading_middle, G019_ar_300p_divisions_last, G029_ar_300p_prose_middle | 15 | 100.0% (30/30) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_mid_en | G030_en_60p_heading_deep, G031_en_20p_divisions_last, G032_en_60p_prose_early, G033_en_20p_heading_middle, G034_en_60p_divisions_deep, G035_en_20p_prose_last, G036_en_60p_heading_early, G037_en_20p_divisions_middle, G040_en_60p_divisions_early, G041_en_20p_prose_middle, G042_en_60p_heading_deep, G043_en_20p_divisions_last, G044_en_60p_prose_early, G045_en_20p_heading_middle, G046_en_60p_divisions_deep, G047_en_20p_prose_last, G050_en_60p_prose_deep, G051_en_20p_heading_last, G052_en_60p_divisions_early, G053_en_20p_prose_middle, G054_en_60p_heading_deep, G055_en_20p_divisions_last, G056_en_60p_prose_early, G057_en_20p_heading_middle | 120 | 100.0% (310/310) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (120/120) | - | 100.0% (24/24) |
| gen_mid_mixed | G038_mixed_60p_prose_deep, G048_mixed_60p_heading_early, G058_mixed_60p_divisions_deep | 15 | 100.0% (40/40) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_mid_ar | G039_ar_20p_heading_last, G049_ar_20p_divisions_middle, G059_ar_20p_prose_last | 15 | 100.0% (30/30) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (15/15) | - | 100.0% (3/3) |
| gen_short_en | G060_en_5p_heading_early, G061_en_2p_divisions_middle, G062_en_5p_prose_deep, G063_en_2p_heading_last, G064_en_5p_divisions_early, G065_en_2p_prose_middle, G066_en_5p_heading_deep, G067_en_2p_divisions_last, G068_en_5p_prose_early, G070_en_5p_divisions_deep, G071_en_2p_prose_last, G072_en_5p_heading_early, G073_en_2p_divisions_middle, G074_en_5p_prose_deep, G075_en_2p_heading_last, G076_en_5p_divisions_early, G077_en_2p_prose_middle, G078_en_5p_heading_deep | 90 | 100.0% (235/235) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (90/90) | - | 100.0% (18/18) |
| gen_short_ar | G069_ar_2p_heading_middle, G079_ar_2p_divisions_last | 10 | 100.0% (20/20) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (10/10) | - | 100.0% (2/2) |
| gen_scan | G080_scan_3p_heading_early, G081_scan_12p_heading_middle, G082_scan_25p_heading_deep, G084_scan_3p_heading_early, G085_scan_12p_heading_middle, G086_scan_25p_heading_deep, G088_scan_3p_heading_early, G089_scan_12p_heading_middle | 40 | 100.0% (105/105) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (40/40) | - | 100.0% (8/8) |
| gen_scan_over_30p | G083_scan_40p_heading_last, G087_scan_40p_heading_last | 10 | 0.0% (0/20) | model stage not run | model stage not run | model stage not run | - | - | 100.0% (10/10) | 100.0% (10/10) | 100.0% (2/2) |

## Per item (first repeat)

| item | status | reached | sent to the model | pages read (first repeat) | fields wrong | reason |
|---|---|---|---|---|---|---|
| P01_2p_text | read | 2/2 | 411 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P02_20p_text | read | 3/3 | 10222 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P03_120p_text | read | 3/3 | 58378 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P04_300p_text_p40 | read | 3/3 | 145538 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P05_300p_text_p155 | read | 3/3 | 146017 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P06_300p_text_p160_divisions | read | 3/3 | 144753 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P07_300p_text_p270 | read | 2/2 | 146381 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P08_20p_text_arabic | read | 2/2 | 4580 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| P09_20p_text_mixed | read | 2/2 | 8880 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| S01_2p_scan | needs_ocr | 2/2 | pdf 2 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| S02_20p_scan_p15 | needs_ocr | 2/2 | pdf 20 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| S03_photo_jpeg | needs_ocr | 2/2 | images 1 pages | all | - | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
| S04_photo_arabic | needs_ocr | 2/2 | images 1 pages | all | - | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
| L01_text_single | read | 0/1 | - | all | activities (WRONG) |  |
| L02_text_general_trading | read | 0/0 | - | all | - |  |
| L03_text_multi_per_line | read | 4/4 | - | all | - |  |
| L04_text_multi_comma | read | 3/3 | - | all | - |  |
| L05_text_expired | read | 1/1 | - | all | - |  |
| L06_text_embedded_font | read | 2/2 | - | all | - |  |
| L07_text_arabic | read | 1/1 | - | all | licence_no, issue_date, expiry_date |  |
| L08_scan_jpeg | needs_ocr | 0/1 | - | all | licence_no, legal_name_en, authority, emirate, issue_date, expiry_date, activities | A photo or scan has no text layer; its words are read by OCR in the customer’s browser, or by a vision model w |
| E01_corrupt_pdf | unreadable | 0/0 | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| E02_password_pdf | unreadable | 0/0 | - | all | - | pdf_unreadable: The PDF could not be read: No password given |
| E03_30mb_text | read | 2/2 | 9149 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| E04_30mb_scan | needs_ocr | 0/1 | - | all | - | The scanned PDF is larger than 12 MB. Upload a smaller file. |
| E05_corrupt_licence | unreadable | 0/0 | - | all | - | pdf_unreadable: The PDF could not be read: Invalid PDF structure. |
| G000_en_120p_heading_early | read | 2/2 | 58484 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G001_en_120p_divisions_middle | read | 3/3 | 57210 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G002_en_120p_prose_deep | read | 3/3 | 57332 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G003_en_120p_heading_last | read | 2/2 | 56948 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G004_en_120p_divisions_early | read | 3/3 | 57323 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G005_en_120p_prose_middle | read | 3/3 | 57244 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G006_en_120p_heading_deep | read | 1/1 | 58427 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G007_en_120p_divisions_last | read | 3/3 | 56924 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G008_mixed_120p_prose_early | read | 3/3 | 57439 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G009_ar_120p_heading_middle | read | 2/2 | 58168 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G010_en_300p_divisions_deep | read | 3/3 | 145055 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G011_en_300p_prose_last | read | 3/3 | 144960 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G012_en_300p_heading_early | read | 2/2 | 146207 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G013_en_300p_divisions_middle | read | 3/3 | 145024 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G014_en_300p_prose_deep | read | 3/3 | 145018 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G015_en_300p_heading_last | read | 2/2 | 145005 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G016_en_300p_divisions_early | read | 3/3 | 145017 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G017_en_300p_prose_middle | read | 3/3 | 145051 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G018_mixed_300p_heading_deep | read | 2/2 | 146244 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G019_ar_300p_divisions_last | read | 2/2 | 144812 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G020_en_300p_prose_early | read | 3/3 | 145039 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G021_en_300p_heading_middle | read | 2/2 | 146304 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G022_en_300p_divisions_deep | read | 3/3 | 145020 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G023_en_300p_prose_last | read | 3/3 | 144957 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G024_en_300p_heading_early | read | 2/2 | 146163 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G025_en_300p_divisions_middle | read | 3/3 | 145039 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G026_en_300p_prose_deep | read | 2/2 | 144981 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G027_en_300p_heading_last | read | 2/2 | 145049 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G028_mixed_300p_divisions_early | read | 3/3 | 145084 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G029_ar_300p_prose_middle | read | 2/2 | 144907 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G030_en_60p_heading_deep | read | 2/2 | 29215 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G031_en_20p_divisions_last | read | 3/3 | 8819 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G032_en_60p_prose_early | read | 3/3 | 28339 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G033_en_20p_heading_middle | read | 1/1 | 9730 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G034_en_60p_divisions_deep | read | 3/3 | 28278 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G035_en_20p_prose_last | read | 3/3 | 8844 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G036_en_60p_heading_early | read | 2/2 | 29405 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G037_en_20p_divisions_middle | read | 3/3 | 8935 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G038_mixed_60p_prose_deep | read | 3/3 | 28325 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G039_ar_20p_heading_last | read | 2/2 | 8770 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G040_en_60p_divisions_early | read | 3/3 | 28321 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G041_en_20p_prose_middle | read | 3/3 | 8898 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G042_en_60p_heading_deep | read | 2/2 | 29249 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G043_en_20p_divisions_last | read | 3/3 | 8790 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G044_en_60p_prose_early | read | 3/3 | 28348 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G045_en_20p_heading_middle | read | 2/2 | 9821 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G046_en_60p_divisions_deep | read | 3/3 | 28295 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G047_en_20p_prose_last | read | 3/3 | 8812 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G048_mixed_60p_heading_early | read | 2/2 | 29471 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G049_ar_20p_divisions_middle | read | 2/2 | 8779 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G050_en_60p_prose_deep | read | 3/3 | 28288 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G051_en_20p_heading_last | read | 2/2 | 8877 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G052_en_60p_divisions_early | read | 3/3 | 28336 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G053_en_20p_prose_middle | read | 2/2 | 8861 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G054_en_60p_heading_deep | read | 2/2 | 29293 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G055_en_20p_divisions_last | read | 3/3 | 8802 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G056_en_60p_prose_early | read | 3/3 | 28352 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G057_en_20p_heading_middle | read | 2/2 | 9755 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G058_mixed_60p_divisions_deep | read | 3/3 | 28353 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G059_ar_20p_prose_last | read | 2/2 | 8701 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G060_en_5p_heading_early | read | 1/1 | 1342 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G061_en_2p_divisions_middle | read | 3/3 | 458 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G062_en_5p_prose_deep | read | 3/3 | 1474 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G063_en_2p_heading_last | read | 2/2 | 327 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G064_en_5p_divisions_early | read | 3/3 | 1538 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G065_en_2p_prose_middle | read | 3/3 | 471 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G066_en_5p_heading_deep | read | 2/2 | 1357 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G067_en_2p_divisions_last | read | 3/3 | 457 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G068_en_5p_prose_early | read | 3/3 | 1501 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G069_ar_2p_heading_middle | read | 2/2 | 288 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G070_en_5p_divisions_deep | read | 3/3 | 1420 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G071_en_2p_prose_last | read | 3/3 | 484 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G072_en_5p_heading_early | read | 2/2 | 1419 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G073_en_2p_divisions_middle | read | 3/3 | 475 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G074_en_5p_prose_deep | read | 3/3 | 1442 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G075_en_2p_heading_last | read | 2/2 | 360 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G076_en_5p_divisions_early | read | 3/3 | 1503 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G077_en_2p_prose_middle | read | 3/3 | 468 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G078_en_5p_heading_deep | read | 2/2 | 1335 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G079_ar_2p_divisions_last | read | 2/2 | 323 characters | all | - | the trades could not be chosen: model stage not run (code-only measurement) |
| G080_scan_3p_heading_early | needs_ocr | 2/2 | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G081_scan_12p_heading_middle | needs_ocr | 2/2 | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G082_scan_25p_heading_deep | needs_ocr | 3/3 | pdf 25 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G083_scan_40p_heading_last | needs_ocr | 0/3 | pdf 30 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G084_scan_3p_heading_early | needs_ocr | 2/2 | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G085_scan_12p_heading_middle | needs_ocr | 3/3 | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G086_scan_25p_heading_deep | needs_ocr | 3/3 | pdf 25 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G087_scan_40p_heading_last | needs_ocr | 0/1 | pdf 30 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G088_scan_3p_heading_early | needs_ocr | 3/3 | pdf 3 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
| G089_scan_12p_heading_middle | needs_ocr | 3/3 | pdf 12 pages | all | - | This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR. |
