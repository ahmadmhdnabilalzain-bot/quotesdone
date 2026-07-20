export const SERVICES_CSS = `:root{--bg:#06121B;--bg2:#0C2330;--panel:rgba(110,231,212,.035);--panel2:rgba(110,231,212,.06);--line:rgba(110,231,212,.10);--line2:rgba(110,231,212,.19);--t:#EAF4F2;--muted:#9DB2B2;--faint:#7C97A3;--teal:#14B8A6;--teal2:#14B8A6;--teal-deep:#0B8276;--gold:#E3C065;--gold2:#F6DD8C;--r:20px;--maxw:1120px}.mk a{color:var(--teal);text-decoration:none}.mk a:hover{color:var(--teal2)}.mk h1, .mk h2, .mk h3{text-wrap:balance;letter-spacing:-.025em;font-family:var(--font-head),system-ui,sans-serif;color:#fff;line-height:1.25}.mk p{text-wrap:pretty;color:#D6E6E3}.mk .wrap{max-width:var(--maxw);margin:0 auto;padding:0 20px}.mk header.site{position:sticky;top:0;z-index:30;background:rgba(5,18,26,.72);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}.mk header.site .wrap{display:flex;align-items:center;gap:16px;padding:13px 20px}.mk .brand{display:inline-flex;align-items:center}.mk .nav{display:flex;gap:20px;margin-left:6px}.mk .nav a{color:var(--muted);font-size:14px;font-weight:500}.mk .nav a:hover{color:#fff}.mk @media(max-width:640px){.mk .nav{display:none}}
.cta{margin-left:auto;background:var(--teal);color:#04231F;font-weight:700;padding:10px 18px;border-radius:14px;box-shadow:0 10px 26px -12px rgba(45,212,191,.7)}.mk .cta:hover{color:#04231F;filter:brightness(1.05)}.mk .hero{padding:54px 0 30px;background:radial-gradient(820px 380px at 18% 0%,rgba(231,181,60,.08),transparent)}.mk h1{font-size:clamp(28px,4vw,42px);margin:0 0 14px;letter-spacing:-.02em}.mk .lead{font-size:clamp(16px,2vw,19px);color:var(--muted);max-width:730px;margin:0}.mk .btn{display:inline-block;background:var(--teal);color:#04231F;font-weight:700;padding:13px 24px;border-radius:14px;margin-top:20px;box-shadow:0 14px 34px -14px rgba(45,212,191,.7)}.mk .btn:hover{color:#04231F;filter:brightness(1.05)}.mk section{padding:24px 0}.mk h2{font-size:clamp(20px,2.4vw,26px);margin:0 0 14px;letter-spacing:-.01em}.mk ul.ticks{list-style:none;padding:0;margin:0}.mk ul.ticks li{padding:8px 0 8px 30px;position:relative;color:#D6E6E3}.mk ul.ticks li:before{content:'✓';color:var(--teal);position:absolute;left:0;font-weight:800}.mk .steps{display:flex;flex-wrap:wrap;gap:16px}.mk .step{flex:1;min-width:220px;background:var(--panel);border:1px solid var(--line);border-radius:var(--r);padding:18px}.mk .step b{color:#fff;display:block;margin-bottom:6px;font-family:var(--font-head),system-ui,sans-serif}.mk .step div{color:var(--muted)}.mk .faq{border-top:1px solid var(--line);padding:16px 0}.mk .faq b{display:block;margin-bottom:6px;color:#fff;font-family:var(--font-head),system-ui,sans-serif}.mk .faq div{color:var(--muted)}.mk .links a{display:inline-block;margin:6px 14px 6px 0}.mk .chips a{display:inline-block;background:var(--panel);border:1px solid var(--line2);color:var(--t);border-radius:999px;padding:8px 15px;margin:5px 8px 5px 0;font-size:14px}.mk .chips a:hover{border-color:var(--teal);color:#fff}.mk .tldr{background:linear-gradient(180deg,rgba(20,184,166,.10),rgba(20,184,166,.04));border:1px solid var(--line2);border-radius:14px;padding:16px 18px;margin:18px 0;color:#dff1ee;font-size:15px}.mk .tldr b{color:#fff}.mk .tldr a{font-weight:600}.mk .blist{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}.mk @media(max-width:900px){.mk .blist{grid-template-columns:repeat(2,1fr)}}
@media(max-width:620px){.mk .blist{grid-template-columns:1fr}}
.bpost{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:22px;overflow:hidden;background:var(--panel);text-decoration:none;color:inherit;transition:transform .16s ease,border-color .16s ease,box-shadow .16s ease}.mk .bpost:hover{transform:translateY(-4px);border-color:var(--line2);box-shadow:0 22px 50px -24px rgba(0,0,0,.7)}.mk .bcover{aspect-ratio:16/9;display:block;background:#0C2330}.mk .bcover svg{width:100%;height:100%;display:block}.mk .bbody{padding:16px 18px 20px}.mk .bchip{display:inline-block;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--gold2);background:rgba(231,181,60,.12);border:1px solid rgba(231,181,60,.28);padding:4px 10px;border-radius:999px;margin-bottom:10px}.mk .bpost h2{font-size:18px;margin:0 0 8px;line-height:1.32}.mk .bpost p{color:var(--muted);margin:0 0 12px;font-size:14.5px}.mk .bpost .more{color:var(--teal);font-weight:700;font-size:14px}.mk .article{max-width:760px;font-size:16.5px}.mk .article h2{margin-top:32px;font-size:22px}.mk .article h3{margin-top:22px;font-size:18px;color:#fff;font-family:var(--font-head),system-ui,sans-serif}.mk .article p{color:#D6E6E3}.mk .article ul, .mk .article ol{padding-left:22px}.mk .article li{margin:6px 0;color:#D6E6E3}.mk .article a{font-weight:600}.mk .article strong{color:#fff}.mk .article table{width:100%;border-collapse:collapse;margin:16px 0;font-size:15px}.mk .article th, .mk .article td{border:1px solid var(--line);padding:9px 11px;text-align:left;color:#D6E6E3}.mk .article th{background:var(--panel);color:#fff}.mk .hero-cover{height:240px;border-radius:22px;overflow:hidden;border:1px solid var(--line);margin:4px 0 6px}.mk .hero-cover svg{display:block;width:100%;height:100%}.mk @media(max-width:620px){.mk .hero-cover{height:170px}}
.crumb{font-size:13px;color:var(--faint);margin-bottom:10px}.mk .crumb a{color:var(--muted)}.mk footer.site{border-top:1px solid var(--line);background:linear-gradient(180deg,transparent,rgba(10,30,39,.55));margin-top:44px;padding:46px 0 28px}.mk .fgrid{display:grid;grid-template-columns:1.5fr 1fr 1fr 1.25fr;gap:34px}.mk @media(max-width:820px){.mk .fgrid{grid-template-columns:1fr 1fr}}
@media(max-width:520px){.mk .fgrid{grid-template-columns:1fr}}
.fcol h4{font-family:var(--font-head),system-ui,sans-serif;font-size:12px;text-transform:uppercase;letter-spacing:.09em;color:var(--faint);margin:0 0 14px}.mk .fcol a{display:block;color:var(--muted);font-size:14px;padding:5px 0}.mk .fcol a:hover{color:#fff}.mk .fbrand p{color:var(--muted);font-size:14px;max-width:290px;margin:14px 0 16px}.mk .fsocial{display:flex;gap:10px}.mk .fsocial a{width:38px;height:38px;border:1px solid var(--line2);border-radius:10px;display:flex;align-items:center;justify-content:center;color:var(--muted)}.mk .fsocial a:hover{color:#fff;border-color:var(--teal)}.mk .fcontact a{display:flex;align-items:center;gap:10px;color:var(--t);font-size:14px;padding:6px 0;font-weight:500}.mk .fcontact a:hover{color:var(--teal)}.mk .fcontact svg{flex:0 0 auto;color:var(--teal)}.mk .fbar{border-top:1px solid var(--line);margin-top:32px;padding-top:18px;display:flex;flex-wrap:wrap;gap:8px;justify-content:space-between;color:var(--faint);font-size:12.5px}.mk #qdLangBtn{position:fixed;top:12px;inset-inline-end:14px;z-index:99999;background:#0d9488;color:#fff;border:none;border-radius:999px;padding:7px 15px;font:600 13px/1 system-ui,'Segoe UI',sans-serif;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.18)}.mk #qdLangBtn:hover{background:#0b7d72}html[dir=rtl] .mk body{direction:rtl}html[dir=rtl] .mk .cta{margin-left:0;margin-right:auto}html[dir=rtl] .mk ul.ticks li{padding:6px 28px 6px 0}html[dir=rtl] .mk ul.ticks li:before{left:auto;right:0}.mk #qda-root *{box-sizing:border-box}.mk #qda-root .qda-btn{position:fixed;right:20px;bottom:20px;z-index:2147483000;width:58px;height:58px;border-radius:50%;border:0;cursor:pointer;background:linear-gradient(135deg,#14B8A6,#0D9488);box-shadow:0 10px 30px rgba(45,212,191,.45);display:flex;align-items:center;justify-content:center;transition:transform .15s}.mk #qda-root .qda-btn:hover{transform:translateY(-2px) scale(1.03)}.mk #qda-root .qda-btn svg{width:26px;height:26px}.mk #qda-root .qda-panel{position:fixed;right:20px;bottom:88px;z-index:2147483000;width:352px;max-width:calc(100vw - 30px);height:474px;max-height:calc(100vh - 118px);background:#0C2330;border:1px solid rgba(255,255,255,.12);border-radius:22px;box-shadow:0 24px 60px rgba(0,0,0,.55);display:none;flex-direction:column;overflow:hidden;font-family:var(--font-body),system-ui,sans-serif}.mk #qda-root.qda-open .qda-panel{display:flex}.mk #qda-root .qda-hd{padding:13px 15px;background:linear-gradient(135deg,rgba(45,212,191,.16),rgba(231,181,60,.10));border-bottom:1px solid rgba(110,231,212,.10);display:flex;align-items:center;gap:9px}.mk #qda-root .qda-dot{width:8px;height:8px;border-radius:50%;background:#14B8A6;box-shadow:0 0 8px #14B8A6;flex:0 0 auto}.mk #qda-root .qda-hd b{color:#EAF4F2;font-size:14px;font-weight:600}.mk #qda-root .qda-hd small{color:#9DB2B2;font-size:11px}.mk #qda-root .qda-x{margin-left:auto;background:0;border:0;color:#9DB2B2;font-size:20px;cursor:pointer;line-height:1}.mk #qda-root .qda-msgs{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:10px}.mk #qda-root .qda-m{max-width:86%;padding:9px 12px;border-radius:14px;font-size:14px;line-height:1.5;white-space:pre-wrap}.mk #qda-root .qda-a{align-self:flex-start;background:rgba(255,255,255,.06);color:#EAF4F2;border:1px solid rgba(110,231,212,.06)}.mk #qda-root .qda-u{align-self:flex-end;background:var(--teal);color:#04231F;font-weight:500}.mk #qda-root .qda-a a{color:#14B8A6}.mk #qda-root .qda-in{display:flex;gap:8px;padding:12px;border-top:1px solid rgba(110,231,212,.10)}.mk #qda-root .qda-in input{flex:1;background:rgba(110,231,212,.035);border:1px solid rgba(255,255,255,.14);color:#EAF4F2;border-radius:10px;padding:10px 12px;font:inherit;font-size:14px;min-width:0}.mk #qda-root .qda-in button{background:var(--teal);color:#04231F;border:0;border-radius:10px;padding:0 15px;font-weight:600;cursor:pointer}

.mk .reveal{opacity:1 !important;transform:none !important}
.mk{color:var(--t,#EAF4F2)}
/* ── BLIND MATCH HARMONISATION ─────────────────────────────────────────── */
.mk{
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
.mk.mk h1,.mk.mk h2,.mk.mk h3,.mk.mk h4{
  font-family:var(--font-head),system-ui,sans-serif;
  color:#fff;text-wrap:balance;font-weight:600;
}
.mk.mk h1{letter-spacing:-.04em;line-height:1.05}
.mk.mk h2{letter-spacing:-.032em;line-height:1.1}
.mk.mk h3{letter-spacing:-.02em;line-height:1.22}
.mk.mk p,.mk.mk li{text-wrap:pretty;color:#C3D6D4;line-height:1.72}
.mk.mk .lead{color:#9DB2B2}

/* the tiny tracked all-caps kicker is the AI tell — quiet, sentence-case label */
.mk.mk .eyebrow{
  text-transform:none;letter-spacing:0;font-size:13px;font-weight:500;
  color:#6EE7D4;display:inline-block;margin-bottom:2px;
}

/* gradient-clipped text is banned; make every accent span solid */
.mk.mk .g,.mk.mk .hero h1 .g,.mk.mk h1 .g,.mk.mk h2 .g,.mk.mk span.g{
  background:none!important;-webkit-background-clip:border-box!important;
  background-clip:border-box!important;color:#6EE7D4!important;
  -webkit-text-fill-color:#6EE7D4!important;box-shadow:none;
}
/* …except when .g is a button: then it is a solid brand key */
.mk.mk a.btn.g,.mk.mk .btn.g,.mk.mk button.g{
  background:#14B8A6!important;color:#04231F!important;
  -webkit-text-fill-color:#04231F!important;
  box-shadow:0 12px 34px -16px rgba(20,184,166,.75)!important;
}
.mk.mk a.btn.g:hover,.mk.mk .btn.g:hover,.mk.mk button.g:hover{background:#1ED0BC!important;transform:none}

/* surfaces: one material, hairline in brand teal, no heavy shadow stacking */
.mk.mk .card,.mk.mk .panel,.mk.mk .box,.mk.mk .tile,.mk.mk .doc,.mk.mk .qa,.mk.mk .item,.mk.mk .concept>div{
  border-color:rgba(110,231,212,.10);
  background:rgba(110,231,212,.035);
  box-shadow:inset 0 1px 0 rgba(110,231,212,.10);
}
.mk.mk a:not(.cta):not(.btn):not(.on){color:#6EE7D4;text-decoration:none;transition:color .22s cubic-bezier(.16,1,.3,1)}
.mk.mk a:not(.cta):not(.btn):not(.on):hover{color:#fff}
/* active pill = filled key, needs dark ink not teal */
.mk.mk a.on,.mk.mk .nav a.on{color:#04231F;background:#14B8A6;border-color:transparent}
/* filled keys keep their dark ink; ghost (.o) keeps teal on transparent */
.mk.mk a.cta,.mk.mk .cta,.mk.mk a.btn:not(.o),.mk.mk .btn:not(.o),.mk.mk button.btn:not(.o){color:#04231F;text-decoration:none}
.mk.mk a.cta:hover,.mk.mk .cta:hover,.mk.mk a.btn:not(.o):hover,.mk.mk .btn:not(.o):hover{color:#04231F;filter:brightness(1.06)}
.mk.mk a.btn.o,.mk.mk .btn.o{color:#6EE7D4;background:transparent}
.mk.mk a.btn.o:hover,.mk.mk .btn.o:hover{color:#fff;border-color:#14B8A6}
.mk.mk strong,.mk.mk b{color:#fff;font-weight:600}
.mk.mk hr{border:0;border-top:1px solid rgba(110,231,212,.10)}
.mk.mk table th{background:rgba(110,231,212,.05);color:#fff}
.mk.mk table th,.mk.mk table td{border-color:rgba(110,231,212,.10)}
.mk.mk code,.mk.mk kbd,.mk.mk .mono,.mk.mk .tabular{font-family:var(--font-mono),ui-monospace,monospace}
.mk.mk ::selection{background:rgba(20,184,166,.3);color:#fff}
.mk.mk :focus-visible{outline:2px solid #6EE7D4;outline-offset:3px;border-radius:6px}
`;
