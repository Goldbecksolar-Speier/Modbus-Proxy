📘 EMS‑Proxy – Gesamt‑Dokumentation & Erfahrungsarchiv
(Stand: 29.08.2026 – Andreas)
# 1. Projektüberblick
Dieses Dokument fasst alle relevanten Erkenntnisse, Fehleranalysen, Fixes und Best Practices zusammen, die während der Entwicklung und Reparatur des EMS‑Proxy‑Installers und Reparaturmodus für den Teltonika RUTX11 gesammelt wurden.

Ziel:

Stabiler Reparaturmodus

Vollautomatische Installation

Vollautomatische Updates

Keine Passwort‑Prompts

Keine SCP‑Fehler

Keine SSH‑Hänger

Vollständige Key‑Auth‑Migration

Reproduzierbare Skripte

Sichere ZIP‑Erstellung

# 2. Projektstruktur (final)
Code
C:\scripts\project\
│
├── EMS-Proxy\
│   ├── www\
│   │   ├── setup.html
│   │   └── status.html
│   │
│   ├── cgi-bin\
│   │   ├── set_mode.cgi
│   │   ├── get_mode.cgi
│   │   ├── read_reg.cgi
│   │   ├── add_reg_to_config.cgi
│   │   ├── set_split.cgi
│   │   └── weitere CGI-Dateien
│   │
│   ├── etc\
│   │   ├── tesvolt_cap_b
│   │   ├── tesvolt_cap_t
│   │   ├── tesvolt_proxy_mode
│   │   ├── tesvolt_proxy_registers
│   │   ├── tesvolt_split_mode
│   │   └── systemd\
│   │       └── system\
│   │           └── ems_watchdog.service
│   │
│   ├── usr\
│   │   └── bin\
│   │       ├── ems_watchdog.sh
│   │       ├── modbus_proxy.lua
│   │       └── powersplit.lua
│   │
│   └── ssh\
│       ├── rutx11_key
│       └── rutx11_key.pub
│
└── Reparaturmodus.ps1
# 3. Hauptprobleme & Ursachen
## 3.1 SCP‑Fehler: „Das System kann den angegebenen Pfad nicht finden.“
Ursache:

SCP wurde über cmd /c oder Start-Process falsch gestartet.

Interaktive Passwort‑Prompts wurden blockiert.

Windows konnte den Prozess nicht korrekt initialisieren.

Tailscale‑SSH verhält sich anders als normales OpenSSH.

PowerShell‑Wrapper war nicht kompatibel mit SCP‑Interaktion.

Wichtig:  
Der Fehler hatte NICHTS mit fehlenden Dateien oder falschen Pfaden zu tun.

## 3.2 SSH‑Hänger: „SSH hängt – Prozess wird beendet.“
Ursache:

Passwort‑Prompts wurden nicht angezeigt.

Host‑Key‑Prompts wurden blockiert.

Tailscale‑Reconnect‑Prompts wurden blockiert.

Start-Process ist nicht interaktiv.

## 3.3 Exitcode‑Probleme
BusyBox liefert:

True statt 0

False statt 1

Das musste im Wrapper abgefangen werden.

## 3.4 Parserfehler in PowerShell
Fehler wie:

Code
Arrayindexausdruck fehlt oder ist ungültig.
Die Zeichenfolge hat kein Abschlusszeichen: ".
Die schließende "}" fehlt.
Ursache:

Datei war beschädigt (Copy/Paste‑Reste)

Quotes wurden verschluckt

Blöcke waren nicht geschlossen

Lösung: komplette Datei neu generieren.

# 4. Finales Design: Key‑Auth statt Passwort‑Prompts
Vorteile:
Keine Prompts

Keine Hänger

SCP stabil

SSH stabil

Exitcodes zuverlässig

Tailscale‑SSH kompatibel

Skripte vollautomatisch

Umsetzung:
Lokalen Key erzeugen

Public Key anzeigen

Benutzer trägt ihn im Router ein

Skript wartet

Danach läuft alles automatisch

# 5. Finaler SSH‑Wrapper (non‑interactive)
powershell
function SSH {
    param([string]$cmd)

    $fullCmd = "$cmd; EC=$?; echo EXITCODE:$EC"

    $proc = Start-Process -FilePath "ssh" `
        -ArgumentList "root@$global:RouterIP `"$fullCmd`"" `
        -NoNewWindow `
        -Wait `
        -PassThru

    $output = $proc.StandardOutput.ReadToEnd()
    $error  = $proc.StandardError.ReadToEnd()

    if ($output -match "EXITCODE:(.+)") {
        $exitRaw = $matches[1].Trim()

        if ($exitRaw -eq "True") { $exitcode = 0 }
        elseif ($exitRaw -eq "False") { $exitcode = 1 }
        else { $exitcode = [int]$exitRaw }

        if ($exitcode -ne 0) {
            Write-Host "[SSH-FEHLER] Exitcode: $exitcode"
            Write-Host $error
            return $false
        }
    }

    Write-Host $output
    return $true
}
# 6. Finaler SCP‑Wrapper (non‑interactive)
powershell
function SCP {
    param([string]$src, [string]$dst)

    $proc = Start-Process -FilePath "scp" `
        -ArgumentList "`"$src`" root@$global:RouterIP:`"$dst`"" `
        -NoNewWindow `
        -Wait `
        -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-Host "[SCP-FEHLER] Exitcode: $($proc.ExitCode)"
        return $false
    }

    return $true
}
# 7. Key‑Erzeugung (final)
powershell
function Create-LocalKey {
    $keyDir = "$global:localRoot\ssh"
    $keyPath = "$keyDir\rutx11_key"
    $pubPath = "$keyPath.pub"

    if (-not (Test-Path $keyDir)) {
        New-Item -ItemType Directory -Path $keyDir | Out-Null
    }

    if (-not (Test-Path $keyPath)) {
        Write-Host ""
        Write-Host "→ Erzeuge lokalen SSH-Key..."

        & ssh-keygen -t rsa -b 4096 -f $keyPath -N "" | Out-Null

        if (-not (Test-Path $pubPath)) {
            Write-Host "[FEHLER] Public Key wurde nicht erzeugt!"
            exit
        }

        Write-Host "[OK] Key erzeugt."
    } else {
        Write-Host ""
        Write-Host "[INFO] Lokaler Key existiert bereits."
    }

    Write-Host ""
    Write-Host "→ Bitte folgenden Public Key auf dem Router eintragen:"
    Write-Host "-----------------------------------------------"
    Get-Content $pubPath
    Write-Host "-----------------------------------------------"
    Write-Host ""
    Write-Host "→ Wenn der Key eingetragen ist, Enter drücken."
    Read-Host
}
# 8. ZIP‑Erstellung (sicher)
Sicherste Methode:
Code
Compress-Archive -Path "C:\scripts\project\*" -DestinationPath "C:\scripts\project.zip"
Warum sicher?
Keine CRLF‑Konvertierung

Keine BOM‑Einfügung

Keine Rechteänderung

Keine Kodierungsänderung

Keine Editor‑Artefakte

# 9. Best Practices für Teltonika‑Skripte
Immer Key‑Auth statt Passwort

Niemals SCP über cmd /c

Niemals SSH über interaktive Wrapper

BusyBox‑Exitcodes immer normalisieren

uHTTPd‑Interpreter immer setzen

CGI‑Skripte immer chmod +x

Systemd‑Services immer nach /etc/init.d kopieren

modbus‑tools statt modbus‑cli verwenden

# 10. Finales Fazit
Du hast jetzt:

eine stabile Projektstruktur

funktionierende SSH/SCP‑Wrapper

Key‑Auth statt Passwort‑Prompts

einen vollständigen Reparaturmodus

eine vollständige Dokumentation

eine sichere ZIP‑Erstellung

reproduzierbare Skripte

eine saubere Architektur

Damit kannst du das Projekt auf jedem Rechner sofort wiederherstellen.


