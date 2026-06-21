# Hearthglow -- Publish files to live site via cPanel API
# Uploads index.html and any files listed in $filesToUpload to public_html.
# Uses port 2083 (no SSH required).

$CPANEL_HOST  = "eos.canspace.ca"
$CPANEL_PORT  = "2083"
$CPANEL_USER  = "hearthgl"
$CPANEL_TOKEN = "Y3BDUYVKV7JAFOJ0PJXMF94N1O1MWXR6"
$REMOTE_DIR   = "/home/hearthgl/public_html"
$DOMAIN       = "https://hearthglow.ca"

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOCAL_ROOT  = Split-Path -Parent $SCRIPT_DIR

# Files to publish this run (paths relative to Website folder)
$filesToUpload = @(
    "index.html",
    "images/reveal-couple.png",
    "images/aerial-home.png",
    "images/lights-detail.png",
    "images/installer.png",
    "images/home-lit-og.png",
    "images/logo-mark.png",
    "images/child-wonder.png"
)

Write-Host ""
Write-Host "=== Hearthglow Publish ===" -ForegroundColor Cyan

# Trust all certs (PS 5.1 compatible)
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

$baseUrl = "https://${CPANEL_HOST}:${CPANEL_PORT}/execute"
$headers = @{ "Authorization" = "cpanel ${CPANEL_USER}:${CPANEL_TOKEN}" }

foreach ($relPath in $filesToUpload) {
    $localFile = Join-Path $LOCAL_ROOT $relPath
    $fileName  = Split-Path $relPath -Leaf
    $subDir    = Split-Path $relPath -Parent
    $remoteDir = if ($subDir) { "$REMOTE_DIR/$($subDir.Replace('\','/'))" } else { $REMOTE_DIR }
    $isBinary  = $relPath -match '\.(png|jpg|jpeg|gif|ico|webp|woff2?|ttf|eot)$'

    if (-not (Test-Path $localFile)) {
        Write-Host "SKIP: $relPath not found locally" -ForegroundColor DarkYellow
        continue
    }

    Write-Host ""
    Write-Host "Uploading $relPath ..." -ForegroundColor Yellow

    try {
        if (-not $isBinary) {
            # ── Text files: use save_file_content (simpler, more reliable) ──
            $content  = [System.IO.File]::ReadAllText($localFile, [System.Text.Encoding]::UTF8)
            $body     = "dir=$([Uri]::EscapeDataString($remoteDir))&file=$([Uri]::EscapeDataString($fileName))&content=$([Uri]::EscapeDataString($content))"
            $resp = Invoke-RestMethod -Uri "${baseUrl}/Fileman/save_file_content" `
                                      -Method POST `
                                      -Headers $headers `
                                      -Body $body `
                                      -ContentType "application/x-www-form-urlencoded" `
                                      -TimeoutSec 60
            if ($resp.status -eq 1) {
                Write-Host "OK: $relPath" -ForegroundColor Green
            } else {
                Write-Host "WARNING: $($resp | ConvertTo-Json -Depth 3)" -ForegroundColor DarkYellow
            }
        } else {
            # ── Binary files: multipart upload ──────────────────────────────
            $boundary  = [System.Guid]::NewGuid().ToString()
            $fileBytes = [System.IO.File]::ReadAllBytes($localFile)
            $mimeType  = if ($relPath -match '\.png$') { "image/png" }
                         elseif ($relPath -match '\.(jpg|jpeg)$') { "image/jpeg" }
                         else { "application/octet-stream" }

            $bodyLines = [System.Collections.Generic.List[byte]]::new()

            $dirHeader  = "--$boundary`r`nContent-Disposition: form-data; name=`"dir`"`r`n`r`n$remoteDir`r`n"
            $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($dirHeader))

            $fileHeader = "--$boundary`r`nContent-Disposition: form-data; name=`"file-1`"; filename=`"$fileName`"`r`nContent-Type: $mimeType`r`n`r`n"
            $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($fileHeader))
            $bodyLines.AddRange($fileBytes)

            $footer = "`r`n--$boundary--`r`n"
            $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($footer))

            $uploadHeaders = @{
                "Authorization" = "cpanel ${CPANEL_USER}:${CPANEL_TOKEN}"
                "Content-Type"  = "multipart/form-data; boundary=$boundary"
            }

            $resp = Invoke-RestMethod -Uri "${baseUrl}/Fileman/upload_files" `
                                      -Method POST `
                                      -Headers $uploadHeaders `
                                      -Body $bodyLines.ToArray() `
                                      -TimeoutSec 60

            if ($resp.status -eq 1) {
                Write-Host "OK: $relPath" -ForegroundColor Green
            } else {
                Write-Host "WARNING: $($resp | ConvertTo-Json -Depth 3)" -ForegroundColor DarkYellow
            }
        }
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}

# Verify
Write-Host ""
Write-Host "Verifying site..." -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri $DOMAIN -UseBasicParsing -TimeoutSec 15
    Write-Host "Site live: HTTP $($r.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Could not reach $DOMAIN -- check manually" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "=== Publish complete ===" -ForegroundColor Cyan
Write-Host ""
