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
