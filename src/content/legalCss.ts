export const LEGAL_CSS = `.legalx{--bg:#06121B;--panel:rgba(110,231,212,.035);--line:rgba(110,231,212,.10);--line2:rgba(110,231,212,.19);--t:#EAF4F2;--mut:#9DB2B2;--faint:#7C97A3;--teal:#14B8A6;--teal2:#14B8A6;--gold:#E3C065;color:var(--t);padding:24px 0 8px}.legalx .docwrap{max-width:880px;margin:0 auto;padding:24px 20px 54px}.legalx .crumb{font-size:12.5px;color:var(--faint);margin:16px 0 16px}.legalx .crumb a{color:var(--mut)}.legalx .nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}.legalx .nav a{font-size:12.5px;font-weight:600;text-decoration:none;color:var(--mut);background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:8px 14px;transition:.22s cubic-bezier(.16,1,.3,1)}.legalx .nav a:hover{color:#fff;border-color:var(--line2)}.legalx .nav a.on{background:var(--teal);color:#04231F;border-color:transparent}.legalx .doc{background:var(--panel);border:1px solid var(--line);border-radius:22px;padding:34px 40px;box-shadow:0 24px 60px -30px rgba(0,0,0,.7)}.legalx .dochead{border-bottom:1px solid var(--line2);padding-bottom:16px;margin-bottom:6px}.legalx .dochead h1{font-size:28px;margin:0 0 6px;color:#fff;letter-spacing:-.01em}.legalx .dochead .meta{color:var(--mut);font-size:13px}.legalx .body{margin-top:10px}.legalx .body>h1:first-child{display:none}.legalx .body .muted{color:var(--mut);font-size:13.5px;font-style:italic;margin:0 0 12px}.legalx .body p{margin:0 0 12px;color:#D6E6E3}.legalx .body h1{font-size:22px;color:#fff;margin:26px 0 8px}.legalx .body h2{font-size:18px;color:#fff;margin:28px 0 8px;}.legalx .body h3{font-size:15px;color:#fff;margin:16px 0 6px}.legalx .body ol, .legalx .body ul{padding-left:22px}.legalx .body li{margin:6px 0;color:#D6E6E3}.legalx .body a{color:var(--teal);font-weight:600}.legalx .body strong{color:#fff}.legalx .body table{width:100%;border-collapse:collapse;font-size:14px;margin:12px 0}.legalx .body th, .legalx .body td{border:1px solid var(--line);padding:8px 10px;text-align:left;color:#D6E6E3}.legalx .body th{background:var(--panel);color:#fff}html[dir=rtl] .legalx .body h2{padding-left:0;padding-right:12px;border-left:0;}html[dir=rtl] .legalx .body ol, html[dir=rtl] .legalx .body ul{padding-left:0;padding-right:22px}html[dir=rtl] .legalx .body th, html[dir=rtl] .legalx .body td{text-align:right}.legalx .note{background:rgba(45,212,191,.06);border:1px solid var(--line2);border-radius:14px;padding:14px 16px;font-size:12.5px;color:var(--mut);margin-top:26px;line-height:1.65}.legalx .note b{color:#fff}.legalx .contact{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:20px 24px;margin-top:18px}.legalx .contact .ct b{color:#fff}.legalx .contact .ct div{color:var(--mut);font-size:13px}.legalx .cbtns{display:flex;gap:10px;flex-wrap:wrap}.legalx .btn{display:inline-flex;align-items:center;gap:7px;text-decoration:none;font-weight:700;font-size:14px;border-radius:11px;padding:11px 18px;cursor:pointer;border:0}.legalx .btn.primary{background:var(--teal);color:#04231F}.legalx .btn.ghost{background:var(--panel);border:1px solid var(--line2);color:var(--t)}@media(max-width:560px){.legalx .doc{padding:24px 20px}}.legalx .body{overflow-wrap:anywhere;word-break:break-word}.legalx .body table{display:block;width:100%;overflow-x:auto;-webkit-overflow-scrolling:touch}.legalx .body img{max-width:100%;height:auto}
/* ── BLIND MATCH HARMONISATION ─────────────────────────────────────────── */
.legalx{
  --teal-l:#6EE7D4;--teal:#14B8A6;--teal2:#14B8A6;--teal-deep:#0B8276;
  --blue:#14B8A6;--blue-l:#6EE7D4;--indigo:#E3C065;
  --gold:#E3C065;--gold-l:#F6DD8C;--gold2:#F6DD8C;
  --bg:#06121B;--bg2:#0C2330;--white:#EAF4F2;--t:#EAF4F2;
  --muted:#9DB2B2;--mut:#9DB2B2;--faint:#7C97A3;
  --line:rgba(110,231,212,.10);--line2:rgba(110,231,212,.19);
  --panel:rgba(110,231,212,.035);--panel2:rgba(110,231,212,.06);
  --grad:none;
  background:transparent;
}
.legalx.legalx h1,.legalx.legalx h2,.legalx.legalx h3,.legalx.legalx h4{
  font-family:var(--font-head),system-ui,sans-serif;
  color:#fff;text-wrap:balance;font-weight:600;
}
.legalx.legalx h1{letter-spacing:-.04em;line-height:1.05}
.legalx.legalx h2{letter-spacing:-.032em;line-height:1.1}
.legalx.legalx h3{letter-spacing:-.02em;line-height:1.22}
.legalx.legalx p,.legalx.legalx li{text-wrap:pretty;color:#C3D6D4;line-height:1.72}
.legalx.legalx .lead{color:#9DB2B2}

/* the tiny tracked all-caps kicker is the AI tell — quiet, sentence-case label */
.legalx.legalx .eyebrow{
  text-transform:none;letter-spacing:0;font-size:13px;font-weight:500;
  color:#6EE7D4;display:inline-block;margin-bottom:2px;
}

/* gradient-clipped text is banned; make every accent span solid */
.legalx.legalx .g,.legalx.legalx .hero h1 .g,.legalx.legalx h1 .g,.legalx.legalx h2 .g,.legalx.legalx span.g{
  background:none!important;-webkit-background-clip:border-box!important;
  background-clip:border-box!important;color:#6EE7D4!important;
  -webkit-text-fill-color:#6EE7D4!important;box-shadow:none;
}
/* …except when .g is a button: then it is a solid brand key */
.legalx.legalx a.btn.g,.legalx.legalx .btn.g,.legalx.legalx button.g{
  background:#14B8A6!important;color:#04231F!important;
  -webkit-text-fill-color:#04231F!important;
  box-shadow:0 12px 34px -16px rgba(20,184,166,.75)!important;
}
.legalx.legalx a.btn.g:hover,.legalx.legalx .btn.g:hover,.legalx.legalx button.g:hover{background:#1ED0BC!important;transform:none}

/* surfaces: one material, hairline in brand teal, no heavy shadow stacking */
.legalx.legalx .card,.legalx.legalx .panel,.legalx.legalx .box,.legalx.legalx .tile,.legalx.legalx .doc,.legalx.legalx .qa,.legalx.legalx .item,.legalx.legalx .concept>div{
  border-color:rgba(110,231,212,.10);
  background:rgba(110,231,212,.035);
  box-shadow:inset 0 1px 0 rgba(110,231,212,.10);
}
.legalx.legalx a:not(.cta):not(.btn):not(.on){color:#6EE7D4;text-decoration:none;transition:color .22s cubic-bezier(.16,1,.3,1)}
.legalx.legalx a:not(.cta):not(.btn):not(.on):hover{color:#fff}
/* active pill = filled key, needs dark ink not teal */
.legalx.legalx a.on,.legalx.legalx .nav a.on{color:#04231F;background:#14B8A6;border-color:transparent}
/* filled keys keep their dark ink; ghost (.o) keeps teal on transparent */
.legalx.legalx a.cta,.legalx.legalx .cta,.legalx.legalx a.btn:not(.o),.legalx.legalx .btn:not(.o),.legalx.legalx button.btn:not(.o){color:#04231F;text-decoration:none}
.legalx.legalx a.cta:hover,.legalx.legalx .cta:hover,.legalx.legalx a.btn:not(.o):hover,.legalx.legalx .btn:not(.o):hover{color:#04231F;filter:brightness(1.06)}
.legalx.legalx a.btn.o,.legalx.legalx .btn.o{color:#6EE7D4;background:transparent}
.legalx.legalx a.btn.o:hover,.legalx.legalx .btn.o:hover{color:#fff;border-color:#14B8A6}
.legalx.legalx strong,.legalx.legalx b{color:#fff;font-weight:600}
.legalx.legalx hr{border:0;border-top:1px solid rgba(110,231,212,.10)}
.legalx.legalx table th{background:rgba(110,231,212,.05);color:#fff}
.legalx.legalx table th,.legalx.legalx table td{border-color:rgba(110,231,212,.10)}
.legalx.legalx code,.legalx.legalx kbd,.legalx.legalx .mono,.legalx.legalx .tabular{font-family:var(--font-mono),ui-monospace,monospace}
.legalx.legalx ::selection{background:rgba(20,184,166,.3);color:#fff}
.legalx.legalx :focus-visible{outline:2px solid #6EE7D4;outline-offset:3px;border-radius:6px}
`;
