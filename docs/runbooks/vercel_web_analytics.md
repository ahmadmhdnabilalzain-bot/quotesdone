# Vercel Web Analytics: switching it on

Seat: marketing (agent: marketing seat builder), 15 Nov 2026. Why: the marketing seat cannot count visits, sources or
visit-to-signup without it (founder rulings 1701, 1705). Measured 15 Nov 2026: the Vercel MCP `aggregate_pageviews` on the
project quotesdone-next answers 404 "Web Analytics not found", because Web Analytics is not enabled on the project.

## What the code already does
- `src/components/WebAnalytics.tsx` adds Vercel's cookieless script (`/_vercel/insights/script.js`, same origin, so the
  CSP in `next.config.mjs` needs no new host) to every page under `src/app/[locale]/layout.tsx`.
- It renders nothing until the build sees `NEXT_PUBLIC_WEB_ANALYTICS=on`. No package is installed (no `npm install`).

## Switching it on (two steps, in this order)
1. Enable Web Analytics on the project. One line, with the token already held in `app_secrets.vercel_token` and the team
   in `app_secrets.vercel_team_id` (never print either):

       npx vercel@latest project web-analytics enable quotesdone-next --scope "$VERCEL_TEAM_ID" --token "$VERCEL_TOKEN"

   The same switch exists in the REST API (`POST /web/insights/toggle`, documented without its body, so the CLI is the
   reliable path) and in the dashboard: Vercel > quotesdone-next > Analytics > Enable. No repository script calls it: the
   only Vercel API callers in this repository read configuration (`scripts/checks/the_vercel_configuration_is_backed_up_every_day.test.mjs`).
2. Set the environment variable `NEXT_PUBLIC_WEB_ANALYTICS=on` for Production on the project and redeploy. Pages then
   load the script and send page views.

## Proving it
- Vercel MCP `count_pageviews` / `aggregate_pageviews` for quotesdone-next returns numbers instead of 404, the morning after.
- The cookie policy says the site sets no cookie and keeps no identifier (§2): Vercel Web Analytics keeps that promise (no
  cookie; visitors are told apart by a hash that changes daily). Add one line naming Vercel Web Analytics as the
  aggregate page-view counter to the cookie policy in the same release.

## Turning it off
`npx vercel@latest project web-analytics disable quotesdone-next --yes --scope "$VERCEL_TEAM_ID" --token "$VERCEL_TOKEN"`
and remove the variable; the component then renders nothing again.
