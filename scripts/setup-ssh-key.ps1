# Hearthglow -- SSH Key Setup for CanSpace
# Generates an Ed25519 SSH key and uploads it to cPanel via the API.
# Run once. After this, deploy.ps1 handles all future deployments.

$CPANEL_HOST  = "eos.canspace.ca"
$CPANEL_PORT  = "2083"
$CPANEL_USER  = "hearthgl"
$CPANEL_TOKEN = "Y3BDUYVKV7JAFOJ0PJXMF94N1O1MWXR6"
$SSH_HOST     = "eos.canspace.ca"
$SSH_PORT     = "22"
$KEY_NAME     = "hearthglow_id_ed25519"
$KEY_PATH     = "$HOME\.ssh\$KEY_NAME"

Write-Host ""
Write-Host "=== Hearthglow SSH Key Setup ===" -ForegroundColor Cyan

# -- Step 1: Generate key pair --
Write-Host ""
Write-Host "[1/4] Generating SSH key pair..." -ForegroundColor Yellow

if (Test-Path $KEY_PATH) {
    Write-Host "Key already exists at $KEY_PATH -- skipping generation." -ForegroundColor DarkYellow
} else {
    $sshDir = "$HOME\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }
    ssh-keygen -t ed25519 -f $KEY_PATH -N '""' -C "hearthglow-deploy"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: ssh-keygen failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "Key generated at $KEY_PATH" -ForegroundColor Green
}

# -- Step 2: Read public key --
Write-Host ""
Write-Host "[2/4] Reading public key..." -ForegroundColor Yellow
$pubKeyPath = "$KEY_PATH.pub"
if (-not (Test-Path $pubKeyPath)) {
    Write-Host "ERROR: Public key not found at $pubKeyPath" -ForegroundColor Red
    exit 1
}
$pubKey = Get-Content $pubKeyPath -Raw
$pubKeyBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pubKey))
Write-Host "Public key read successfully." -ForegroundColor Green

# -- Step 3: Upload public key to cPanel --
Write-Host ""
Write-Host "[3/4] Uploading public key to cPanel..." -ForegroundColor Yellow

# Allow self-signed certs (PowerShell 5.1 compatible)
add-type @"
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

$headers = @{ "Authorization" = "cpanel ${CPANEL_USER}:${CPANEL_TOKEN}" }
$baseUrl = "https://${CPANEL_HOST}:${CPANEL_PORT}/execute"

# Import the key
try {
    $importUrl = "${baseUrl}/SSH/import_key"
    $importBody = "name=${KEY_NAME}&type=public&key=${pubKeyBase64}"
    $importResp = Invoke-RestMethod -Uri $importUrl -Headers $headers -Method POST -Body $importBody -TimeoutSec 20
    if ($importResp.status -eq 1) {
        Write-Host "Public key imported to cPanel." -ForegroundColor Green
    } else {
        Write-Host "Import response: $($importResp | ConvertTo-Json)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "ERROR importing key: $_" -ForegroundColor Red
    exit 1
}

# Authorize the key
try {
    $authUrl = "${baseUrl}/SSH/authkey"
    $authBody = "name=${KEY_NAME}&type=public"
    $authResp = Invoke-RestMethod -Uri $authUrl -Headers $headers -Method POST -Body $authBody -TimeoutSec 20
    if ($authResp.status -eq 1) {
        Write-Host "Key authorized on server." -ForegroundColor Green
    } else {
        Write-Host "Auth response: $($authResp | ConvertTo-Json)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "ERROR authorizing key: $_" -ForegroundColor Red
    exit 1
}

# -- Step 4: Test SSH connection --
Write-Host ""
Write-Host "[4/4] Testing SSH connection to $SSH_HOST..." -ForegroundColor Yellow
$testResult = ssh -i $KEY_PATH -p $SSH_PORT -o StrictHostKeyChecking=no -o BatchMode=yes "${CPANEL_USER}@${SSH_HOST}" "echo SSH_OK" 2>&1
if ($testResult -match "SSH_OK") {
    Write-Host "SSH connection successful -- passwordless deploy is ready." -ForegroundColor Green
} else {
    Write-Host "SSH test output: $testResult" -ForegroundColor DarkYellow
    Write-Host "Connection may still work -- try running deploy.ps1 to confirm." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "=== Setup complete. Run deploy.ps1 to push your first update. ===" -ForegroundColor Cyan
Write-Host ""
