// prevented by: Outlook drops white-space:pre-wrap, so the supplier invitation arrived in Outlook as one
// paragraph (marketing, ledger 993, 24 Sep 2026). Fails if the frame stops turning line breaks into <br>.
import { assert } from 'jsr:@std/assert';
import { tmpl } from './render.ts';

Deno.test('a wrapped supplier body keeps its line breaks as <br>', () => {
  const html = tmpl({ body: 'Dear X,\n\nLine two\r\n- bullet', logo: '', name: 'A', title: 'F', channelEmail: 'r@x', unsub: '', wrapper: '<div>{{BODY}}</div>' });
  assert(html.includes('Dear X,<br><br>Line two<br>- bullet'), html);
});

Deno.test('the unwrapped frame keeps its line breaks as <br>', () => {
  const html = tmpl({ body: 'a\nb', logo: '', name: 'A', title: 'F', channelEmail: 'r@x', unsub: '' });
  assert(html.includes('a<br>b'));
});
