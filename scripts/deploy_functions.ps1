# GO-FORWARD DEPLOY STANDARD (decision D1, 3 Aug 2026).
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_functions.ps1 slug_a slug_b ...
#
# This replaces the per-batch deploy scripts in qd-check. Two rules are baked in, both learned the
# hard way today:
#
# 1. NO verify_jwt FLAG IS PASSED. supabase/config.toml is the single source of truth and the CLI
#    reads it. Proven on production 3 Aug 2026: vercel_status (verify_jwt=false) redeployed with no
#    flag stayed false, where the CLI's own default would have flipped it to true. Passing a flag
#    here would put the truth back in the caller's hands, which is the whole problem D1 fixed.
#
# 2. NO $ErrorActionPreference = 'Stop'. The Supabase CLI writes to stderr on SUCCESS. With Stop
#    set, the run aborts on the first stderr write and the deploy silently does not happen.
#
# It refuses to deploy anything if config.toml and live have drifted, because in that state nobody
# knows which value a deploy is about to apply.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Slugs)

if (-not $Slugs -or $Slugs.Count -eq 0) { Write-Output 'No function slugs given. Nothing to do.'; exit 1 }

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$t = (Get-Content C:\Users\Opera\.supabase\access-token -Raw).Trim()
$env:SUPABASE_ACCESS_TOKEN = $t
$h = @{ Authorization = "Bearer $t" }

Write-Output '--- verify_jwt drift check ---'
& node scripts/gen_supabase_config.mjs --check
if ($LASTEXITCODE -ne 0) {
  Write-Output ''
  Write-Output 'REFUSING TO DEPLOY. config.toml and the live project disagree about verify_jwt.'
  Write-Output 'Resolve it deliberately: either regenerate (node scripts/gen_supabase_config.mjs)'
  Write-Output 'and review the diff, or fix the live value. Do not deploy through drift.'
  exit 1
}

# Capture live versions so the deploy can be verified against the deployed bundle afterwards,
# rather than trusting the CLI exit code.
$before = @{}
foreach ($f in $Slugs) {
  try { $m = Invoke-RestMethod -Uri ("https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/functions/" + $f) -Headers $h; $before[$f] = [int]$m.version }
  catch { $before[$f] = -1 }
}

Write-Output ''
Write-Output "--- deploying $($Slugs.Count) function(s) ---"
$failed = @()
$i = 0
foreach ($f in $Slugs) {
  $i++
  $out = & supabase functions deploy $f --project-ref htdblwldjkcgjvmqkbeh --use-api 2>&1 | Out-String
  $code = $LASTEXITCODE
  if ($code -ne 0) { $failed += $f; Write-Output ("[{0}/{1}] {2} DEPLOY FAILED exit={3}" -f $i, $Slugs.Count, $f, $code); Write-Output $out }
  else { Write-Output ("[{0}/{1}] {2} deployed" -f $i, $Slugs.Count, $f) }
}

Write-Output ''
Write-Output '--- verifying against the DEPLOYED bundle ---'
$pass = 0; $bad = @()
foreach ($f in $Slugs) {
  try {
    $m = Invoke-RestMethod -Uri ("https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/functions/" + $f) -Headers $h
    $bumped = ($before[$f] -ge 0) -and ([int]$m.version -gt $before[$f])
    if ($bumped) { $pass++ } else { $bad += $f }
    Write-Output ("{0,-24} v{1,-4} (was v{2,-4}) bumped={3,-5} verify_jwt={4}" -f $f, $m.version, $before[$f], $bumped, $m.verify_jwt)
  } catch { $bad += $f; Write-Output ("{0,-24} CHECK FAILED: {1}" -f $f, $_.Exception.Message) }
}

Write-Output ''
Write-Output '--- post-deploy drift re-check (a deploy must not have changed any verify_jwt) ---'
& node scripts/gen_supabase_config.mjs --check
$driftAfter = $LASTEXITCODE

Write-Output ''
Write-Output ("DEPLOYED_OK {0}/{1}" -f $pass, $Slugs.Count)
if ($failed.Count) { Write-Output ("DEPLOY FAILURES: " + ($failed -join ' ')) }
if ($bad.Count)    { Write-Output ("NOT VERIFIED:    " + ($bad -join ' ')) }
if ($driftAfter -ne 0) { Write-Output 'POST-DEPLOY DRIFT: a deploy changed a verify_jwt value. Investigate before doing anything else.' }
if ($failed.Count -or $bad.Count -or $driftAfter -ne 0) { exit 1 }
Write-Output 'ALL GOOD'
