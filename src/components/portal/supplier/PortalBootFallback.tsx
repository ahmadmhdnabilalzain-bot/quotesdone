// WHAT THE SUPPLIER SEES IF THE PORTAL'S SCRIPT NEVER RUNS (11 Nov 2026, customer_support; supplier registration certification,
// second free round, J5 desktop run 1). One of the portal's JavaScript chunks answered 502 to the browser and was refused
// ("Refused to execute script ... MIME type 'text/plain'"); the portal never mounted, SupplierPortal renders nothing until it
// mounts, so the page stayed an empty dark screen for the whole 240 s the walk waited. Nothing told the supplier anything.
// The chunk itself was served normally before and after (Vercel cache HIT, no production deploy between 02:51 and 03:41 UTC)
// and the container's egress relay logged tunnel failures to quotesdone.com in the same minutes, so that 502 was most likely
// the test container's network, but a phone on a poor connection can lose a chunk the same way.
// So the server renders this line with the page: "Opening the supplier portal…", hidden the moment the portal mounts
// (SupplierPortal sets html[data-qd-portal="mounted"]), and after 12 s without a mount it says so and offers a reload.
// Plain inline script and CSS, no import: it must work exactly when the bundle did not. English only (ruling 1008).
// Prevented by: scripts/checks/the_supplier_portal_never_stays_a_blank_page.test.mjs
const STYLE = 'html[data-qd-portal="mounted"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;line-height:1.5}#qd-portal-boot button{margin-top:12px;min-height:44px;padding:0 18px;border-radius:10px;border:1px solid currentColor;background:transparent;color:inherit;font:inherit;cursor:pointer}';
// A PAGE CHUNK THAT FAILED IS ANSWERED IN SECONDS, NOT AT 12 s (11 Nov 2026, customer_support; free round 6, run 1 J2 mobile: chunk
// 339rcm1dz4b7r.js answered 502 text/plain from Vercel's edge and was refused, and this line stood ~9 s before Turbopack's one
// retry mounted the portal). A <script> under /_next/ that fails (a 5xx, a refused MIME type: both fire `error` on the element,
// caught here in the capture phase, or already in the Resource Timing list with responseStatus >= 400) arms a 3 s check: the
// bundle's loader retries a failed chunk once within a second, and if the portal has still not mounted the reload is offered then.
const LATE = `(function(){var shown=false;function late(){try{if(shown||document.documentElement.getAttribute('data-qd-portal')==='mounted')return;var b=document.getElementById('qd-portal-boot');if(!b)return;shown=true;var t=b.querySelector('[data-qd-boot-text]');if(t)t.textContent='The supplier portal is taking longer than usual to open. Please reload the page.';var r=b.querySelector('button');if(r){r.hidden=false;r.onclick=function(){location.reload()}}}catch(_e){}}setTimeout(late,12000);var armed=false;function failed(){if(!armed){armed=true;setTimeout(late,3000)}}try{window.addEventListener('error',function(e){var s=e&&e.target;if(s&&s.tagName==='SCRIPT'&&String(s.src||'').indexOf('/_next/')>=0)failed()},true)}catch(_e){}try{var es=performance.getEntriesByType('resource');for(var i=0;i<es.length;i++){if(es[i].responseStatus>=400&&String(es[i].name).indexOf('/_next/')>=0)failed()}}catch(_e){}})();`;

export function PortalBootFallback() {
  return (
    <div id="qd-portal-boot" role="status" aria-live="polite">
      <style dangerouslySetInnerHTML={{ __html: STYLE }} />
      <p data-qd-boot-text="">Opening the supplier portal…</p>
      <button type="button" hidden>Reload the page</button>
      <script dangerouslySetInnerHTML={{ __html: LATE }} />
    </div>
  );
}
