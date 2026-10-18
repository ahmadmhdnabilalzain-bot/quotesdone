// chat_images — a photo or drawing a customer sends with a chat message goes to the model (founder ruling 1200,
// 12 Oct 2026: "a customer shares a photo of a studio for a wardrobe, and the agent must use it"). The gateway already
// routes a message with image parts to a vision-capable model (ai_gateway inferCaps); this file decides what is
// ACCEPTED, so a public endpoint cannot be used to push large or foreign content through a paid model:
//   - at most MAX_IMAGES per message;
//   - a data: URL of a JPEG, PNG or WebP image of at most MAX_DATA_URL_CHARS (the widget resizes before sending), or
//     an https URL on our own Supabase storage (a portal or WhatsApp attachment already stored by us);
//   - anything else is refused and named, never fetched.
// prevented by: _shared/chat_images.test.ts
export const MAX_IMAGES = 2;
export const MAX_DATA_URL_CHARS = 1_600_000;   // ≈ 1.2 MB of image: a 1280 px JPEG at quality 0.8 is far below it

const DATA_URL = /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/;

export function acceptImages(raw: unknown, storageHost?: string | null): { images: string[]; refused: string[] } {
  const list = Array.isArray(raw) ? raw : [];
  const images: string[] = []; const refused: string[] = [];
  for (const x of list) {
    const u = typeof x === 'string' ? x : String((x as { url?: unknown } | null)?.url ?? '');
    if (images.length >= MAX_IMAGES) { refused.push('too_many'); continue; }
    if (u.startsWith('data:')) {
      if (u.length > MAX_DATA_URL_CHARS) refused.push('too_large');
      else if (!DATA_URL.test(u)) refused.push('not_an_image');
      else images.push(u);
      continue;
    }
    try {
      const url = new URL(u);
      if (url.protocol === 'https:' && storageHost && url.host === storageHost && url.pathname.startsWith('/storage/v1/')) images.push(u);
      else refused.push('foreign_url');
    } catch (_e) { refused.push('not_a_url'); }
  }
  return { images, refused };
}

/** The OpenAI-shape user content: the text, then the images. A message without images stays a plain string. */
export function withImages(text: string, images: string[] = []): string | { type: string; text?: string; image_url?: { url: string } }[] {
  return images.length ? [{ type: 'text', text }, ...images.map((url) => ({ type: 'image_url', image_url: { url } }))] : text;
}
