// deno test supabase/functions/send_whatsapp/registration_reminder.test.ts
// The first supplier_registration_reminder WhatsApp twin (2 Nov 2026 05:00Z) was skipped "no WhatsApp template mapping".
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from './test_source.ts';
import { registrationNeeds } from './registration_reminder.ts';

const started = 'Dear ZZ DEMO Trading LLC,\n\nThank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. It still needs: trade licence, company profile, the signed supplier terms.\n\nContinue where you left off:\n\nhttps://quotesdone.com/en/portal\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
const incomplete = 'Dear ZZ DEMO Trading LLC,\n\nYour registration is saved, but it still needs: company profile, a trade licence that is in date. Please complete it by 16 Nov 2026; after that date the registration closes automatically.';
const clicked = 'Dear Sir or Madam,\n\nThank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. It takes a few minutes.\n\nTo register, open your supplier portal here:\n\nhttps://quotesdone.com/en/portal?t=zz-demo-token';

Deno.test('each stage of the email becomes one clause naming what is missing', () => {
  assertEquals(registrationNeeds(started), 'your supplier registration still needs: trade licence, company profile, the signed supplier terms');
  assertEquals(registrationNeeds(incomplete), 'your supplier registration still needs: company profile, a trade licence that is in date (by 16 Nov 2026)');
  assertEquals(registrationNeeds(clicked), 'your company has not registered as a supplier yet');
  assertEquals(registrationNeeds(null), 'your supplier registration is not finished yet');
});

Deno.test('KNOWN-BAD control: no clause carries a link, a newline or the greeting', () => {
  for (const b of [started, incomplete, clicked]) {
    const v = registrationNeeds(b);
    assert(!/https?:|\?t=|\n|Dear /.test(v), v);
  }
});

Deno.test('send_whatsapp maps the type to its own template and fills it from this clause and the portal', () => {
  const src = functionSource();
  assertMatch(src, /if\(t==='supplier_registration_reminder'\) return 'supplier_registration_reminder';/);
  assertMatch(src, /key==='supplier_registration_reminder'\) return \{'1': waVar\(registrationNeeds\(n\.body\), 160\), '2': linkFor\(key\)\}/);
  const setup = Deno.readTextFileSync(new URL('../wa_template_setup/index.ts', import.meta.url));
  const entry = setup.slice(setup.indexOf('  supplier_registration_reminder: {'), setup.indexOf('  },', setup.indexOf('  supplier_registration_reminder: {')));
  assertMatch(entry, /english_only: true/);
  // Meta refuses a body that opens or closes with a variable
  const body = entry.match(/en: '([^']+)'/)![1];
  assert(!body.startsWith('{{') && !body.endsWith('}}'), body);
});
