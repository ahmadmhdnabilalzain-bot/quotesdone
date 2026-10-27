// AN ERROR'S OWN WORDS, SAFE TO STORE (it_engineer, 27 Oct 2026). Measured on production at 20:30Z: five held
// questions failed on fetches that threw, and llm.ts recorded only 'client_error' while ml_embed_client.ts returned
// null with no reason at all, so the step detail could not say whether the hop timed out, was refused or never
// reached a worker. Callers now keep the message - cut to `max` characters, with anything shaped like a credential
// (a bearer token, a key=value secret, a long unbroken token) replaced, because the text lands in rows people read.
// prevented by: _shared/error_text.test.ts
export function errorText(e: unknown, max = 160): string {
  const raw = e instanceof Error ? (e.name && e.name !== 'Error' ? e.name + ': ' : '') + e.message : String(e ?? '');
  return raw
    .replace(/\b(bearer|basic)\s+[^\s,;]+/gi, '$1 [redacted]')
    // any name that CONTAINS one of these words: access_token, client_secret, x-api-key (review of #1688: a \b before
    // the word never matched after an underscore, so ?access_token= and "client_secret":"..." went through)
    .replace(/([\w-]*(?:secret|token|key|password|passwd|authorization|signature|credential)[\w-]*)(["']?\s*[:=]\s*["']?)[^\s"',;&]+/gi, '$1$2[redacted]')
    // a key whose prefix says what it is, however short: sb_secret_..., sb_publishable_..., sk-...
    .replace(/\b(?:sb_(?:secret|publishable)_|sk-)[\w-]+/gi, '[redacted]')
    .replace(/[A-Za-z0-9_\-+=]{32,}/g, '[redacted]')     // a JWT's segments, an API key; a URL's '/' and '.' break the run
    .replace(/\s+/g, ' ').trim().slice(0, max);
}
