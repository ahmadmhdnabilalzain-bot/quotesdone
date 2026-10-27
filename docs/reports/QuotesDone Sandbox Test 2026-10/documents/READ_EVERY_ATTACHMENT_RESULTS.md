# Every attachment is read — measured result (ruling 1177)

Measured 2026-10-11T22:05:51.519Z on project htdblwldjkcgjvmqkbeh, rehearsal run `fecf70f2`, cap USD 2. Spend: 7 logged call(s), AED 0.0080.
Code only (before the ruling): 3/8 read. With the model: 7/8 read.
Target (0 held except the deliberately degraded file, every read file carries its words): **MET**.

| file | path | code only | with model | by | attempts | words | quote total |
|---|---|---|---|---|---|---|---|
| boq_text_pdf | customer BOQ (customer_api analyze_document) | read | read | code | 0 | 5/5 |  |
| boq_scan_jpg | customer BOQ photo (drawing_boq document mode) | unreadable | read | model | 1 | 5/5 |  |
| boq_scan_pdf | scanned BOQ PDF (doc_extract / drawing_boq) | unreadable | read | model | 1 | 5/5 |  |
| drawing_pdf | drawing PDF (drawing_boq) | read | read | code | 0 | 2/2 |  |
| drawing_png | drawing PNG (drawing_boq photo) | unreadable | read | model | 1 | 2/2 |  |
| quote_text_pdf | supplier quotation (quote review / quote_extract) | read | read | code | 0 | 2/2 | 15000 ✓ |
| quote_scan_jpg | supplier quotation photo (quote review) | unreadable | read | model | 1 | 2/2 | 15000 ✓ |
| degraded_jpg (degraded on purpose) | deliberately degraded scan | unreadable | unreadable | - | 2 | 0/0 |  |
