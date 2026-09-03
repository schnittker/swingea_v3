# Task Scheduler Setup - Erstellt automatische Health Checks
# Führt das Health-Check-Skript zu festgelegten Zeiten aus

Write-Host "=== Task Scheduler Setup für Health Check ===" -ForegroundColor Cyan
Write-Host ""

# Prüfen ob als Administrator ausgeführt
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "FEHLER: Dieses Skript muss als Administrator ausgeführt werden!" -ForegroundColor Red
    Write-Host "Rechtsklick auf PowerShell -> Als Administrator ausführen" -ForegroundColor Yellow
    exit 1
}

# Pfade definieren
$scriptPath = "C:\Scripts"
$healthCheckScript = "$scriptPath\health-check.ps1"

# Prüfen ob Health-Check-Skript existiert
if (-not (Test-Path $scriptPath)) {
    New-Item -Path $scriptPath -ItemType Directory -Force | Out-Null
    Write-Host "Ordner erstellt: $scriptPath" -ForegroundColor Green
}

# Health-Check-Skript kopieren (falls es hier im aktuellen Verzeichnis liegt)
$currentHealthCheck = Join-Path $PSScriptRoot "health-check.ps1"
if (Test-Path $currentHealthCheck) {
    Copy-Item -Path $currentHealthCheck -Destination $healthCheckScript -Force
    Write-Host "Health-Check-Skript kopiert nach: $healthCheckScript" -ForegroundColor Green
} elseif (-not (Test-Path $healthCheckScript)) {
    Write-Host "WARNUNG: health-check.ps1 nicht gefunden!" -ForegroundColor Yellow
    Write-Host "Bitte kopiere health-check.ps1 nach $healthCheckScript" -ForegroundColor Yellow
}

# Task-Aktion definieren
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$healthCheckScript`""

# Trigger für die 5 Zeiten erstellen
$trigger1 = New-ScheduledTaskTrigger -Daily -At 06:00
$trigger2 = New-ScheduledTaskTrigger -Daily -At 10:00
$trigger3 = New-ScheduledTaskTrigger -Daily -At 14:00
$trigger4 = New-ScheduledTaskTrigger -Daily -At 18:00
$trigger5 = New-ScheduledTaskTrigger -Daily -At 22:00

# Task-Einstellungen
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Prüfen ob Task bereits existiert
$taskName = "ServerHealthCheck"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Task '$taskName' existiert bereits. Soll er überschrieben werden? (J/N)" -ForegroundColor Yellow
    $overwrite = Read-Host

    if ($overwrite -eq "J" -or $overwrite -eq "j") {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Alter Task gelöscht." -ForegroundColor Green
    } else {
        Write-Host "Setup abgebrochen." -ForegroundColor Yellow
        exit 0
    }
}

# Task registrieren
try {
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger1, $trigger2, $trigger3, $trigger4, $trigger5 `
        -Settings $settings `
        -Description "Sendet Health Check E-Mails um 6, 10, 14, 18 und 22 Uhr" `
        -RunLevel Highest

    Write-Host ""
    Write-Host "Task Scheduler erfolgreich eingerichtet!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Der Task '$taskName' sendet E-Mails zu folgenden Zeiten:" -ForegroundColor Cyan
    Write-Host "  - 06:00 Uhr" -ForegroundColor White
    Write-Host "  - 10:00 Uhr" -ForegroundColor White
    Write-Host "  - 14:00 Uhr" -ForegroundColor White
    Write-Host "  - 18:00 Uhr" -ForegroundColor White
    Write-Host "  - 22:00 Uhr" -ForegroundColor White
    Write-Host ""
    Write-Host "Du kannst den Task in der Aufgabenplanung (taskschd.msc) verwalten." -ForegroundColor Cyan

    # Task manuell testen anbieten
    Write-Host ""
    Write-Host "Möchtest du den Task jetzt testweise ausführen? (J/N)" -ForegroundColor Yellow
    $runTest = Read-Host

    if ($runTest -eq "J" -or $runTest -eq "j") {
        Start-ScheduledTask -TaskName $taskName
        Write-Host ""
        Write-Host "Task wird ausgeführt... Prüfe in wenigen Sekunden dein E-Mail-Postfach." -ForegroundColor Green
        Write-Host "Log-Datei: C:\Scripts\health-check.log" -ForegroundColor Cyan
    }

} catch {
    Write-Host ""
    Write-Host "FEHLER beim Erstellen des Tasks:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Setup abgeschlossen!" -ForegroundColor Green
