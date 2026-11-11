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
const LATE = `(function(){setTimeout(function(){try{if(document.documentElement.getAttribute('data-qd-portal')==='mounted')return;var b=document.getElementById('qd-portal-boot');if(!b)return;var t=b.querySelector('[data-qd-boot-text]');if(t)t.textContent='The supplier portal is taking longer than usual to open. Please reload the page.';var r=b.querySelector('button');if(r){r.hidden=false;r.onclick=function(){location.reload()}}}catch(_e){}},12000)})();`;

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
