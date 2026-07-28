// kb_retrieve — RETIRED 22 Jul 2026 (OS audit F7). Orphaned duplicate of kb_search (the wired retrieval path is
// fn_kb_search -> kb_search, a newer hybrid semantic+FTS+RRF retriever). kb_retrieve had 0 references and was the
// only KB function mis-set to verify_jwt=true. 410 stub; recover from git history if ever needed.
Deno.serve(() => new Response(JSON.stringify({ error: 'kb_retrieve is retired — use kb_search' }), { status: 410, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }));
