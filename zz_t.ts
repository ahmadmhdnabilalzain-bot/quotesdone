import { pdfText, licenceFieldsFromText } from './supabase/functions/_shared/document_expiry.ts';
for (const f of Deno.args) { const b = await Deno.readFile(f); const t = await pdfText(b); console.log('== ' + f + '\n' + (t||'').slice(0, 900)); console.log(JSON.stringify(licenceFieldsFromText(t||''))); }
