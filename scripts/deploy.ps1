# Hearthglow -- Deploy Website to CanSpace
# Copies all website files to the server via SCP using your SSH key.
# Run setup-ssh-key.ps1 once before using this script.

$CPANEL_USER  = "hearthgl"
$SSH_HOST     = "eos.canspace.ca"
$SSH_PORT     = "22"
$KEY_PATH     = "$HOME\.ssh\hearthglow_id_ed25519"
$REMOTE_ROOT  = "/home/hearthgl/public_html"
$DOMAIN       = "https://hearthglow.ca"

# Derive local website root (parent of the scripts folder)
$SCRIPT_DIR   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOCAL_ROOT   = Split-Path -Parent $SCRIPT_DIR

# Files/folders to exclude from deployment
$EXCLUDE_DIRS  = @("scripts", "backups", "logs", ".git")
$EXCLUDE_EXTS  = @("*.ps1", "*.sh", "*.md", "*.log")

Write-Host ""
Write-Host "=== Hearthglow Deploy ===" -ForegroundColor Cyan
Write-Host "Source : $LOCAL_ROOT" -ForegroundColor White
Write-Host "Target : ${CPANEL_USER}@${SSH_HOST}:${REMOTE_ROOT}" -ForegroundColor White
Write-Host ""

# -- Check SSH key exists --
if (-not (Test-Path $KEY_PATH)) {
    Write-Host "ERROR: SSH key not found at $KEY_PATH" -ForegroundColor Red
    Write-Host "Run setup-ssh-key.ps1 first." -ForegroundColor Yellow
    exit 1
}

# -- Build staging area --
Write-Host "[1/3] Staging files..." -ForegroundColor Yellow
$stagingDir = "$env:TEMP\hearthglow-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $stagingDir | Out-Null

# Copy files to staging, excluding what we don't want on the server
$robocopyExcludes = $EXCLUDE_DIRS | ForEach-Object { "/XD $_" }
$robocopyExtExcludes = $EXCLUDE_EXTS -join " "

# Build robocopy command
$roboArgs = @(
    $LOCAL_ROOT,
    $stagingDir,
    "/E",           # include subdirectories
    "/NFL",         # no file list in output
    "/NDL",         # no dir list in output
    "/NJH",         # no job header
    "/NJS"          # no job summary
)
foreach ($dir in $EXCLUDE_DIRS) {
    $roboArgs += "/XD"
    $roboArgs += $dir
}
foreach ($ext in $EXCLUDE_EXTS) {
    $roboArgs += "/XF"
    $roboArgs += $ext
}

& robocopy @roboArgs | Out-Null
$stagedFiles = (Get-ChildItem $stagingDir -Recurse -File).Count
Write-Host "Staged $stagedFiles files to temp folder." -ForegroundColor Green

# -- Upload via SCP --
Write-Host ""
Write-Host "[2/3] Uploading to server..." -ForegroundColor Yellow

# Convert staging path to forward slashes for scp
$stagingSlash = $stagingDir.Replace("\", "/").Replace("C:", "/c")

$scpArgs = @(
    "-i", $KEY_PATH,
    "-P", $SSH_PORT,
    "-o", "StrictHostKeyChecking=no",
    "-r",
    "$stagingDir\*",
    "${CPANEL_USER}@${SSH_HOST}:${REMOTE_ROOT}/"
)

scp @scpArgs
$scpExit = $LASTEXITCODE

# -- Clean up staging --
Remove-Item -Recurse -Force $stagingDir

if ($scpExit -ne 0) {
    Write-Host ""
    Write-Host "ERROR: SCP failed with exit code $scpExit" -ForegroundColor Red
    exit 1
}

Write-Host "Upload complete." -ForegroundColor Green

# -- Verify site is up --
Write-Host ""
Write-Host "[3/3] Verifying site..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $DOMAIN -UseBasicParsing -TimeoutSec 15
    if ($response.StatusCode -eq 200) {
        Write-Host "Site is live: $DOMAIN returned HTTP $($response.StatusCode)" -ForegroundColor Green
    } else {
        Write-Host "Warning: $DOMAIN returned HTTP $($response.StatusCode)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "Warning: Could not reach $DOMAIN -- check manually." -ForegroundColor DarkYellow
}

# -- Log the deploy --
$logDir = Join-Path $LOCAL_ROOT "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -- Deploy completed by $env:USERNAME ($stagedFiles files)"
Add-Content -Path "$logDir\deploy.log" -Value $logEntry

Write-Host ""
Write-Host "=== Deploy complete ===" -ForegroundColor Cyan
Write-Host "Log entry written to logs\deploy.log" -ForegroundColor White
Write-Host ""
