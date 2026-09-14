// deno test supabase/functions/dropbox_backup/dropbox.test.ts
// An expired access token is answered by one refresh and one repeat, never by a failed backup; a
// refresh that fails is 'no_dropbox_auth'; non-ASCII names are escaped for the header.
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { apiArg, DropboxClient } from './dropbox.ts';

Deno.test('a 401 refreshes the token once and repeats the call once', async () => {
  const seen: string[] = []; let n = 0;
  const f = (_u: string, init: RequestInit) => {
    seen.push((init.headers as Record<string, string>).Authorization);
    return Promise.resolve(new Response('{}', { status: seen.length === 1 ? 401 : 200 }));
  };
  const dbx = new DropboxClient(() => Promise.resolve('T' + (++n)), f);
  const r = await dbx.call('api', 'files/get_metadata', { path: '/a' });
  assertEquals(r.status, 200);
  assertEquals(seen, ['Bearer T1', 'Bearer T2']);
  assertEquals(dbx.refreshes, 2);
});

Deno.test('a second 401 is returned, not looped on', async () => {
  const dbx = new DropboxClient(() => Promise.resolve('T'), () => Promise.resolve(new Response('', { status: 401 })));
  assertEquals((await dbx.call('api', 'users/get_space_usage', null)).status, 401);
});

Deno.test('a refresh that fails is no_dropbox_auth', async () => {
  const dbx = new DropboxClient(() => Promise.resolve(null), () => Promise.resolve(new Response('')));
  await assertRejects(() => dbx.call('api', 'users/get_space_usage', null), Error, 'no_dropbox_auth');
});

Deno.test('Arabic and emoji are escaped in Dropbox-API-Arg', () => {
  const a = apiArg({ path: '/مستند 🏗️' });
  assertEquals(/^[\x00-\x7e]*$/.test(a), true);
  assertEquals(JSON.parse(a).path, '/مستند 🏗️');
});
