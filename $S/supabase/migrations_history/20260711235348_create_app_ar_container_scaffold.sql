-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711235348   name: create_app_ar_container_scaffold
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

delete from pages where slug='app-ar';
insert into pages(slug, html) select 'app-ar', html from pages where slug='app';

update pages set html = replace(html, '<html lang="en">', '<html lang="ar" dir="rtl">') where slug='app-ar';
update pages set html = replace(html, '#05121A', '#0C2330') where slug='app-ar';
update pages set html = replace(html, '#030A0F', '#06121B') where slug='app-ar';

update pages set html = replace(
  html,
  '</head>',
  '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800&display=swap" rel="stylesheet">'
  || '<style id="qd-rtl">'
  || 'body{font-family:Tajawal,Inter,-apple-system,Segoe UI,Roboto,sans-serif}'
  || 'h1,h2,h3,.step,.price,.kpi .n{font-family:Tajawal,Sora,Inter,sans-serif}'
  || '[dir=rtl] .qda-panel{right:auto;left:20px}'
  || '[dir=rtl] .qda-btn{right:auto;left:20px}'
  || '[dir=rtl] .qda-u{align-self:flex-start}'
  || '[dir=rtl] .qda-a{align-self:flex-end}'
  || '</style></head>')
  where slug='app-ar';
