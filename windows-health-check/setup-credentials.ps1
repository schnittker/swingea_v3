# Setup-Skript - Speichert iCloud Credentials sicher
# Einmalig ausführen zur Einrichtung

Write-Host "=== iCloud Mail Credentials Setup ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "WICHTIG: Du benötigst ein App-spezifisches Passwort von iCloud!" -ForegroundColor Yellow
Write-Host "So erhältst du es:" -ForegroundColor Yellow
Write-Host "1. Gehe zu https://appleid.apple.com" -ForegroundColor Yellow
Write-Host "2. Melde dich an" -ForegroundColor Yellow
Write-Host "3. Sicherheit -> App-spezifische Passwörter -> Passwort generieren" -ForegroundColor Yellow
Write-Host "4. Name: 'Windows Server Health Check'" -ForegroundColor Yellow
Write-Host "5. Kopiere das generierte Passwort (Format: xxxx-xxxx-xxxx-xxxx)" -ForegroundColor Yellow
Write-Host ""

# Ordner erstellen
$scriptPath = "C:\Scripts"
if (-not (Test-Path $scriptPath)) {
    New-Item -Path $scriptPath -ItemType Directory -Force | Out-Null
    Write-Host "Ordner erstellt: $scriptPath" -ForegroundColor Green
}

# Credentials abfragen
Write-Host "Bitte gib deine iCloud-Anmeldedaten ein:" -ForegroundColor Cyan
Write-Host "Benutzername: markusschnittker@icloud.com" -ForegroundColor Cyan
Write-Host "Passwort: [App-spezifisches Passwort]" -ForegroundColor Cyan
Write-Host ""

$credential = Get-Credential -UserName "markusschnittker@icloud.com" -Message "iCloud App-spezifisches Passwort"

# Credentials speichern
$credentialPath = "$scriptPath\icloud-cred.xml"
$credential | Export-Clixml -Path $credentialPath

Write-Host ""
Write-Host "Credentials erfolgreich gespeichert in: $credentialPath" -ForegroundColor Green
Write-Host ""

# Test-E-Mail senden
Write-Host "Möchtest du eine Test-E-Mail senden? (J/N)" -ForegroundColor Cyan
$testMail = Read-Host

if ($testMail -eq "J" -or $testMail -eq "j") {
    try {
        Send-MailMessage -From "markusschnittker@icloud.com" `
            -To "markusschnittker@icloud.com" `
            -Subject "Test - Health Check Setup erfolgreich" `
            -Body "Dies ist eine Test-E-Mail. Das Setup wurde erfolgreich abgeschlossen um $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')" `
            -SmtpServer "smtp.mail.me.com" `
            -Port 587 `
            -UseSsl `
            -Credential $credential `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "Test-E-Mail erfolgreich gesendet! Prüfe dein Postfach." -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "FEHLER beim Senden der Test-E-Mail:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Bitte prüfe:" -ForegroundColor Yellow
        Write-Host "- Hast du ein App-spezifisches Passwort verwendet?" -ForegroundColor Yellow
        Write-Host "- Ist die E-Mail-Adresse korrekt?" -ForegroundColor Yellow
        Write-Host "- Hast du eine Internetverbindung?" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Setup abgeschlossen!" -ForegroundColor Green
