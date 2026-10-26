-- ROW #3 s25 — four task classes the company performs every day and routes by accident.
--
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s25-routing-seven-task-classes  MISSING  3 of 7 named task class(es) have an active policy;
--                                            missing: OCR, summarization, translation, vision
--
-- model_policy holds 34 active classes and none of them declares vision, OCR, translation or
-- summarization. Each of the four is a task this system demonstrably performs:
--
--   vision         supplier trade licences, drawings and photos are read (attach_photos,
--                  drawing_redact, doc_extract). The `doc_extraction` critical capability says so
--                  in its own words: "Supplier documents are read, including scanned PDFs."
--   OCR            the scanned half of that. `ocr_cleanup` exists, but it is the TEXT TIDYING that
--                  happens after OCR — routed to a cheap text model with a 1,200-token ceiling. It
--                  is not a policy for turning a scan into text, and it never was.
--   translation    customer_api translates whole quotations into Modern Standard Arabic for the
--                  UAE B2B market. A real, quality-sensitive LLM call with no policy over it.
--   summarization  briefs, digests and report bodies. `content_drafting` and `general_drafting`
--                  cover writing something new, not compressing something that exists.
--
-- So these are four LLM workloads running today with no declared tier, no fallback and no cost
-- ceiling. That is the gap; the check merely names it.
--
-- ── EVERY MODEL NAMED HERE HAS A VERIFIED RATE ──────────────────────────────────────────────────
-- institutional_memory: "Rates are now fetched from the provider and stored with a source URL and
-- verification date. No routing rule may name a model that has no verified row in model_rate."
-- All four rules draw from the six models verified on 2026-08-05 and from nothing else.
--
-- STAGING ONLY. apply_sql --ddl forbids carrying row data to production; these rows reach
-- production through promote_rows_to_production.mjs, which reads the verified value back out.
insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, active, cache_ttl_min)
values
  ('vision', 'medium', 'google/gemini-3.5-flash', 'anthropic/claude-sonnet-5', 8000,
   'Looking at an image and describing or judging what is in it — a trade licence, a site photo, a drawing. Multimodal and long-context; the same model document_extraction already uses to read a whole document, because it is the same capability pointed at a picture instead of a page.',
   true, 0),
  ('ocr', 'medium', 'google/gemini-3.5-flash', 'anthropic/claude-sonnet-5', 8000,
   'Turning a scan or a photographed page into text. Distinct from ocr_cleanup, which tidies text that has ALREADY been extracted and is deliberately routed to a small model — reading the scan in the first place needs the multimodal tier or the characters are guessed.',
   true, 0),
  ('translation', 'medium', 'anthropic/claude-sonnet-5', 'google/gemini-3.5-flash', 4000,
   'Arabic quotation and correspondence translation for the UAE market. Not routed to the small tier on purpose: numbers, units, emirate names and Latin brand codes must survive intact, and a mistranslated quantity on a quotation is a commercial error, not a wording one.',
   true, 0),
  ('summarization', 'small', '~anthropic/claude-haiku-latest', 'anthropic/claude-sonnet-5', 1500,
   'Compressing text that already exists — briefs, digests, report bodies. The cheap tier is correct here because the source is present and correct; the work is selection, not judgement. Escalates to sonnet when the summary must survive being acted on.',
   true, 60)
on conflict (task_class) do update
  set tier = excluded.tier, model_primary = excluded.model_primary,
      model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens,
      rationale = excluded.rationale, active = excluded.active, cache_ttl_min = excluded.cache_ttl_min;
