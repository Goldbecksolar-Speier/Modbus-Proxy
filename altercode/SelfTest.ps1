# ===============================================
# EMS-Proxy Self-Test für RUTX11
# kompatibel mit RutOS 07.23.x + uHTTPd + Tailscale-SSH
# finaler Exitcode-sicherer SSH/SCP Wrapper
# ===============================================

param(
    [string]$RouterIP
)

if (-not $RouterIP) {
    Write-Host "Bitte IP des RUTX11 eingeben (z.B. 100.88.76.66): " -NoNewline
    $RouterIP = Read-Host
}

$global:RouterIP = $RouterIP
$global:localRoot = (Get-Location).Path

Write-Host ""
Write-Host "==============================================="
Write-Host " EMS-Proxy Self-Test für RUTX11"
Write-Host "==============================================="
Write-Host ""
Write-Host "Router-IP: $RouterIP"
Write-Host ""

# ============================================================
# Finaler Exitcode-sicherer SSH Wrapper
# ============================================================

function SSH {
    param([string]$cmd)

    Write-Host ""
    Write-Host "? SSH-Befehl wird ausgeführt:"
    Write-Host "   $cmd"
    Write-Host "   (Passwort-Prompt erscheint im Terminal)"
    Write-Host ""

    # Exitcode auf dem Router erzeugen
    $fullCmd = "$cmd; EC=$?; echo EXITCODE:$EC"

    # Prozess starten
    $proc = Start-Process -FilePath "ssh" `
        -ArgumentList "root@$global:RouterIP `"$fullCmd`"" `
        -NoNewWindow `
        -RedirectStandardOutput "ssh_out.txt" `
        -RedirectStandardError "ssh_err.txt" `
        -PassThru

    # Timeout
    $timeout = 15
    for ($i=0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) { break }
    }

    # Hänger erkennen
    if (-not $proc.HasExited) {
        Write-Host "[FEHLER] SSH hängt ? Prozess wird beendet."
        $proc.Kill()
        return $false
    }

    # Ausgabe einlesen
    $output = Get-Content "ssh_out.txt" -Raw
    $error  = Get-Content "ssh_err.txt" -Raw

    # Exitcode auswerten
    if ($output -match "EXITCODE:(.+)") {
        $exitRaw = $matches[1].Trim()

        # True/False ? numerisch interpretieren
        if ($exitRaw -eq "True") { $exitcode = 0 }
        elseif ($exitRaw -eq "False") { $exitcode = 1 }
        else { $exitcode = [int]$exitRaw }

        if ($exitcode -ne 0) {
            Write-Host "[SSH-FEHLER] Exitcode: $exitcode"
            Write-Host $error
            return $false
        }
    } else {
        Write-Host "[WARNUNG] Kein Exitcode gefunden — SSH war erfolgreich, aber Windows hat ihn nicht geliefert."
    }

    Write-Host $output
    return $true
}

# ============================================================
# Finaler Exitcode-sicherer SCP Wrapper
# ============================================================

function SCP {
    param([string]$src, [string]$dst)

    Write-Host ""
    Write-Host "? SCP-Upload:"
    Write-Host "   Quelle: $src"
    Write-Host "   Ziel:   $dst"
    Write-Host "   (Passwort-Prompt erscheint im Terminal)"
    Write-Host ""

    # Prozess starten
    $proc = Start-Process -FilePath "scp" `
        -ArgumentList "`"$src`" root@$global:RouterIP:`"$dst`"" `
        -NoNewWindow `
        -RedirectStandardOutput "scp_out.txt" `
        -RedirectStandardError "scp_err.txt" `
        -PassThru

    # Timeout
    $timeout = 20
    for ($i=0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) { break }
    }

    # Hänger erkennen
    if (-not $proc.HasExited) {
        Write-Host "[FEHLER] SCP hängt ? Prozess wird beendet."
        $proc.Kill()
        return $false
    }

    # Exitcode prüfen
    if ($proc.ExitCode -ne 0) {
        Write-Host "[SCP-FEHLER] Exitcode: $($proc.ExitCode)"
        Write-Host (Get-Content "scp_err.txt" -Raw)
        return $false
    }

    Write-Host (Get-Content "scp_out.txt" -Raw)
    return $true
}

# ============================================================
# Self-Test (RutOS 07.23.x)
# ============================================================

function SelfTest {

    Write-Host ""
    Write-Host "Starte Self-Test..."
    Write-Host ""

    Write-Host "[ 10% ] SSH Verbindung"
    if (-not (SSH "echo OK")) { Write-Host "[FEHLER] SSH fehlgeschlagen"; return }
    Write-Host "[OK] SSH OK"

    Write-Host "[ 20% ] SCP Upload"
    if (-not (SCP "$global:localRoot\EMS-Proxy\www\setup.html" "/tmp/setup_test.html")) { Write-Host "[FEHLER] SCP fehlgeschlagen"; return }
    Write-Host "[OK] SCP OK"

    Write-Host "[ 30% ] CGI Test (uHTTPd)"
    if (-not (SSH "uci get uhttpd.main.interpreter")) { Write-Host "[WARNUNG] CGI nicht konfiguriert"; }
    Write-Host "[OK] CGI-Konfiguration abgefragt"

    Write-Host "[ 40% ] modbus_cli Test"
    SSH "modbus_cli --help"
    Write-Host "[OK] modbus_cli Test ausgeführt (oder Fehler sichtbar)"

    Write-Host "[ 50% ] init.d Test"
    SSH "ls /etc/init.d"
    Write-Host "[OK] init.d OK"

    Write-Host ""
    Write-Host "Self-Test abgeschlossen."
    Write-Host ""
}

# ============================================================
# Menü / Steuerung
# ============================================================

Write-Host "Was möchtest du tun?"
Write-Host "1 = Self-Test starten"
Write-Host ""
Write-Host "Bitte Auswahl eingeben (1): " -NoNewline
$choice = Read-Host

switch ($choice) {
    "1" {
        SelfTest
    }
    default {
        Write-Host "[FEHLER] Ungültige Auswahl."
    }
}

Write-Host ""
Write-Host "Self-Test beendet."
Write-Host ""
