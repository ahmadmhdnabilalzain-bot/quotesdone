# The ZZ DEMO product-label photo fixture (21 Sep 2026, instruction 576): a nameplate with a product-type
# line and a model/rating line, invented, for catalogue_read.test.ts's OCR case (tesseract.js reads it,
# the catalogue reader must name UPS systems from it). Windows PowerShell 5.1, System.Drawing, no download.
#   powershell -File supabase/functions/_shared/catalogue_fixtures/make_zz_demo_ups_label.ps1
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 900, 360
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::White)
$big = New-Object System.Drawing.Font('Arial', 34, [System.Drawing.FontStyle]::Bold)
$mid = New-Object System.Drawing.Font('Arial', 24)
$b = [System.Drawing.Brushes]::Black
$g.DrawString('ZZ DEMO ZENTEK', $big, $b, 30, 20)
$g.DrawString('LINE INTERACTIVE UPS', $mid, $b, 30, 100)
$g.DrawString('Model: ZZ-UPS1500  Capacity 1500VA', $mid, $b, 30, 160)
$g.DrawString('Input 230V 50Hz  Output 230V', $mid, $b, 30, 220)
$g.DrawString('QuotesDone fixture, not a real product', $mid, $b, 30, 285)
$out = Join-Path $PSScriptRoot 'zz_demo_ups_label.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
