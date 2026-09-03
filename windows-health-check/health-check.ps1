# Health Check Script - Sendet E-Mail via iCloud
# Datum: 2025-12-19

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

# Credentials laden (müssen vorher gespeichert werden)
$credentialPath = "C:\Scripts\icloud-cred.xml"

try {
    # Prüfen ob Credentials existieren
    if (-not (Test-Path $credentialPath)) {
        Write-Error "Credential-Datei nicht gefunden: $credentialPath"
        Write-Host "Bitte führe zuerst das Setup-Skript aus!"
        exit 1
    }

    # Credentials laden
    $credential = Import-Clixml -Path $credentialPath

    # E-Mail senden
    Send-MailMessage -From $emailFrom `
        -To $emailTo `
        -Subject $subject `
        -Body $body `
        -SmtpServer $smtpServer `
        -Port $smtpPort `
        -UseSsl `
        -Credential $credential `
        -ErrorAction Stop

    # Erfolg loggen
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path "C:\Scripts\health-check.log" -Value "$timestamp - E-Mail erfolgreich gesendet"
    Write-Host "E-Mail erfolgreich gesendet um $timestamp"

} catch {
    # Fehler loggen
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $errorMessage = "$timestamp - FEHLER: $($_.Exception.Message)"
    Add-Content -Path "C:\Scripts\health-check.log" -Value $errorMessage
    Write-Error $errorMessage
    exit 1
}
