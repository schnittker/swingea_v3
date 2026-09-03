# All-in-One Installation - Server Health Check
# Richtet alles automatisch ein
# WICHTIG: Dieses Skript als Administrator ausführen!

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Server Health Check - Installation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Prüfen ob als Administrator ausgeführt
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "FEHLER: Dieses Skript muss als Administrator ausgeführt werden!" -ForegroundColor Red
    Write-Host "Rechtsklick auf PowerShell -> Als Administrator ausführen" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Drücke Enter zum Beenden"
    exit 1
}

# Konfiguration
$scriptPath = "C:\Scripts"
$emailFrom = "markusschnittker@icloud.com"
$emailTo = "markusschnittker@icloud.com"
$smtpServer = "smtp.mail.me.com"
$smtpPort = 587
$appPassword = "oivv-srkk-nupn-xvad"

Write-Host "[1/5] Erstelle Verzeichnis..." -ForegroundColor Yellow
if (-not (Test-Path $scriptPath)) {
    New-Item -Path $scriptPath -ItemType Directory -Force | Out-Null
    Write-Host "      Ordner erstellt: $scriptPath" -ForegroundColor Green
} else {
    Write-Host "      Ordner existiert bereits: $scriptPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "[2/5] Speichere Credentials..." -ForegroundColor Yellow
try {
    $securePassword = ConvertTo-SecureString $appPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($emailFrom, $securePassword)
    $credentialPath = "$scriptPath\icloud-cred.xml"
    $credential | Export-Clixml -Path $credentialPath -Force
    Write-Host "      Credentials gespeichert: $credentialPath" -ForegroundColor Green
} catch {
    Write-Host "      FEHLER beim Speichern der Credentials!" -ForegroundColor Red
    Write-Host "      $_" -ForegroundColor Red
    Read-Host "Drücke Enter zum Beenden"
    exit 1
}

Write-Host ""
Write-Host "[3/5] Erstelle Health-Check-Skript..." -ForegroundColor Yellow
$healthCheckContent = @'
# Health Check Script - Sendet E-Mail via iCloud
$emailFrom = "markusschnittker@icloud.com"
$emailTo = "markusschnittker@icloud.com"
$subject = "Server Health Check - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
$body = @"
Server Health Check erfolgreich!

Server: $env:COMPUTERNAME
Zeitpunkt: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
Betriebssystem: $([System.Environment]::OSVersion.VersionString)
Uptime: $((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)

Der Server ist erreichbar und läuft ordnungsgemäß.
"@

$smtpServer = "smtp.mail.me.com"
$smtpPort = 587
$credentialPath = "C:\Scripts\icloud-cred.xml"

try {
    if (-not (Test-Path $credentialPath)) {
        Write-Error "Credential-Datei nicht gefunden: $credentialPath"
        exit 1
    }

    $credential = Import-Clixml -Path $credentialPath

    Send-MailMessage -From $emailFrom `
        -To $emailTo `
        -Subject $subject `
        -Body $body `
        -SmtpServer $smtpServer `
        -Port $smtpPort `
        -UseSsl `
        -Credential $credential `
        -ErrorAction Stop

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path "C:\Scripts\health-check.log" -Value "$timestamp - E-Mail erfolgreich gesendet"
    Write-Host "E-Mail erfolgreich gesendet um $timestamp"

} catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $errorMessage = "$timestamp - FEHLER: $($_.Exception.Message)"
    Add-Content -Path "C:\Scripts\health-check.log" -Value $errorMessage
    Write-Error $errorMessage
    exit 1
}
'@

$healthCheckScript = "$scriptPath\health-check.ps1"
Set-Content -Path $healthCheckScript -Value $healthCheckContent -Force
Write-Host "      Health-Check-Skript erstellt: $healthCheckScript" -ForegroundColor Green

Write-Host ""
Write-Host "[4/5] Richte Task Scheduler ein..." -ForegroundColor Yellow
try {
    # Task-Aktion
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$healthCheckScript`""

    # Trigger für die 5 Zeiten
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

    # Alten Task löschen falls vorhanden
    $taskName = "ServerHealthCheck"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "      Alter Task wurde entfernt" -ForegroundColor Yellow
    }

    # Neuen Task registrieren
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger1, $trigger2, $trigger3, $trigger4, $trigger5 `
        -Settings $settings `
        -Description "Sendet Health Check E-Mails um 6, 10, 14, 18 und 22 Uhr" `
        -RunLevel Highest | Out-Null

    Write-Host "      Task '$taskName' erfolgreich erstellt" -ForegroundColor Green

} catch {
    Write-Host "      FEHLER beim Erstellen des Tasks!" -ForegroundColor Red
    Write-Host "      $_" -ForegroundColor Red
    Read-Host "Drücke Enter zum Beenden"
    exit 1
}

Write-Host ""
Write-Host "[5/5] Teste die Konfiguration..." -ForegroundColor Yellow
Write-Host "      Sende Test-E-Mail..." -ForegroundColor White

try {
    Send-MailMessage -From $emailFrom `
        -To $emailTo `
        -Subject "Test - Health Check Installation erfolgreich" `
        -Body "Die Installation wurde erfolgreich abgeschlossen um $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss').`n`nDer automatische Health Check ist nun aktiv!" `
        -SmtpServer $smtpServer `
        -Port $smtpPort `
        -UseSsl `
        -Credential $credential `
        -ErrorAction Stop

    Write-Host "      Test-E-Mail erfolgreich gesendet!" -ForegroundColor Green

} catch {
    Write-Host "      WARNUNG: Test-E-Mail konnte nicht gesendet werden!" -ForegroundColor Yellow
    Write-Host "      Fehler: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      Bitte prüfe die Konfiguration manuell." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation erfolgreich!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Health-Check E-Mails werden gesendet um:" -ForegroundColor Cyan
Write-Host "  - 06:00 Uhr" -ForegroundColor White
Write-Host "  - 10:00 Uhr" -ForegroundColor White
Write-Host "  - 14:00 Uhr" -ForegroundColor White
Write-Host "  - 18:00 Uhr" -ForegroundColor White
Write-Host "  - 22:00 Uhr" -ForegroundColor White
Write-Host ""
Write-Host "Installierte Dateien:" -ForegroundColor Cyan
Write-Host "  - $healthCheckScript" -ForegroundColor White
Write-Host "  - $credentialPath" -ForegroundColor White
Write-Host "  - C:\Scripts\health-check.log (wird erstellt)" -ForegroundColor White
Write-Host ""
Write-Host "Task Scheduler:" -ForegroundColor Cyan
Write-Host "  - Task-Name: ServerHealthCheck" -ForegroundColor White
Write-Host "  - Ansehen: taskschd.msc" -ForegroundColor White
Write-Host ""
Write-Host "WICHTIG:" -ForegroundColor Yellow
Write-Host "  - Prüfe dein E-Mail-Postfach für die Test-E-Mail" -ForegroundColor Yellow
Write-Host "  - Du kannst dieses Install-Skript jetzt löschen" -ForegroundColor Yellow
Write-Host "  - Log-Datei: C:\Scripts\health-check.log" -ForegroundColor Yellow
Write-Host ""
Write-Host "Task jetzt testen? (J/N)" -ForegroundColor Cyan
$runTest = Read-Host

if ($runTest -eq "J" -or $runTest -eq "j") {
    Write-Host ""
    Write-Host "Starte Task..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 3

    if (Test-Path "C:\Scripts\health-check.log") {
        Write-Host ""
        Write-Host "Log-Datei:" -ForegroundColor Cyan
        Get-Content "C:\Scripts\health-check.log" -Tail 5
    }

    Write-Host ""
    Write-Host "Prüfe dein E-Mail-Postfach!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Fertig! Drücke Enter zum Beenden..." -ForegroundColor Green
Read-Host
