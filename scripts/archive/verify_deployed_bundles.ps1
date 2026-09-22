# Verify the pass-3 deploy against the DEPLOYED bundles, not the CLI's exit code.
$t = (Get-Content C:\Users\Opera\.supabase\access-token -Raw).Trim()
$h = @{ Authorization = "Bearer $t" }
$targets = (Get-Content C:\Users\Opera\qd-check\targets3_changed.txt -Raw).Trim() -split '\s+'
$pre = @{}; $prejwt = @{}
Import-Csv C:\Users\Opera\qd-check\pre_deploy_meta_95b.csv | ForEach-Object { $pre[$_.slug] = [int]$_.version; $prejwt[$_.slug] = $_.verify_jwt }
$pass = 0; $fail = @()
foreach ($f in $targets) {
  try {
    $meta = Invoke-RestMethod -Uri ("https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/functions/" + $f) -Headers $h
    $tmp = [System.IO.Path]::GetTempFileName()
    Invoke-WebRequest -Uri ("https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/functions/" + $f + "/body") -Headers $h -OutFile $tmp
    $txt = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($tmp))
    Remove-Item $tmp -Force
    $bumped  = ([int]$meta.version -gt $pre[$f])
    $bundled = $txt.Contains('fn_internal_auth')
    $jwtSame = ([string]$meta.verify_jwt -eq [string]$prejwt[$f])
    $ok = $bumped -and $bundled -and $jwtSame
    if ($ok) { $pass++ } else { $fail += $f }
    Write-Output ("{0,-22} v{1,-4} (was v{2}) bumped={3,-5} verifier_bundled={4,-5} jwt_unchanged={5,-5} {6}" -f `
      $f, $meta.version, $pre[$f], $bumped, $bundled, $jwtSame, $(if ($ok) { 'PASS' } else { 'FAIL' }))
  } catch { $fail += $f; Write-Output ("{0,-22} CHECK FAILED: {1}" -f $f, $_.Exception.Message) }
}
Write-Output ''
Write-Output ("VERIFIED {0}/{1}" -f $pass, $targets.Count)
if ($fail.Count) { Write-Output ("FAILURES: " + ($fail -join ' ')) }
