# GO-FORWARD DEPLOY STANDARD (decision D1, 3 Aug 2026).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\archive\deploy_functions.ps1 `
#              -ProjectRef htdblwldjkcgjvmqkbeh slug_a slug_b ...
#
#   Production requires -IMeanProduction as well. That is deliberate: this script was pinned to
#   the production ref in three places, so the only deploy tool in the repo could only ever target
#   production - and staging could therefore never run the application at all.
#
# Two rules are baked in, both learned the hard way on 3 Aug:
#
# 1. NO verify_jwt FLAG IS PASSED. supabase/config.toml is the single source of truth and the CLI
#    reads it. Proven on production 3 Aug 2026: vercel_status (verify_jwt=false) redeployed with no
#    flag stayed false, where the CLI's own default would have flipped it to true. Passing a flag
#    here would put the truth back in the caller's hands, which is the whole problem D1 fixed.
#
# 2. NO $ErrorActionPreference = 'Stop'. The Supabase CLI writes to stderr on SUCCESS. With Stop
#    set, the run aborts on the first stderr write and the deploy silently does not happen.
#
# It refuses to deploy if config.toml and live have drifted, because in that state nobody knows
# which value a deploy is about to apply. A target with no functions yet cannot have drifted, so
# that check is skipped on a first deploy rather than blocking it.

param(
  [string]$ProjectRef,
  [switch]$IMeanProduction,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Slugs
)

$PROD_REF = 'htdblwldjkcgjvmqkbeh'

if (-not $ProjectRef) { $ProjectRef = $env:QD_TARGET_REF }
if (-not $ProjectRef) {
  Write-Output 'No -ProjectRef given and QD_TARGET_REF is unset. Refusing to guess a deploy target.'
  exit 1
}
if ($ProjectRef -eq $PROD_REF -and -not $IMeanProduction) {
  Write-Output "REFUSED: -ProjectRef is production ($PROD_REF). Pass -IMeanProduction to mean it."
  exit 1
}
if (-not $Slugs -or $Slugs.Count -eq 0) { Write-Output 'No function slugs given. Nothing to do.'; exit 1 }

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$t = if ($env:SUPABASE_ACCESS_TOKEN) { $env:SUPABASE_ACCESS_TOKEN.Trim() } else { (Get-Content (Join-Path $HOME '.supabase/access-token') -Raw).Trim() }
$env:SUPABASE_ACCESS_TOKEN = $t
$env:QD_TARGET_REF = $ProjectRef
$h = @{ Authorization = "Bearer $t" }

Write-Output "target project: $ProjectRef"

$live = @()
try { $live = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ProjectRef/functions" -Headers $h }
catch { Write-Output "Could not list functions on $ProjectRef : $($_.Exception.Message)"; exit 1 }

Write-Output '--- verify_jwt drift check ---'
if ($live.Count -eq 0) {
  Write-Output "SKIPPED: $ProjectRef has no deployed functions yet, so config.toml cannot have drifted from it."
} else {
  & node scripts/gen_supabase_config.mjs --check "--deploying=$($Slugs -join ',')"
  if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'REFUSING TO DEPLOY. config.toml and the live project disagree about verify_jwt.'
    Write-Output 'Resolve it deliberately: either regenerate (node scripts/gen_supabase_config.mjs)'
    Write-Output 'and review the diff, or fix the live value. Do not deploy through drift.'
    exit 1
  }
}

# Capture live versions so the deploy can be verified against the deployed bundle afterwards,
# rather than trusting the CLI exit code.
$before = @{}
foreach ($f in $Slugs) {
  try { $m = Invoke-RestMethod -Uri ("https://api.supabase.com/v1/projects/$ProjectRef/functions/" + $f) -Headers $h; $before[$f] = [int]$m.version }
  catch { $before[$f] = -1 }
}

Write-Output ''
Write-Output "--- deploying $($Slugs.Count) function(s) to $ProjectRef ---"
$failed = @()
$i = 0
foreach ($f in $Slugs) {
  $i++
  $out = & supabase functions deploy $f --project-ref $ProjectRef --use-api 2>&1 | Out-String
  $code = $LASTEXITCODE
  if ($code -ne 0) { $failed += $f; Write-Output ("[{0}/{1}] {2} DEPLOY FAILED exit={3}" -f $i, $Slugs.Count, $f, $code); Write-Output $out }
  else { Write-Output ("[{0}/{1}] {2} deployed" -f $i, $Slugs.Count, $f) }
}

Write-Output ''
Write-Output '--- verifying against the DEPLOYED bundle ---'
$pass = 0; $bad = @()
foreach ($f in $Slugs) {
  try {
    $m = Invoke-RestMethod -Uri ("https://api.supabase.com/v1/projects/$ProjectRef/functions/" + $f) -Headers $h
    # A first deploy has no previous version, so "bumped" is satisfied by the function now existing.
    $bumped = if ($before[$f] -lt 0) { [int]$m.version -ge 1 } else { [int]$m.version -gt $before[$f] }
    if ($bumped) { $pass++ } else { $bad += $f }
    Write-Output ("{0,-24} v{1,-4} (was v{2,-4}) ok={3,-5} verify_jwt={4}" -f $f, $m.version, $before[$f], $bumped, $m.verify_jwt)
  } catch { $bad += $f; Write-Output ("{0,-24} CHECK FAILED: {1}" -f $f, $_.Exception.Message) }
}

Write-Output ''
Write-Output ("DEPLOYED_OK {0}/{1}" -f $pass, $Slugs.Count)
if ($failed.Count) { Write-Output ("DEPLOY FAILURES: " + ($failed -join ' ')) }
if ($bad.Count)    { Write-Output ("NOT VERIFIED:    " + ($bad -join ' ')) }
if ($failed.Count -or $bad.Count) { exit 1 }
Write-Output 'ALL GOOD'
