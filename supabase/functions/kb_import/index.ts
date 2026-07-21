// kb_import — one-off importer for uploaded knowledge libraries. Secret-gated.
// op 'sign'  -> returns a signed upload URL for backups/imports/kb_final.json
// op 'ingest'-> downloads that JSON and bulk-inserts chunks into kb_chunks (source_kind='library'), idempotent.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
const BUCKET = 'backups'; const PATH = 'imports/kb_final.json';
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(() => ({} as any));
    if (b.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    if (b.op === 'sign') {
      try { await admin.storage.createBucket(BUCKET, { public: false }); } catch (_e) { /* exists */ }
      const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(PATH, { upsert: true } as any);
      if (error || !data) return J({ error: error?.message || 'sign failed' }, 500);
      const sp = (data as any).signedUrl as string;
      return J({ ok: true, full_url: SUPA + '/storage/v1' + (sp.startsWith('/') ? sp : '/' + sp), path: PATH });
    }
    if (b.op === 'ingest') {
      const { data: blob, error } = await admin.storage.from(BUCKET).download(PATH);
      if (error || !blob) return J({ error: 'download failed: ' + (error?.message || 'no file') }, 500);
      let rows: any[]; try { rows = JSON.parse(await blob.text()); } catch (e) { return J({ error: 'bad json: ' + String(e) }, 400); }
      if (!Array.isArray(rows)) return J({ error: 'not an array' }, 400);
      const today = new Date().toISOString().slice(0, 10);
      await admin.from('kb_chunks').delete().eq('source_kind', 'library');
      let n = 0;
      for (let i = 0; i < rows.length; i += 200) {
        const batch = rows.slice(i, i + 200).map((r: any) => ({ source_kind: 'library', source_id: String(r.category || 'library'), category: String(r.category || 'general'), title: String(r.title || '').slice(0, 300), content: String(r.content || ''), citation: String(r.citation || ''), effective_date: today }));
        const { error: ie } = await admin.from('kb_chunks').insert(batch);
        if (ie) return J({ error: 'insert failed at ' + i + ': ' + ie.message, inserted: n }, 500);
        n += batch.length;
      }
      return J({ ok: true, inserted: n });
    }
    return J({ error: 'unknown op' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
