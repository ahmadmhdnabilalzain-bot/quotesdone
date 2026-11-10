---
name: a-whatsapp-voice-note-is-heard-only-once-a-provider-is-set
description: "10 Nov 2026: WhatsApp voice notes are transcribed by wa_inbound/hear.ts through _shared/speech_to_text.ts, but only when app_secrets.voice_transcription_provider is 'hf' (needs hf_inference_token, founder-held, not in the estate) or 'gateway' (OpenRouter, on hold). Default off = the honest please-type reply."
metadata:
  type: project
---

**What exists (branch it_engineer-whatsapp-followup, 10 Nov 2026).** A voice-note-only WhatsApp message is downloaded, sniffed,
measured (ogg granule / wav header), capped and transcribed; the speaker is sent "I heard: ..." (Arabic for a customer who spoke
Arabic, English for a supplier), and the transcript becomes the turn's Body, so the same intake/interview turn runs as for typed
text. The portal recorder (transcribe) uses the same module and keeps its gateway route while the provider is off.

**Config (app_secrets):** `voice_transcription_provider` (off | hf | gateway; missing = off), `voice_transcription_max_seconds`
(120), `voice_transcription_daily_cap` (300, every sender), `voice_transcription_per_sender_daily` (20),
`voice_transcription_timeout_ms` (25 000), `voice_transcription_hf_model` (openai/whisper-large-v3-turbo), `hf_inference_token`.
Caps are claimed on a `wa_messages` row (meta.route voice_claim) before the call.

**What is missing to run live:** measured 10 Nov, no speech key in app_secrets or the edge secrets. 'hf' needs a fine-grained
token of the Quotesdone Hugging Face account ("Make calls to Inference Providers") stored as `hf_inference_token`; 'gateway'
needs the OpenRouter hold lifted, and whether the provider takes 'ogg' input_audio is the live check's to establish. The live
check (no real person: a fixture number through the ops.wa_replay JSON path with an inline data: URL) and its expected cost are
in the header of `supabase/functions/_shared/speech_to_text.ts`.

**How to apply:** do not tell anyone voice notes "work" until the live check has run on the chosen provider. Do not add a third
provider without reading the cost lines in that header.

Related: [[an-edge-call-runs-where-its-caller-is]], [[the-engineer-and-support-reply-only-through-the-model]].
