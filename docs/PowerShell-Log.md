# PowerShell-/Deployment-Log (fortlaufendes Ledger)

> Regel: Jeder Deployment-Aufruf (PowerShell oder SSH direkt auf dem Router)
> wird hier als datierte Zeile dokumentiert - inklusive Fehlern und der
> Korrektur, mit der es schliesslich funktioniert hat. Zeilen werden nie
> ueberschrieben.
>
> Format: Datum/Zeit (UTC) | Skript/Befehl | Ziel | Ergebnis (OK/FEHLER + Exitcode) | Fehlermeldung (Kurzform) | Korrektur

## Ledger

| Datum/Zeit (UTC) | Skript / Befehl | Ziel | Ergebnis | Fehlermeldung | Korrektur |
|---|---|---|---|---|---|
| 2026-08-29 (vor Optimierung) | scp ... (Alt-Deployment, via cmd /c) | RUTX11 | FEHLER | "Das System kann den angegebenen Pfad nicht finden" | Key-Auth + BatchMode=yes, direkter scp-Aufruf statt cmd /c (siehe Learnings) |
| 2026-08-29 | deploy/install_ems_proxy.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erst nach Bedarf; Self-Update via github_update.sh ist der Hauptweg |
| 2026-08-29 | deploy/update_rutx11.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erst nach Erstinstallation nutzen |
| 2026-08-29 13:49 | Bootstrap-Einzeiler (wget, 2x --header) | RUTX11 (SSH) | FEHLER | wget: unrecognized option | BusyBox-wget kann keine Header -> curl nutzen |
| 2026-08-29 13:53 | Bootstrap-Einzeiler (curl -> /usr/bin) | RUTX11 (SSH) | FEHLER | curl: (23) client returned ERROR on write of 88 bytes | / ist squashfs read-only -> Ziel /usr/local/bin (Commits 875625d, f995952) |
| 2026-08-29 13:59 | Bootstrap-Einzeiler (curl -> /usr/local/bin) + github_update.sh feature/optimierung | RUTX11 (SSH) | OK | Hinweis "Skipping invalid Lua prefix" beim uhttpd-Restart (unkritisch, stammt von der uci/uhttpd-Konfigpruefung) | ERSTES ERFOLGREICHES DEPLOYMENT: Token-Auth ok, uhttpd-Instanz Port 8080 angelegt, Watchdog gestartet (PID 17078) |
| 2026-08-29 14:06 | Verifikation: ps, netstat, tail Log | RUTX11 (SSH) | OK | - | VERIFIZIERT: ems_watchdog.sh (PID 17078) + modbus_proxy.lua (PID 17088) laufen; luasocket funktioniert; Ports 1502 + 8080 LISTEN; Schutzmodus aktiv (Tesvolt=nil, BLUESUN=nil, Exception 0x0A) - System bereit fuer Setup-UI |
| 2026-08-29 14:18 | Setup-UI "Speichern" im Browser | RUTX11 (Port 8080) | FEHLER | /etc/tesvolt_ip_t/ip_b fehlen, cap_t/cap_b leer - CGIs liefern OK, schreiben aber nichts | Fehlersuche via debug.cgi gestartet |
| 2026-08-29 14:21 | debug.cgi (QUERY_STRING/id/Schreibtest) | RUTX11 (SSH+curl) | DIAGNOSE | QS ok, sed-Parsing ok, WRITE=FAIL | URSACHE: uhttpd fuehrt CGIs als User 'uhttpd' (uid 575) aus, nicht root -> kein Schreibrecht auf /etc |
| 2026-08-29 14:23 | Fix committed: github_update.sh legt /etc/tesvolt_* an + chown uhttpd:uhttpd, chmod 664 | GitHub (Commits 832cec7, 58653c8) | OK | - | Truncate auf eigene Datei braucht kein Schreibrecht auf /etc-Verzeichnis |
| 2026-08-29 14:27 | github_update.sh feature/optimierung (Fix-Rollout) | RUTX11 (SSH) | OK | - | Alle 7 Konfigdateien mit Owner uhttpd:uhttpd, chmod 664; Watchdog neu gestartet (PID 22337) |
| 2026-08-29 14:28 | curl set_ips.cgi?ip_t=10.0.0.1&ip_b=10.0.0.2 + cat | RUTX11 (SSH) | OK | - | VERIFIZIERT: CGI schreibt jetzt korrekt nach /etc/tesvolt_ip_t/ip_b; debug.cgi entfernt; Setup-UI-Speicherpfad komplett funktionsfaehig |
| 2026-08-29 14:41 | curl read_reg.cgi?reg=30001 (Test status.html-Backend) | RUTX11 (SSH) | FEHLER | ERR:proxy connection refused; Log: "EMS-Proxy gestartet" alle ~8 s | DIAGNOSE: Restart-Schleife - Watchdog-Check nutzte modbus_cli, das auf RUTOS NICHT existiert; Fix: mb_cli.lua (luasocket) + Watchdog-Logik EXC=lebt (Commits 173bc50, 6e751e0) |
| 2026-08-29 14:45 | github_update.sh feature/optimierung (mb_cli-Rollout) | RUTX11 (SSH) | FEHLER | Restart-Schleife weiterhin; read_reg jetzt ERR:timeout header | URSACHE 2: Proxy (single-threaded) blockiert 2 s beim Connect auf nicht existierende Test-IP 10.0.0.1 -> laenger als mb_cli-Timeout -> Watchdog killt; Loesung: Simulationsmodus ohne Geraete (Commits 9cc95c8, b05bf57) |
| 2026-08-29 14:54 | github_update.sh feature/optimierung (Sim + Start/Stop-Rollout) + echo 1 > /etc/tesvolt_sim | RUTX11 (SSH) | OK | - | VERIFIZIERT: Log "SIMULATION: beantworte Anfragen mit Fantasiewerten", keine Restarts mehr; curl read_reg.cgi?reg=30001 -> OK:64 - status.html-Datenpfad Ende-zu-Ende funktionsfaehig |
| 2026-08-29 ~15:30 | github_update.sh feature/optimierung (Proxy-Kill-Fix + Plausibilitaet + neue Sim-Werte) | RUTX11 (SSH) | OK | Zuvor: alte Sim-Werte (SOC_B=341) liefen trotz Update weiter | URSACHE: Lua laedt Code nur beim Prozessstart; Fix Commit 88c35c3: Update killt laufenden Proxy (pgrep+kill), Watchdog startet frischen Code; einmalig manueller kill noetig, danach automatisch; UI-Plausibilitaetspruefung Commit 042e360 |
| 2026-08-29 ~16:15 | github_update.sh feature/optimierung (Grid-Limit + Netzanschluss-Tabelle) | RUTX11 (SSH) | OK | - | VERIFIZIERT per Screenshot: 3 neue Grid-Konfigdateien angelegt (Commit 1b1a4c1), Netzanschluss-Grenzwerte als eigene Tabelle neben PowerSplit-Parametern (Commits 771274f, 40e388a, b9ef61a); "nicht gesetzt!"-Warnung sichtbar |
| 2026-08-29 ~16:23 | github_update.sh feature/optimierung (Verlaufskurven statt Farb-Heatmap) | RUTX11 (SSH) | OK | Farbkachel-Heatmap war schwer lesbar (User-Feedback) | Commit 4c873d4: Flaechendiagramme pro Register (80 px hoch, Min/Max-Achse, gestrichelte Nulllinie bei Power, Luecken bleiben Luecken); localStorage-Historie blieb erhalten; User-Bestaetigung "perfect" |

## Konventionen fuer Eintraege

- Ergebnis: OK (EXITCODE:0) oder FEHLER (EXITCODE:n bzw. Marker aus BusyBox).
- Bei Fehlern: Fehlermeldung in Kurzform, vollstaendige Ausgabe bei Bedarf als
  Datei unter docs/logs/ ablegen.
- Nach jeder Korrektur-Iteration eine neue Zeile - so bleibt die komplette
  Fehlersuche nachvollziehbar.
