# Migration: EMS-Proxy auf einem neuen RUTX11 mit anderen Modbus-Clients

> Stand: 2026-09-06, Branch feature/device-test-ui (HEAD 48bfdfc).
> Das Deployment ist bewusst so gebaut, dass KEINE Anlagenparameter im
> Repo liegen - ein neuer Router braucht nur Bootstrap + Setup-UI.

## Teil A: Neuen Router aufsetzen (ca. 15 Minuten)

### 1. Voraussetzungen pruefen
- Teltonika RUTX11 mit RUTOS (getestet: FW 07.x), Internetzugang
- SSH-Zugang: RUTOS/dropbear kennt NUR root (NICHT admin - das ist nur WebUI!)
- Vor jedem Schritt Geraet verifizieren (mehrere Router im Zugriff!):
  `ubus call system board` bzw. SSH-Banner pruefen

### 2. SSH-Key hinterlegen
Public Key nach `/etc/dropbear/authorized_keys` (gilt nur fuer root).
Einmalig per Passwort-Login oder WebUI (System -> Administration -> SSH).

PowerShell-Test vom PC:
```powershell
ssh -i $env:USERPROFILE\.ssh\rutx11_key -o BatchMode=yes -o StrictHostKeyChecking=no root@<NEUE-ROUTER-IP> "ubus call system board"
```

### 3. GitHub-Token ablegen (privates Repo!)
```sh
echo '<TOKEN>' > /etc/github_token
chmod 600 /etc/github_token
```
Das Token NIEMALS ins Repo committen (Regel 7). Fuer den neuen Router
am besten ein eigenes Fine-Grained-Token (nur Contents:Read auf
Goldbecksolar-Speier/Modbus-Proxy) erzeugen - laesst sich getrennt widerrufen.

### 4. Bootstrap: github_update.sh holen
BusyBox-wget kann keine Header - IMMER curl (auf RUTX11 vorinstalliert):
```sh
curl -fsSL -H "Authorization: token $(cat /etc/github_token)" \
  -o /usr/local/bin/github_update.sh \
  "https://raw.githubusercontent.com/Goldbecksolar-Speier/Modbus-Proxy/<BRANCH>/EMS-Proxy/usr/bin/github_update.sh"
chmod +x /usr/local/bin/github_update.sh
```
(`mkdir -p /usr/local/bin` falls noetig; / ist squashfs read-only -
nur /etc, /usr/local, /tmp, /var sind beschreibbar.)

### 5. Update ZWEIMAL ausfuehren
```sh
/usr/local/bin/github_update.sh <BRANCH>
/usr/local/bin/github_update.sh <BRANCH>
```
Warum zweimal: der erste Lauf arbeitet noch mit dem Bootstrap-Skript im
Speicher; erst der zweite Lauf setzt garantiert die Rechte fuer alle
(auch neue) Konfigdateien (Learning 2026-09-04, Selbst-Update-Effekt).

Das Skript erledigt automatisch: Dateien nach /usr/local/bin + /usr/local/www,
uhttpd-Instanz 'emsproxy' auf Port 8080, luasocket via opkg, init.d-Watchdog
enable+restart, Konfigdatei-Rechte fuer den uhttpd-User, Proxy-Neustart.

### 6. Konfigurieren - NUR ueber die Setup-UI
`http://<NEUE-ROUTER-IP>:8080/setup.html`
- EMS-Quelle (Tesvolt EMS / SMA Data Manager) + deren IPs
- Geraete-IPs (ip_t, ip_b), Unit-IDs (BLUESUN/UDAN: Default 10)
- Kapazitaeten, Split-Modus, Netzanschluss-Limits (grid_max_chg/_dis)
- Aktivierungsflags en_t/en_b/en_sma: NICHT vorhandene bzw. anders
  angebundene Geraete (z.B. CAN) DEAKTIVIEREN - der Proxy ueberspringt
  sie dann komplett (seit 564e18f)
- Zum Inbetriebnahme-Test zuerst Simulation EIN (/etc/tesvolt_sim=1):
  UI-Roundtrip ohne echte Geraete testen, erst danach Simulation aus

### 7. Verifikation
- `http://<IP>:8080/status.html` - Badge gruen; unerreichbare Geraete = gelb EXC
- `http://<IP>:8080/test.html` - Geraete einzeln, dosiert testen
  (Limit /etc/tesvolt_test_max_kw, NOT-AUS, Auto-Standby-Guard 60 s)
- Log: `tail -f /var/log/ems_proxy.log`

## Teil B: Andere Modbus-Clients anbinden

Die Architektur (Proxy Port 1502, Split-Engine, Failsafe, Watchdog, UI)
ist geraeteneutral - geraetespezifisch sind NUR die Register-Mappings:

| Was | Datei | Anpassen |
|---|---|---|
| Batterie 2 (bisher BLUESUN/UDAN) | `EMS-Proxy/usr/bin/modbus_proxy.lua` | Tabelle `BS` (Register, Skalierung, Unit-ID) + `write_bluesun_setpoint()`/`bluesun_init()` an das Steuerkonzept des neuen Geraets anpassen |
| EMS-Seite (bisher Tesvolt) | `EMS-Proxy/usr/bin/modbus_proxy.lua` | Tabelle `EMS` (SOC, SETPOWER, Limit-Register) |
| Status-Anzeige | `EMS-Proxy/www/status.html` | Register-Maps + Plausibilitaetsgrenzen |
| Testseite | `EMS-Proxy/www/test.html` | Presets pro Sektion (Adresse, FC, Unit-ID, Skalierung) |
| Split-Logik | `EMS-Proxy/usr/bin/powersplit.lua` | i.d.R. UNVERAENDERT (arbeitet nur mit W-Werten, en-Flags, Limits) |

Checkliste fuer JEDES neue Geraet (Reihenfolge einhalten):
1. Offizielle Registerliste des Herstellers besorgen - KEINE Profilannahmen
   (Learning SMA: Unit-ID und Registerbelegung nur aus der Doku).
2. Klaeren: Unit-ID, FC (03/04/06/16), Adress-Offset, Datentyp/Word-Order,
   Skalierung (x10/x100!), Vorzeichenkonvention (Laden/Entladen).
3. Klaeren: Hat das Geraet einen eigenen Watchdog/Timeout? Wenn NEIN
   (wie UDAN-EMS): clientseitiger Failsafe (Standby+0) ist PFLICHT (Regel 13).
4. Klaeren: Mindestabstand zwischen Requests (UDAN: 200 ms)?
5. Anbindung pruefen: Modbus TCP oder CAN? CAN-Strecken sind fuer den
   Proxy unsichtbar (docs/Architektur-Szenarien.md) - solche Geraete
   per en-Flag deaktivieren.
6. Erst read-only am Geraet verifizieren (test.html), dann kleiner
   Schreibtest mit Minimalwert, dann Split aktivieren.
7. Ergebnisse als neue Zeilen in docs/Learnings.md nachtragen.

Empfehlung: fuer den neuen Standort einen eigenen Branch anlegen
(z.B. `site/<name>`), Mappings dort anpassen, Router per
`github_update.sh site/<name>` versorgen. Gemeinsame Verbesserungen
weiter ueber main.

## Was NICHT mitgenommen werden muss
- /etc/tesvolt_* des alten Routers (anlagenspezifisch, kommt per Setup-UI)
- /etc/github_token (pro Router eigenes Token erzeugen)
- /var/log/* (RAM, geht bei Reboot ohnehin verloren)

## Dauerhaft gueltige Regeln (docs/Learnings.md)
ANSI/ASCII fuer PS1; nur /usr/local/bin, /usr/local/www, /etc beschreibbar;
CGIs laufen als uhttpd-User; Lua-Prozess nach Codeupdate neu starten;
Timeout-Ketten von innen nach aussen (Regel 17); Geraet vor Diagnose
verifizieren (Regel 14).
