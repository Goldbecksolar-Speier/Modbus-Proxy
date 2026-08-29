# Modbus-Proxy fuer Teltonika RUTX11

EMS-Proxy zwischen **Tesvolt EMS** (Master) und zwei Batteriespeichern:
**Tesvolt-Batterie** + **BLUESUN PCS** (Liquid Cooling Storage 120KW/261KWH).
Die angeforderte Leistung wird gewichtet auf beide Speicher verteilt
(Split nach Kapazitaet oder SOC).

## Architektur

```
Tesvolt EMS (Master, Modbus TCP)
        |
        v  Port 1502
RUTX11: modbus_proxy.lua  ---(passthrough)---> Tesvolt-Batterie (Port 502)
        |
        +--(split via powersplit.lua)--------> BLUESUN PCS
        |                                       SetPower_B 0x1144 (x100)
        |                                       Mode       0x1143
        +-- ems_watchdog.sh (Service): ueberwacht Proxy, EMS-Link,
            BLUESUN-Link; Failsafe -> passthrough + SetPower_B=0
```

## Verzeichnisstruktur

| Pfad | Inhalt |
|---|---|
| `EMS-Proxy/usr/bin/` | `modbus_proxy.lua`, `powersplit.lua`, `ems_watchdog.sh` |
| `EMS-Proxy/etc/` | Konfigdateien + `systemd/system/ems_watchdog.service` |
| `EMS-Proxy/cgi-bin/` | CGI-Schnittstelle (Mode, Register, Split, Parameter, IPs) |
| `EMS-Proxy/www/` | Web-UI: `setup.html`, `status.html` |
| `deploy/` | PowerShell-Installer und Update-Skript (ANSI speichern!) |
| `docs/` | Register-Mapping, Learnings, SSH-Setup |
| `altercode/` | Alte Codestaende (Archiv, nicht mehr verwenden) |

## Betriebsmodi

- **passthrough** (Default/Failsafe): alle EMS-Anfragen 1:1 an Tesvolt.
- **split**: SetPower wird nach `capacity` oder `soc` gewichtet verteilt,
  inkl. Limit-Clamping gegen ChargeLimit_B (0x361D) / DchgLimit_B (0x361F).

## Installation

1. Key-Auth einrichten: siehe `docs/SSH_Setup.md`
2. `powershell -ExecutionPolicy Bypass -File deploy\install_ems_proxy.ps1 -RouterIP <IP>`
3. Updates: `powershell -ExecutionPolicy Bypass -File deploy\update_rutx11.ps1 -RouterIP <IP>`

## Wichtige Regeln

- PowerShell-Dateien **immer in ANSI speichern** (sonst Parserfehler/Beschaedigung).
- Alle Skriptdateien nur in diesem GitHub-Projekt pflegen (kein OneDrive/SharePoint).
- Learnings und Doku als Markdown in `docs/` ablegen.
