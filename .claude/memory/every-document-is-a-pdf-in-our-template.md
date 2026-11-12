---
name: every-document-is-a-pdf-in-our-template
description: "Founder rulings 1671 and 1672 of 12 Nov 2026: every document QuotesDone produces or shows him is a PDF in the QuotesDone template. Never raw JSON, a text file, a spreadsheet dump or a screenshot of data. Applies to what a supplier or customer downloads ('Download my data') and to anything he asks to be shown."
metadata:
  type: feedback
  modified: 2026-11-12
---

**What happened (12 Nov 2026, ledger 1669).** The founder pressed "Download my data" in the supplier portal on his iPhone
and got a raw JSON file with broken emoji. His word for it: *"horrible"*.

**The founder, verbatim:**
- 1671: *"Download my data should be a pdf with our template"*
- 1672: *"And everything is PDF. Whenever I tell you, show me a document, it's always a PDF in our template. Always, any
  document for Code's Done. Every single thing that comes out is a PDF in our template."* (The session reads "Code's Done" as the phone's
  spelling of QuotesDone; that reading is the session's, not his.)

**How to apply (the session's reading of his rulings, labelled as its own; only the two quotes above are his).**
- The template has one home: `supabase/functions/_shared/doc_template.ts`, rendered by `supabase/functions/pdf_native/`.
  A new document is a new payload for that renderer, never a second layout.
- Anything a person downloads from a portal, anything mailed as an attachment that we composed, and anything the session
  sends the founder as "the document" is that PDF. A machine-readable copy may exist beside it; it is never the thing he
  is handed.
- Before calling a document done, render it and look at the page as an image: the template, no empty placeholders, no
  raw keys or codes, names as a person would write them.
- A report for the repository (`docs/reports/`) stays Markdown: that is our working record, not a QuotesDone document.

Related: [[nothing-is-done-until-a-browser-proved-it]].
