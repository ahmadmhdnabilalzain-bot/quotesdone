$ErrorActionPreference = 'Continue'
$cfg = Join-Path $env:APPDATA 'supabase\access-token'
if (Test-Path $cfg) { Write-Output ('cli_token_file=PRESENT len=' + (Get-Item $cfg).Length) }
else { Write-Output 'cli_token_file=ABSENT' }
$alt = Join-Path $env:USERPROFILE '.supabase\access-token'
if (Test-Path $alt) { Write-Output ('alt_token_file=PRESENT len=' + (Get-Item $alt).Length) }
else { Write-Output 'alt_token_file=ABSENT' }
