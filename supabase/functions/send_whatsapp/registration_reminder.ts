// {{1}} of the supplier_registration_reminder WhatsApp template (it_engineer, 2 Nov 2026), read from the email twin's
// body that fn_supplier_registration_reminder_compose wrote (English only: suppliers are always written in English).
// The template says "QuotesDone reminder: {{1}}. You can continue your supplier registration here: {{2}} ...", so this
// returns one clause with no trailing full stop: what is still missing, by when if the email gives a date, or that the
// company has not started. Anything else (the free-form reply follow-up) gets the plain sentence.
// prevented by: send_whatsapp/registration_reminder.test.ts
export function registrationNeeds(body: string | null | undefined): string {
  const b = String(body || '').replace(/\s+/g, ' ');
  const needs = b.match(/still needs: (.+?)\.(?: |$)/i);
  if (needs) {
    const due = b.match(/complete it by ([0-9]{1,2} [A-Za-z]{3} [0-9]{4})/);
    return 'your supplier registration still needs: ' + needs[1].trim() + (due ? ' (by ' + due[1] + ')' : '');
  }
  if (/has not registered yet/i.test(b)) return 'your company has not registered as a supplier yet';
  return 'your supplier registration is not finished yet';
}
