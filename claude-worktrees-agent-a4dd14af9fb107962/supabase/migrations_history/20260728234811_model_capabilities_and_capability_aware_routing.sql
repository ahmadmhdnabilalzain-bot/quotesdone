-- WHY. ai_gateway could only carry plain text. Routing knew a model's tier and price but not
-- whether it can see an image, hear audio, or call a tool, so an image payload could be routed to
-- a text-only model and fail. That single gap is why ~33 edge functions were still calling
-- OpenRouter directly: 33 blind spots in ai_cost_log, 33 places the budget halt cannot reach.
-- Capability becomes a first-class routing input here.

alter table public.model_registry
  add column if not exists supports_vision boolean not null default false,
  add column if not exists supports_audio  boolean not null default false,
  add column if not exists supports_tools  boolean not null default false;

comment on column public.model_registry.supports_vision is 'Accepts image_url / file content parts. Set from the provider''s published modality list, not from a guess.';
comment on column public.model_registry.supports_audio  is 'Accepts input_audio content parts (speech-to-text without a separate ASR vendor).';
comment on column public.model_registry.supports_tools  is 'Supports OpenAI-style tools / tool_calls.';

update public.model_registry set supports_vision = true,  supports_tools = true,  supports_audio = false
 where model_id in ('anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8', '~anthropic/claude-haiku-latest');

update public.model_registry set supports_vision = true,  supports_tools = true,  supports_audio = true
 where model_id in ('google/gemini-3.5-flash', 'google/gemini-3.1-flash-lite');

-- Conservative until verified: a wrong "true" here routes real traffic to a model that will reject it.
update public.model_registry set supports_vision = false, supports_tools = true,  supports_audio = false
 where model_id in ('qwen/qwen3.7-plus');

-- Two classes the policy table was missing. Without them, document work inherited ocr_cleanup's
-- 1200-token ceiling and silently truncated long extractions, and speech had no home at all.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, active) values
  ('document_extraction', 'medium', 'google/gemini-3.5-flash', 'anthropic/claude-sonnet-5', 4000,
   'Reading a whole document (scan, drawing, licence, quotation) and returning its full content. Long-context medium model first; the ceiling is high on purpose because truncating an extraction is worse than the token cost.', true),
  ('speech_transcription', 'small', 'google/gemini-3.1-flash-lite', 'google/gemini-3.5-flash', 1024,
   'Verbatim speech to text. Cheapest audio-capable model; quality difference on transcription does not justify a larger tier.', true)
on conflict (task_class) do update
  set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
      max_tokens = excluded.max_tokens, rationale = excluded.rationale, active = true;

-- Route the document and speech functions to the classes that actually fit them.
insert into public.fn_task_class (fn, task_class, note, active) values
  ('extract_text',    'document_extraction', 'Full-document read for the Secretary chat; 4000-token output is the point.', true),
  ('doc_extract',     'document_extraction', 'Supplier document ingestion, including the scanned-PDF OCR path.', true),
  ('quote_extract',   'document_extraction', 'Reads a supplier quotation PDF/image into structured lines.', true),
  ('license_extract', 'document_extraction', 'UAE trade licence scan - first step of supplier verification.', true),
  ('drawing_boq',     'document_extraction', 'Reads a construction drawing into a bill of quantities.', true),
  ('drawing_redact',  'document_extraction', 'Finds identifying marks on a drawing before it is shown anonymously.', true),
  ('transcribe',      'speech_transcription', 'Server-side speech to text, Arabic/English mixed.', true),
  ('secretary_act',   'chief_of_staff_decision', 'The founder''s Chief of Staff with tool access - it was mis-mapped to customer_communication, whose 800-token ceiling truncates multi-tool turns.', true),
  ('customer_api',    'customer_communication', 'Was unmapped, so it silently defaulted to general_drafting.', true)
on conflict (fn) do update
  set task_class = excluded.task_class, note = excluded.note, active = true, updated_at = now();