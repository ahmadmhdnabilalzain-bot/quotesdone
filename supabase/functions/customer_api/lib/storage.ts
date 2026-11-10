// customer_api — signed URLs for the private buckets, and base64 to bytes.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { admin } from '../context.ts';

export async function signedReviewPhotos(paths: string[]): Promise<string[]> { const urls = await Promise.all(paths.map(async (p) => { try { const { data } = await admin.storage.from('review-photos').createSignedUrl(p, 3600); return data?.signedUrl || null; } catch { return null; } })); return urls.filter((u): u is string => !!u); }
export async function signedDrawing(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('drawing-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
export async function signedDoc(bucket: string | null | undefined, path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from(bucket || 'agent-docs').createSignedUrl(path, 7 * 24 * 3600); return data?.signedUrl || null; } catch { return null; } }

function b64ToBytes(b64: string): Uint8Array { const raw = atob(String(b64).replace(/^data:[^;]+;base64,/, '')); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i); return arr; }
