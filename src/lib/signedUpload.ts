// A file sent straight to storage on a signed upload URL, without a storage client.
// Assigned: it_engineer. 27 Oct 2026, stage-2 rerun of run 0a717394 (ledger 1121/1261).
//
// MEASURED. The supplier portal's uploadDirect (19 Oct, #1496) called SB().storage.from(...).uploadToSignedUrl, but
// SB() is supaClient(), which since 28 Sep builds an AUTH-ONLY client ({ auth }) - there is no .storage. Every company
// profile and catalogue a supplier picked threw "Cannot read properties of undefined (reading 'from')" before a byte
// left the browser; the throw escaped the Documents tab's upload(), so the button stayed on "Uploading..." with no
// message, and Save on the registration form said "Still needed to register: Company profile" forever. A ZZ DEMO
// supplier walked it on production on 27 Oct (registration walk 390dafcc): profile never on file, approval never
// reached. No real supplier could finish registering since 19 Oct.
//
// THE REQUEST is the one @supabase/storage-js sends for uploadToSignedUrl: PUT
// <url>/storage/v1/object/upload/sign/<bucket>/<path>?token=<token>, the anon apikey, x-upsert false, the file as the
// body with its own content type. It never throws: a network failure is returned as an error like a refusal is.
// Guard: scripts/checks/a_supplier_document_upload_never_calls_a_client_the_portal_does_not_build.test.mjs
export function signedUploadRequest(supaUrl: string, anon: string, bucket: string, path: string, token: string, file: Blob, contentType?: string) {
  const enc = path.split('/').map(encodeURIComponent).join('/');
  const url = new URL(`storage/v1/object/upload/sign/${encodeURIComponent(bucket)}/${enc}`, supaUrl.replace(/\/?$/, '/'));
  url.searchParams.set('token', token);
  return {
    url: url.href,
    init: {
      method: 'PUT',
      headers: { apikey: anon, Authorization: `Bearer ${anon}`, 'x-upsert': 'false', 'cache-control': 'max-age=3600',
        'Content-Type': contentType || file.type || 'application/octet-stream' },
      body: file,
    } as RequestInit,
  };
}

// THE BYTES HE HAS SENT, AS THEY GO (12 Nov 2026, customer_support; browser perfection walk H2, founder ruling 1645: "there is no
// loading animation when you are submitting something"). fetch() cannot report an upload's progress, so when the caller asks
// for it (`onProgress`, 0..1) the same PUT goes by XMLHttpRequest, whose upload.onprogress can; without it nothing changes.
// It still never throws: a dropped connection or a timeout is status 0, as a fetch failure is.
// Prevented by: src/lib/signedUpload.test.mjs.
// A STALLED UPLOAD ENDS, AND ONLY A STALLED ONE (12 Nov 2026, customer_support; review of the registration form, rounds 1 and 2).
// Round 1: at 40 s it still said "Uploading… 0%", the picker and Submit disabled, no way out. Round 2: a ceiling sized at 50,000
// bytes a second cut a 1.43 MB photo at 82% three times on a 160 kbit/s line (it needed 72 s) and stored nothing. So the upload
// ends only when no byte has been sent for STALL_MS; while bytes move it goes on, however slowly, showing its percentage.
// SAFETY_MS is not a speed rule: 15 minutes is far beyond any honest case (a 10 MB licence at 100 kbit/s takes about 14 min) and
// is there only so a browser that stops reporting progress can never hold the form for good.
// Round 3: once every byte has left (loaded === total) they may still sit in the phone's send buffer while storage answers, so the
// no-bytes clock gives way to ANSWER_MS (60 s) for the answer. A `signal` that aborts (the form's "Cancel") ends it as 'cancelled';
// the safety limit ends it as 'too_slow'. Neither is transient: uploadDirect never asks again after either (src/lib/signedUpload.ts
// isTransientUploadError, status -1).
export const STALL_MS = 20_000;
export const ANSWER_MS = 60_000;
export const SAFETY_MS = 15 * 60_000;
export function putWithProgress(url: string, init: RequestInit, onProgress: (done: number) => void,
  Xhr: { new(): XMLHttpRequest } = XMLHttpRequest, stallMs = STALL_MS, safetyMs = SAFETY_MS, signal?: AbortSignal, answerMs = ANSWER_MS): Promise<{ ok: boolean; status: number; text: string }> {
  return new Promise((resolve) => {
    const x = new Xhr();
    let ended = false; let why = '';
    const end = (r: { ok: boolean; status: number; text: string }) => { if (ended) return; ended = true; clearTimeout(stall); clearTimeout(ceiling); signal?.removeEventListener('abort', cancel); resolve(r); };
    const giveUp = (w: string, status = 0) => { why = w; try { x.abort(); } catch (_e) { /* already over */ } end({ ok: false, status, text: w }); };
    const cancel = () => giveUp('cancelled', -1);
    if (signal?.aborted) { resolve({ ok: false, status: -1, text: 'cancelled' }); return; }
    signal?.addEventListener('abort', cancel);
    let stall = setTimeout(() => giveUp('stalled'), stallMs);
    const ceiling = setTimeout(() => giveUp('too_slow', -1), safetyMs);
    let sent = -1;
    x.open(String(init.method || 'PUT'), url);
    for (const [k, v] of Object.entries((init.headers || {}) as Record<string, string>)) x.setRequestHeader(k, v);
    x.upload.onprogress = (e) => {
      if (e.loaded > sent) { sent = e.loaded; clearTimeout(stall); stall = setTimeout(() => giveUp('stalled'), e.lengthComputable && e.total > 0 && e.loaded >= e.total ? answerMs : stallMs); }
      if (e.lengthComputable && e.total > 0) onProgress(Math.min(1, e.loaded / e.total));
    };
    x.onload = () => { if (x.status >= 200 && x.status < 300) onProgress(1); end({ ok: x.status >= 200 && x.status < 300, status: x.status, text: String(x.responseText || '') }); };
    x.onerror = () => end({ ok: false, status: 0, text: 'network' });
    x.ontimeout = () => end({ ok: false, status: 0, text: 'timeout' });
    x.onabort = () => end({ ok: false, status: why === 'cancelled' || why === 'too_slow' ? -1 : 0, text: why || 'aborted' });
    x.send(init.body as XMLHttpRequestBodyInit);
  });
}

export async function uploadToSignedUrl(supaUrl: string, anon: string, bucket: string, path: string, token: string, file: Blob,
  contentType?: string, doFetch: typeof fetch = fetch, onProgress?: (done: number) => void, signal?: AbortSignal): Promise<{ error: null } | { error: { status: number; message: string } }> {
  try {
    const { url, init } = signedUploadRequest(supaUrl, anon, bucket, path, token, file, contentType);
    if (onProgress && typeof XMLHttpRequest !== 'undefined') {
      const r = await putWithProgress(url, init, onProgress, XMLHttpRequest, STALL_MS, SAFETY_MS, signal);
      return r.ok ? { error: null } : { error: { status: r.status, message: r.text.slice(0, 300) } };
    }
    const r = await doFetch(url, init);
    if (r.ok) return { error: null };
    return { error: { status: r.status, message: (await r.text().catch(() => '')).slice(0, 300) } };
  } catch (e) {
    return { error: { status: 0, message: String((e as Error)?.message || e) } };
  }
}

// A gateway 502/503/546 or a dropped leg is the platform busy, not the file refused (walk 41379033121, 2 Nov 2026: one 502
// on the catalogue's upload_url call ended a registration). `e` is call()'s failure object or uploadToSignedUrl's error.
export function isTransientUploadError(e: any): boolean {
  if (!e) return false;
  if (e.status === 0 || e.status >= 500 || e._http >= 500) return true;
  return e.code === 'timeout' || e.code === 'network' || (e.code === 'bad_response' && !(e._http >= 400 && e._http < 500));
}

// Runs one whole upload (sign, then PUT; the path is new each time) up to `tries` times while the failure is transient.
export async function retryTransient<T extends { error?: any }>(attempt: () => Promise<T>, tries = 3, waitMs = 1500): Promise<T> {
  let r = await attempt();
  for (let i = 1; i < tries && r.error && isTransientUploadError(r.error); i++) {
    await new Promise((res) => setTimeout(res, waitMs * i));
    r = await attempt();
  }
  return r;
}
