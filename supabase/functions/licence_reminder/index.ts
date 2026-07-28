// licence_reminder — RETIRED 22 Jul 2026 (OS audit F7). Orphaned duplicate of the live document-reminder path
// (doc_reminders_daily -> run_doc_reminders -> doc_reminder). Its only caller, run_licence_reminders, is not
// scheduled and not referenced elsewhere. 410 stub; recover from git history if ever needed.
Deno.serve(() => new Response(JSON.stringify({ error: 'licence_reminder is retired — use doc_reminder' }), { status: 410, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }));
