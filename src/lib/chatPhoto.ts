// A photo or drawing for a chat message (founder ruling 1200). Resized in the browser to at most 1280 px on its long
// side and encoded as a JPEG at quality 0.8, so it stays well under the server's cap (supabase/functions/_shared/
// chat_images.ts MAX_DATA_URL_CHARS) and the upload is small on a phone. Shared by the website widget and the portal
// chat. Returns '' for a file that is not an image or cannot be read.
export async function photoToDataUrl(f: File | undefined | null, maxSide = 1280): Promise<string> {
  if (!f || !f.type.startsWith('image/')) return '';
  const img = await createImageBitmap(f).catch(() => null);
  if (!img) return '';
  const k = Math.min(1, maxSide / Math.max(img.width, img.height));
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
  c.getContext('2d')?.drawImage(img, 0, 0, c.width, c.height);
  return c.toDataURL('image/jpeg', 0.8);
}
