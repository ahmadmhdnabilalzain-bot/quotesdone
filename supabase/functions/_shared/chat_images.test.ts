// What a chat message may carry to the model as an image (chat_images.ts). No network.
import { assertEquals } from 'jsr:@std/assert';
import { acceptImages, MAX_DATA_URL_CHARS, withImages } from './chat_images.ts';

const JPEG = 'data:image/jpeg;base64,' + 'A'.repeat(100);
const HOST = 'testref.supabase.co';

// prevented by: this test. A public endpoint never pushes a large, foreign or non-image payload through a paid model.
Deno.test('a small photo or our own stored file is accepted; size, count, type and foreign URLs are refused', () => {
  assertEquals(acceptImages([JPEG], HOST), { images: [JPEG], refused: [] });
  const stored = `https://${HOST}/storage/v1/object/sign/chat/x.jpg?token=t`;
  assertEquals(acceptImages([{ url: stored }], HOST).images, [stored]);
  assertEquals(acceptImages(['data:image/jpeg;base64,' + 'A'.repeat(MAX_DATA_URL_CHARS)], HOST).refused, ['too_large']);
  assertEquals(acceptImages(['data:text/html;base64,AAAA'], HOST).refused, ['not_an_image']);
  assertEquals(acceptImages(['https://evil.example/x.jpg'], HOST).refused, ['foreign_url']);
  assertEquals(acceptImages([JPEG, JPEG, JPEG], HOST).refused, ['too_many']);
  assertEquals(acceptImages('nope', HOST), { images: [], refused: [] });
});

Deno.test('the message content carries the text then the images; no image keeps a plain string', () => {
  assertEquals(withImages('hello'), 'hello');
  assertEquals(withImages('fit a wardrobe here', [JPEG]), [{ type: 'text', text: 'fit a wardrobe here' }, { type: 'image_url', image_url: { url: JPEG } }]);
});
