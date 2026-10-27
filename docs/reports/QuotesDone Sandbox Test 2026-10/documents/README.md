# Supplier document intake accuracy suite — 7 Oct 2026 (ledger 1162)

Seats: sales_engineer (supplier verification + matching), it_engineer (harness).
Corpus: 59 SYNTHETIC documents (every name "ZZ DEMO", every number invented): 50 trade licences across 18 issuing
authorities (Dubai DED old + DET, ADDED, ADGM, SEDD, Ajman, RAK DED, RAKEZ, UAQ, Fujairah, JAFZA, DMCC, DAFZA, DSO,
IFZA, Meydan, SHAMS, DIFC) in text PDF (colon and table layouts), scanned PDF, PNG, JPG, rotated, skewed, low-DPI,
phone photo, multi-page, bilingual and Arabic-only; an expired licence (text + scan), another company's licence
(text + scan), a blank page, a blank photo and a missing licence; 6 company profiles (PDF/DOCX/PPTX/PNG), a catalogue,
a VAT certificate and an ISO certificate. Each run's files and truth are in its run-*/corpus folder.

| run | gate decisions correct | UNSAFE approvals | licence no. / name / expiry (text licences) | any field guessed wrong | wrong trade proposed | wrong supplier reached |
|---|---|---|---|---|---|---|
| BEFORE: main as deployed (code only; model switch off) | 17/50 | **1** | 0% / 50% / 100% | 1 | 14 | 10 |
| AFTER: this PR, code only (model switch still off) | 27/50 + 23 held safely | 0 | 100% / 100% / 100% | 0 | 0 | 0 |
| AFTER: this PR, with the model fallback (tagged window, 27 calls, AED 0.0175) | **50/50** | 0 | 100% / 100% / 100% | 2 (one Arabic-only licence: the model spaced the synthetic Arabic name "زد زد" as "ز د ز د"; the Arabic name is not used by the gate) | 0 | 0 |

Files: ACCURACY_<run>.md (tables per field, per authority, per format, gate rows, trade proposals, matching probe, and
every failure with its cause); run-<run>/result.json (machine-readable); run-<run>/probe.sql (the rolled-back gate +
match transaction). Demo rows: the gate/match probe always rolls back (leftover leads 0, storage 0 measured after each
run); the model stage's one ZZ DEMO subject supplier was torn down by the run.

Known remaining gaps (stated, not hidden): an activity worded "Aluminium Works Contracting" / "Aluminium works" names
no exact trade (it is ambiguous between the aluminium trade and the aluminium-sheet stock trade by meaning), so it is
proposed as nothing and the supplier confirms it in the portal; a profile that is only a photo proposes no trades
(no OCR on the server); the field labels of the corpus were written by the same author as the reader.

## Re-measured after founder rulings 1176 and 1177 (7 Oct 2026) — ACCURACY_after-rulings-1176-1177.md
Corpus now 60 documents / 51 licences (added: an already-approved supplier who swaps in a licence printing another
name). Model on (tagged window, 28 calls, AED 0.0492).
| gate decisions correct | UNSAFE | held | licence no./name/expiry (text) | fields guessed wrong | wrong trades | wrong supplier reached |
|---|---|---|---|---|---|---|
| 51/51 | 0 | only the deliberately blank page and blank photo (licence_unreadable, supplier asked for a clearer copy) | 100% / 100% / 100% | 0 | 0 | 0 |
- Ruling 1176: the mismatched licences (text, scan, and the approved supplier's swap) are now APPROVED with the
  company name changed to the licence name ("ZZ DEMO Mirage Contracting LLC", "ZZ DEMO Atlas Building Works FZ LLC");
  the old name is kept in agent_actions and the supplier is told in English.
- Ruling 1177: the photo-only company profile is now read by the vision model: flooring + joinery, both right.
- Not measured here (customer side, follow-up): BOQs, drawings and quotes uploaded by customers, and the email /
  WhatsApp inbound paths beyond licences.

## Final run, 12 Oct 2026, on main + #1275 (merged) — ACCURACY_final-12-oct-model-on.md
Model on (tagged window, 28 calls, AED 0.0498); gate = #1275's merged body + rulings 1176/1177 (rolled-back probe).
Gate 51/51 correct, 0 unsafe; licence no./name/expiry 100% on every licence the model or code could read; 0 fields
guessed wrong; 0 wrong trades; 0 wrong suppliers reached; held only the deliberately blank page and photo; the
photo-only profile read right. Leftovers after the run: 0 leads, 0 storage objects, 0 open windows.
Customer-side attachments (BOQs, drawings, supplier quotes, email/WhatsApp inbound, other portal uploads) are covered
by a separate follow-up PR with its own inventory and measurements (READ_EVERY_ATTACHMENT_INVENTORY.md when it lands).
