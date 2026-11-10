$ErrorActionPreference = 'Continue'
try { $n = (node --version) 2>$null } catch { $n = 'MISSING' }
Write-Output ("node=" + $n)
$tok = [Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN','User')
if ($tok) { Write-Output ("token_var=PRESENT len=" + $tok.Length + " prefix=" + $tok.Substring(0,4)) }
else { Write-Output "token_var=ABSENT" }
