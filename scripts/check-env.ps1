# Hearthglow -- Environment Check
# Run this in PowerShell to see what tools are available for deployment

Write-Host ""
Write-Host "=== Hearthglow Deployment Environment Check ===" -ForegroundColor Cyan

# WSL
Write-Host ""
Write-Host "[WSL]" -ForegroundColor Yellow
try {
    $wsl = wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "FOUND: WSL is installed" -ForegroundColor Green
        wsl --list --verbose 2>&1 | ForEach-Object { Write-Host "   $_" }
    } else {
        Write-Host "NOT FOUND: WSL not available" -ForegroundColor Red
    }
} catch {
    Write-Host "NOT FOUND: WSL not available" -ForegroundColor Red
}

# Git
Write-Host ""
Write-Host "[Git]" -ForegroundColor Yellow
try {
    $git = git --version 2>&1
    Write-Host "FOUND: $git" -ForegroundColor Green
} catch {
    Write-Host "NOT FOUND: Git not found" -ForegroundColor Red
}

# Git Bash
Write-Host ""
Write-Host "[Git Bash]" -ForegroundColor Yellow
$gitBashPaths = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe"
)
$gitBashFound = $false
$gitBashExe = ""
foreach ($path in $gitBashPaths) {
    if (Test-Path $path) {
        Write-Host "FOUND: Git Bash at $path" -ForegroundColor Green
        $gitBashFound = $true
        $gitBashExe = $path
        break
    }
}
if (-not $gitBashFound) {
    Write-Host "NOT FOUND: Git Bash not at standard paths" -ForegroundColor Red
}

# SSH
Write-Host ""
Write-Host "[SSH]" -ForegroundColor Yellow
try {
    $ssh = ssh -V 2>&1
    Write-Host "FOUND: $ssh" -ForegroundColor Green
} catch {
    Write-Host "NOT FOUND: SSH not found" -ForegroundColor Red
}

# rsync
Write-Host ""
Write-Host "[rsync]" -ForegroundColor Yellow
if ($gitBashFound) {
    $rsyncCheck = & $gitBashExe -c "rsync --version 2>&1 | head -1" 2>&1
    if ($rsyncCheck -match "rsync") {
        Write-Host "FOUND: $rsyncCheck" -ForegroundColor Green
    } else {
        Write-Host "NOT FOUND: rsync not in Git Bash (deploy.sh needs this)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "SKIPPED: Git Bash not found, cannot check rsync" -ForegroundColor DarkYellow
}

# Existing SSH keys
Write-Host ""
Write-Host "[SSH Keys]" -ForegroundColor Yellow
$keyPath = "$HOME\.ssh\hearthglow_id_ed25519"
if (Test-Path $keyPath) {
    Write-Host "FOUND: Hearthglow SSH key already exists at $keyPath" -ForegroundColor Green
} else {
    Write-Host "NOT FOUND: No Hearthglow SSH key yet -- setup will create one" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Share the output above." -ForegroundColor White
Write-Host ""
