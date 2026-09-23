$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\Opera\quotesdone'
Write-Output '=== npm test ==='
npm test 2>&1 | Select-Object -Last 25
Write-Output ('npm test exit: ' + $LASTEXITCODE)
Write-Output '=== typecheck ==='
npx --no-install tsc --noEmit 2>&1 | Select-Object -Last 15
Write-Output ('typecheck exit: ' + $LASTEXITCODE)
Write-Output '=== deno check (gated) ==='
$deno = Get-Command deno -ErrorAction SilentlyContinue
if ($null -eq $deno) {
  Write-Output 'deno not on PATH; checking the local shim'
  if (Test-Path "$HOME\.deno\bin\deno.exe") { $deno = "$HOME\.deno\bin\deno.exe" }
}
if ($deno) {
  $files = Get-ChildItem -Path 'supabase/functions' -Filter '*.ts' -Recurse -ErrorAction SilentlyContinue
  Write-Output ('edge function ts files: ' + $files.Count)
  & $(if ($deno -is [string]) { $deno } else { $deno.Source }) check --quiet (Get-ChildItem -Path 'supabase/functions' -Filter 'index.ts' -Recurse | ForEach-Object { $_.FullName }) 2>&1 | Select-Object -Last 15
  Write-Output ('deno check exit: ' + $LASTEXITCODE)
} else {
  Write-Output 'deno unavailable on this machine'
}
