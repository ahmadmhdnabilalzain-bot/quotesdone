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

export async function uploadToSignedUrl(supaUrl: string, anon: string, bucket: string, path: string, token: string, file: Blob,
  contentType?: string, doFetch: typeof fetch = fetch): Promise<{ error: null } | { error: { status: number; message: string } }> {
  try {
    const { url, init } = signedUploadRequest(supaUrl, anon, bucket, path, token, file, contentType);
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
