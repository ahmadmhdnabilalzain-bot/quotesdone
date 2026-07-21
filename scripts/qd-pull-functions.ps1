# qd-pull-functions.ps1 - re-sync EVERY deployed edge function into git.
#
# WHY THIS EXISTS
# ---------------
# scripts/edge-functions.sh does the same job but needs bash. This is the Windows
# path. Run it whenever backend work has been deployed, so the git mirror matches
# production.
#
# On 21 Jul 2026 the mirror was found to be 5 functions short, and route_inquiry
# was stale IN PLACE while still carrying a newer file timestamp than the deploy.
# That is the important lesson: file mtime does NOT prove the content is current.
# Only a real download does. Never audit this mirror by timestamp.
#
# The token is read interactively and kept in the CURRENT SESSION ONLY. It is not
# written to disk, not persisted with setx, and not committed.
#
#   powershell -ExecutionPolicy Bypass -File scripts\qd-pull-functions.ps1

$ErrorActionPreference = 'Stop'
$REF  = 'htdblwldjkcgjvmqkbeh'
$ROOT = Split-Path -Parent $PSScriptRoot

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Host ''
  Write-Host 'Supabase access token needed (starts with sbp_).' -ForegroundColor Cyan
  Write-Host 'Generate one at https://supabase.com/dashboard/account/tokens -> "Generate new token".'
  Write-Host 'It is shown once. Paste it below.'
  $env:SUPABASE_ACCESS_TOKEN = (Read-Host 'Token').Trim()
}
if ($env:SUPABASE_ACCESS_TOKEN -notmatch '^sbp_') {
  throw 'That does not look like a Supabase access token - it should start with sbp_'
}

Set-Location $ROOT
Write-Host ''
Write-Host "Listing functions on $REF ..."
$fns = (npx --yes supabase@latest functions list --project-ref $REF -o json) | ConvertFrom-Json
Write-Host "$($fns.Count) functions deployed."
Write-Host ''

$ok = 0; $fail = @()
foreach ($f in $fns) {
  Write-Host -NoNewline ("  {0,-38} " -f $f.slug)
  npx --yes supabase@latest functions download $f.slug --project-ref $REF *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host 'ok' -ForegroundColor Green; $ok++ }
  else { Write-Host 'SKIP' -ForegroundColor Yellow; $fail += $f.slug }
}

Write-Host ''
Write-Host "Mirrored $ok / $($fns.Count) functions into supabase/functions/"
if ($fail.Count) { Write-Host "Failed: $($fail -join ', ')" -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Changed files:' -ForegroundColor Cyan
git -C $ROOT status --porcelain -- supabase/functions
Write-Host ''
Write-Host 'Review the diff, then commit:'
Write-Host '  git add supabase/functions'
Write-Host '  git commit -m "Re-sync edge function mirror with production"'
